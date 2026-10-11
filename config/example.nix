# Example configuration for the pve-autoinstall generator (unit tests).
# Copy to config/default.nix and fill with real values for real deployments.
{
  hosts = [
    {
      name = "pve01";
      keyboard = "en-us";
      country = "us";
      timezone = "UTC";
      fqdn = "pve01.example.tld";
      cidr = "192.168.10.11/24";
      dns = "192.168.10.1";
      gateway = "192.168.10.1";
      bootMac = "AA:BB:CC:DD:EE:01";
      mailto = "admin@example.tld";
      # example only; use rootPasswordHashed for real hosts and reset after
      # deploy
      rootPassword = "changeme";
      diskList = [ "sda" ];
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
    }
    {
      name = "pve02";
      keyboard = "en-us";
      country = "us";
      timezone = "UTC";
      fqdn = "pve02.example.tld";
      cidr = "192.168.10.12/24";
      dns = "192.168.10.1";
      gateway = "192.168.10.1";
      bootMac = "AA:BB:CC:DD:EE:11";
      mailto = "admin@example.tld";
      rootPassword = "changeme";
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
    }
    {
      name = "pve03";
      keyboard = "en-us";
      country = "us";
      timezone = "UTC";
      fqdn = "pve03.example.tld";
      cidr = "192.168.10.13/24";
      dns = "192.168.10.1";
      gateway = "192.168.10.1";
      bootMac = "AA:BB:CC:DD:EE:21";
      mailto = "admin@example.tld";
      rootPassword = "changeme";
      diskList = [ "sda" ];
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
    }
  ];
}
