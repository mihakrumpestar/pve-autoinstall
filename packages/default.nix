# pve-autoinstall builder: evaluates a host configuration against the typed
# module (../modules/schema.nix self-validates values and asserts the policy
# rules), then produces per-host answer files, prepared ISOs, bundle dirs and
# PVE-tool checks.
#
# Non-vacuous render/reject flake checks live in ./tests.nix so this factory
# stays focused on building artifacts; the flake wires both together.
{
  pkgs,
  lib,
  pveIso,
  srcIso,
  # Module: path to a config file or an attrset; see ../config/example.nix for
  # the shape and ../modules/schema.nix for options. Defaults to the committed
  # example config (why: see the comment in flake.nix).
  config ? ../config/example.nix,
}:
let
  # Evaluating a config module against the schema, kept in one place.
  evalConfig =
    cfg:
    lib.evalModules {
      specialArgs = {
        # Locale value sets (keyboard/country/timezone) derived from the same
        # sources PVE uses, so bad values fail here at evaluation.
        locales = import ../lib/locales.nix { inherit pkgs lib; };
      };
      modules = [
        ../modules/schema.nix
        cfg
      ];
    };

  # Evaluate `cfg` and throw the aggregated assertion messages if invalid.
  # Used by the main path and by the build-time rejection checks.
  validate =
    cfg:
    let
      e = evalConfig cfg;
    in
    lib.throwIf (e.config.assertions != [ ]) (
      "pve-autoinstall config invalid: " + lib.concatStringsSep "; " e.config.assertions
    ) e;

  eval = validate config;

  hosts = eval.config.hosts;
  renderAnswer = import ../lib/render-answer.nix lib;
  answerFile = name: h: pkgs.writeText "pve-answer-${name}.toml" (renderAnswer h);

  answers = lib.mapAttrs answerFile hosts;
  isos = lib.mapAttrs (
    name: h:
    pkgs.runCommand "proxmox-ve_${pveIso.version}-autoinstall-${name}.iso"
      {
        nativeBuildInputs = with pkgs; [
          proxmox-auto-install-assistant
          xorriso
        ];
        # Best-effort determinism; xorriso/prepare-iso may still embed
        # timestamps in the generated ISO.
        SOURCE_DATE_EPOCH = "0";
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

  # Validate rendered answers and built ISOs with the PVE-supplied tools.
  assistant = lib.getExe pkgs.proxmox-auto-install-assistant;

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
    pkgs.runCommand "${isoCheckPrefix}${host}" { } ''
      ${assistant} inspect-iso ${isos.${host}} \
        | tee inspect.log
      grep -q "Auto-install:.*enabled" inspect.log
      grep -q "Fetch mode:.*iso$" inspect.log
      grep -q "Embedded answer file" inspect.log
      touch $out
    '';

  # Per-host check-name contract: one prefix per check kind, kept in one place.
  answerCheckPrefix = "pve-answer-validates-";
  isoCheckPrefix = "pve-iso-is-autoinstall-";

  # Build only the checks `mode` requests, straight from the constructors
  # above: "answers" builds validate-answer checks only, "isos" only
  # inspect-iso checks, anything else ("all") both.
  checksForMode =
    hosts: mode:
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
      ) hosts
    );

  # Both check kinds per host; the documented `checksForHosts` API, built from
  # the same constructor as selectChecks.
  checksForHosts = hosts: checksForMode hosts "all";

  # Subset of the per-host checks matching what a caller built: "answers"
  # keeps only validate-answer checks, "isos" only inspect-iso checks, "all"
  # keeps everything. Lets the CLI avoid forcing artifacts it did not build.
  selectChecks =
    {
      hosts ? hostNames,
      mode ? "all",
    }:
    checksForMode hosts mode;

  # Per-host checks only; the render/reject checks live in ./tests.nix.
  checks = checksForHosts hostNames;
in
{
  inherit (eval) config;
  inherit
    answers
    isos
    answersDir
    isosDir
    checks
    checksForHosts
    selectChecks
    evalConfig
    validate
    renderAnswer
    ;
}
