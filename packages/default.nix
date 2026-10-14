# pve-autoinstall builder: evaluates a host configuration against the typed
# module (../modules/schema.nix self-validates values and asserts the policy
# rules), then produces per-host answer files, prepared ISOs, bundle dirs and
# PVE-tool checks.
{
  pkgs,
  lib,
  pveIso,
  # Module: path to a config file or an attrset; see ../config/example.nix
  # for the shape and ../modules/schema.nix for the options.
  config,
}:
let
  inherit (import ../lib/eval-config.nix { inherit pkgs lib; }) evalConfig validate;

  eval = validate (evalConfig config);

  hosts = eval.config.hosts;
  renderAnswer = import ../lib/render-answer.nix lib;
  answerFile = name: h: pkgs.writeText "pve-answer-${name}.toml" (renderAnswer h);

  answers = lib.mapAttrs answerFile hosts;

  # Assistant decision point: proxmox-auto-install-assistant is always the
  # NATIVE (build-platform) one, for prepare-iso and the checks alike.
  # prepare-iso is arch-agnostic toward its input ISO (source-verified: pure
  # xorriso ISO9660 file injection, sole precondition is the ISO's
  # /auto-installer-capable marker), so a native build prepares any target
  # ISO and needs no cross toolchain; the host's `arch` only selects the
  # source ISO. The assistant shells out to xorriso for its ISO reads
  # (prepare-iso and inspect-iso alike), so the two tools travel together
  # wherever the assistant runs.
  assistantTools = [
    pkgs.proxmox-auto-install-assistant
    pkgs.xorriso
  ];
  assistant = lib.getExe pkgs.proxmox-auto-install-assistant;

  # Per-host source ISO, selected by the host's install-target arch pin.
  srcIsoFor =
    arch:
    pkgs.fetchurl {
      url = pveIso.urlFor arch;
      hash = pveIso.hashFor arch;
    };

  isos = lib.mapAttrs (
    name: h:
    # Output name mirrors the arch's source ISO name.
    pkgs.runCommand
      "proxmox-ve_${pveIso.version}${pveIso.arches.${h.arch}.suffix}-autoinstall-${name}.iso"
      {
        nativeBuildInputs = assistantTools;
        # Best-effort determinism; xorriso/prepare-iso may still embed
        # timestamps in the generated ISO.
        SOURCE_DATE_EPOCH = "0";
      }
      ''
        export TMPDIR=$NIX_BUILD_TOP/tmp
        mkdir -p "$TMPDIR"
        # prepare-iso writes its working copy next to the source
        # ISO (read-only in the store), so run it on a local copy
        cp ${srcIsoFor h.arch} src.iso
        chmod u+w src.iso
        proxmox-auto-install-assistant prepare-iso \
          src.iso \
          --fetch-from iso \
          --answer-file ${answerFile name h} \
          --output $out
      ''
  ) hosts;

  hostNames = lib.attrNames hosts;

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

  # Per-host check-name contract: one prefix per check kind, kept in one place.
  answerCheckPrefix = "pve-answer-validates-";
  isoCheckPrefix = "pve-iso-is-autoinstall-";

  # Validate rendered answers and built ISOs with the PVE-supplied tools.
  answerCheck =
    host:
    pkgs.runCommand "${answerCheckPrefix}${host}" { } ''
      # validate-answer returns rc 0 even on issues, so the check relies on
      # the "parsed successfully" line; pipefail makes a hard tool failure
      # (bad invocation) fail the check too.
      set -o pipefail
      ${assistant} validate-answer ${answers.${host}} \
        | tee validate.log | grep -q "parsed successfully"
      touch $out
    '';

  isoCheck =
    host:
    pkgs.runCommand "${isoCheckPrefix}${host}" { nativeBuildInputs = assistantTools; } ''
      ${assistant} inspect-iso ${isos.${host}} \
        | tee inspect.log
      grep -q "Auto-install:.*enabled" inspect.log
      grep -q "Fetch mode:.*iso$" inspect.log
      grep -q "Embedded answer file" inspect.log
      touch $out
    '';

  # Per-host checks from the constructors above: "answers" builds
  # validate-answer checks only, "isos" only inspect-iso checks, anything
  # else ("all") both. Lets a caller (the CLI) build just the checks matching
  # the artifacts it built.
  checksFor =
    {
      hostList ? hostNames,
      mode ? "all",
    }:
    lib.listToAttrs (
      lib.concatMap (
        host:
        lib.optional (mode != "isos") {
          name = "${answerCheckPrefix}${host}";
          value = answerCheck host;
        }
        ++ lib.optional (mode != "answers") {
          name = "${isoCheckPrefix}${host}";
          value = isoCheck host;
        }
      ) hostList
    );

  # Per-host checks only; the render/reject checks live in ./tests.nix.
  checks = checksFor { };
in
{
  inherit
    answers
    isos
    answersDir
    isosDir
    checks
    checksFor
    ;
}
