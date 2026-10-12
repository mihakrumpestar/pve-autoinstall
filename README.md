# pve-autoinstall

Nix flake that turns a typed Nix configuration into Proxmox VE autoinstall answer files (TOML) and prepared ISOs with the answer embedded (`--fetch-from iso`).

Validation is layered: Nix types and assertions reject bad values at evaluation, using the same locale lists PVE uses (`lib/locales.nix`); the PVE tools `validate-answer` and `inspect-iso` own final validation of the rendered output. The end-to-end install workflow lives in the infrastructure repo's `pve/autoinstall.md`; this flake automates the render, validate and build steps.

## Quickstart

Requirements: Nix with flakes enabled. Building ISOs needs network access to fetch the pinned PVE ISO and an x86_64-linux builder (see Flake outputs).

```sh
nix run github:mihakrumpestar/pve-autoinstall -- ./hosts.nix
```

That renders the TOML answer files, builds the prepared ISOs, and symlinks the results into `./pve-result` (override with `-o`): `answers/<host>.toml` and `isos/<host>.iso`. The results are `nix build` out-links into the Nix store, so they survive garbage collection. Validation runs by default, answer files through `validate-answer` and ISOs through `inspect-iso`, the same per-host checks as `nix flake check`.

In this flake's own checkout, the committed example config (`config/example.nix`) is what the packages build:

```sh
nix build .#pve-answers      # answers/<host>.toml
nix build .#pve-isos         # isos/<host>.iso
nix build .#pve-autoinstall  # the CLI
nix flake check .            # validate-answer + inspect-iso per host, plus the render/reject and docs pattern checks
```

## Configuration reference

One config module with `hosts = { <name> = { ... }; }`, one entry per host. The key names the output files. Options are grouped by the TOML section they render into, in the same order as `modules/schema.nix`. The answer-file reference is the official Proxmox wiki: [Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation). The host key is the identity and is not rendered into the TOML; the system hostname comes from `fqdn`. It must match `^[A-Za-z0-9][A-Za-z0-9_+-]*$` (no dots: the first label of `fqdn` must equal the key and can never contain one).

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
  outputs = { pve-autoinstall, ... }: {
    packages.x86_64-linux = {
      pve-answers = (pve-autoinstall.lib.mkPve { config = ./hosts.nix; }).answersDir;
      pve-isos = (pve-autoinstall.lib.mkPve { config = ./hosts.nix; }).isosDir;
    };
  };
}
```

Then build as usual with `nix build .#pve-answers` / `nix build .#pve-isos`. For a single-file config, pass the attrset inline as `config` (see `config/example.nix` for the full shape, including pinning and hashed passwords). To use the CLI against your pinned input, re-export its app (`apps.x86_64-linux.pve-autoinstall = pve-autoinstall.apps.x86_64-linux.default;`) and run `nix run .#pve-autoinstall -- ./hosts.nix`.

## Flake outputs

`lib`:
- `lib.mkPve { config = ...; }` renders a config module (path or attrset) into per-host answers, prepared ISOs, bundle dirs, and PVE-tool checks. It returns `answers`, `isos`, `answersDir`, `isosDir`, `checks`, `checksForHosts`, `selectChecks` (pick per-host checks by host and mode: `answers`, `isos`, `all`; used by the CLI), and the evaluated `config`, plus `evalConfig` (evaluate a config against the schema), `validate` (evaluate and throw the aggregated assertion messages), and `renderAnswer` (render one host's TOML). The tests use `evalConfig`, `validate` and `renderAnswer`.
- `lib.pveIso` is the pinned PVE ISO: `version` and `hash` live in `flake.nix`, with the URL derived from `version` (`proxmox-ve_<version>.iso`). See ISO pin.

`packages.x86_64-linux` (the bundles build the committed `config/example.nix`):
- `pve-answers`: bundle dir with `answers/<host>.toml`.
- `pve-isos`: bundle dir with `isos/<host>.iso`.
- `pve-autoinstall`: the CLI (takes any config at runtime).
- `default`: alias for `pve-isos`.

`apps.<system>.default`: the `pve-autoinstall` CLI.

`checks.x86_64-linux`: per host, `pve-answer-validates-<host>` (runs `validate-answer`) and `pve-iso-is-autoinstall-<host>` (runs `inspect-iso`); `pve-render-golden` (an exact full-file diff of each golden fixture's rendered TOML against its expected output, not a substring match); one `pve-rejects-<case>` per invalid fixture (each must be rejected at type level or by its specific assertion message); and `pve-host-key-pattern-consistent` (this README documents the host-key pattern exactly as enforced). See `config/fixtures.nix`.

`formatter.<system>`: `nixfmt-tree`, so `nix fmt` matches the devenv formatting.

`packages` and `checks` are x86_64-linux only: the PVE ISOs and `proxmox-auto-install-assistant` are x86_64. `apps` and `formatter` are exposed for both x86_64-linux and aarch64-linux, so `nix run` and `nix fmt` work on either.

## Development

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
| `task test` | Golden/reject checks, the docs pattern check and the CLI bats tests against the built CLI; no ISO builds. |
| `task update-inputs` | Update flake inputs, or one input with `task update-inputs -- <name>`. |
| `task update-iso` | Fetch a new PVE ISO and print the SRI hash for `flake.nix`. |

`nix flake check` runs the full check set listed under Flake outputs. The CLI's argument parsing is covered by bats tests in `tests/cli.bats`; `task test` builds `.#pve-autoinstall` and runs them (they skip without `PVE_CLI`).

CI (`.github/workflows/ci.yml`) runs two jobs on every push, pull request and manual dispatch, both driven by devenv (`devenv --profile ci shell`) so CI uses the same toolchain as local: `Lint & Test` (`task ci` and `task test`) and `Nix Check` (`task check`, the full `nix flake check`). The lint job fails if `task ci` left the working tree dirty, so run `task ci` locally and commit the result.

`devenv.nix` keeps the toolchain in one place: a ci tool group (`gitleaks`, `nixfmt-tree`, `deadnix`, `statix`, `flake-checker`, `go-task`, `bats`) and a pve tool group (`proxmox-auto-install-assistant`, `xorriso`) for manual answer/ISO work. A plain `devenv shell` includes both; the `ci` profile drops the pve group via a profile override, so CI realises a small, cacheable toolchain. On shell entry devenv installs a git pre-commit hook that runs `task ci` (made a no-op under the `ci` profile).

## ISO pin

The pinned ISO lives in `flake.nix` (`pveIso`): `version` and `hash`, with the URL derived from `version` (`proxmox-ve_<version>.iso`). To bump:

1. Note the new release name from https://www.proxmox.com/en/downloads and set `version`.
2. Fetch and hash the new ISO without trusting it: `nix store prefetch-file --json --hash-type sha256 <URL>`, and copy the printed `hash` (SRI form) into `pveIso`. `task update-iso` does the same fetch and prints the hash.
3. Re-run `nix flake check`: the `validate-answer` and `inspect-iso` checks confirm the updated ISO still embeds the per-host answers.

The pin uses `enterprise.proxmox.com` because `download.proxmox.com` currently serves a mismatching TLS cert (same ISO, HTTP 200).
