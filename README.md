# pve-autoinstall

A CLI and Nix flake that turns a typed Nix configuration into Proxmox VE autoinstall answer files (TOML) and prepared ISOs with the answer embedded (`--fetch-from iso`).

## Quickstart

Requirements: Nix with flakes enabled. Building ISOs needs network access to fetch the pinned PVE ISO and a Linux builder (`x86_64-linux` or `aarch64-linux`, see Flake outputs). Each host's install-target arch is set by its `arch` option, independent of the build host.

**Write `hosts.nix`, then run it:**

```nix config/minimal.nix
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
```

```sh
nix run github:mihakrumpestar/pve-autoinstall -- ./hosts.nix
```

One entry per host; the key names the output files and must be `fqdn`'s first label (PVE takes the hostname from it). Everything not shown defaults: `arch = "x86_64"`, `filesystem = "zfs"`, `zfsRaid = "raid0"`, NIC names auto-pinned `nic0/nic1/...`.

For a complete three-host config (zfs raid1, ext4, btrfs, interface pinning) see [config/example.nix](config/example.nix). Every option is listed in the Configuration reference below.

That renders the TOML answer files, builds the prepared ISOs with the answer embedded, and symlinks both into `./pve-result` (override with `-o`): `answers/<host>.toml` and `isos/<host>.iso`. Boot each ISO on its host. The output directory is wiped and recreated on every run, so a re-run never leaves stale artifacts behind.

Validation runs by default (`validate-answer` on the answers, `inspect-iso` on the ISOs), the same per-host checks as `nix flake check`. The results are `nix build` out-links into the Nix store, so they survive garbage collection until you delete them.

Only need the answers? `--answers-only` skips the ISO builds and the download; see the CLI section below.

## Configuration reference

One config module with `hosts = { <name> = { ... }; }`, one entry per host. The key names the output files. Options are grouped by the TOML section they render into, in the same order as `modules/schema.nix`. The answer-file reference is the official Proxmox wiki: [Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation). The host key is the identity and is not rendered into the TOML; the system hostname comes from `fqdn`. It must match `^[A-Za-z0-9][A-Za-z0-9_+-]*$` (no dots: the first label of `fqdn` must equal the key and can never contain one).

### Install target

Not rendered into the answer TOML (the answer format has no architecture field):

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `arch` | `x86_64`/`aarch64` | `"x86_64"` | install-target architecture of the host; selects the pinned PVE installer ISO (see ISO pin); the answer file itself is architecture independent |

### `[global]`

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `keyboard` | one of 25 PVE layouts | required | e.g. `en-us`, `de-ch`, `pt-br` (full list below) |
| `country` | `^[a-z]{2}$` | required | lowercase ISO 3166-1 alpha-2 code present in iso-codes (e.g. `us`, `at`) |
| `fqdn` | FQDN (dotted) | required | must start with the host key plus a dot (first label == host key) and be unique across hosts; PVE sets the hostname from the first label and the domain from the rest (used as the DNS search domain), and rejects a purely numeric first label; a bare hostname with no domain is rejected |
| `mailto` | email | required | root mail target; must not be the PVE placeholder `mail@example.invalid` |
| `timezone` | tzdata zone | required | a `zone.tab` zone (e.g. `Europe/Vienna`) or the literal `UTC` |
| `rootPassword` | string or null | null | plain `root-password`, at least 8 characters; set exactly one of the two password options (an empty value counts as unset) |
| `rootPasswordHashed` | crypt hash or null | null | `root-password-hashed` (e.g. `mkpasswd -m yescrypt` or `openssl passwd -6`); must be a crypt hash, empty/malformed values are rejected |
| `sshKeys` | list of strings | `[ ]` | root `authorized_keys` entries in `type blob [comment]` form (the space is required); printable ASCII only, no control characters or newlines |

`keyboard` must be one of PVE's layouts: `de`, `de-ch`, `dk`, `en-gb`, `en-us`, `es`, `fi`, `fr`, `fr-be`, `fr-ca`, `fr-ch`, `hu`, `is`, `it`, `jp`, `lt`, `mk`, `nl`, `no`, `pl`, `pt`, `pt-br`, `se`, `si`, `tr`.

### `[network]`

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `cidr` | IPv4 CIDR | required | management NIC, static |
| `dns` | IPv4 | required | |
| `gateway` | IPv4 | required | |
| `bootMac` | MAC | required | install/management NIC; collect with `proxmox-auto-install-assistant device-info -t network` |

