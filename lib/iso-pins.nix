# Single source of truth for the pinned PVE installer ISOs: the release
# version, the supported install-target arch set and the per-arch name/url/hash
# derivation. Pure data plus tiny helpers, consumed by flake.nix (lib.pveIso),
# modules/schema.nix (the arch enum) and packages/default.nix (per-host ISO
# selection).
#
# Bump by editing `version` and the two `sha256` values together (one version
# covers both arches): get the new releases from
# https://www.proxmox.com/en/downloads, then `task update-iso` prefetches both
# derived URLs and prints the hashes. Names and URLs are derived from `version`,
# never written twice. Note: download.proxmox.com currently serves a
# mismatching TLS cert, so the pin uses enterprise.proxmox.com (serves the
# same ISOs, HTTP 200).
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

  isoNameFor = arch: "proxmox-ve_${version}${arches.${arch}.suffix}.iso";
  urlFor = arch: "${baseUrl}/${isoNameFor arch}";
  hashFor = arch: arches.${arch}.sha256;
in
{
  inherit
    version
    arches
    urlFor
    hashFor
    ;
}
