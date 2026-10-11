# pve-autoinstall

Nix flake that turns typed Nix configuration into Proxmox VE autoinstall answer files and prepared ISOs (answer embedded, `--fetch-from iso`).

The configuration is a Nix module (`modules/schema.nix`): values are self-validating (types check CIDR/MAC/mailto format, enums restrict filesystem and raid levels), and module assertions enforce the rest (exactly one password variant, disk list present, unique host names). The generated TOML and the built ISOs are validated with the PVE-supplied tools (`validate-answer`, `inspect-iso`); there are no hand-rolled schema checks. The end-to-end workflow is documented in the infrastructure repo's `pve/autoinstall.md` (single source of truth for structure); this package automates the render/validate/build steps.

## Options (per host, in `hosts = [ ... ]`)

Option order here (and in `modules/schema.nix`) follows the rendered TOML sections.

| Option | Type | Default | Notes |
|---|---|---|---|
| `name` | `^[a-z][a-z0-9-]*$` | required | short host name; used for output naming (not rendered) |
| `keyboard` | string | `"si"` | [global] |
| `country` | string | `"si"` | [global] |
| `timezone` | string | `"Europe/Ljubljana"` | [global] |
| `fqdn` | string | required | [global]; domain part becomes the search domain |
| `mailto` | email | required | [global] root mail target |
| `rootPassword` | string or null | null | [global] plain `root-password`; set exactly one of the two password options |
| `rootPasswordHashed` | string or null | null | [global] `root-password-hashed` (e.g. `mkpasswd -m yescrypt`) |
| `sshKeys` | list of strings | `[ ]` | [global] root `authorized_keys` entries |
| `cidr` | IPv4 CIDR | required | [network] management NIC, static |
| `dns` | IPv4 | required | [network] |
| `gateway` | IPv4 | required | [network] |
| `bootMac` | MAC | required | [network] install/management NIC; collected with `proxmox-auto-install-assistant device-info -t network` |
| `pinning.enabled` | bool | `true` | [network.interface-name-pinning] |
| `pinning.mappings` | list of `{ mac; name; }` | `[ ]` | [network.interface-name-pinning] MAC to name pairs, first entry should be the boot NIC; omit for deterministic auto-pinned `nic0/nic1/...` names; MACs render lowercase |
| `filesystem` | `zfs`/`ext4`/`xfs`/`btrfs` | `"zfs"` | [disk-setup] |
| `zfsRaid` | `single`/`mirror`/`raid0`/`raid1`/`raid10`/`raidz1`/`raidz2`/`raidz3` | `"raid0"` | [disk-setup] only used when `filesystem = "zfs"` |
| `diskList` | list of strings | required | [disk-setup] target root disks; confirm per host with `device-info -t disk` |

Assertions (fail at evaluation with a message): exactly one of `rootPassword`/`rootPasswordHashed`, non-empty `diskList`, unique host names, and all type formats above.

## Password policy

Set `rootPassword` (or the hashed variant) in the config, deploy, then reset the root password after deployment for easier management.

The password value (plain or hash) is stored verbatim in the generated answer file and embedded verbatim in the built ISO. Keep built answer files and ISOs out of any shared/public store (and keep the answers directory private, e.g. mode 700). A real `config/default.nix` never enters git (gitignored); the example config carries only throwaway values.

## Usage

```sh
nix build .#pve-answers   # answers/<host>.toml
nix build .#pve-isos      # isos/<host>.iso
nix flake check .         # validate-answer + inspect-iso per host
```

Default config resolution: `config/default.nix` if it exists, else `config/example.nix` (unit-test example). For real hosts, create `config/default.nix` with the same shape and real values (it is gitignored), or call the factory directly with any module (path or attrset):

```nix
builtins.getFlake <path-to-root-flake>.inputs.pve-autoinstall.mkPve {
  config = ./my-hosts.nix;
}
```

## ISO pin

The pinned ISO constants live in `flake.nix` (`pveIso = { version, url, hash }`). To bump:

1. Note the new release name from https://www.proxmox.com/en/downloads.
2. Fetch and hash the new URL without trusting it: `nix store prefetch-file --json --hash-type sha256 <URL>` and copy the printed `hash` (SRI form) plus `version` into `pveIso`.
3. Re-run `nix flake check`: the `validate-answer` and `inspect-iso` checks confirm the updated ISO still embeds the per-host answers.

`download.proxmox.com` currently serves a mismatching TLS cert, so the pin uses `enterprise.proxmox.com` (same ISO, HTTP 200).
