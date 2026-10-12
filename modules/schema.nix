{
  config,
  lib,
  # Locale data comes from tzdata/isocodes; see ../lib/locales.nix.
  locales,
  ...
}:
let
  # Shared validation patterns/helpers; defined once in ../lib/validators.nix
  # so a pattern is never repeated as a literal.
  validators = import ../lib/validators.nix { inherit lib; };
  inherit (validators) patterns;

  # Full-range IPv4 / CIDR option types (PVE parses these as Rust IpAddr/Cidr,
  # which reject leading-zero octets, octets > 255 and prefixes > 32).
  ipv4Type = lib.types.addCheck lib.types.str validators.isIpv4 // {
    name = "IPv4 address";
  };
  cidrType = lib.types.addCheck lib.types.str validators.isCidr // {
    name = "IPv4 CIDR";
  };

  # Minimum disk count per raid level (raid0 has no minimum beyond one disk).
  zfsRaidMinDisks = {
    raid0 = 1;
    raid1 = 2;
    raid10 = 4;
    "raidz-1" = 3;
    "raidz-2" = 4;
    "raidz-3" = 5;
  };
  btrfsRaidMinDisks = {
    raid0 = 1;
    raid1 = 2;
    raid10 = 4;
  };

  # fqdn must be unique across hosts (PVE derives the hostname from it).
  fqdns = map (n: config.hosts.${n}.fqdn) (lib.attrNames config.hosts);
  duplicateFqdns = lib.unique (lib.filter (f: lib.count (x: x == f) fqdns > 1) fqdns);

  # Per-host policy checks; returns the list of assertion messages for one host.
  hostAssertions =
    name: host:
    let
      # One assertion rule: an optional "host <name>: <text>" message.
      fail = cond: text: lib.optional cond "host ${name}: ${text}";
      diskCount = lib.length host.diskList;
      lowerDisks = map lib.toLower host.diskList;
      mappingMacs = map (m: lib.toLower m.mac) host.pinning.mappings;
      # PVE interface names are case-insensitive, so dedupe on the lower form.
      mappingNames = map (m: lib.toLower m.name) host.pinning.mappings;
      # Treat an empty password as unset (the type already rejects an empty
      # hash); exactly one of the two must be set.
      pSet = host.rootPassword != null && host.rootPassword != "";
      hSet = host.rootPasswordHashed != null;
      # Shared min-disk and raid10 parity rules for one raid option.
      raidDiskRules =
        fs: opt: val: minDisks:
        let
          min = if val == null then null else minDisks.${val} or null;
        in
        fail (
          host.filesystem == fs && min != null && diskCount < min
        ) "${opt} '${val}' requires at least ${toString min} disks"
        ++ fail (
          host.filesystem == fs && val == "raid10" && lib.mod diskCount 2 != 0
        ) "${opt} 'raid10' requires an even number of disks";
    in
    fail (!validators.firstLabelMatchesHost name host.fqdn)
      "fqdn '${host.fqdn}' must have '${name}' as its first label (PVE uses the first label as the hostname)"
    # PVE's fqdn parser rejects a purely numeric first label (bugzilla 1054).
    ++ fail (
      builtins.match "[0-9]+" (validators.firstLabel host.fqdn) != null
    ) "fqdn '${host.fqdn}' must not have a purely numeric first label (PVE rejects numeric hostnames)"
    ++ fail (pSet == hSet) "set exactly one of rootPassword or rootPasswordHashed"
    ++ fail (
      pSet && lib.stringLength host.rootPassword < 8
    ) "rootPassword must be at least 8 characters"
    ++ fail (host.diskList == [ ]) "diskList must name the root disk(s)"
    ++ fail (
      lib.length lowerDisks != lib.length (lib.unique lowerDisks)
    ) "diskList contains duplicate entries"
    ++
      lib.concatMap
        (opt: fail (host.${opt} == null) "${opt} is required (PVE has no answer-file default)")
        [
          "keyboard"
          "country"
          "timezone"
        ]
    ++ fail (
      host.timezone != null && !(lib.elem host.timezone locales.timezones)
    ) "timezone '${host.timezone}' is not a valid tzdata zone (use e.g. Europe/Vienna, or UTC)"
    ++ fail (
      host.country != null && !(lib.elem host.country locales.countries)
    ) "country '${host.country}' is not a valid ISO 3166-1 alpha-2 code"
    ++ raidDiskRules "zfs" "zfsRaid" host.zfsRaid zfsRaidMinDisks
    ++ fail (
      host.filesystem == "btrfs" && host.btrfsRaid == null
    ) "btrfsRaid is required when filesystem = btrfs"
    ++ raidDiskRules "btrfs" "btrfsRaid" host.btrfsRaid btrfsRaidMinDisks
    ++ fail (
      (host.filesystem == "ext4" || host.filesystem == "xfs") && diskCount != 1
    ) "filesystem '${host.filesystem}' requires exactly one disk"
    ++ fail (
      host.filesystem != "zfs" && host.zfsRaid != "raid0"
    ) "zfsRaid is only used when filesystem = zfs"
    ++ fail (
      host.filesystem != "btrfs" && host.btrfsRaid != null
    ) "btrfsRaid is only used when filesystem = btrfs"
    ++ fail (
      !host.pinning.enabled && host.pinning.mappings != [ ]
    ) "pinning.mappings is set but pinning is disabled"
    ++ fail (
      host.pinning.enabled
      && host.pinning.mappings != [ ]
      && !(lib.elem (lib.toLower host.bootMac) mappingMacs)
    ) "pinning.mappings must include the boot NIC MAC (${host.bootMac})"
    ++ fail (
      host.pinning.enabled && (lib.length mappingMacs) != (lib.length (lib.unique mappingMacs))
    ) "pinning.mappings has duplicate MACs"
    ++ fail (
      host.pinning.enabled && (lib.length mappingNames) != (lib.length (lib.unique mappingNames))
    ) "pinning.mappings has duplicate names"
    ++ fail (
      host.pinning.enabled && lib.any (m: lib.stringLength m.name > 15) host.pinning.mappings
    ) "pinning.mappings names must be at most 15 characters (IFNAMSIZ-1)"
    ++ fail (
      host.mailto == "mail@example.invalid"
    ) "mailto must not be the PVE placeholder mail@example.invalid";
