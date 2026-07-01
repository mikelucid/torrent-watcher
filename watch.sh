#!/usr/bin/env bash
set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DOWNLOADS_DIR="${HOME}/Downloads"
TORRENTS_DIR="${HOME}/Documents/.transmission/torrents"
SEEDS_DIR="${HOME}/Documents/.transmission/seeds"
LOG_FILE="${HOME}/Library/Logs/torrent-watcher.log"
CHECK_INTERVAL=1
QUIET_MODE=false
HEADLESS_MODE=false
TRANSMISSION_RPC_PORT=6969
TRANSMISSION_RPC_URL="http://localhost:${TRANSMISSION_RPC_PORT}/rpc"
STATE_FILE="${HOME}/.torrent-watcher-state"

# Parse command-line arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --headless)
        HEADLESS_MODE=true
        shift
        ;;
      --gui)
        HEADLESS_MODE=false
        shift
        ;;
      --quiet)
        QUIET_MODE=true
        shift
        ;;
      --downloads)
        DOWNLOADS_DIR="$2"
        shift 2
        ;;
      --torrents)
        TORRENTS_DIR="$2"
        shift 2
        ;;
      --seeds)
        SEEDS_DIR="$2"
        shift 2
        ;;
      --interval)
        CHECK_INTERVAL="$2"
        shift 2
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        error "Unknown argument: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

# Show help message
show_help() {
  cat << 'EOF'
╔════════════════════════════════════════════════════════╗
║             Torrent Watcher - Help                     ║
╚════════════════════════════════════════════════════════╝

USAGE:
  torrent-watcher.sh [OPTIONS]

OPTIONS:
  --headless              Run in headless mode (background seeding)
  --gui                   Run in GUI mode (default, opens Transmission window)
  --quiet                 Suppress console output
  --downloads DIR         Set downloads directory (default: ~/Downloads)
  --torrents DIR          Set torrents directory (default: ~/Documents/.transmission/torrents)
  --seeds DIR             Set seeds directory (default: ~/Documents/.transmission/seeds)
  --interval SEC          Set check interval in seconds (default: 1)
  --help, -h              Show this help message

EXAMPLES:
  # Start in GUI mode (default)
  ./torrent-watcher.sh

  # Start in headless mode
  ./torrent-watcher.sh --headless

  # Start in headless quiet mode
  ./torrent-watcher.sh --headless --quiet

  # Custom directories
  ./torrent-watcher.sh --downloads /path/to/downloads --torrents /path/to/torrents --seeds /path/to/seeds

  # Run in background in headless mode
  ./torrent-watcher.sh --headless --quiet &

INTERACTIVE COMMANDS (when running):
  h / H                   Toggle between headless and GUI mode
  q / Q                   Quit the script
  s / S                   Show current status

FOLDER STRUCTURE:
  ~/Downloads/              - Active downloads (partial & complete)
  ~/.transmission/torrents/ - .torrent files storage
  ~/.transmission/seeds/    - Seeding directory

BEHAVIOR:
  - On startup: Scans Downloads for .torrent files and moves them to Torrents folder
  - Partial/Active torrents: Stay in Downloads folder
  - Complete torrents: Seed from Seeds folder
  - New torrents: Downloaded to Downloads, metadata stored in Torrents

EOF
}

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
  local level=$1
  shift
  local message="$@"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
  [ "$QUIET_MODE" = false ] && echo -e "${BLUE}[${timestamp}]${NC} $message"
}

# Error logging
error() {
  local message="$@"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
  [ "$QUIET_MODE" = false ] && echo -e "${RED}[ERROR]${NC} $message" >&2
}

# Success logging
success() {
  local message="$@"
  log "SUCCESS" "$message"
  [ "$QUIET_MODE" = false ] && echo -e "${GREEN}✓ $message${NC}"
}

# Warning logging
warning() {
  local message="$@"
  log "WARNING" "$message"
  [ "$QUIET_MODE" = false ] && echo -e "${YELLOW}⚠ $message${NC}"
}

# Info logging
info() {
  local message="$@"
  log "INFO" "$message"
  [ "$QUIET_MODE" = false ] && echo -e "${CYAN}ℹ $message${NC}"
}

# Check if file is a torrent file
is_torrent() {
  local filename=$1
  [[ "$filename" == *.torrent ]]
}

# Check if file is currently being accessed (locked by Transmission)
is_file_locked() {
  local file=$1
  
  # Check if file is open by any process
  if lsof "$file" &>/dev/null; then
    return 0  # File is locked
  fi
  
  return 1  # File is not locked
}

# Check if torrent is complete in Transmission
is_torrent_complete() {
  local filename=$1
  local torrent_name="${filename%.torrent}"
  
  # Query Transmission for this torrent's status
  local response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    --data "{
      \"method\": \"torrent-get\",
      \"arguments\": {
        \"fields\": [\"name\", \"percentDone\", \"isFinished\"],
        \"filters\": [[\"name\", \"contains\", \"$torrent_name\"]]
      }
    }" \
    "$TRANSMISSION_RPC_URL" 2>/dev/null)
  
  # Check if percentDone is 1 (100%) or isFinished is true
  if echo "$response" | grep -q '"percentDone":1' || echo "$response" | grep -q '"isFinished":true'; then
    return 0  # Torrent is complete
  fi
  
  return 1  # Torrent is not complete
}

