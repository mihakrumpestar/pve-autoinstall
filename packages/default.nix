# pve-autoinstall builder: evaluates a host configuration against the typed
# module (../modules/schema.nix self-validates values and asserts the policy
# rules), then produces per-host answer files, prepared ISOs, bundle dirs and
# PVE-tool checks.
{
  pkgs,
  lib,
  pveIso,
  srcIso,
  # Module: path to a config file or an attrset; see ../config/example.nix
  # for the shape and ../modules/schema.nix for options.
  config ?
    if builtins.pathExists ../config/default.nix then ../config/default.nix else ../config/example.nix,
}:
let
  eval = lib.evalModules {
    modules = [
      ../modules/schema.nix
      config
    ];
  };
  hosts = eval.config.hosts;
  renderAnswer = import ../lib/render-answer.nix lib;
  answerFile = h: pkgs.writeText "pve-answer-${h.name}.toml" (renderAnswer h);

  answers = lib.listToAttrs (map (h: lib.nameValuePair h.name (answerFile h)) hosts);
  isos = lib.listToAttrs (
    map (
      h:
      lib.nameValuePair h.name (
        pkgs.runCommand "proxmox-ve_${pveIso.version}-autoinstall-${h.name}.iso"
          {
            nativeBuildInputs = with pkgs; [
              proxmox-auto-install-assistant
              xorriso
            ];
          }
          ''
            export TMPDIR=$NIX_BUILD_TOP/tmp
            mkdir -p "$TMPDIR"
            # prepare-iso writes its working copy next to the source
            # ISO (read-only in the store), so run it on a local copy
            cp ${srcIso} src.iso
            chmod u+w src.iso
            proxmox-auto-install-assistant prepare-iso \
              src.iso \
              --fetch-from iso \
              --answer-file ${answerFile h} \
              --output $out
          ''
      )
    ) hosts
  );

  hostNames = lib.attrNames answers;

  answersDir = pkgs.runCommand "pve-autoinstall-answers" { } (
    ''
      mkdir -p $out/answers
    ''
    + lib.concatMapStrings (host: ''
      cp ${answers.${host}} $out/answers/${host}.toml
    '') hostNames
  );

  isosDir = pkgs.runCommand "pve-autoinstall-isos" { } (
    ''
      mkdir -p $out/isos
    ''
    + lib.concatMapStrings (host: ''
      ln -s ${isos.${host}} $out/isos/${host}.iso
    '') hostNames
  );

  # Validate rendered answers and built ISOs with the PVE-supplied tools.
  assistant = lib.getExe pkgs.proxmox-auto-install-assistant;

  answerCheck =
    host:
    pkgs.runCommand "pve-answer-validates-${host}" { } ''
      ${assistant} validate-answer ${answers.${host}} \
        | tee validate.log | grep -q "parsed successfully"
      touch $out
    '';

  isoCheck =
    host:
    pkgs.runCommand "pve-iso-is-autoinstall-${host}"
      {
        nativeBuildInputs = with pkgs; [
          proxmox-auto-install-assistant
          xorriso
        ];
      }
      ''
        ${assistant} inspect-iso ${isos.${host}} \
          | tee inspect.log
        grep -q "Auto-install:.*enabled" inspect.log
        grep -q "Fetch mode:.*iso$" inspect.log
        grep -q "Embedded answer file" inspect.log
        touch $out
      '';

  checks = lib.listToAttrs (
    lib.concatMap (host: [
      {
        name = "pve-answer-validates-${host}";
        value = answerCheck host;
      }
      {
        name = "pve-iso-is-autoinstall-${host}";
        value = isoCheck host;
      }
    ]) hostNames
  );
in
lib.throwIf (eval.config.assertions != [ ])
  ("pve-autoinstall config invalid: " + lib.concatStringsSep "; " eval.config.assertions)
  {
    inherit (eval) config;
    inherit
      answers
      isos
      answersDir
      isosDir
      checks
      ;
  }
