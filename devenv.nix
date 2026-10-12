{
  pkgs,
  lib,
  ...
}:
let
  # Tool groups. Each group is declared once and referenced both by the full
  # local shell (installs every group) and by the slim CI profile at the
  # bottom, so the tool lists never diverge.
  ciTools = with pkgs; [
    bats
    deadnix
    flake-checker
    go-task
    gitleaks
    nixfmt-tree
    statix
  ];
  # PVE tooling for manual answer/ISO work. Not needed by the lint/test gate:
  # the flake checks bring the PVE tools they need from their own derivations,
  # so the CI profile drops this group.
  pveTools = with pkgs; [
    proxmox-auto-install-assistant
    xorriso
  ];
in
{
  packages = ciTools ++ pveTools;

  # Git hooks are declared here and installed by devenv on shell entry. The
  # `ci` hook stays registered in every profile so the generated
  # .pre-commit-config.yaml always lists exactly one hook: the git-installed
  # hook outlives any single shell entry, and pre-commit rejects both a
  # missing and an empty config. What the hook runs varies per profile via
  # `entry`. By default it gates commits with `task ci`. The generated file is
  # gitignored.
  git-hooks.enable = true;
  git-hooks.hooks.ci = {
    enable = true;
    entry = "task ci";
    language = "system";
    pass_filenames = false;
  };

  # Slim shell for CI. It keeps only the ci tool group so the devenv closure
  # stays small (fast and cacheable) while the toolchain stays identical to
  # what `devenv shell` provides. The hook entry is overridden to a no-op so
  # `git-hooks:run` does not repeat the suite at shell entry.
  # Usage: devenv --profile ci shell -- task ci
  profiles.ci.module = {
    packages = lib.mkForce ciTools;
    git-hooks.hooks.ci.entry = lib.mkForce "true";
  };
}
