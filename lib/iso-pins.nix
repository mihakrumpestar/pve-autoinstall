# Pinned PVE installer ISOs: release version, per-arch suffix/sha256, and the
# name/url/hash derivations. Consumed by flake.nix (lib.pveIso),
# modules/schema.nix (arch enum) and packages/default.nix (ISO selection).
#
# Hashes are the vendor's own (SHA256SUMS), so the pin cannot disagree with the
# published image; `task update-iso` refreshes them.
#
# download.proxmox.com serves a mismatching TLS cert, so the pin uses
# enterprise.proxmox.com (same ISOs).
let
  version = "9.3-1";
  baseUrl = "https://enterprise.proxmox.com/iso";

  # Per install-target arch: ISO filename suffix and pinned sha256 (SRI form).
  arches = {
    x86_64 = {
      suffix = "";
      sha256 = "sha256-zE/Je5rDpXEq1bZlGVdTVxkjoY4R9cLrsRP9wppQvTY=";
    };
    aarch64 = {
      suffix = "-arm64";
      sha256 = "sha256-oJ+ss00vzJ9dFpqFtVsAh4R5KsTW4lkBOXhUJR7QqN4=";
    };
  };

  isoNameFor = version: arch: "proxmox-ve_${version}${arches.${arch}.suffix}.iso";
  # Version-parameterized so update-iso-pins.sh can render candidate releases.
  urlForVersion = version: arch: "${baseUrl}/${isoNameFor version arch}";
  urlFor = urlForVersion version;
  hashFor = arch: arches.${arch}.sha256;
in
{
  inherit
    version
    baseUrl
    arches
    urlForVersion
    urlFor
    hashFor
    ;
}