in
{
  options = {
    hosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            # [global] section, in render order.
            keyboard = lib.mkOption {
              type = lib.types.nullOr (lib.types.enum locales.keyboardLayouts);
              default = null;
              description = "PVE keyboard layout (required; PVE has no answer-file default).";
            };

            country = lib.mkOption {
              # Shape only here; membership is enforced by the assertion
              # against locales.countries.
              type = lib.types.nullOr (lib.types.strMatching validators.patterns.countryCode);
              default = null;
              description = "ISO 3166-1 alpha-2 country code, lowercase (required; PVE has no answer-file default).";
            };

            fqdn = lib.mkOption {
              type = lib.types.strMatching patterns.fqdn;
              description = "Fully qualified domain name (required; PVE rejects a value without a domain part). PVE derives the hostname from its first label and the search domain from the rest, so it must start with the host's key plus a dot (the first label must not be purely numeric).";
            };

            mailto = lib.mkOption {
              type = lib.types.strMatching patterns.email;
              description = "Root mail target (PVE rejects the placeholder mail@example.invalid).";
            };

            timezone = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Canonical tzdata zone, e.g. Europe/Vienna or UTC (required; PVE has no answer-file default).";
            };

            rootPassword = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Plain root password, at least 8 characters. Set exactly one of rootPassword/rootPasswordHashed; reset after deploy for easier management.";
            };

            rootPasswordHashed = lib.mkOption {
              type = lib.types.nullOr (lib.types.strMatching patterns.cryptHash);
              default = null;
              description = "Root password as a crypt hash (mkpasswd -m yescrypt or openssl passwd -6). Set exactly one of rootPassword/rootPasswordHashed.";
            };

            sshKeys = lib.mkOption {
              type = lib.types.listOf (lib.types.strMatching patterns.sshKey);
              default = [ ];
              description = "Public SSH keys added to root's authorized_keys.";
            };

            # [network] section, in render order.
            cidr = lib.mkOption {
              type = cidrType;
              description = "Management NIC static address in CIDR notation.";
            };

            dns = lib.mkOption {
              type = ipv4Type;
              description = "DNS server address.";
            };

            gateway = lib.mkOption {
              type = ipv4Type;
              description = "Gateway address.";
            };

            bootMac = lib.mkOption {
              type = lib.types.strMatching patterns.mac;
              description = "Install/management NIC MAC address; rendered as the filter.ID_NET_NAME_MAC match.";
            };

            # [network.interface-name-pinning] section.
            pinning = lib.mkOption {
              description = "Network interface name pinning. Omit `mappings` for deterministic auto-pinned names (nic0, nic1, ...).";
              default = { };
              type = lib.types.submodule {
                options = {
                  enabled = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Enable interface name pinning.";
                  };

                  mappings = lib.mkOption {
                    type = lib.types.listOf (
                      lib.types.submodule {
                        options = {
                          mac = lib.mkOption {
                            type = lib.types.strMatching patterns.mac;
                            description = "NIC MAC address (normalized to lowercase when rendered).";
                          };

                          name = lib.mkOption {
                            type = lib.types.strMatching patterns.pinningName;
                            description = "Interface name to pin (e.g. lan0), at most 15 characters.";
                          };
                        };
                      }
                    );
                    default = [ ];
                    description = "MAC to name mappings; must include the boot NIC MAC. Putting the boot NIC first is the usual convention.";
                  };
                };
              };
            };

            # [disk-setup] section, in render order.
            filesystem = lib.mkOption {
              type = lib.types.enum [
                "zfs"
                "ext4"
                "xfs"
                "btrfs"
              ];
              default = "zfs";
              description = "Root filesystem.";
            };

            zfsRaid = lib.mkOption {
              type = lib.types.enum (lib.attrNames zfsRaidMinDisks);
              default = "raid0";
              description = "ZFS raid level, serialized lowercase (only used when filesystem = zfs).";
            };

            btrfsRaid = lib.mkOption {
              type = lib.types.nullOr (lib.types.enum (lib.attrNames btrfsRaidMinDisks));
              default = null;
              description = "Btrfs raid level (required when filesystem = btrfs; only used then).";
            };

            diskList = lib.mkOption {
              type = lib.types.listOf (lib.types.strMatching patterns.diskName);
              description = "Target root disks as the installer names them; confirm per host with `proxmox-auto-install-assistant device-info -t disk`.";
              example = [ "sda" ];
            };
          };
        }
      );
      description = "Hosts to install, keyed by host name (used for output naming).";
    };

    assertions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
      default = [ ];
    };
  };

  config = {
    assertions =
      lib.optionals (config.hosts == { }) [
        "at least one host must be defined"
      ]
      ++ map (n: "host ${n}: name must match ${patterns.hostName}") (
        lib.filter (n: !(validators.isHostName n)) (lib.attrNames config.hosts)
      )
      ++ lib.optionals (duplicateFqdns != [ ]) [
        "fqdn must be unique across hosts; duplicated: ${lib.concatStringsSep ", " duplicateFqdns}"
      ]
      ++ lib.concatLists (lib.mapAttrsToList (n: h: hostAssertions n h) config.hosts);
  };
}
