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

      # Host tooling (`nix run`, `nix fmt`) works on any of these systems.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;

      # ISO tooling (`lib.mkPve`, `packages`, `checks`) is x86_64-linux by
      # design: PVE ISOs and proxmox-auto-install-assistant are x86_64 only.
      # `nix run`/`nix fmt` still work on every system in `systems`.
      system = "x86_64-linux";
      pkgs = pkgsFor system;

      # Pinned PVE 9.x ISO. Bump by editing version + hash together: get the
      # new release from https://www.proxmox.com/en/downloads, then
      #   nix store prefetch-file --json --hash-type sha256 <URL>
      # and paste the printed hash (SRI form) below; the URL is derived from
      # the version. Note: download.proxmox.com currently serves a mismatching
      # TLS cert, so the pin uses enterprise.proxmox.com (serves the same ISO,
      # HTTP 200).
      pveIso =
        let
          version = "9.2-1";
        in
        {
          inherit version;
          url = "https://enterprise.proxmox.com/iso/proxmox-ve_${version}.iso";
          hash = "sha256-Toj+QW35tSdiShdfJMmqB8cU0zMq+x7j2/OHlXPvLGw=";
        };

      srcIso = pkgs.fetchurl {
        inherit (pveIso) url hash;
      };

      # Canonical factory: renders a typed config module into per-host answers,
      # prepared ISOs, bundle dirs and PVE-tool checks. `pkgs`/`pveIso`/`srcIso`
      # are provided by the flake, not the consumer: they are applied last, so a
      # caller-supplied pkgs/pveIso is deliberately ignored (the pinned ISO must
      # not be silently overridable).
      mkPve =
        args:
        import ./packages (
          args
          // {
            inherit
              pkgs
              lib
              pveIso
              srcIso
              ;
          }
        );

      # The flake's `packages` and `checks` always use the committed example
      # config: config/default.nix is gitignored, so it is never part of the
      # flake source and must not be auto-detected (doing so would silently
      # build the example with a throwaway password while the user believes
      # their real config was used). Supply a real config via the CLI
      # (`nix run . -- <config.nix>`) or by calling
      # `lib.mkPve { config = ...; }`.
      default = mkPve { config = ./config/example.nix; };
    in
    {
      # Canonical consumer entrypoint; also what the CLI resolves via the flake.
      # pveIso lives under lib so `nix flake check` does not warn about an
      # unknown top-level output.
      lib = {
        inherit pveIso mkPve;
      };

      # ISO-bearing outputs are x86_64-linux only (see the `system` comment).
      # The CLI is not x86_64-bound (it only shells out to nix), so its
      # package is built for every system in `systems` (each with that
      # system's pkgs).
      packages = forAllSystems (
        s:
        {
          pve-autoinstall = import ./packages/cli.nix {
            pkgs = pkgsFor s;
            inherit lib pveIso;
            flakeSrc = self.outPath;
          };
        }
        // lib.optionalAttrs (s == system) {
          pve-answers = default.answersDir;
          pve-isos = default.isosDir;
          default = default.isosDir;
        }
      );

      # Per-host PVE-tool checks plus the render/reject checks from
      # packages/tests.nix (golden render, non-vacuous rejection cases and the
      # host-key docs pattern check).
      checks.${system} =
        default.checks
        // (import ./packages/tests.nix {
          inherit pkgs lib;
          factory = default;
        }).checks;

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
