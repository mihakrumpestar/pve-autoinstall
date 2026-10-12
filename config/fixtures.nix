# Deterministic fixtures for the non-vacuous flake checks in
# ../packages/default.nix (pve-render-golden and pve-rejects-*). Plain data
# (no lib) so both the schema module and the renderer consume them unchanged.
#
# `golden`: VALID single-host configs; their rendered answer must contain every
#           line in `present` and none of the lines in `absent`.
# `reject`: configs that MUST fail validation; each comment names the rule it
#           exercises so a failure points straight at the missing assertion.
let
  # Baseline valid host. Fixtures override only the field under test.
  baseHost = {
    keyboard = "en-us";
    country = "us";
    timezone = "UTC";
    fqdn = "pve01.example.tld";
    cidr = "192.168.10.11/24";
    dns = "192.168.10.1";
    gateway = "192.168.10.1";
    bootMac = "AA:BB:CC:DD:EE:01";
    mailto = "admin@example.tld";
    rootPassword = "changeme";
    diskList = [ "sda" ];
  };

  # Wrap a host into a full (single-host) config module.
  configWith = host: {
    hosts = {
      pve01 = host;
    };
  };

  # A valid config differing from the baseline only by `overrides`.
  withHost = overrides: configWith (baseHost // overrides);
in
{
  golden = [
    {
      name = "pinning-mapping";
      # Boot MAC is upper-case in config; the renderer must de-colonize and
      # lower-case it into the udev filter key and emit the pinning section.
      cfg = withHost {
        pinning = {
          enabled = true;
          mappings = [
            {
              mac = "AA:BB:CC:DD:EE:01";
              name = "lan0";
            }
            {
              mac = "AA:BB:CC:DD:EE:02";
              name = "lan1";
            }
          ];
        };
      };
      present = [
        "filter.ID_NET_NAME_MAC = \"*aabbccddee01\""
        "[network.interface-name-pinning]"
        "enabled = true"
      ];
      absent = [ ];
    }
    {
      name = "pinning-disabled";
      # enabled = false must suppress the whole pinning section.
      cfg = withHost {
        pinning = {
          enabled = false;
        };
      };
      present = [ "filter.ID_NET_NAME_MAC = \"*aabbccddee01\"" ];
      absent = [ "[network.interface-name-pinning]" ];
    }
    {
      name = "toml-escaping";
      # Password with quote, backslash, tab and newline: TOML basic strings
      # must escape these as \" \\ \t \n (see ../lib/render-answer.nix).
      cfg = withHost { rootPassword = "a\"b\\c\td\ne"; };
      present = [ "root-password = \"a\\\"b\\\\c\\td\\ne\"" ];
      absent = [ ];
    }
    {
      name = "zfs-raid";
      # filesystem = zfs (the default) emits the raid level line.
      cfg = withHost {
        zfsRaid = "raid1";
        diskList = [
          "sda"
          "sdb"
        ];
      };
      present = [ "zfs.raid = \"raid1\"" ];
      absent = [ ];
    }
    {
      name = "ext4-no-raid";
      # filesystem = ext4 must not emit any zfs raid line.
      cfg = withHost { filesystem = "ext4"; };
      present = [ "filesystem = \"ext4\"" ];
      absent = [ "zfs.raid =" ];
    }
    {
      name = "hashed-password";
      # rootPasswordHashed renders root-password-hashed and no plaintext key.
      cfg = withHost {
        rootPassword = null;
        rootPasswordHashed = "$6$abc$xyz";
      };
      present = [ "root-password-hashed = \"$6$abc$xyz\"" ];
      absent = [ "root-password = " ];
    }
  ];

  reject = [
    {
      name = "both-passwords";
      # exactly one of rootPassword/rootPasswordHashed.
      cfg = withHost { rootPasswordHashed = "$6$abc$xyz"; };
    }
    {
      name = "neither-password";
      # exactly one of rootPassword/rootPasswordHashed.
      cfg = withHost { rootPassword = null; };
    }
    {
      name = "empty-disklist";
      # diskList must name the root disk(s).
      cfg = withHost { diskList = [ ]; };
    }
    {
      name = "duplicate-disks";
      # diskList entries must be unique.
      cfg = withHost {
        diskList = [
          "sda"
          "sda"
        ];
      };
    }
    {
      name = "empty-hosts";
      # at least one host must be defined.
      cfg = {
        hosts = { };
      };
    }
    {
      name = "bad-timezone";
      # not a tzdata Area/Location zone (and not UTC).
      cfg = withHost { timezone = "Etc/GMT+1"; };
    }
    {
      name = "bad-fqdn";
      # fqdn must contain a domain part (PVE rejects a bare hostname).
      cfg = withHost { fqdn = "foobar"; };
    }
    {
      name = "bad-keyboard";
      # not one of the PVE keyboard layout enum values.
      cfg = withHost { keyboard = "xx-yy"; };
    }
    {
      name = "uppercase-country";
      # country must be ISO 3166-1 alpha-2, lower-case.
      cfg = withHost { country = "US"; };
    }
    {
      name = "bad-zfsraid";
      # not one of the ZFS raid enum values (kebab-case).
      cfg = withHost { zfsRaid = "raidz1"; };
    }
    {
      name = "zfsraid-with-ext4";
      # zfsRaid is only used when filesystem = zfs.
      cfg = withHost {
        filesystem = "ext4";
        zfsRaid = "raid1";
        diskList = [
          "sda"
          "sdb"
        ];
      };
    }
    {
      name = "raidz2-too-few-disks";
      # raidz-2 requires at least 4 disks.
      cfg = withHost {
        zfsRaid = "raidz-2";
        diskList = [
          "sda"
          "sdb"
          "sdc"
        ];
      };
    }
    {
      name = "pinning-missing-bootmac";
      # mappings must include the boot MAC (AA:BB:CC:DD:EE:01).
      cfg = withHost {
        pinning = {
          enabled = true;
          mappings = [
            {
              mac = "AA:BB:CC:DD:EE:99";
              name = "lan0";
            }
          ];
        };
      };
    }
  ];
}
