{
  config,
  lib,
  # Locale value sets (keyboard/country/timezone) derived from the sources PVE
  # itself uses; supplied by ../packages/default.nix so this module stays free
  # of nixpkgs coupling.
  locales,
  ...
}:
let
  # Shared validation patterns; single source of truth for the option types
  # below so a pattern is never repeated as a literal.
  macPattern = "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$";
  ipv4Pattern = "^[0-9]{1,3}(\\.[0-9]{1,3}){3}$";
  cidrPattern = "^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$";
  # At least two labels (PVE rejects a bare hostname), each 1-63 chars of
  # [A-Za-z0-9-], no leading/trailing dash.
  fqdnPattern = "^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$";
  emailPattern = "^[^@ ]+@[^@ ]+$";
  # PVE interface names are lowercase, start with a letter, 2-21 chars of
  # [a-z0-9_].
  pinningNamePattern = "^[a-z][a-z0-9_]{1,20}$";

  # Minimum disk count per ZFS raid level (raid0 has no minimum).
  zfsRaidMinDisks = {
    raid1 = 2;
    raid10 = 4;
    "raidz-1" = 3;
    "raidz-2" = 4;
    "raidz-3" = 5;
  };

  # Per-host policy checks; returns the list of assertion messages for one host.
  hostAssertions =
    name: host:
    let
      minDisks = zfsRaidMinDisks.${host.zfsRaid} or null;
      mappingMacs = map (m: lib.toLower m.mac) host.pinning.mappings;
      mappingNames = map (m: m.name) host.pinning.mappings;
    in
    lib.optionals ((host.rootPassword == null) == (host.rootPasswordHashed == null)) [
      "host ${name}: set exactly one of rootPassword or rootPasswordHashed"
    ]
    ++ lib.optionals (host.diskList == [ ]) [
      "host ${name}: diskList must name the root disk(s)"
    ]
    ++ lib.optionals ((lib.length host.diskList) != (lib.length (lib.unique host.diskList))) [
      "host ${name}: diskList contains duplicate entries"
    ]
    ++ map (opt: "host ${name}: ${opt} is required (PVE has no answer-file default)") (
      lib.filter (opt: host.${opt} == null) [
        "keyboard"
        "country"
        "timezone"
      ]
    )
    ++ lib.optionals (host.timezone != null && !(lib.elem host.timezone locales.timezones)) [
      "host ${name}: timezone '${host.timezone}' is not a valid tzdata zone (use e.g. Europe/Vienna, or UTC)"
    ]
    ++
      lib.optionals
        (host.filesystem == "zfs" && minDisks != null && (lib.length host.diskList) < minDisks)
        [
          "host ${name}: zfsRaid '${host.zfsRaid}' requires at least ${toString minDisks} disks"
        ]
    ++ lib.optionals (host.filesystem != "zfs" && host.zfsRaid != "raid0") [
      "host ${name}: zfsRaid is only used when filesystem = zfs"
    ]
    ++
      lib.optionals
        (
          host.pinning.enabled
          && host.pinning.mappings != [ ]
          && !(lib.elem (lib.toLower host.bootMac) mappingMacs)
        )
        [
          "host ${name}: pinning.mappings must include the boot NIC MAC (${host.bootMac})"
        ]
    ++ lib.optionals ((lib.length mappingMacs) != (lib.length (lib.unique mappingMacs))) [
      "host ${name}: pinning.mappings has duplicate MACs"
    ]
    ++ lib.optionals ((lib.length mappingNames) != (lib.length (lib.unique mappingNames))) [
      "host ${name}: pinning.mappings has duplicate names"
    ];
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
              type = lib.types.nullOr (lib.types.strMatching locales.countryPattern);
              default = null;
              description = "ISO 3166-1 alpha-2 country code, lowercase (required; PVE has no answer-file default).";
            };

            fqdn = lib.mkOption {
              type = lib.types.strMatching fqdnPattern;
              description = "Fully qualified domain name (required; PVE rejects a value without a domain part). PVE derives the hostname from its first label and the search domain from the rest, so it must start with the host's key plus a dot.";
            };

            mailto = lib.mkOption {
              type = lib.types.strMatching emailPattern;
              description = "Root mail target.";
            };

            timezone = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Canonical tzdata zone, e.g. Europe/Vienna or UTC (required; PVE has no answer-file default).";
            };

            rootPassword = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Plain root password. Set exactly one of rootPassword/rootPasswordHashed; reset after deploy for easier management.";
            };

            rootPasswordHashed = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Root password as a crypt hash (mkpasswd -m yescrypt or openssl passwd -6). Set exactly one of rootPassword/rootPasswordHashed.";
            };

            sshKeys = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Public SSH keys added to root's authorized_keys.";
            };

            # [network] section, in render order.
            cidr = lib.mkOption {
              type = lib.types.strMatching cidrPattern;
              description = "Management NIC static address in CIDR notation.";
            };

            dns = lib.mkOption {
              type = lib.types.strMatching ipv4Pattern;
              description = "DNS server address.";
            };

            gateway = lib.mkOption {
              type = lib.types.strMatching ipv4Pattern;
              description = "Gateway address.";
            };

            bootMac = lib.mkOption {
              type = lib.types.strMatching macPattern;
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
                            type = lib.types.strMatching macPattern;
                            description = "NIC MAC address (normalized to lowercase when rendered).";
                          };

                          name = lib.mkOption {
                            type = lib.types.strMatching pinningNamePattern;
                            description = "Interface name to pin (e.g. lan0).";
                          };
                        };
                      }
                    );
                    default = [ ];
                    description = "MAC to name mappings. The first entry should be the boot NIC.";
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
              type = lib.types.enum [
                "raid0"
                "raid1"
                "raid10"
                "raidz-1"
                "raidz-2"
                "raidz-3"
              ];
              default = "raid0";
              description = "ZFS raid level, serialized lowercase (only used when filesystem = zfs).";
            };

            diskList = lib.mkOption {
              type = lib.types.listOf lib.types.str;
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
      ++ lib.concatLists (lib.mapAttrsToList (n: h: hostAssertions n h) config.hosts);
  };
}
