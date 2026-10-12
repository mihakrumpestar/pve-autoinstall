# Deterministic fixtures for the non-vacuous flake checks in
# ../packages/tests.nix (pve-render-golden and pve-rejects-*). Plain data
# (no lib) so the tests consume them unchanged.
#
# `golden`: VALID single-host configs; `expect` is the exact rendered TOML,
#           compared full-file against the real renderer.
# `reject`: configs that MUST fail; `expect` is a stable substring of the
#           expected assertion message, or null for a type-level rejection
#           (shape/enum/pattern). Each name names the rule it exercises.
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

  # Pinning section content lines (rendered between the filter line and
  # [disk-setup]); an empty list suppresses the whole section. The region is
  # wrapped in blank lines and collapses to nothing when suppressed.
  pinningSection = [
    "[network.interface-name-pinning]"
    "enabled = true"
  ];
  pinningWithMappings =
    mappings:
    pinningSection
    ++ [
      ""
      "[network.interface-name-pinning.mapping]"
    ]
    ++ mappings;
  pinningText =
    pinning: if pinning == [ ] then "" else "\n${builtins.concatStringsSep "\n" pinning}\n";

  # ONE hand-written expected-TOML template shared by all golden cases, so a
  # change to the rendered output is reflected here exactly once instead of
  # once per case. Written by hand and independent of the renderer
  # implementation on purpose: that is what makes the golden test a real
  # oracle. Cases override only the few holes that vary.
  expectFor =
    {
      rootAuth ? ''root-password = "changeme"'', # root-password[-hashed] line
      sshKeys ? "root-ssh-keys = [ ]",
      pinning ? pinningSection,
      filesystem ? ''filesystem = "zfs"'',
      raid ? ''zfs.raid = "raid0"'', # "" renders the blank line (no raid)
      disks ? ''disk-list = [ "sda" ]'',
    }:
    ''
      [global]
      keyboard = "en-us"
      country = "us"
      fqdn = "pve01.example.tld"
      mailto = "admin@example.tld"
      timezone = "UTC"
      ${rootAuth}
      ${sshKeys}

      [network]
      source = "from-answer"
      cidr = "192.168.10.11/24"
      dns = "192.168.10.1"
      gateway = "192.168.10.1"
      # the installer matches the enx-prefixed MAC property, so the literal
      # MAC goes last and the leading * stays:
      filter.ID_NET_NAME_MAC = "*aabbccddee01"
      ${pinningText pinning}
      [disk-setup]
      ${filesystem}
      ${raid}
      # per host: keep the intended root disk, confirm the name with
      # proxmox-auto-install-assistant device-info -t disk
      ${disks}
    '';
