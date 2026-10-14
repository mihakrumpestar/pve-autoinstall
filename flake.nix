{
  description = "Proxmox VE autoinstall: per-host answer files and prepared ISOs";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      # Only proxmox-auto-install-assistant is unfree; keep the allowance narrow
      # so no other unfree package slips in unnoticed.
      allowUnfreePredicate = p: builtins.elem (lib.getName p) [ "proxmox-auto-install-assistant" ];

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = allowUnfreePredicate;
        };

      # Every output is exported for each build-host system in this list: the
      # CLI and the ISO tooling build natively on each. Each host's
      # install-target arch is chosen in its config (modules/schema.nix),
      # independent of the build host.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;

      # Pinned PVE ISOs per install-target arch. Single source of truth in
      # lib/iso-pins.nix (bump instructions live there).
      pveIso = import ./lib/iso-pins.nix;

      # Canonical factory: renders a typed config module into per-host answers,
      # prepared ISOs, bundle dirs and PVE-tool checks. Pin authority: a
      # caller passing `pkgs` or `pveIso` gets a loud "unexpected argument"
      # error, so the pinned ISOs cannot be silently overridden. `system`
      # selects the build host's pkgs (the per-host install-target arch comes
      # from the config).
      mkPve =
        {
          config,
          system ? "x86_64-linux",
        }:
        import ./packages {
          inherit config lib pveIso;
          pkgs = pkgsFor system;
        };

      # The flake's `packages` and `checks` always use the committed example
      # config: config/default.nix is gitignored, so it is never part of the
      # flake source and must not be auto-detected (doing so would silently
      # build the example with a throwaway password while the user believes
      # their real config was used). Supply a real config via the CLI
      # (`nix run . -- <config.nix>`) or by calling
      # `lib.mkPve { config = ...; }`.
      defaultFor =
        system:
        mkPve {
          config = ./config/example.nix;
          inherit system;
        };
    in
    {
      # Canonical consumer entrypoint; also what the CLI resolves via the flake.
      # pveIso lives under lib so `nix flake check` does not warn about an
      # unknown top-level output.
      lib = {
        inherit pveIso mkPve;
      };

      # All outputs are exported for every system in `systems`; the ISO-bearing
      # ones use that system's pkgs (the native assistant prepares any target
      # ISO, see packages/default.nix).
      packages = forAllSystems (
        s:
        let
          default = defaultFor s;
        in
        {
          pve-autoinstall = import ./packages/cli.nix {
            pkgs = pkgsFor s;
            inherit (lib) escapeShellArg;
            pveIsoVersion = pveIso.version;
            flakeSrc = self.outPath;
          };
          pve-answers = default.answersDir;
          pve-isos = default.isosDir;
          default = default.isosDir;
        }
      );

      # Per-host PVE-tool checks plus the render/reject checks from
      # packages/tests.nix.
      checks = forAllSystems (
        s:
        let
          default = defaultFor s;
        in
        default.checks
        // (import ./packages/tests.nix {
          pkgs = pkgsFor s;
          inherit lib;
        }).checks
      );

      # `nix run` executes the CLI package exported under `packages`.
      apps = forAllSystems (s: {
        default = {
          type = "app";
          program = "${self.packages.${s}.pve-autoinstall}/bin/pve-autoinstall";
          meta.description = self.packages.${s}.pve-autoinstall.meta.description;
        };
      });

      # `nix fmt` uses the same treefmt/nixfmt setup as devenv.nix.
      formatter = forAllSystems (s: (pkgsFor s).nixfmt-tree);
    };
}
