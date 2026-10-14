# One schema-eval entry point for every consumer: the builder
# (../packages/default.nix) and the checks (../packages/tests.nix). The
# locales wiring and the validation policy live here so they exist once.
{
  pkgs,
  lib,
}:
let
  # Locale value sets (keyboard/country/timezone) derived from the same
  # sources PVE uses, so bad values fail here at evaluation.
  locales = import ./locales.nix { inherit pkgs lib; };
in
{
  # Evaluating a config module against the schema.
  evalConfig =
    cfg:
    lib.evalModules {
      specialArgs = { inherit locales; };
      modules = [
        ../modules/schema.nix
        cfg
      ];
    };

  # Throw the aggregated assertion messages of an evaluated config if any
  # failed, else return it unchanged.
  validate =
    e:
    lib.throwIf (e.config.assertions != [ ]) (
      "pve-autoinstall config invalid: " + lib.concatStringsSep "; " e.config.assertions
    ) e;
}
