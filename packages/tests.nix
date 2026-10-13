# Non-vacuous flake checks for the schema and renderer, driven by
# ../config/fixtures.nix:
#   - pve-render-golden: exact full-file render comparison per golden fixture.
#   - pve-rejects-<name>: configs that must be rejected, at type level or by a
#     specific assertion message.
#   - pve-host-key-pattern-consistent: the host-key pattern quoted in README.md
#     must be the exact literal lib/validators.nix enforces.
#   - pve-readme-sample-consistent: config/minimal.nix must pass the schema and
#     appear byte-exact in README.md's Quickstart.
#
# Wired in flake.nix as
#   import ./packages/tests.nix { inherit pkgs lib; factory = default; }
# and expected to return { checks }.
{
  pkgs,
  lib,
  factory,
}:
let
  fixtures = import ../config/fixtures.nix;

  # Render the (single) host of a VALID fixture through the real renderer, so
  # defaults are applied exactly as in production.
  renderFixture =
    cfg: factory.renderAnswer (builtins.head (lib.attrValues (factory.validate cfg).config.hosts));

  # Golden render check: exact full-file diff of each fixture's rendered answer
  # against its `expect`. All cases aggregate into ONE derivation so the check
  # name stays `pve-render-golden`.
  golden = pkgs.runCommand "pve-render-golden" { } (
    lib.concatMapStrings (
      c:
      let
        expected = pkgs.writeText "pve-render-golden-${c.name}.expected.toml" c.expect;
        actual = pkgs.writeText "pve-render-golden-${c.name}.actual.toml" (renderFixture c.cfg);
      in
      ''
        if ! diff -u ${expected} ${actual} >&2; then
          echo "pve-render-golden: '${c.name}' rendered output differs from expected (- expected, + actual)" >&2
          exit 1
        fi
      ''
    ) fixtures.golden
    + ''
      echo "pve-render-golden: ${toString (lib.length fixtures.golden)} golden renders match"
      touch $out
    ''
  );

  # Classify a fixture config's rejection. The WHOLE evaluated config is forced
  # under tryEval: option types are lazy, so forcing only `assertions` would
  # never touch unreferenced options (e.g. cidr) and miss their type errors.
  # `type` means a shape/enum/pattern failure threw while forcing; `assertions`
  # carries the plain assertion messages.
  evalOutcome =
    cfg:
    let
      e = factory.evalConfig cfg;
      t = builtins.tryEval (builtins.deepSeq e.config e.config);
    in
    if t.success then
      {
        kind = "assertions";
        value = t.value.assertions;
      }
    else
      { kind = "type"; };

  rejectCheck =
    c:
    let
      outcome = evalOutcome c.cfg;
    in
    pkgs.runCommand "pve-rejects-${c.name}" { } (
      if outcome.kind == "type" then
        if c.expect == null then
          "touch $out"
        else
          ''
            echo "pve-rejects-${c.name}: expected assertion '${c.expect}' but the config was rejected at type level" >&2
            exit 1
          ''
      else if outcome.value == [ ] then
        ''
          echo "pve-rejects-${c.name}: config was accepted but should be rejected" >&2
          exit 1
        ''
      else if c.expect == null then
        ''
          echo "pve-rejects-${c.name}: expected a type-level rejection but got assertions: ${lib.concatStringsSep "; " outcome.value}" >&2
          exit 1
        ''
      else if lib.hasInfix c.expect (lib.concatStringsSep "; " outcome.value) then
        "touch $out"
      else
        ''
          echo "pve-rejects-${c.name}: expected assertion '${c.expect}' but got: ${lib.concatStringsSep "; " outcome.value}" >&2
          exit 1
        ''
    );

  # Docs drift check on the host-key pattern: README.md must quote the exact
  # literal lib/validators.nix enforces (patterns.hostName). Plain string
  # matching, no parsing.
  hostKeyPattern = "^[A-Za-z0-9][A-Za-z0-9_+-]*$";
  hostKeyPatternConsistent =
    pkgs.runCommand "pve-host-key-pattern-consistent"
      {
        readme = ../README.md;
        validators = ../lib/validators.nix;
      }
      ''
        if ! grep -qF -- '${hostKeyPattern}' "$readme"; then
          echo "pve-host-key-pattern-consistent: README.md does not quote the host-key pattern '${hostKeyPattern}'" >&2
          exit 1
        fi
        if ! grep -qF -- '${hostKeyPattern}' "$validators"; then
          echo "pve-host-key-pattern-consistent: lib/validators.nix does not contain the host-key pattern '${hostKeyPattern}'" >&2
          exit 1
        fi
        touch $out
      '';

  # Docs consistency on the Quickstart sample: config/minimal.nix must pass the
  # schema (forcing the evaluated config turns a failure into an eval error)
  # and appear in README.md byte-exact, so the documented sample cannot drift.
  sampleConfig = builtins.deepSeq (factory.validate (import ../config/minimal.nix)).config "valid";
  readmeSampleConsistent =
    pkgs.runCommand "pve-readme-sample-consistent"
      {
        readme = ../README.md;
        sample = ../config/minimal.nix;
        inherit sampleConfig;
      }
      ''
        awk '/^```nix config\/minimal\.nix$/ {f=1; next} f && /^```$/ {exit} f' "$readme" > extracted
        if ! diff -u "$sample" extracted >&2; then
          echo "pve-readme-sample-consistent: the README Quickstart sample differs from config/minimal.nix" >&2
          exit 1
        fi
        echo "pve-readme-sample-consistent: sample config is $sampleConfig and matches the README"
        touch $out
      '';
in
{
  checks = {
    pve-render-golden = golden;
    pve-host-key-pattern-consistent = hostKeyPatternConsistent;
    pve-readme-sample-consistent = readmeSampleConsistent;
  }
  // (lib.listToAttrs (
    map (c: lib.nameValuePair "pve-rejects-${c.name}" (rejectCheck c)) fixtures.reject
  ));
}
