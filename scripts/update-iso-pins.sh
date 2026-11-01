#!/usr/bin/env bash
# Repin lib/iso-pins.nix: take the newest release from the vendor SHA256SUMS
# that ships every pinned arch, and rewrite `version` plus the per-arch
# `sha256` lines from that listing. No ISO download: the hash is checked
# against the real file when the ISO is actually built (fetchurl).
#
#   scripts/update-iso-pins.sh [--version <release>] [--dry-run]
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pins=$root/lib/iso-pins.nix

die() { printf 'update-iso-pins: %s\n' "$*" >&2; exit 1; }
warn() { printf 'update-iso-pins: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: scripts/update-iso-pins.sh [--version <release>] [--dry-run]

  --version <release>  pin this release instead of the newest
  --dry-run            print the rewritten file, write nothing
EOF
}

# pins_render <pins-file> <version> <arch>=<sri>...
# Rewrites the version line and each named arch's sha256 line, nothing else.
# Buffers output, so a bad file yields an error and empty stdout.
pins_render() {
  awk -v version="$2" -v pairs="${*:3}" '
    function fail(msg) { printf "update-iso-pins: %s\n", msg > "/dev/stderr"; failed = 1; exit 1 }
    BEGIN {
      n = split(pairs, kv, " ")
      if (n == 0) fail("no arch=hash arguments")
      for (i = 1; i <= n; i++) {
        p = index(kv[i], "=")
        if (p < 2 || p == length(kv[i])) fail("bad arch=hash argument: " kv[i])
        a = substr(kv[i], 1, p - 1)
        want[a] = substr(kv[i], p + 1)
        requested[a] = 1
      }
    }
    {
      if ($0 ~ /^    [A-Za-z0-9_]+ = \{$/) { cur = substr($0, 5, length($0) - 8); seen[cur] = 1 }
      else if ($0 == "    };") cur = ""
      else if ($0 ~ /^  version = ".*";$/) { vhits++; out[++k] = "  version = \"" version "\";"; next }
      else if (cur != "" && (cur in requested) && $0 ~ /^      sha256 = ".*";$/) {
        shits[cur]++
        out[++k] = "      sha256 = \"" want[cur] "\";"
        next
      }
      out[++k] = $0
    }
    END {
      if (failed) exit 1
      if (vhits != 1) fail("expected one version line, found " vhits + 0)
      for (a in requested) {
        if (!(a in seen)) fail("no " a " block in " FILENAME)
        if (shits[a] != 1) fail("expected one sha256 line in " a ", found " shits[a] + 0)
      }
      for (i = 1; i <= k; i++) print out[i]
    }
  ' "$1"
}

sums_hex() { # <sums-file> <version> <suffix>
  awk -v f="proxmox-ve_$2$3.iso" '$2 == f { print $1 }' "$1"
}

# Newest release with an ISO for every suffix in the arch table.
sums_newest() { # <sums-file> <arch-table>
  local v s ok
  for v in $(awk '{ print $2 }' "$1" |
    sed -n 's/^proxmox-ve_\([0-9.]*-[0-9]*\)\(-.*\)\{0,1\}\.iso$/\1/p' | sort -uVr); do
    ok=1
    while IFS='|' read -r _ s _; do
      [[ -n $(sums_hex "$1" "$v" "$s") ]] || { ok=0; break; }
    done <"$2"
    (( ok )) && { printf '%s\n' "$v"; return; }
  done
}

pin_json() {
  nix eval --json "path:$root#lib.pveIso" --apply \
    'p: { inherit (p) version baseUrl; arches = builtins.mapAttrs (a: v: { inherit (v) suffix sha256; }) p.arches; }'
}

verify_pin() { # <version> <arch>=<sri>...
  local json got
  json=$(pin_json)
  [[ $(jq -r .version <<<"$json") == "$1" ]] || { warn "version is not $1"; return 1; }
  shift
  for pair in "$@"; do
    got=$(jq -r --arg a "${pair%%=*}" '.arches[$a].sha256 // ""' <<<"$json")
    [[ $got == "${pair#*=}" ]] || { warn "${pair%%=*}: expected ${pair#*=}, got $got"; return 1; }
  done
}

restore_pin() {
  cp -p "$1" "$pins"
  rm -f "$1" "$2"
  warn "restored the previous lib/iso-pins.nix"
}

main() {
  local target="" dry_run=0
  while (( $# )); do
    case $1 in
      --version) (( $# >= 2 )) || die "--version needs a value"; target=$2; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  for c in nix jq curl; do command -v "$c" >/dev/null || die "$c is required"; done
  [[ -z $target || $target =~ ^[0-9]+\.[0-9]+-[0-9]+$ ]] || die "malformed release '$target'"

  local json base sums table
  json=$(pin_json)
  base=$(jq -r .baseUrl <<<"$json")
  # arch|suffix|pinned sha256; suffix may be empty, so not whitespace-separated.
  table=$(jq -r '.arches | to_entries[] | [.key, .value.suffix, .value.sha256] | join("|")' <<<"$json")

  sums=$(mktemp "${TMPDIR:-/tmp}/pve-sums.XXXXXX")
  trap 'rm -f "$sums"' EXIT
  curl -fsSL "$base/SHA256SUMS" -o "$sums" || die "cannot fetch $base/SHA256SUMS"
  [[ -n $target ]] || target=$(sums_newest "$sums" <(printf '%s\n' "$table"))
  [[ -n $target ]] || die "no release ships every pinned arch"

  local -a args=()
  local arch suffix pinned hex sri changed=0
  while IFS='|' read -r arch suffix pinned; do
    hex=$(sums_hex "$sums" "$target" "$suffix")
    [[ -n $hex ]] || die "$target ships no $arch ISO (proxmox-ve_$target$suffix.iso)"
    sri=$(nix hash convert --hash-algo sha256 --to sri "$hex")
    args+=("$arch=$sri")
    [[ $sri == "$pinned" ]] || changed=1
  done <<<"$table"

  if (( dry_run )); then
    pins_render "$pins" "$target" "${args[@]}"
    exit 0
  fi
  if [[ $target == $(jq -r .version <<<"$json") && $changed == 0 ]]; then
    printf 'lib/iso-pins.nix is up to date at %s\n' "$target"
    exit 0
  fi

  if (( dry_run )); then
    pins_render "$pins" "$target" "${args[@]}"
    exit 0
  fi
  if [[ $target == $(jq -r .version <<<"$json") && $changed == 0 ]]; then
    printf 'lib/iso-pins.nix is up to date at %s\n' "$target"
    exit 0
  fi

  for pair in "${args[@]}"; do
    arch=${pair%%=*}
    new=${pair#*=}
    old=$(jq -r --arg a "$arch" '.arches[$a].sha256' <<<"$json")
    [[ $new == "$old" ]] || printf '%s: %s -> %s\n' "$arch" "$old" "$new"
  done

  local tmp backup
  tmp=$(mktemp)
  chmod --reference="$pins" "$tmp"
  backup=$(mktemp)
  cp -p "$pins" "$backup"
  pins_render "$pins" "$target" "${args[@]}" >"$tmp" || { rm -f "$tmp"; die "render failed, pin unchanged"; }
  trap 'restore_pin "$backup" "$sums"' EXIT
  mv "$tmp" "$pins"
  verify_pin "$target" "${args[@]}" || die "rewritten pin does not evaluate as intended"
  trap - EXIT
  rm -f "$backup" "$sums"
  printf 'lib/iso-pins.nix now pins %s\n' "$target"
}

main "$@"
