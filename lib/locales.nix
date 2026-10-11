# Locale value sets accepted by the PVE answer file, derived from the same
# sources PVE itself uses, so ../modules/schema.nix can reject bad values at
# evaluation instead of only at the PVE validate-answer/inspect-iso check.
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
in
{
  # KeyboardLayout enum variants, serialized kebab-case (source order).
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

  # ISO 3166-1 alpha-2, lowercased (PVE's COUNTRY_CODE_REGEX / iso-codes keys).
  countryPattern = "^[a-z]{2}$";

  inherit timezones;
}
