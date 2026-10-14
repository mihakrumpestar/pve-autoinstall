# Example configuration for the pve-autoinstall generator.
# Copy to config/default.nix and fill with real values for real deployments.
#
# One entry per host under `hosts`; everything shared lives in `common` and is
# merged into each host with `//`, so a host entry only names what differs.
# This three-host example covers zfs raid1, ext4 and btrfs roots plus
# interface-name pinning.
#
# rootPasswordHashed is a crypt(3) hash (mkpasswd -m yescrypt or
# openssl passwd -6). Plain rootPassword is available but discouraged: a
# plaintext password would be embedded verbatim in the answer file and ISO.
# The values below are documented throwaways, not real credentials.
let
  # Shared by every host.
  common = {
    keyboard = "en-us";
    country = "us";
    timezone = "UTC";

    mailto = "admin@example.tld";
    rootPasswordHashed = "$y$j9T$Xk9vXq0h0e9XoY3q$0QOGR4mS4H.j7v0rVZScMB.HoS.5iN7dR2FhV6s3Z8";
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExamplePlaceholderKey000000000000000000 admin@example.tld"
    ];

    dns = "192.168.10.1";
    gateway = "192.168.10.1";
  };
in
{
  hosts = {
    # zfs raid1 across two disks.
    pve01 = common // {
      fqdn = "pve01.example.tld";
      cidr = "192.168.10.11/24";
      bootMac = "AA:BB:CC:DD:EE:01";
      filesystem = "zfs";
      zfsRaid = "raid1";
      diskList = [
        "sda"
        "sdb"
      ];
      pinning.mappings = [
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
    # ext4 on a single disk.
    pve02 = common // {
      fqdn = "pve02.example.tld";
      cidr = "192.168.10.12/24";
      bootMac = "AA:BB:CC:DD:EE:11";
      filesystem = "ext4";
      diskList = [ "sda" ];
      pinning.mappings = [
        {
          mac = "AA:BB:CC:DD:EE:11";
          name = "lan0";
        }
        {
          mac = "AA:BB:CC:DD:EE:12";
          name = "lan1";
        }
      ];
    };
    # btrfs raid1 across two disks.
    pve03 = common // {
      fqdn = "pve03.example.tld";
      cidr = "192.168.10.13/24";
      bootMac = "AA:BB:CC:DD:EE:21";
      filesystem = "btrfs";
      btrfsRaid = "raid1";
      diskList = [
        "sda"
        "sdb"
      ];
      pinning.mappings = [
        {
          mac = "AA:BB:CC:DD:EE:21";
          name = "lan0";
        }
        {
          mac = "AA:BB:CC:DD:EE:22";
          name = "lan1";
        }
      ];
    };
  };
}
