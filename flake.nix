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
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      inherit (nixpkgs) lib;

      # Pinned PVE 9.x ISO. Bump by editing url + hash together: get the new
      # release from https://www.proxmox.com/en/downloads, then
      #   nix store prefetch-file --json --hash-type sha256 <URL>
      # and paste the printed hash (SRI form) below. Note:
      # download.proxmox.com currently serves a mismatching TLS cert, so the
      # pin uses enterprise.proxmox.com (serves the same ISO, HTTP 200).
      pveIso = {
        version = "9.2-1";
        url = "https://enterprise.proxmox.com/iso/proxmox-ve_9.2-1.iso";
        hash = "sha256-Toj+QW35tSdiShdfJMmqB8cU0zMq+x7j2/OHlXPvLGw=";
      };

      srcIso = pkgs.fetchurl {
        inherit (pveIso) url hash;
      };

      # Canonical factory: renders a typed config module into per-host answers,
      # prepared ISOs, bundle dirs and PVE-tool checks.
      mkPve =
        args:
        import ./packages (
          {
            inherit
              pkgs
              lib
              pveIso
              srcIso
              ;
          }
          // args
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

      packages.${system} = {
        pve-answers = default.answersDir;
        pve-isos = default.isosDir;
        default = default.isosDir;
      };

      apps.${system}.default = import ./packages/cli.nix {
        inherit pkgs lib pveIso;
        flakeSrc = self.outPath;
      };

      checks.${system} = default.checks;

      # `nix fmt` uses the same treefmt/nixfmt setup as devenv.nix.
      formatter.${system} = pkgs.nixfmt-tree;
    };
}