# Toggle headless mode
toggle_headless() {
  if [ "$HEADLESS_MODE" = true ]; then
    HEADLESS_MODE=false
    info "Switched to ${GREEN}GUI Mode${NC} - Transmission will open in the foreground"
    echo "false" > "$STATE_FILE"
  else
    HEADLESS_MODE=true
    info "Switched to ${MAGENTA}Headless Mode${NC} - Torrents will seed in the background"
    echo "true" > "$STATE_FILE"
  fi
}

# Display status
show_status() {
  local mode_text
  local mode_color
  
  if [ "$HEADLESS_MODE" = true ]; then
    mode_text="Headless (Background)"
    mode_color="$MAGENTA"
  else
    mode_text="GUI (Foreground)"
    mode_color="$GREEN"
  fi
  
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "Mode: ${mode_color}${mode_text}${NC}"
  echo -e "Downloads: ${CYAN}${DOWNLOADS_DIR}${NC}"
  echo -e "Torrents: ${CYAN}${TORRENTS_DIR}${NC}"
  echo -e "Seeds: ${CYAN}${SEEDS_DIR}${NC}"
  echo -e "Interval: ${CYAN}${CHECK_INTERVAL}s${NC}"
  echo -e ""
  echo -e "Controls:"
  echo -e "  ${YELLOW}h${NC} = toggle headless mode"
  echo -e "  ${YELLOW}s${NC} = show status"
  echo -e "  ${YELLOW}q${NC} = quit"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Check for keyboard input (non-blocking)
check_keyboard_input() {
  local input
  
  # Use timeout to read stdin without blocking
  if timeout 0.1 bash -c 'read -t 0.1 -n 1 input; echo "$input"' 2>/dev/null; then
    input=$(timeout 0.1 bash -c 'read -t 0.1 -n 1 input; echo "$input"' 2>/dev/null)
    case "$input" in
      h|H)
        toggle_headless
        ;;
      s|S)
        show_status
        ;;
      q|Q)
        error "Torrent Watcher stopped by user"
        log "INFO" "Torrent Watcher stopped by user"
        exit 0
        ;;
      *)
        ;;
    esac
  fi
}

# Validate directories
validate_dirs() {
  if [ ! -d "$DOWNLOADS_DIR" ]; then
    error "Downloads directory not found: $DOWNLOADS_DIR"
    return 1
  fi
  
  mkdir -p "$TORRENTS_DIR" || {
    error "Failed to create torrents directory: $TORRENTS_DIR"
    return 1
  }
  
  mkdir -p "$SEEDS_DIR" || {
    error "Failed to create seeds directory: $SEEDS_DIR"
    return 1
  }
  
  return 0
}

# Get file size in human-readable format
get_file_size() {
  local file=$1
  if [ -f "$file" ]; then
    du -h "$file" | awk '{print $1}'
  fi
}

# Add torrent to Transmission via RPC (headless mode)
add_torrent_headless() {
  local filename=$1
  local file_path="${TORRENTS_DIR}/${filename}"
  
  # Base64 encode the torrent file
  local base64_content
  base64_content=$(base64 < "$file_path" | tr -d '\n')
  
  # Send RPC request to Transmission
  local response
  response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    --data "{
      \"method\": \"torrent-add\",
      \"arguments\": {
        \"metainfo\": \"$base64_content\",
        \"download-dir\": \"$DOWNLOADS_DIR\"
      }
    }" \
    "$TRANSMISSION_RPC_URL" 2>/dev/null)
  
  # Check if the request was successful
  if echo "$response" | grep -q '"result":"success"'; then
    success "Added to Transmission (headless): ${GREEN}${filename}${NC}"
    log "INFO" "Torrent added via RPC: $filename"
    return 0
  else
    warning "Could not add via RPC, attempting GUI launch..."
    return 1
  fi
}

# Open a torrent file with the local Transmission client or system default
open_with_transmission() {
  local file_path=$1

  if command -v transmission-gtk >/dev/null 2>&1; then
    transmission-gtk "$file_path" >/dev/null 2>&1 &
    return 0
  fi

  if command -v transmission-qt >/dev/null 2>&1; then
    transmission-qt "$file_path" >/dev/null 2>&1 &
    return 0
  fi

  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$file_path" >/dev/null 2>&1 &
    return 0
  fi

  if command -v open >/dev/null 2>&1; then
    open -a Transmission "$file_path" >/dev/null 2>&1 &
    return 0
  fi

  warning "No supported Transmission launcher found. Please open $file_path manually."
  return 1
}