in
{
  golden = [
    {
      name = "zfs-raid0-baseline";
      # Defaults: filesystem = zfs, zfsRaid = raid0, one disk, pinning on with
      # no explicit mappings.
      cfg = withHost { };
      expect = expectFor { };
    }
    {
      name = "zfs-raid1";
      cfg = withHost {
        zfsRaid = "raid1";
        diskList = [
          "sda"
          "sdb"
        ];
      };
      expect = expectFor {
        raid = ''zfs.raid = "raid1"'';
        disks = ''disk-list = [ "sda", "sdb" ]'';
      };
    }
    {
      name = "zfs-raid10";
      cfg = withHost {
        zfsRaid = "raid10";
        diskList = [
          "sda"
          "sdb"
          "sdc"
          "sdd"
        ];
      };
      expect = expectFor {
        raid = ''zfs.raid = "raid10"'';
        disks = ''disk-list = [ "sda", "sdb", "sdc", "sdd" ]'';
      };
    }
    {
      name = "ext4-single";
      # ext4 has no zfs/btrfs raid line.
      cfg = withHost { filesystem = "ext4"; };
      expect = expectFor {
        filesystem = ''filesystem = "ext4"'';
        raid = "";
      };
    }
    {
      name = "xfs-single";
      cfg = withHost { filesystem = "xfs"; };
      expect = expectFor {
        filesystem = ''filesystem = "xfs"'';
        raid = "";
      };
    }
    {
      name = "btrfs-raid0";
      cfg = withHost {
        filesystem = "btrfs";
        btrfsRaid = "raid0";
      };
      expect = expectFor {
        filesystem = ''filesystem = "btrfs"'';
        raid = ''btrfs.raid = "raid0"'';
      };
    }
    {
      name = "btrfs-raid1";
      cfg = withHost {
        filesystem = "btrfs";
        btrfsRaid = "raid1";
        diskList = [
          "sda"
          "sdb"
        ];
      };
      expect = expectFor {
        filesystem = ''filesystem = "btrfs"'';
        raid = ''btrfs.raid = "raid1"'';
        disks = ''disk-list = [ "sda", "sdb" ]'';
      };
    }
    {
      name = "btrfs-raid10";
      cfg = withHost {
        filesystem = "btrfs";
        btrfsRaid = "raid10";
        diskList = [
          "sda"
          "sdb"
          "sdc"
          "sdd"
        ];
      };
      expect = expectFor {
        filesystem = ''filesystem = "btrfs"'';
        raid = ''btrfs.raid = "raid10"'';
        disks = ''disk-list = [ "sda", "sdb", "sdc", "sdd" ]'';
      };
    }
    {
      name = "pinning-mapping";
      # Boot MAC is upper-case in config; the renderer must de-colonize and
      # lower-case it into the udev filter key and emit the mapping table.
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
      expect = expectFor {
        pinning = pinningWithMappings [
          ''"aa:bb:cc:dd:ee:01" = "lan0"''
          ''"aa:bb:cc:dd:ee:02" = "lan1"''
        ];
      };
    }
    {
      name = "pinning-disabled";
      # enabled = false suppresses the whole pinning section.
      cfg = withHost {
        pinning = {
          enabled = false;
        };
      };
      expect = expectFor { pinning = [ ]; };
    }
    {
      name = "pinning-vlan";
      # VLAN name keeps its .<id> suffix (only the MAC is normalized).
      cfg = withHost {
        pinning = {
          enabled = true;
          mappings = [
            {
              mac = "AA:BB:CC:DD:EE:01";
              name = "lan0.10";
            }
          ];
        };
      };
      expect = expectFor {
        pinning = pinningWithMappings [
          ''"aa:bb:cc:dd:ee:01" = "lan0.10"''
        ];
      };
    }
    {
      name = "toml-escaping";
      # Password with quote, backslash, tab and newline: TOML basic strings
      # must escape these as \" \\ \t \n in the rendered output.
      cfg = withHost { rootPassword = "a\"b\\c\td\ne"; };
      expect = expectFor { rootAuth = ''root-password = "a\"b\\c\td\ne"''; };
    }
    {
      name = "hashed-password-sha512";
      cfg = withHost {
        rootPassword = null;
        rootPasswordHashed = "$6$abc$xyz";
      };
      expect = expectFor { rootAuth = ''root-password-hashed = "$6$abc$xyz"''; };
    }
    {
      name = "hashed-password-yescrypt";
      cfg = withHost {
        rootPassword = null;
        rootPasswordHashed = "$y$j9T$abcdefghijkl$zyxwvutsrqpo";
      };
      expect = expectFor {
        rootAuth = ''root-password-hashed = "$y$j9T$abcdefghijkl$zyxwvutsrqpo"'';
      };
    }
    {
      name = "ssh-keys-present";
      cfg = withHost {
        sshKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIroot key"
        ];
      };
      expect = expectFor {
        sshKeys = ''root-ssh-keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIroot key" ]'';
      };
    }
  ];

  reject = [
    # Type-level rejections (shape/enum/pattern); expect = null.
    {
      name = "bad-ipv4";
      cfg = withHost { dns = "999.999.999.999"; };
      expect = null;
    }
    {
      name = "leading-zero-ipv4";
      cfg = withHost { dns = "01.2.3.4"; };
      expect = null;
    }
    {
      name = "bad-cidr-prefix";
      cfg = withHost { cidr = "1.2.3.4/99"; };
      expect = null;
    }
    {
      name = "uppercase-country";
      cfg = withHost { country = "US"; };
      expect = null;
    }
    {
      name = "invalid-crypt-hash";
      cfg = withHost {
        rootPassword = null;
        rootPasswordHashed = "not-a-hash";
      };
      expect = null;
    }
    {
      name = "empty-crypt-hash";
      cfg = withHost {
        rootPassword = null;
        rootPasswordHashed = "";
      };
      expect = null;
    }
    {
      name = "bad-ssh-key-nospace";
      cfg = withHost { sshKeys = [ "noseparator" ]; };
      expect = null;
    }
    {
      name = "bad-ssh-key-newline";
      cfg = withHost { sshKeys = [ "ssh-ed25519 AAAA\nbad" ]; };
      expect = null;
    }
    {
      name = "bad-disk-name";
      cfg = withHost { diskList = [ "/dev/sda" ]; };
      expect = null;
    }
    {
      name = "bad-pinning-name";
      # Starts with a digit: fails the interface-name pattern.
      cfg = withHost {
        pinning = {
          enabled = true;
          mappings = [
            {
              mac = "AA:BB:CC:DD:EE:01";
              name = "1lan";
            }
          ];
        };
      };
      expect = null;
    }
    {
      name = "bad-zfsraid-enum";
      cfg = withHost { zfsRaid = "raidz1"; };
      expect = null;
    }
    {
      name = "bad-btrfsraid-enum";
      cfg = withHost {
        filesystem = "btrfs";
        btrfsRaid = "raidz1";
      };
      expect = null;
    }
    {
      name = "bad-keyboard";
      cfg = withHost { keyboard = "xx-yy"; };
      expect = null;
    }

    # Assertion-level rejections; expect is a substring of the message.
    {
      name = "fqdn-not-matching-key";
      cfg = withHost { fqdn = "other.example.tld"; };
      expect = "as its first label";
    }
    {
      # PVE rejects a purely numeric first label (bugzilla 1054).
      name = "numeric-first-label";
      cfg = {
        hosts = {
          "123" = baseHost // {
            fqdn = "123.example.tld";
          };
        };
      };
      expect = "purely numeric first label";
    }
    {
      name = "duplicate-fqdn-across-hosts";
      cfg = {
        hosts = {
          pve01 = baseHost;
          pve02 = baseHost // {
            cidr = "192.168.10.12/24";
            bootMac = "AA:BB:CC:DD:EE:11";
          };
        };
      };
      expect = "fqdn must be unique across hosts";
    }
    {
      name = "rootpassword-too-short";
      cfg = withHost { rootPassword = "short"; };
      expect = "rootPassword must be at least 8 characters";
    }
    {
      name = "both-passwords";
      cfg = withHost { rootPasswordHashed = "$6$abc$xyz"; };
      expect = "set exactly one of rootPassword or rootPasswordHashed";
    }
    {
      name = "neither-password";
      cfg = withHost { rootPassword = null; };
      expect = "set exactly one of rootPassword or rootPasswordHashed";
    }
    {
      name = "empty-disklist";
      cfg = withHost { diskList = [ ]; };
      expect = "diskList must name the root disk(s)";
    }
    {
      name = "duplicate-disks-case-insensitive";
      cfg = withHost {
        diskList = [
          "sda"
          "SDA"
        ];
      };
      expect = "diskList contains duplicate entries";
    }
    {
      name = "zfs-raidz2-too-few-disks";
      cfg = withHost {
        zfsRaid = "raidz-2";
        diskList = [
          "sda"
          "sdb"
          "sdc"
        ];
      };
      expect = "requires at least 4 disks";
    }
    {
      name = "zfs-raid10-odd-disks";
      cfg = withHost {
        zfsRaid = "raid10";
        diskList = [
          "sda"
          "sdb"
          "sdc"
        ];
      };
      expect = "zfsRaid 'raid10' requires an even number of disks";
    }
    {
      name = "btrfs-without-raid";
      cfg = withHost { filesystem = "btrfs"; };
      expect = "btrfsRaid is required when filesystem = btrfs";
    }
    {
      name = "btrfs-raid1-one-disk";
      cfg = withHost {
        filesystem = "btrfs";
        btrfsRaid = "raid1";
      };
      expect = "btrfsRaid 'raid1' requires at least 2 disks";
    }
    {
      name = "btrfs-raid10-odd-disks";
      cfg = withHost {
        filesystem = "btrfs";
        btrfsRaid = "raid10";
        diskList = [
          "sda"
          "sdb"
          "sdc"
        ];
      };
      expect = "btrfsRaid 'raid10' requires an even number of disks";
    }
    {
      name = "ext4-two-disks";
      cfg = withHost {
        filesystem = "ext4";
        diskList = [
          "sda"
          "sdb"
        ];
      };
      expect = "filesystem 'ext4' requires exactly one disk";
    }
    {
      name = "xfs-two-disks";
      cfg = withHost {
        filesystem = "xfs";
        diskList = [
          "sda"
          "sdb"
        ];
      };
      expect = "filesystem 'xfs' requires exactly one disk";
    }
    {
      name = "zfsraid-with-ext4";
      cfg = withHost {
        filesystem = "ext4";
        zfsRaid = "raid1";
      };
      expect = "zfsRaid is only used when filesystem = zfs";
    }
    {
      name = "btrfsraid-with-zfs";
      cfg = withHost { btrfsRaid = "raid1"; };
      expect = "btrfsRaid is only used when filesystem = btrfs";
    }
    {
      name = "pinning-mappings-disabled";
      cfg = withHost {
        pinning = {
          enabled = false;
          mappings = [
            {
              mac = "AA:BB:CC:DD:EE:01";
              name = "lan0";
            }
          ];
        };
      };
      expect = "pinning.mappings is set but pinning is disabled";
    }
    {
      name = "pinning-missing-bootmac";
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
      expect = "pinning.mappings must include the boot NIC MAC";
    }
    {
      name = "duplicate-pinning-macs";
      cfg = withHost {
        pinning = {
          enabled = true;
          mappings = [
            {
              mac = "AA:BB:CC:DD:EE:01";
              name = "lan0";
            }
            {
              mac = "AA:BB:CC:DD:EE:01";
              name = "lan1";
            }
          ];
        };
      };
      expect = "pinning.mappings has duplicate MACs";
    }
    {
      name = "duplicate-pinning-names";
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
              name = "lan0";
            }
          ];
        };
      };
      expect = "pinning.mappings has duplicate names";
    }
    {
      name = "duplicate-pinning-names-case-insensitive";
      # PVE interface names are case-insensitive: lan0 and LAN0 collide.
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
              name = "LAN0";
            }
          ];
        };
      };
      expect = "pinning.mappings has duplicate names";
    }
    {
      name = "pinning-name-too-long";
      cfg = withHost {
        pinning = {
          enabled = true;
          mappings = [
            {
              mac = "AA:BB:CC:DD:EE:01";
              name = "abcdefghijklmnop";
            }
          ];
        };
      };
      expect = "names must be at most 15 characters";
    }
    {
      name = "mailto-placeholder";
      cfg = withHost { mailto = "mail@example.invalid"; };
      expect = "must not be the PVE placeholder";
    }
    {
      name = "bad-host-key";
      cfg = {
        hosts = {
          "bad host" = baseHost;
        };
      };
      expect = "name must match";
    }
    {
      name = "dotted-host-key";
      # Dots are rejected in host keys: the fqdn's first label can never
      # contain a dot, so a dotted key could never match.
      cfg = {
        hosts = {
          "pve.01" = baseHost;
        };
      };
      expect = "name must match";
    }
    {
      name = "country-not-in-iso-set";
      # Shape-valid lowercase alpha-2, but not a real ISO 3166-1 code.
      cfg = withHost { country = "zz"; };
      expect = "is not a valid ISO 3166-1 alpha-2 code";
    }
  ];
}
