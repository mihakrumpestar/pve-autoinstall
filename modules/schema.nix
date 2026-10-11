{
  config,
  lib,
  # Locale value sets (keyboard/country/timezone) derived from the sources PVE
  # itself uses; supplied by ../packages/default.nix so this module stays free
  # of nixpkgs coupling.
  locales,
  ...
}:
{
  options = {
    hosts = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            # Host identity; not rendered into the TOML, used for output naming.
            name = lib.mkOption {
              type = lib.types.strMatching "^[a-z][a-z0-9-]*$";
              description = "Short host name (e.g. pve01); used for output naming.";
            };

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

            timezone = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Canonical tzdata zone, e.g. Europe/Vienna or UTC (required; PVE has no answer-file default).";
            };

            fqdn = lib.mkOption {
              type = lib.types.str;
              description = "Fully qualified domain name. The domain part becomes the search domain.";
            };

            mailto = lib.mkOption {
              type = lib.types.strMatching "^[^@ ]+@[^@ ]+$";
              description = "Root mail target.";
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
              type = lib.types.strMatching "^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$";
              description = "Management NIC static address in CIDR notation.";
            };

            dns = lib.mkOption {
              type = lib.types.strMatching "^[0-9]{1,3}(\\.[0-9]{1,3}){3}$";
              description = "DNS server address.";
            };

            gateway = lib.mkOption {
              type = lib.types.strMatching "^[0-9]{1,3}(\\.[0-9]{1,3}){3}$";
              description = "Gateway address.";
            };

            bootMac = lib.mkOption {
              type = lib.types.strMatching "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$";
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
                            type = lib.types.strMatching "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$";
                            description = "NIC MAC address (normalized to lowercase when rendered).";
                          };

                          name = lib.mkOption {
                            type = lib.types.str;
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
                "single"
                "mirror"
                "raid0"
                "raid1"
                "raid10"
                "raidz1"
                "raidz2"
                "raidz3"
              ];
              default = "raid0";
              description = "ZFS raid level (only used when filesystem = zfs).";
            };

            diskList = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Target root disks as the installer names them; confirm per host with `proxmox-auto-install-assistant device-info -t disk`.";
              example = [ "sda" ];
            };
          };
        }
      );
      description = "One entry per host to install.";
    };

    assertions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
      default = [ ];
    };
  };

  config = {
    assertions =
      lib.concatMap (
        host:
        lib.optionals ((host.rootPassword == null) == (host.rootPasswordHashed == null)) [
          "host ${host.name}: set exactly one of rootPassword or rootPasswordHashed"
        ]
        ++ lib.optionals (host.diskList == [ ]) [
          "host ${host.name}: diskList must name the root disk(s)"
        ]
        ++ map (opt: "host ${host.name}: ${opt} is required (PVE has no answer-file default)") (
          lib.filter (opt: host.${opt} == null) [
            "keyboard"
            "country"
            "timezone"
          ]
        )
        ++ lib.optionals (host.timezone != null && !(lib.elem host.timezone locales.timezones)) [
          "host ${host.name}: timezone '${host.timezone}' is not a valid tzdata zone (use e.g. Europe/Vienna, or UTC)"
        ]
      ) config.hosts
      ++ (
        let
          names = map (h: h.name) config.hosts;
        in
        lib.optionals ((lib.length names) != (lib.length (lib.unique names))) [
          "host names must be unique"
        ]
      );
  };
}