# Process torrent file - move from Downloads to Torrents folder
process_torrent() {
  local filename=$1
  local source="${DOWNLOADS_DIR}/${filename}"
  local dest="${TORRENTS_DIR}/${filename}"
  
  if [ ! -f "$source" ]; then
    warning "File disappeared: $filename"
    return 1
  fi
  
  local file_size=$(get_file_size "$source")
  info "Processing: ${MAGENTA}${filename}${NC} (${CYAN}${file_size}${NC})"
  
  # Move file to torrents folder
  if mv "$source" "$dest"; then
    success "Moved to torrents folder: ${GREEN}${filename}${NC}"
    
    # Open based on mode
    if [ "$HEADLESS_MODE" = true ]; then
      # Try RPC first, fall back to GUI if it fails
      if ! add_torrent_headless "$filename"; then
        info "Starting Transmission GUI..."
        open_with_transmission "$dest"
      fi
    else
      # GUI mode - open normally
      if open_with_transmission "$dest"; then
        success "Opened with Transmission (GUI): ${GREEN}${filename}${NC}"
      else
        warning "Could not open with Transmission. Please open manually: $dest"
      fi
    fi
  else
    error "Failed to move file: $filename"
    return 1
  fi
}

# Initial scan of Downloads folder
initial_scan() {
  info "Performing initial scan of Downloads folder..."
  
  local torrent_count=0
  local skipped_count=0
  
  for file in "$DOWNLOADS_DIR"/*.torrent; do
    [ -e "$file" ] || continue
    
    local filename=$(basename "$file")
    local dest="${TORRENTS_DIR}/${filename}"
    
    # Skip if already in torrents folder
    if [ -f "$dest" ]; then
      info "Already in torrents folder: ${YELLOW}${filename}${NC}"
      ((skipped_count++))
      continue
    fi
    
    # Check if file is locked (being used by Transmission)
    if is_file_locked "$file"; then
      info "Torrent is active (locked): ${YELLOW}${filename}${NC} - Keeping in Downloads"
      ((skipped_count++))
      continue
    fi
    
    # If not locked, move to torrents folder
    info "Found torrent file: ${MAGENTA}${filename}${NC}"
    process_torrent "$filename"
    ((torrent_count++))
  done
  
  if [ "$torrent_count" -gt 0 ] || [ "$skipped_count" -gt 0 ]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    info "Initial scan complete: ${GREEN}${torrent_count}${NC} moved, ${YELLOW}${skipped_count}${NC} skipped/active"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  else
    info "Initial scan complete: No torrents found"
  fi
}

# Main watcher loop
main() {
  validate_dirs || exit 1
  
  # Load previous state if not explicitly set via CLI
  if [ "$HEADLESS_MODE" = false ] && [ -f "$STATE_FILE" ]; then
    HEADLESS_MODE=$(cat "$STATE_FILE")
  fi
  
  local mode_display
  if [ "$HEADLESS_MODE" = true ]; then
    mode_display="Headless"
  else
    mode_display="GUI"
  fi
  
  if [ "$QUIET_MODE" = false ]; then
    echo -e "${MAGENTA}"
    echo "╔════════════════════════════════════════╗"
    echo "║   Torrent Watcher Started               ║"
    echo "║   Mode: $mode_display"
    echo "║   Watching: $DOWNLOADS_DIR"
    echo "║   Torrents: $TORRENTS_DIR"
    echo "║   Seeds: $SEEDS_DIR"
    echo "║   Log File: $LOG_FILE"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"
  fi
  
  log "INFO" "Torrent Watcher started (Headless: $HEADLESS_MODE, Quiet: $QUIET_MODE)"
  
  # Perform initial scan
  initial_scan
  
  if [ "$QUIET_MODE" = false ]; then
    show_status
  fi
  
  first=1
  prev=$(ls -f "$DOWNLOADS_DIR/" 2>/dev/null)
  
  while true; do
    # Check for keyboard input
    check_keyboard_input
    
    curr=$(ls -f "$DOWNLOADS_DIR/" 2>/dev/null)
    
    if [ "$first" -eq 1 ]; then
      info "Watching for new .torrent files..."
      first=0
    fi
    
    if [ "$curr" != "$prev" ]; then
      [ "$QUIET_MODE" = false ] && echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      info "Change detected in Downloads folder"
      
      # Get new files
      file_list=$(diff <(echo "$prev") <(echo "$curr") | grep '^>' | awk '{$1=""; print $0}' | sed 's/^ //')
      
      prev=$curr
      
      # Process each new file
      while IFS= read -r filename; do
        [ -z "$filename" ] && continue
        
        if is_torrent "$filename"; then
          # Give file time to fully write if it was just created          
          local source="${DOWNLOADS_DIR}/${filename}"
          if [ -f "$source" ]; then
            # Check if it's locked (still being downloaded)
            if is_file_locked "$source"; then
              info "Torrent is being downloaded: ${YELLOW}${filename}${NC} - Keeping in Downloads"
            else
              # Not locked, move to torrents folder
              process_torrent "$filename"
            fi
          fi
        else
          info "Skipped non-torrent file: ${YELLOW}${filename}${NC}"
        fi
      done <<< "$file_list"
      
      [ "$QUIET_MODE" = false ] && echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
    
    sleep "$CHECK_INTERVAL"
  done
}

# Parse CLI arguments and start the watcher
parse_arguments "$@"
main
