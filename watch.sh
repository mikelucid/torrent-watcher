#!/usr/bin/env bash
set -euo pipefail

# macOS Search and Quarantine Helper
# Works on Monterey and later. This script is a helper, not a replacement for a full AV scan.

QUARANTINE_DIR="${HOME}/Quarantine"
SCAN_PATHS=("${HOME}/Downloads" "${HOME}/Desktop" "${HOME}/Documents" "${HOME}/Applications" "/tmp")
DRY_RUN=false
VERBOSE=true

print_help() {
  cat <<'EOF'
Usage: mac_search_quarantine.sh [options]

Options:
  --scan-only           Only list suspicious files, do not quarantine or move them.
  --quarantine          Move suspicious files to ~/Quarantine and apply quarantine metadata.
  --path DIR            Add an additional directory to scan.
  --quiet               Suppress informational output.
  --help, -h            Show this help message.

Example:
  ./mac_search_quarantine.sh --scan-only
  ./mac_search_quarantine.sh --quarantine --path /Volumes/USB
EOF
}

log() {
  if [ "$VERBOSE" = true ]; then
    printf '%s\n' "$1"
  fi
}

error() {
  printf 'ERROR: %s\n' "$1" >&2
}

check_macos() {
  if [ "$(uname)" != "Darwin" ]; then
    error "This script is intended for macOS only."
    exit 1
  fi
}

ensure_quarantine_dir() {
  mkdir -p "$QUARANTINE_DIR"
}

file_has_quarantine_attr() {
  local file="$1"
  xattr -p com.apple.quarantine "$file" >/dev/null 2>&1
}

suspicious_name_match() {
  local base="$1"
  case "$base" in
    *crack*|*keygen*|*serial*|*license*|*patch*|*trojan*|*backdoor*|*exploit*|*payload*|*virus*|*malware*|*installer*|*update*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

scan_directory() {
  local path="$1"
  local result

  if [ ! -e "$path" ]; then
    return
  fi

  while IFS= read -r -d '' file; do
    local base
    base=$(basename "$file")

    if [ -d "$file" ] && [[ "$file" == *.app ]]; then
      log "  [APP]   $file"
      suspicious_files+=("$file")
      continue
    fi

    if [ -f "$file" ]; then
      local mode
      mode=$(stat -f '%A' "$file" 2>/dev/null || true)

      if [ -x "$file" ] || [[ "$file" == *.command ]] || [[ "$file" == *.sh ]] || [[ "$file" == *.pkg ]] || [[ "$file" == *.dmg ]] || [[ "$file" == *.py ]] || [[ "$file" == *.jar ]] || [[ "$file" == *.zip ]] || [[ "$file" == *.tar* ]] || [[ "$file" == *.deb ]] || [[ "$file" == *.exe ]] || [[ "$file" == *.bat ]] || [[ "$file" == *.apk ]]; then
        if suspicious_name_match "$base" || ! file_has_quarantine_attr "$file" || [[ "$mode" =~ x ]]; then
          log "  [FILE]  $file"
          suspicious_files+=("$file")
        fi
      fi
    fi
  done < <(find "$path" -maxdepth 3 \( -iname '*.app' -o -iname '*.pkg' -o -iname '*.dmg' -o -iname '*.command' -o -iname '*.sh' -o -iname '*.py' -o -iname '*.jar' -o -iname '*.zip' -o -iname '*.tar' -o -iname '*.tar.gz' -o -iname '*.tar.bz2' -o -iname '*.exe' -o -iname '*.bat' -o -iname '*.apk' \) -print0 2>/dev/null)
}

quarantine_file() {
  local file="$1"
  local target
  target="$QUARANTINE_DIR/$(basename "$file")"

  if [ -e "$target" ]; then
    target="$QUARANTINE_DIR/$(basename "$file")-$(date +%s)"
  fi

  if mv "$file" "$target"; then
    xattr -w com.apple.quarantine "0083;00000000;mac_search_quarantine;" "$target" >/dev/null 2>&1 || true
    log "    -> quarantined: $target"
  else
    error "Failed to quarantine: $file"
  fi
}

main() {
  check_macos
  ensure_quarantine_dir

  local ACTION="scan"
  local extra_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --scan-only)
        ACTION="scan"
        shift
        ;;
      --quarantine)
        ACTION="quarantine"
        shift
        ;;
      --path)
        extra_path="$2"
        SCAN_PATHS+=("$extra_path")
        shift 2
        ;;
      --quiet)
        VERBOSE=false
        shift
        ;;
      --help|-h)
        print_help
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        print_help
        exit 1
        ;;
    esac
  done

  log "Scanning macOS paths. This is a helper script, not a full antivirus scan."

  suspicious_files=()
  for path in "${SCAN_PATHS[@]}"; do
    if [ -d "$path" ]; then
      log "Scanning: $path"
      scan_directory "$path"
    fi
  done

  if [ ${#suspicious_files[@]} -eq 0 ]; then
    log "No obvious suspicious files found in the standard directories."
    exit 0
  fi

  log "Found ${#suspicious_files[@]} suspicious file(s)."
  for file in "${suspicious_files[@]}"; do
    log "  - $file"
  done

  if [ "$ACTION" = "quarantine" ]; then
    log "Quarantining suspicious files into: $QUARANTINE_DIR"
    for file in "${suspicious_files[@]}"; do
      quarantine_file "$file"
    done
    log "Quarantine complete. Review files in $QUARANTINE_DIR before deleting."
  else
    log "Run with --quarantine to move these files into quarantine."
  fi
}

main "$@"
