# pve-autoinstall builder: evaluates a host configuration against the typed
# module (../modules/schema.nix self-validates values and asserts the policy
# rules), then produces per-host answer files, prepared ISOs, bundle dirs and
# PVE-tool checks.
#
# It also exposes non-vacuous flake checks (a golden render assertion plus
# build-time rejection cases) driven by ../config/fixtures.nix, so schema and
# renderer regressions fail `nix flake check` instead of shipping silently.
{
  pkgs,
  lib,
  pveIso,
  srcIso,
  # Module: path to a config file or an attrset; see ../config/example.nix
  # for the shape and ../modules/schema.nix for options. The default is the
  # committed example config: the flake's `packages`/`checks` always build
  # that example because config/default.nix is gitignored and therefore never
  # part of the flake source. A real config is supplied via the CLI
  # (`nix run . -- <config.nix>`) or by a consumer calling
  # `lib.mkPve { config = ...; }`.
  config ? ../config/example.nix,
}:
let
  # Single source of truth for evaluating a config module against the schema.
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
  # Used by the main path and by the build-time rejection checks below.
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
    pkgs.runCommand "pve-answer-validates-${host}" { } ''
      ${assistant} validate-answer ${answers.${host}} \
        | tee validate.log | grep -q "parsed successfully"
      touch $out
    '';

  isoCheck =
    host:
    pkgs.runCommand "pve-iso-is-autoinstall-${host}"
      {
        # Only runs `inspect-iso`; xorriso is needed solely to build an ISO.
        nativeBuildInputs = with pkgs; [
          proxmox-auto-install-assistant
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

  # Single source of truth for the per-host check-name contract
  # (`pve-answer-validates-<host>` / `pve-iso-is-autoinstall-<host>`); exposed
  # so consumers such as the CLI never hardcode those names.
  checksForHosts =
    hostNames:
    lib.listToAttrs (
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

  fixtures = import ../config/fixtures.nix;

  # Render every host of a VALID fixture config through the real renderer, so
  # defaults are applied exactly as in production.
  renderFixture = cfg: map renderAnswer (lib.attrValues (validate cfg).config.hosts);

  # Shell snippets asserting a literal line is present/absent in a file.
  # escapeShellArg keeps the exact rendered bytes (quotes, backslashes) intact.
  assertPresent =
    file: line:
    "grep -qF -- ${lib.escapeShellArg line} ${file} || { echo ${lib.escapeShellArg "pve-render-golden: MISSING expected line: ${line}"} >&2; exit 1; }\n";
  assertAbsent =
    file: line:
    "if grep -qF -- ${lib.escapeShellArg line} ${file}; then echo ${lib.escapeShellArg "pve-render-golden: FORBIDDEN line present: ${line}"} >&2; exit 1; fi\n";

  # Golden render check: exact rendered TOML lines for representative valid
  # fixtures (pinning, TOML escaping, zfs/ext4, hashed password).
  golden = pkgs.runCommand "pve-render-golden" { } (
    lib.concatMapStrings (
      c:
      let
        file = pkgs.writeText "pve-render-golden-${c.name}.toml" (builtins.head (renderFixture c.cfg));
      in
      lib.concatMapStrings (l: assertPresent file l) c.present
      + lib.concatMapStrings (l: assertAbsent file l) c.absent
    ) fixtures.golden
    + ''
      echo "pve-render-golden: all golden render assertions passed"
      touch $out
    ''
  );

  # Rejection checks run at build time: `validate` is wrapped in tryEval, so a
  # fixture that should be rejected produces a failing derivation (not an
  # evaluation error), and one wrongly accepted makes the build fail loudly.
  rejects =
    name: cfg:
    pkgs.runCommand "pve-rejects-${name}" { } (
      if (builtins.tryEval (builtins.deepSeq (validate cfg).config true)).success then
        ''
          echo 'ERROR: config "${name}" was accepted but should be rejected' >&2
          exit 1
        ''
      else
        "touch $out"
    );

  checks =
    checksForHosts hostNames
    // {
      pve-render-golden = golden;
    }
    // (lib.listToAttrs (
      map (c: lib.nameValuePair "pve-rejects-${c.name}" (rejects c.name c.cfg)) fixtures.reject
    ));
in
{
  inherit (eval) config;
  # `lib` is exposed so consumers (the CLI) can filter the checks.
  inherit lib;
  inherit
    answers
    isos
    answersDir
    isosDir
    checks
    checksForHosts
    ;
}
