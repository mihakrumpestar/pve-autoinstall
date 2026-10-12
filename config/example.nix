# Example configuration for the pve-autoinstall generator.
# Copy to config/default.nix and fill with real values for real deployments.
#
# rootPasswordHashed is a crypt(3) hash (mkpasswd -m yescrypt or
# openssl passwd -6). Plain rootPassword is available but discouraged: a
# plaintext password would be embedded verbatim in the answer file and ISO.
# The hash below is a documented throwaway, not a real credential.
{
  hosts = {
    # zfs raid1 across two disks.
    pve01 = {
      keyboard = "en-us";
      country = "us";
      timezone = "UTC";
      fqdn = "pve01.example.tld";
      cidr = "192.168.10.11/24";
      dns = "192.168.10.1";
      gateway = "192.168.10.1";
      bootMac = "AA:BB:CC:DD:EE:01";
      mailto = "admin@example.tld";
      rootPasswordHashed = "$y$j9T$Xk9vXq0h0e9XoY3q$0QOGR4mS4H.j7v0rVZScMB.HoS.5iN7dR2FhV6s3Z8";
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
    pve02 = {
      keyboard = "en-us";
      country = "us";
      timezone = "UTC";
      fqdn = "pve02.example.tld";
      cidr = "192.168.10.12/24";
      dns = "192.168.10.1";
      gateway = "192.168.10.1";
      bootMac = "AA:BB:CC:DD:EE:11";
      mailto = "admin@example.tld";
      rootPasswordHashed = "$6$pveAutoInstall$0QOGR4mS4H.j7v0rVZScMB.HoS.5iN7dR2FhV6s3Z8";
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
    pve03 = {
      keyboard = "en-us";
      country = "us";
      timezone = "UTC";
      fqdn = "pve03.example.tld";
      cidr = "192.168.10.13/24";
      dns = "192.168.10.1";
      gateway = "192.168.10.1";
      bootMac = "AA:BB:CC:DD:EE:21";
      mailto = "admin@example.tld";
      rootPasswordHashed = "$y$j9T$Xk9vXq0h0e9XoY3q$0QOGR4mS4H.j7v0rVZScMB.HoS.5iN7dR2FhV6s3Z8";
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
