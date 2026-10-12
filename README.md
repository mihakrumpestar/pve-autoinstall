# pve-autoinstall

Nix flake that turns typed Nix configuration into Proxmox VE autoinstall answer files and prepared ISOs (answer embedded, `--fetch-from iso`).

The configuration is a Nix module (`modules/schema.nix`): values are self-validating (types check CIDR/MAC/mailto format, keyboard layout, country code, and timezone, and enums restrict filesystem and raid levels), and module assertions enforce the rest (exactly one password variant, disk list present, required keyboard/country/timezone, a dotted `fqdn`). Locale value sets are derived from the sources PVE uses (`lib/locales.nix`). The generated TOML and the built ISOs are validated with the PVE-supplied tools (`validate-answer`, `inspect-iso`); there are no hand-rolled schema checks. The end-to-end workflow is documented in the infrastructure repo's `pve/autoinstall.md` (single source of truth for structure); this package automates the render/validate/build steps.

## Options (per host, in `hosts = { <name> = { ... }; }`)

`hosts` is an attrset keyed by host name; each value describes one host. The key names the output files (`answers/<name>.toml`, `isos/<name>.iso`). Options are grouped by the TOML section they render into; order here (and in `modules/schema.nix`) follows that order.

### Identity

The host key (`hosts.<name>`) is the identity and names the output files. It is not rendered into the TOML; the system hostname comes from `fqdn` (see `[global]` below).

### `[global]`

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `keyboard` | one of 25 PVE layouts | required | e.g. `en-us`, `de-ch`, `pt-br` (full list below) |
| `country` | `^[a-z]{2}$` | required | ISO 3166-1 alpha-2, lowercase (e.g. `us`, `at`) |
| `fqdn` | FQDN (dotted) | required | PVE sets the hostname from the first label and the domain from the rest (written to `/etc/hostname` + `/etc/hosts`); a bare hostname with no domain is rejected |
| `mailto` | email | required | root mail target |
| `timezone` | tzdata zone | required | canonical tzdata zone (e.g. `Europe/Vienna`) or `UTC` |
| `rootPassword` | string or null | null | plain `root-password`; set exactly one of the two password options |
| `rootPasswordHashed` | string or null | null | `root-password-hashed` (e.g. `mkpasswd -m yescrypt`) |
| `sshKeys` | list of strings | `[ ]` | root `authorized_keys` entries |

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
| `pinning.mappings` | list of `{ mac; name; }` | `[ ]` | MAC to name pairs; when pinning is enabled the list must include the boot NIC MAC (conventionally first); omit the list for deterministic auto-pinned `nic0/nic1/...`; MACs render lowercase |

### `[disk-setup]`

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `filesystem` | `zfs`/`ext4`/`xfs`/`btrfs` | `"zfs"` | |
| `zfsRaid` | `raid0`/`raid1`/`raid10`/`raidz-1`/`raidz-2`/`raidz-3` | `"raid0"` | only used when `filesystem = "zfs"`; `raid1`/`raid10`/`raidz-1`/`raidz-2`/`raidz-3` require at least 2/4/3/4/5 disks |
| `diskList` | list of strings | required | target root disks; confirm per host with `device-info -t disk` |

Assertions fail at evaluation with a message: at least one host; exactly one of `rootPassword`/`rootPasswordHashed`; non-empty `diskList` with no duplicate disks; required `keyboard`/`country`/`timezone`; `timezone` present in tzdata; a dotted `fqdn`; `zfsRaid` only set when `filesystem = "zfs"`; the per-level minimum disk count; and, when pinning is enabled with mappings, that they include the boot NIC MAC and have unique MACs and names. All type formats above are enforced by the module system.

## Password policy

Set `rootPassword` (or the hashed variant) in the config, deploy, then reset the root password after deployment for easier management.

The password value (plain or hash) is stored verbatim in the generated answer file and embedded verbatim in the built ISO. Keep built answer files and ISOs out of any shared/public store (and keep the answers directory private, e.g. mode 700). A real `config/default.nix` never enters git (gitignored); the example config carries only throwaway values.

## Usage

### CLI

Build the per-host answer files and ISOs from any Nix config module:

```sh
nix run github:mihakrumpestar/pve-autoinstall -- ./hosts.nix
```

`pve-autoinstall <config.nix>` renders the TOML answer files, builds the prepared ISOs, and symlinks the results into the output directory (default `./pve-result`):

```
pve-result/
├── answers/<host>.toml
└── isos/<host>.iso
```

Results are `nix build` out-links into the Nix store, so they survive garbage collection as usual.

Options:

