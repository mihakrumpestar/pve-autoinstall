# Minimal pve-autoinstall config: one host, required options only. Copy to
# hosts.nix and adjust.
{
  hosts.pve01 = {
    keyboard = "en-us";
    country = "us";
    timezone = "UTC";
    fqdn = "pve01.example.tld"; # first label must equal the key
    cidr = "192.168.10.11/24";
    dns = "192.168.10.1";
    gateway = "192.168.10.1";
    bootMac = "AA:BB:CC:DD:EE:01";
    mailto = "admin@example.tld";
    rootPasswordHashed = "$y$j9T$Xk9vXq0h0e9XoY3q$0QOGR4mS4H.j7v0rVZScMB.HoS.5iN7dR2FhV6s3Z8"; # mkpasswd -m yescrypt
    diskList = [ "sda" ]; # zfs raid0 (the defaults) on one disk
  };
}
