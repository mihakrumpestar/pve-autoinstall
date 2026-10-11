{ pkgs, ... }:
{
  packages = with pkgs; [
    deadnix
    flake-checker
    go-task
    gitleaks
    nixfmt-tree
    statix

    # PVE tooling for manual answer/ISO work
    proxmox-auto-install-assistant
    xorriso
  ];

  # Git hooks are declared here and installed by devenv on shell entry.
  # The generated .pre-commit-config.yaml is gitignored.
  git-hooks.hooks.ci = {
    enable = true;
    entry = "task ci";
    language = "system";
    pass_filenames = false;
  };
}