### `[network.interface-name-pinning]`

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `pinning.enabled` | bool | `true` | |
| `pinning.mappings` | list of `{ mac; name; }` | `[ ]` | MAC to name pairs; when pinning is enabled the list must include the boot NIC MAC (putting it first is the usual convention); it must be empty when pinning is disabled; omit the list for deterministic auto-pinned `nic0/nic1/...`; MACs render lowercase |
| `pinning.mappings[].name` | interface name | required | starts with a letter, then 1-20 letters/digits/underscores, with an optional VLAN suffix (`lan0.10` or `lan0:10`); at most 15 characters (PVE's check is case-insensitive; names are conventionally lowercase) |

### `[disk-setup]`

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `filesystem` | `zfs`/`ext4`/`xfs`/`btrfs` | `"zfs"` | `ext4` and `xfs` require exactly one disk |
| `zfsRaid` | `raid0`/`raid1`/`raid10`/`raidz-1`/`raidz-2`/`raidz-3` | `"raid0"` | only used when `filesystem = "zfs"`; minimum disks `raid0`=1, `raid1`=2, `raid10`=4, `raidz-1`=3, `raidz-2`=4, `raidz-3`=5; `raid10` also needs an even count |
| `btrfsRaid` | `raid0`/`raid1`/`raid10` or null | null | required when `filesystem = "btrfs"` (and only used then); minimum disks `raid0`=1, `raid1`=2, `raid10`=4; `raid10` also needs an even count |
| `diskList` | list of strings | required | target root disks as the installer names them (no `/dev/` prefix, no spaces), unique case-insensitively; confirm per host with `device-info -t disk` |

Every rule in the tables above is enforced at evaluation; errors name the host and the rule. Formats (CIDR, MAC, email, hash, key, names) are checked by option types; the cross-field rules (one password only, disk counts per filesystem, pinning consistency) by assertions.

## Passwords

The password (plain or hash) is stored verbatim in the answer file and embedded in the ISO. Both live in the world-readable Nix store, and the CLI's `pve-result` out-links keep that copy alive until you delete them and run garbage collection. The CLI's `umask 077` only protects its output directory, not the store copy.

Use `rootPasswordHashed` (`mkpasswd -m yescrypt` or `openssl passwd -6`): the plaintext then never enters the answer file, the ISO, or a shared binary cache. Set the plain `rootPassword` only for throwaway setups, and reset the root password after deployment either way. A real `config/default.nix` is gitignored and never committed; the example config carries only throwaway values.

## CLI

| Option | Effect |
| --- | --- |
| `-o, --out DIR` | Output directory (default `./pve-result`); an empty value is rejected |
| `--answers-only` | Build only the answer files |
| `--isos-only` | Build only the ISOs |
| `-H, --host NAME` | Restrict to one host (repeatable); an empty value is rejected |
| `--list` | Print host names from the config and exit (respects `-H`) |
| `--no-check` | Skip per-host validation checks |
| `--` | End option parsing; the next argument is taken as `<config.nix>` |
| `-h, --help` | Show usage and the pinned PVE ISO version |

`--answers-only` and `--isos-only` are mutually exclusive. Example: `pve-autoinstall ./hosts.nix --answers-only -H pve01 -o ./out`.

## As a flake input

Add pve-autoinstall as an input, call `lib.mkPve` with your config module (path or inline attrset), and expose the bundles you need:

```nix
{
  inputs.pve-autoinstall.url = "github:mihakrumpestar/pve-autoinstall";
  outputs = { pve-autoinstall, ... }:
    let
      # Your build host: x86_64-linux or aarch64-linux. Keep it in sync with
      # the `system` passed to mkPve (it selects the build host's pkgs).
      system = "x86_64-linux";
    in
    {
      packages.${system} = {
        pve-answers = (pve-autoinstall.lib.mkPve {
          config = ./hosts.nix;
          inherit system;
        }).answersDir;
        pve-isos = (pve-autoinstall.lib.mkPve {
          config = ./hosts.nix;
          inherit system;
        }).isosDir;
      };
    };
}
```

Then build as usual with `nix build .#pve-answers` / `nix build .#pve-isos`. For a single-file config, pass the attrset inline as `config` (see [config/example.nix](config/example.nix) for the full shape, including pinning and hashed passwords). To use the CLI against your pinned input, re-export its app (`apps.${system}.pve-autoinstall = pve-autoinstall.apps.${system}.default;`) and run `nix run .#pve-autoinstall -- ./hosts.nix`.

## Flake outputs

`lib`:
- `lib.mkPve { config = ...; system ? "x86_64-linux"; }` renders a config module (path or attrset) into per-host answers, prepared ISOs, bundle dirs, and PVE-tool checks (`system` selects the build host's pkgs; the per-host install-target arch comes from the config's `arch`). It returns `answers`, `isos`, `answersDir`, `isosDir`, `checks`, and `checksFor { hostList ? all hosts, mode ? "all" }` (pick per-host checks by host and mode: `answers`, `isos`, `all`; used by the CLI). Schema evaluation (`evalConfig`, `validate`) and TOML rendering (`renderAnswer`) live in [lib/eval-config.nix](lib/eval-config.nix) and [lib/render-answer.nix](lib/render-answer.nix).
- `lib.pveIso` is the pinned PVE ISOs, defined in [lib/iso-pins.nix](lib/iso-pins.nix): `version`, `arches` (per arch: ISO name `suffix` and `sha256`) and the pure helpers `urlFor`, `hashFor`; names and URLs are derived from `version` (`proxmox-ve_<version>.iso`, `proxmox-ve_<version>-arm64.iso`). See ISO pin.

`packages.<system>` (the bundles build the committed `config/example.nix`):
- `pve-answers`: bundle dir with `answers/<host>.toml`.
- `pve-isos`: bundle dir with `isos/<host>.iso`.
- `pve-autoinstall`: the CLI (takes any config at runtime).
- `default`: alias for `pve-isos`.

`apps.<system>.default`: the `pve-autoinstall` CLI.

`checks.<system>`: per host, `pve-answer-validates-<host>` (runs `validate-answer`) and `pve-iso-is-autoinstall-<host>` (runs `inspect-iso`); `pve-render-golden` (an exact full-file diff of each golden fixture's rendered TOML against its expected output, not a substring match); one `pve-rejects-<case>` per invalid fixture (each must be rejected at type level or by its specific assertion message); `pve-host-key-pattern-consistent` (this README documents the host-key pattern exactly as enforced); and `pve-readme-sample-consistent` (the Quickstart sample is exactly [config/minimal.nix](config/minimal.nix), and that config passes the schema). See [config/fixtures.nix](config/fixtures.nix).

`formatter.<system>`: `nixfmt-tree`, so `nix fmt` matches the devenv formatting.

`packages` and `checks` are exposed for both `x86_64-linux` and `aarch64-linux`: the native `proxmox-auto-install-assistant` prepares any target ISO (`prepare-iso` is arch-agnostic toward its input), and each host's `arch` selects its pinned ISO. `apps` and `formatter` are exposed for both systems too, so `nix run` and `nix fmt` work on either.

## Development

In this flake's own checkout, the committed example config (`config/example.nix`) is what the packages build:

```sh
nix build .#pve-answers      # answers/<host>.toml
nix build .#pve-isos         # isos/<host>.iso
nix build .#pve-autoinstall  # the CLI
nix flake check .            # validate-answer + inspect-iso per host, plus the render, reject and docs consistency checks
```

`Taskfile.yml` wraps the common workflows:

| Task | Effect |
| --- | --- |
| `task answers` | Build the answer bundle (`nix build .#pve-answers`) into `result-answers`. |
| `task isos` | Build the ISO bundle (`nix build .#pve-isos`) into `result-isos`. |
| `task build` | Run `answers`, then `isos`. |
| `task check` | Run `nix flake check`, which builds and validates the prepared ISOs; needs network for the pinned PVE ISO. |
| `task run` | Run the CLI against a config, e.g. `task run -- config/example.nix --answers-only`. |
| `task clean` | Remove the build out-links (`result`, `result-answers`, `result-isos`) and `pve-result`. |
| `task ci` | Fast pre-commit gate (also the git hook): `gitleaks`, `treefmt`, `deadnix`, `statix`, `flake-checker`. No ISO builds. |
| `task verify` | `ci` plus the heavy `nix flake check`. |
| `task test` | Every check except the per-host `validate-answer`/`inspect-iso` ones, plus the CLI bats tests against the built CLI; no ISO builds. |
| `task update-inputs` | Update flake inputs, or one input with `task update-inputs -- <name>`. |
| `task update-iso` | Prefetch both pinned PVE ISOs and print their SRI hashes for `lib/iso-pins.nix`. |

`nix flake check` runs the full check set listed under Flake outputs. The CLI's argument parsing is covered by bats tests in `tests/cli.bats`; `task test` builds `.#pve-autoinstall` and runs them (they skip without `PVE_CLI`).

CI (`.github/workflows/ci.yml`) runs a single lint job on every push, pull request and manual dispatch: `task ci` under `devenv --profile ci shell`, so CI uses the same toolchain as local. Tests and ISO validation stay local (`task test`, `task check`, `task verify`) to keep CI fast. The job fails if `task ci` left the working tree dirty, so run `task ci` locally and commit the result.

`devenv.nix` keeps the toolchain in one place: a ci tool group (`gitleaks`, `nixfmt-tree`, `deadnix`, `statix`, `flake-checker`, `go-task`, `bats`) and a pve tool group (`proxmox-auto-install-assistant`, `xorriso`) for manual answer/ISO work. A plain `devenv shell` includes both; the `ci` profile drops the pve group via a profile override, so CI realises a small, cacheable toolchain. On shell entry devenv installs a git pre-commit hook that runs `task ci` (made a no-op under the `ci` profile).

## ISO pin

The pinned ISOs live in [lib/iso-pins.nix](lib/iso-pins.nix) (exported as `lib.pveIso`): `version` plus one `sha256` per install-target arch (`arches`), with the ISO names and URLs derived from `version` (`proxmox-ve_<version>.iso`, `proxmox-ve_<version>-arm64.iso`). To bump:

1. Note the new release name from https://www.proxmox.com/en/downloads and set `version` (one bump covers both arches).
2. Fetch and hash the new ISOs without trusting them: `task update-iso` prefetches both derived URLs and prints the `sha256` values (SRI form) to copy into `lib/iso-pins.nix` (manual: `nix store prefetch-file --json --hash-type sha256 <URL>`).
3. Re-run `nix flake check`: the `validate-answer` and `inspect-iso` checks confirm the updated ISOs still embed the per-host answers.

The pin uses `enterprise.proxmox.com` because `download.proxmox.com` currently serves a mismatching TLS cert (same ISOs, HTTP 200).
