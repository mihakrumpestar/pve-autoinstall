# Pure validation helpers and patterns for the PVE answer file. Defined once
# here and used by ../modules/schema.nix (option types + assertions); the
# checks mirror what PVE enforces in proxmox-installer-types/src/answer.rs and
# pve-installer/src/utils.rs.
{ lib }:
let
  patterns = {
    # Six colon-separated hex octets.
    mac = "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$";
    # At least two labels (PVE rejects a bare hostname), each 1-63 chars of
    # [A-Za-z0-9-], no leading/trailing dash.
    fqdn = "^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$";
    email = "^[^@ ]+@[^@ ]+$";
    # PVE's interface-name regex is case-insensitive and allows an optional
    # VLAN suffix; Nix has no inline flags, so both cases are spelled out. The
    # 15-character (IFNAMSIZ-1) limit is enforced by an assertion in
    # ../modules/schema.nix, not by this pattern.
    pinningName = "^[A-Za-z][A-Za-z0-9_]{1,20}([:.][0-9]+)?$";
    # Block/partition device names (sda, nvme0n1, ...).
    diskName = "^[A-Za-z0-9][A-Za-z0-9._-]*$";
    # crypt(3) modular hash, e.g. $6$salt$hash or $y$j9T$salt$hash.
    cryptHash = "^\\$[0-9a-z]+\\$([^$]+\\$)+[^$]+$";
    # One printable-ASCII key blob, then a space and an optional comment; no
    # tabs, newlines or other control characters.
    sshKey = "^[!-~]+ [ -~]*$";
    # ISO 3166-1 alpha-2, lowercase (PVE keys its country map by lc(alpha_2)).
    countryCode = "^[a-z]{2}$";
    # Store-path and Nix-attribute safe host key. No dot: PVE sets the hostname
    # from the fqdn's first label, so a dotted key could never match (see
    # firstLabelMatchesHost).
    hostName = "^[A-Za-z0-9][A-Za-z0-9_+-]*$";
  };

  # One dotted-decimal octet: 1-3 digits, no leading zero (except "0"), <= 255.
  isOctet =
    p:
    builtins.match "^[0-9]{1,3}$" p != null && !(lib.hasPrefix "0" p && p != "0") && lib.toInt p <= 255;

  isIpv4 =
    s:
    let
      parts = lib.splitString "." s;
    in
    lib.length parts == 4 && lib.all isOctet parts;

  isCidr =
    s:
    let
      parts = lib.splitString "/" s;
    in
    lib.length parts == 2
    && isIpv4 (lib.elemAt parts 0)
    && builtins.match "^(0|[1-9][0-9]?)$" (lib.elemAt parts 1) != null
    && lib.toInt (lib.elemAt parts 1) <= 32;

  firstLabel = fqdn: lib.head (lib.splitString "." fqdn);
in
{
  inherit patterns;

  inherit isIpv4 isCidr firstLabel;

  isHostName = s: builtins.match patterns.hostName s != null;

  # PVE sets the hostname to the fqdn's first dot-separated label, so the fqdn
  # must have the host key as its first label exactly (not merely as a prefix).
  firstLabelMatchesHost = name: fqdn: (firstLabel fqdn) == name;
}