| Option | Effect |
| --- | --- |
| `-o, --out DIR` | Output directory (default `./pve-result`) |
| `--answers-only` | Build only the answer files |
| `--isos-only` | Build only the ISOs |
| `-H, --host NAME` | Restrict to one host (repeatable) |
| `--list` | Print host names from the config and exit |
| `--no-check` | Skip per-host validation checks |
| `-h, --help` | Show usage and the pinned PVE ISO version |

For example, build only the answer files for one host from a real config:

```sh
pve-autoinstall ./hosts.nix --answers-only -H pve01 -o ./out
```

Validation runs by default: answer files through PVE `validate-answer`, ISOs through `inspect-iso`, mirroring `nix flake check`.

### As a flake output

Add pve-autoinstall as an input, call `lib.mkPve` with your config module (path or attrset), and expose the bundles you need:

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

`config` accepts a path to a module or an inline attrset, so a small deployment can stay in one file:

```nix
packages.x86_64-linux.pve-isos = (pve-autoinstall.lib.mkPve {
  config = {
    hosts = {
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
        rootPassword = "changeme";
        diskList = [ "sda" ];
      };
    };
  };
}).isosDir;
```

Then build as usual with `nix build .#pve-answers` / `nix build .#pve-isos`. To use the CLI against your pinned input, re-export its app:

```nix
apps.x86_64-linux.pve-autoinstall = pve-autoinstall.apps.x86_64-linux.default;
```

and run `nix run .#pve-autoinstall -- ./hosts.nix`.

### Inside this flake's checkout

The committed example config (`config/example.nix`) is exposed as packages (`config/default.nix` is gitignored and never part of the flake source):

```sh
nix build .#pve-answers   # answers/<host>.toml
nix build .#pve-isos      # isos/<host>.iso
nix flake check .         # validate-answer + inspect-iso per host
```

## Flake outputs

`lib`:
- `lib.mkPve { config = ...; }` renders a config module (path or attrset) into per-host answers, prepared ISOs, bundle dirs, and PVE-tool checks. It returns `answers`, `isos`, `answersDir`, `isosDir`, `checks`, `checksForHosts`, and the evaluated `config`.
- `lib.pveIso` is the pinned PVE ISO (`{ version, url, hash }`); see ISO pin.

`packages.<system>` (always the committed `config/example.nix`):
- `pve-answers`: bundle dir with `answers/<host>.toml`.
- `pve-isos`: bundle dir with `isos/<host>.iso`.
- `default`: alias for `pve-isos`.

`apps.<system>.default`: the `pve-autoinstall` CLI.

`checks.<system>`: per host, `pve-answer-validates-<host>` (runs `validate-answer`) and `pve-iso-is-autoinstall-<host>` (runs `inspect-iso`); plus `pve-render-golden` (exact rendered TOML for representative configs) and one `pve-rejects-<case>` per invalid fixture (each must fail validation). See `config/fixtures.nix`.

`formatter.<system>`: `nixfmt-tree`, so `nix fmt` matches the devenv formatting.

## Tasks

`Taskfile.yml` wraps the common workflows:

| Task | Effect |
| --- | --- |
| `task answers` | Build the answer bundle (`nix build .#pve-answers`) into `result-answers`. |
| `task isos` | Build the ISO bundle (`nix build .#pve-isos`) into `result-isos`. |
| `task build` | Run `answers`, then `isos`. |
| `task check` | Run `nix flake check`, which builds and validates the prepared ISOs (not just a lint). |
| `task run` | Run the CLI against a config, e.g. `task run -- config/example.nix --answers-only`. |
| `task clean` | Remove the build out-links (`result`, `result-answers`, `result-isos`) and `pve-result`. |
| `task ci` | Lint, format, and secret-scan (also the pre-commit hook). |
| `task update-inputs` | Update flake inputs, or one input with `task update-inputs -- <name>`. |

## Development shell

`devenv.nix` provides a dev shell with `deadnix`, `flake-checker`, `go-task`, `gitleaks`, `nixfmt-tree`, `statix`, `proxmox-auto-install-assistant`, and `xorriso`. On shell entry devenv installs a git pre-commit hook that runs `task ci`.

## ISO pin

The pinned ISO constants live in `flake.nix` (`pveIso = { version, url, hash }`). To bump:

1. Note the new release name from https://www.proxmox.com/en/downloads.
2. Fetch and hash the new URL without trusting it: `nix store prefetch-file --json --hash-type sha256 <URL>` and copy the printed `hash` (SRI form) plus `version` into `pveIso`.
3. Re-run `nix flake check`: the `validate-answer` and `inspect-iso` checks confirm the updated ISO still embeds the per-host answers.

`download.proxmox.com` currently serves a mismatching TLS cert, so the pin uses `enterprise.proxmox.com` (same ISO, HTTP 200).
