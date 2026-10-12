# pve-autoinstall CLI: a thin bash frontend over the flake's factory. The flake
# source path is baked in at build time; every nix expression goes through the
# same prelude (resolving flake + config via the environment) so the factory and
# renderer are never imported directly from the script.
#
# Host names are never interpolated into shell or nix source: selections travel
# through the environment and are read back with builtins.getEnv /
# builtins.fromJSON. The output directory is created only once a build will run.
{
  pkgs,
  lib,
  flakeSrc,
  pveIso,
}:
let
  script = pkgs.writeShellApplication {
    name = "pve-autoinstall";
    # readlink/dirname must resolve hermetically, so coreutils is pinned too.
    runtimeInputs = [
      pkgs.nix
      pkgs.coreutils
    ];
    meta.description = "Build Proxmox VE autoinstall answer files and prepared ISOs from a Nix config module";
    text = ''
      export PVE_AUTOINSTALL_FLAKE=${lib.escapeShellArg (toString flakeSrc)}
      PVE_VERSION=${lib.escapeShellArg pveIso.version}
      NIX_CMD=${lib.escapeShellArg (lib.getExe pkgs.nix)}
      PROG=pve-autoinstall

      # Answers can embed secrets (the hashed root password); keep the output
      # directory private from the moment the script starts.
      umask 077

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
            --list           Print host names from the config (or only those selected with -H), one per line, and exit
            --no-check       Skip per-host validation checks
        -h, --help           Show this help

      Use `--` to end option parsing; the next argument is taken as <config.nix>.
      USAGE
        printf 'PVE ISO: %s\n' "$PVE_VERSION"
      }

      # nix 2.34.x wants these flags after the subcommand, not before it.
      nix_run() {
        sub="$1"
        shift
        "$NIX_CMD" "$sub" --extra-experimental-features "nix-command flakes" --impure --no-write-lock-file "$@"
      }

      # JSON-quote one host name. Names are already charset-validated by the
      # schema (^[A-Za-z0-9][A-Za-z0-9_+-]*$); the escaping is defensive only.
      json_string() {
        local value="$1"
        value="''${value//\\/\\\\}"
        value="''${value//\"/\\\"}"
        printf '"%s"' "$value"
      }

      # Every nix expression goes through this one prelude: resolve the flake
      # and the config from the environment, then build the factory result.
      PRELUDE='let flake = builtins.getFlake (builtins.getEnv "PVE_AUTOINSTALL_FLAKE"); config = /. + builtins.getEnv "PVE_AUTOINSTALL_CONFIG"; p = flake.lib.mkPve { inherit config; }; in '
      HOSTNAMES_EXPR="$PRELUDE"'builtins.concatStringsSep " " (builtins.attrNames p.answers)'
      ANSWERS_EXPR="$PRELUDE"'builtins.getAttr (builtins.getEnv "PVE_AUTOINSTALL_HOST") p.answers'
      ISOS_EXPR="$PRELUDE"'builtins.getAttr (builtins.getEnv "PVE_AUTOINSTALL_HOST") p.isos'

      out=./pve-result
      answers_only=0
      isos_only=0
      no_check=0
      do_list=0
      end_of_opts=0
      config=
      selected_hosts=()
      all_hosts=()

      while [ "$#" -gt 0 ]; do
        # After `--` the remaining arguments are positionals (only one allowed).
        if [ "$end_of_opts" -eq 1 ]; then
          if [ -z "$config" ]; then
            config="$1"
          else
            err "unexpected argument: $1"
            exit 2
          fi
          shift
          continue
        fi
        case "$1" in
          -o|--out)
            if [ "$#" -lt 2 ]; then err "option $1 requires an argument"; exit 2; fi
            if [ -z "$2" ]; then err "option $1 requires a non-empty directory"; exit 2; fi
            out="$2"
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
            if [ -z "$2" ]; then err "option $1 requires a non-empty host name"; exit 2; fi
            selected_hosts+=("$2")
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
          --)
            end_of_opts=1
            shift
            ;;
          -*)
            err "unknown option: $1"
            exit 2
            ;;
          *)
            if [ -z "$config" ]; then config="$1"; else err "unexpected argument: $1"; exit 2; fi
            shift
            ;;
        esac
      done

      if [ -z "$config" ]; then
        err "missing required <config.nix> argument"
        exit 2
      fi

      # Flag validation stays up here so a broken config never masks a flag
      # error (the config is only resolved below).
      if [ "$answers_only" -eq 1 ] && [ "$isos_only" -eq 1 ]; then
        err "--answers-only and --isos-only are mutually exclusive"
        exit 2
      fi

      # Derive the whole build state from the two mode flags in one place:
      # what to build and which checks to run. check_mode picks the matching
      # subset of the factory's per-host checks, so --answers-only /
      # --isos-only never force the other artifact to be built.
      build_answers=1
      build_isos=1
      check_mode=all
      if [ "$answers_only" -eq 1 ]; then
        build_isos=0
        check_mode=answers
      elif [ "$isos_only" -eq 1 ]; then
        build_answers=0
        check_mode=isos
      fi

      # readlink -f fails (exit 1) when a parent component is missing; capture it
      # explicitly so a bad path reports the friendly error instead of aborting.
      resolved=$(readlink -f "$config" 2>/dev/null) || resolved=
      if [ -z "$resolved" ] || [ ! -f "$resolved" ]; then
        err "config not found or not a regular file: $config"
        exit 2
      fi
      config="$resolved"
      export PVE_AUTOINSTALL_CONFIG="$config"

      # Resolve the config's host list once, then validate any -H selection
      # against it so an unknown host fails fast with the valid names.
      all_hosts_raw=$(nix_run eval --raw --expr "$HOSTNAMES_EXPR") || exit 1
      read -r -a all_hosts <<< "$all_hosts_raw" || true

      if [ "''${#selected_hosts[@]}" -gt 0 ]; then
        for host in "''${selected_hosts[@]}"; do
          known=0
          for candidate in "''${all_hosts[@]}"; do
            if [ "$host" = "$candidate" ]; then known=1; break; fi
          done
          if [ "$known" -eq 0 ]; then
            err "unknown host: $host (valid: ''${all_hosts[*]})"
            exit 2
          fi
        done
      else
        selected_hosts=("''${all_hosts[@]}")
      fi

      # --list is eval-only: it never realizes the answer/ISO derivations.
      if [ "$do_list" -eq 1 ]; then
        for host in "''${selected_hosts[@]}"; do
          printf '%s\n' "$host"
        done
        exit 0
      fi

      # Create the output dirs only now that a build is actually going to run.
      if [ "$build_answers" -eq 1 ]; then mkdir -p "$out/answers"; fi
      if [ "$build_isos" -eq 1 ]; then mkdir -p "$out/isos"; fi

      for host in "''${selected_hosts[@]}"; do
        export PVE_AUTOINSTALL_HOST="$host"
        if [ "$build_answers" -eq 1 ]; then
          nix_run build --out-link "$out/answers/$host.toml" --expr "$ANSWERS_EXPR" || exit 1
        fi
        if [ "$build_isos" -eq 1 ]; then
          nix_run build --out-link "$out/isos/$host.iso" --expr "$ISOS_EXPR" || exit 1
        fi
      done

      if [ "$no_check" -eq 0 ]; then
        # Hosts travel as a JSON array via the environment; nix reads it back
        # with builtins.fromJSON, so no host name is ever spliced into source.
        hosts_json="["
        sep=
        for host in "''${selected_hosts[@]}"; do
          hosts_json+="$sep$(json_string "$host")"
          sep=,
        done
        hosts_json+="]"
        export PVE_AUTOINSTALL_HOSTS="$hosts_json"

        CHECKS_EXPR="$PRELUDE"'p.selectChecks { hosts = builtins.fromJSON (builtins.getEnv "PVE_AUTOINSTALL_HOSTS"); mode = "'"$check_mode"'"; }'
        nix_run build --no-link --expr "$CHECKS_EXPR" || exit 1
      fi

      if [ "$build_answers" -eq 1 ]; then
        printf '%s: built answers for %s -> %s/answers\n' "$PROG" "''${selected_hosts[*]}" "$out"
      fi
      if [ "$build_isos" -eq 1 ]; then
        printf '%s: built isos for %s -> %s/isos\n' "$PROG" "''${selected_hosts[*]}" "$out"
      fi
    '';
  };
in
script
