# Render the PVE answer file for one host from the typed configuration
# (see ../modules/schema.nix; the module system validates the values before
# they reach this renderer). Structure mirrors the template in
# /pve/autoinstall.md (single source of truth); keys are kebab-case.
lib: h:
let
  escape = s: builtins.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] s;
  q = s: "\"${escape s}\"";
  qlist = xs: lib.concatMapStringsSep ", " q xs;
  # udev MAC properties (ID_NET_NAME_MAC etc.) use lowercase hex;
  # normalize here regardless of how the config spells the MACs.
  mac = lib.toLower;
  mappingLines = lib.concatMapStrings (m: "${q (mac m.mac)} = ${q m.name}\n") h.pinning.mappings;
  pinningTables = lib.optionalString (h.pinning.enabled && h.pinning.mappings != [ ]) ''

    [network.interface-name-pinning]
    enabled = true

    [network.interface-name-pinning.mapping]
    ${mappingLines}'';
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
  filter.ID_NET_NAME_MAC = ${q ("*" + mac h.bootMac)}
  ${pinningTables}
  [disk-setup]
  filesystem = ${q h.filesystem}
  ${zfsRaidLine}
  # per host: keep the intended root disk, confirm the name with
  # proxmox-auto-install-assistant device-info -t disk
  disk-list = [ ${qlist h.diskList} ]
''
