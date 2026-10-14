# Non-vacuous flake checks for the schema and renderer, driven by
# ../config/fixtures.nix:
#   - pve-render-golden: exact full-file render comparison per golden fixture.
#   - pve-rejects-<name>: configs that must be rejected, at type level or by a
#     specific assertion message.
#   - pve-host-key-pattern-consistent: the host-key pattern quoted in README.md
#     must be the exact literal lib/validators.nix enforces.
#   - pve-readme-sample-consistent: config/minimal.nix must pass the schema and
#     appear byte-exact in README.md's Quickstart.
{
  pkgs,
  lib,
}:
let
  fixtures = import ../config/fixtures.nix;
  inherit (import ../lib/eval-config.nix { inherit pkgs lib; }) evalConfig validate;
  renderAnswer = import ../lib/render-answer.nix lib;

  # Render the (single) host of a VALID fixture through the real renderer, so
  # defaults are applied exactly as in production.
  renderFixture =
    cfg: renderAnswer (builtins.head (lib.attrValues (validate (evalConfig cfg)).config.hosts));

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

  # Classify what a fixture config did. The WHOLE evaluated config is forced
  # under tryEval: option types are lazy, so forcing only `assertions` would
  # never touch unreferenced options (e.g. cidr) and miss their type errors.
  # `type` means a shape/enum/pattern failure threw while forcing; `accepted`
  # means nothing to report; `assertions` carries the plain messages.
  evalOutcome =
    cfg:
    let
      e = evalConfig cfg;
      t = builtins.tryEval (builtins.deepSeq e.config e.config);
    in
    if !t.success then
      {
        kind = "type";
        messages = "";
      }
    else
      {
        kind = if t.value.assertions == [ ] then "accepted" else "assertions";
        messages = lib.concatStringsSep "; " t.value.assertions;
      };

  # One decision per fixture: `c.expect` is null when a type-level rejection
  # is required, else a substring the assertion message must contain.
  rejectCheck =
    c:
    let
      outcome = evalOutcome c.cfg;
      want = if c.expect == null then "a type-level rejection" else "assertion containing '${c.expect}'";
      got =
        if outcome.kind == "type" then
          "rejected at type level"
        else if outcome.kind == "accepted" then
          "the config was accepted"
        else
          "assertions: ${outcome.messages}";
      ok =
        if c.expect == null then
          outcome.kind == "type"
        else
          outcome.kind == "assertions" && lib.hasInfix c.expect outcome.messages;
    in
    pkgs.runCommand "pve-rejects-${c.name}" { } (
      if ok then
        "touch $out"
      else
        ''
          echo "pve-rejects-${c.name}: expected ${want}, got ${got}" >&2
          exit 1
        ''
    );

  # Docs drift check on the host-key pattern: README.md must quote the exact
  # literal lib/validators.nix enforces (patterns.hostName, imported here so
  # the check cannot drift from the enforced pattern). Plain string matching,
  # no parsing.
  hostKeyPattern = (import ../lib/validators.nix { inherit lib; }).patterns.hostName;
  hostKeyPatternConsistent =
    pkgs.runCommand "pve-host-key-pattern-consistent" { readme = ../README.md; }
      ''
        if ! grep -qF -- '${hostKeyPattern}' "$readme"; then
          echo "pve-host-key-pattern-consistent: README.md does not quote the host-key pattern '${hostKeyPattern}'" >&2
          exit 1
        fi
        touch $out
      '';

  # Docs consistency on the Quickstart sample: config/minimal.nix must pass the
  # schema (forcing the evaluated config turns a failure into an eval error)
  # and appear in README.md byte-exact, so the documented sample cannot drift.
  sampleConfig = builtins.deepSeq (validate (evalConfig (import ../config/minimal.nix))).config "valid";
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
