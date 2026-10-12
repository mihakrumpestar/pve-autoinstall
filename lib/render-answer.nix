# Render the PVE answer file for one host from the typed configuration
# (see ../modules/schema.nix; the module system validates the values before
# they reach this renderer). Structure mirrors the template in
# /pve/autoinstall.md (single source of truth); keys are kebab-case.
lib: h:
let
  # TOML basic-string escaping. Nix strings cannot contain NUL (U+0000), so
  # the control characters we must handle are U+0001..U+001F and U+007F; TOML
  # gives a short escape to some, the rest become \uXXXX with four uppercase
  # hex digits. This keeps arbitrary user input (passwords, keys, mailto) valid.
  ctrlCodes = lib.range 1 31 ++ [ 127 ];
  ctrlChars = lib.stringToCharacters (
    builtins.fromJSON (
      "\""
      + lib.concatMapStrings (n: "\\u" + lib.fixedWidthString 4 "0" (lib.toHexString n)) ctrlCodes
      + "\""
    )
  );
  escapeControl =
    n:
    if n == 8 then
      "\\b"
    else if n == 9 then
      "\\t"
    else if n == 10 then
      "\\n"
    else if n == 12 then
      "\\f"
    else if n == 13 then
      "\\r"
    else
      "\\u" + lib.fixedWidthString 4 "0" (lib.toUpper (lib.toHexString n));
  escape =
    s:
    builtins.replaceStrings
      (
        ctrlChars
        ++ [
          "\\"
          "\""
        ]
      )
      (
        map escapeControl ctrlCodes
        ++ [
          "\\\\"
          "\\\""
        ]
      )
      s;
  q = s: "\"${escape s}\"";
  qlist = xs: lib.concatMapStringsSep ", " q xs;
  # Pinning mapping keys are /sys/class/net MACs: lowercase, colons kept.
  mac = lib.toLower;
  # PVE matches filter.ID_NET_NAME_MAC against the enx-prefixed udev property
  # (enxaabbccddee01, no separators), so strip the colons from the boot MAC.
  filterMac = builtins.replaceStrings [ ":" ] [ "" ] (mac h.bootMac);
  mappingLines = lib.concatMapStrings (m: "${q (mac m.mac)} = ${q m.name}\n") h.pinning.mappings;
  # With the section present and enabled = true, PVE assigns nic0/nic1/... on
  # its own, so the header is always emitted when pinning is enabled; the
  # mapping table is emitted only when explicit mappings are configured.
  pinningHeader = "\n[network.interface-name-pinning]\nenabled = true\n";
  pinningMapping = "\n[network.interface-name-pinning.mapping]\n" + mappingLines;
  pinningTables =
    lib.optionalString h.pinning.enabled pinningHeader
    + lib.optionalString (h.pinning.enabled && h.pinning.mappings != [ ]) pinningMapping;
  passwordLine =
    if h.rootPasswordHashed != null then
      "root-password-hashed = ${q h.rootPasswordHashed}"
    else
      "root-password = ${q h.rootPassword}";
  sshKeysLine =
    if h.sshKeys == [ ] then "root-ssh-keys = [ ]" else "root-ssh-keys = [ ${qlist h.sshKeys} ]";
  zfsRaidLine = lib.optionalString (h.filesystem == "zfs") "zfs.raid = ${q h.zfsRaid}";
in
''
  [global]
  keyboard = ${q h.keyboard}
  country = ${q h.country}
  fqdn = ${q h.fqdn}
  mailto = ${q h.mailto}
  timezone = ${q h.timezone}
  ${passwordLine}
  ${sshKeysLine}

  [network]
  source = "from-answer"
  cidr = ${q h.cidr}
  dns = ${q h.dns}
  gateway = ${q h.gateway}
  # the installer matches the enx-prefixed MAC property, so the literal
  # MAC goes last and the leading * stays:
  filter.ID_NET_NAME_MAC = ${q ("*" + filterMac)}
  ${pinningTables}
  [disk-setup]
  filesystem = ${q h.filesystem}
  ${zfsRaidLine}
  # per host: keep the intended root disk, confirm the name with
  # proxmox-auto-install-assistant device-info -t disk
  disk-list = [ ${qlist h.diskList} ]
''
