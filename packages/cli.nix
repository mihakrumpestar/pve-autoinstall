# pve-autoinstall CLI: a thin bash frontend over the flake's factory. The flake
# source path is baked in at build time; every nix expression goes through the
# same prelude (resolving flake + config via the environment) so the factory and
# renderer are never imported directly from the script.
{
  pkgs,
  lib,
  flakeSrc,
  pveIso,
}:
let
  script = pkgs.writeShellScript "pve-autoinstall" ''
    set -u

    export PVE_AUTOINSTALL_FLAKE=${lib.escapeShellArg (toString flakeSrc)}
    PVE_VERSION=${lib.escapeShellArg pveIso.version}
    NIX_CMD=${lib.escapeShellArg (lib.getExe pkgs.nix)}
    PROG=pve-autoinstall

    err() {
      printf '%s: %s\n' "$PROG" "$1" >&2
      printf "Run '%s --help' for usage.\n" "$PROG" >&2
    }

    usage() {
      cat <<'USAGE'
    pve-autoinstall [OPTIONS] <config.nix>

    Build per-host Proxmox VE autoinstall answer files (.toml) and prepared ISOs
    from a Nix configuration module.

    Options:
      -o, --out DIR        Output directory (default: ./pve-result)
          --answers-only   Build only the answer files
          --isos-only      Build only the ISOs
      -H, --host NAME      Restrict to host NAME (repeatable)
          --list           Print host names from the config, one per line, and exit
          --no-check       Skip per-host validation checks
      -h, --help           Show this help
    USAGE
      printf 'PVE ISO: %s\n' "$PVE_VERSION"
    }

    # nix 2.34.x wants these flags after the subcommand, not before it.
    nix_run() {
      sub=$1
      shift
      "$NIX_CMD" "$sub" --extra-experimental-features "nix-command flakes" --impure --no-write-lock-file "$@"
    }

    # Single source of truth for every nix expression: resolve the flake and the
    # config from the environment, then build the factory result.
    PRELUDE='let flake = builtins.getFlake (builtins.getEnv "PVE_AUTOINSTALL_FLAKE"); config = /. + builtins.getEnv "PVE_AUTOINSTALL_CONFIG"; p = flake.lib.mkPve { inherit config; }; in '

    out=./pve-result
    answers_only=0
    isos_only=0
    no_check=0
    do_list=0
    hosts=""
    config=

    while [ "$#" -gt 0 ]; do
      case "$1" in
        -o|--out)
          if [ "$#" -lt 2 ]; then err "option $1 requires an argument"; exit 2; fi
          out=$2
          shift 2
          ;;
        --answers-only)
          answers_only=1
          shift
          ;;
        --isos-only)
          isos_only=1
          shift
          ;;
        -H|--host)
          if [ "$#" -lt 2 ]; then err "option $1 requires an argument"; exit 2; fi
          if [ -z "$hosts" ]; then hosts=$2; else hosts="$hosts $2"; fi
          shift 2
          ;;
        --list)
          do_list=1
          shift
          ;;
        --no-check)
          no_check=1
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        -*)
          err "unknown option: $1"
          exit 2
          ;;
        *)
          if [ -z "$config" ]; then config=$1; else err "unexpected argument: $1"; exit 2; fi
          shift
          ;;
      esac
    done

    if [ -z "$config" ]; then
      err "missing required <config.nix> argument"
      exit 2
    fi

    config=$(readlink -f "$config")
    if [ ! -f "$config" ]; then
      err "config not found or not a regular file: $config"
      exit 2
    fi
    export PVE_AUTOINSTALL_CONFIG=$config

    if [ "$answers_only" -eq 1 ] && [ "$isos_only" -eq 1 ]; then
      err "--answers-only and --isos-only are mutually exclusive"
      exit 2
    fi

    if [ "$do_list" -eq 1 ]; then
      nix_run eval --raw --expr "$PRELUDE builtins.concatStringsSep \"\\n\" (builtins.attrNames p.answers)" || exit 1
      printf '\n'
      exit 0
    fi

    build_answers=1
    build_isos=1
    if [ "$answers_only" -eq 1 ]; then build_isos=0; fi
    if [ "$isos_only" -eq 1 ]; then build_answers=0; fi

    all_hosts=$(nix_run eval --raw --expr "$PRELUDE builtins.concatStringsSep \" \" (builtins.attrNames p.answers)") || exit 1

    if [ -n "$hosts" ]; then
      selected_hosts=$hosts
    else
      selected_hosts=$all_hosts
    fi

    for host in $selected_hosts; do
      if [ "$build_answers" -eq 1 ]; then
        link="$out/answers/$host.toml"
        mkdir -p "$(dirname "$link")"
        nix_run build --out-link "$link" --expr "$PRELUDE p.answers.$host" || exit 1
      fi
      if [ "$build_isos" -eq 1 ]; then
        link="$out/isos/$host.iso"
        mkdir -p "$(dirname "$link")"
        nix_run build --out-link "$link" --expr "$PRELUDE p.isos.$host" || exit 1
      fi
    done

    if [ "$no_check" -eq 0 ]; then
      if [ -z "$hosts" ] && [ "$build_answers" -eq 1 ] && [ "$build_isos" -eq 1 ]; then
        nix_run build --no-link --expr "$PRELUDE p.checks" || exit 1
      else
        # pve-answer-validates-<host> / pve-iso-is-autoinstall-<host> are the
        # factory's public check-name contract defined in packages/default.nix.
        checks_expr="$PRELUDE {"
        for host in $selected_hosts; do
          if [ "$build_answers" -eq 1 ]; then
            checks_expr="$checks_expr inherit (p.checks) pve-answer-validates-$host;"
          fi
          if [ "$build_isos" -eq 1 ]; then
            checks_expr="$checks_expr inherit (p.checks) pve-iso-is-autoinstall-$host;"
          fi
        done
        checks_expr="$checks_expr }"
        nix_run build --no-link --expr "$checks_expr" || exit 1
      fi
    fi

    if [ "$build_answers" -eq 1 ]; then
      printf '%s: built answers for %s -> %s/answers\n' "$PROG" "$selected_hosts" "$out"
    fi
    if [ "$build_isos" -eq 1 ]; then
      printf '%s: built isos for %s -> %s/isos\n' "$PROG" "$selected_hosts" "$out"
    fi
  '';
in
{
  type = "app";
  program = toString script;
  meta.description = "Build Proxmox VE autoinstall answer files and prepared ISOs from a Nix config module";
}
