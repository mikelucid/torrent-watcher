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
