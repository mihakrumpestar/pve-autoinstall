#!/usr/bin/env bats
# CLI argument-parsing tests. These need only the built CLI, not the ISO
# build, so they run fast; the -H rejection test additionally runs one nix
# eval of the example config (no builds).
#
# Point PVE_CLI at the built executable (a store bin path, or the store output
# directory containing bin/pve-autoinstall). `task test` builds it and exports
# the path; without PVE_CLI every test is skipped.
#
#   PVE_CLI=/nix/store/...-pve-autoinstall/bin/pve-autoinstall bats tests/cli.bats

setup() {
  if [ -z "${PVE_CLI:-}" ]; then
    skip "PVE_CLI is not set; build the CLI app and export its path"
  fi
  CLI="$PVE_CLI"
  if [ -d "$CLI" ]; then
    CLI="$CLI/bin/pve-autoinstall"
  fi
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CONFIG="$REPO_ROOT/config/example.nix"
}

@test "--help exits 0 and prints usage" {
  run "$CLI" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"pve-autoinstall [OPTIONS]"* ]]
  [[ "$output" == *"PVE ISO:"* ]]
}

@test "missing config exits 2" {
  run "$CLI"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing required <config.nix>"* ]]
}

@test "-o without an argument exits 2" {
  run "$CLI" -o
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires an argument"* ]]
}

@test "--answers-only and --isos-only are mutually exclusive (exit 2)" {
  run "$CLI" --answers-only --isos-only "$CONFIG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "unknown option exits 2" {
  run "$CLI" --definitely-not-an-option
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "-H with an empty value exits 2" {
  run "$CLI" -H ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"non-empty host name"* ]]
}

@test "-H with an unknown host exits 2 and lists the valid hosts" {
  run "$CLI" -H no-such-host "$CONFIG"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown host: no-such-host (valid:"* ]]
}

@test "-o with an empty value exits 2" {
  run "$CLI" -o ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"non-empty directory"* ]]
}

@test "-- ends option parsing (a following flag is a positional)" {
  # Without --, --help would print usage and exit 0; after -- it is a config
  # path, so it must fail as a missing file instead.
  run "$CLI" -- --help
  [ "$status" -eq 2 ]
  [[ "$output" == *"config not found"* ]]
  [[ "$output" != *"pve-autoinstall [OPTIONS]"* ]]
}

@test "-- allows only one positional argument" {
  run "$CLI" -- "$CONFIG" extra.nix
  [ "$status" -eq 2 ]
  [[ "$output" == *"unexpected argument: extra.nix"* ]]
}
