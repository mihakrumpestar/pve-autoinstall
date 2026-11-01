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
  version = "9.2-1";
  baseUrl = "https://enterprise.proxmox.com/iso";

  # Per install-target arch: ISO filename suffix and pinned sha256 (SRI form).
  arches = {
    x86_64 = {
      suffix = "";
      sha256 = "sha256-Toj+QW35tSdiShdfJMmqB8cU0zMq+x7j2/OHlXPvLGw=";
    };
    aarch64 = {
      suffix = "-arm64";
      sha256 = "sha256-sWGdzR9bGm1n13tZ5+L6IDMXRVHR4bncIrIXHsCTq70=";
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
