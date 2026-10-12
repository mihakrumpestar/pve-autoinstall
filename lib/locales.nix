# Locale value sets (keyboard/country/timezone) accepted by the PVE answer
# file, derived from the same sources PVE itself uses, so
# ../modules/schema.nix can reject bad values at evaluation instead of only at
# the PVE validate-answer/inspect-iso check. Built by ../packages/default.nix
# from pkgs.tzdata and pkgs.isocodes, so consumers stay free of nixpkgs
# coupling.
#
# Mirrors proxmox-installer-types (proxmox.git, src/answer.rs) and the locale
# generator in pve-installer (country.pl + proxmox-auto-installer/src/utils.rs
# verify_locale_settings).
{ pkgs, lib }:
let
  # PVE's parse_zoneinfo reads tzdata's zone.tab and only keeps zones of the
  # form "Area/Location" (its regex requires a "/"); verify_locale_settings
  # then special-cases the literal "UTC".
  zoneTab = builtins.readFile "${pkgs.tzdata}/share/zoneinfo/zone.tab";
  zoneOf =
    line:
    let
      fields = lib.splitString "\t" line;
    in
    lib.optional (lib.length fields >= 3) (lib.elemAt fields 2);
  dataLines = lib.filter (l: l != "" && !(lib.hasPrefix "#" l)) (lib.splitString "\n" zoneTab);
  timezones =
    lib.unique (lib.filter (z: z != "" && lib.hasInfix "/" z) (lib.concatMap zoneOf dataLines))
    ++ [ "UTC" ];

  # PVE generates its country map from iso-codes, keyed by lc(alpha_2), so the
  # valid set is exactly the alpha_2 codes of iso_3166-1, lowercased.
  iso3166 = builtins.fromJSON (
    builtins.readFile "${pkgs.isocodes}/share/iso-codes/json/iso_3166-1.json"
  );
  countries = lib.unique (map (c: lib.toLower c.alpha_2) iso3166."3166-1");
in
{
  # KeyboardLayout enum variants, serialized kebab-case (source order).
  # Mirrors proxmox-installer-types KeyboardLayout.
  keyboardLayouts = [
    "de"
    "de-ch"
    "dk"
    "en-gb"
    "en-us"
    "es"
    "fi"
    "fr"
    "fr-be"
    "fr-ca"
    "fr-ch"
    "hu"
    "is"
    "it"
    "jp"
    "lt"
    "mk"
    "nl"
    "no"
    "pl"
    "pt"
    "pt-br"
    "se"
    "si"
    "tr"
  ];

  inherit countries timezones;
}
