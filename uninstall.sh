#!/bin/bash
# X++ uninstaller (Linux / macOS) - safe by default.
#
#   ./uninstall.sh                 # dry-run: list what it would remove
#   ./uninstall.sh --yes           # remove known X++ installs
#   ./uninstall.sh --yes --deep    # also scan XPP/Xite-named dirs on home+/usr/local
#   ./uninstall.sh --yes --deep --full   # scan the whole filesystem (slow)
set -u
cd "$(dirname "$0")"
PY="python3"
command -v "$PY" >/dev/null 2>&1 || PY="python"
if ! command -v "$PY" >/dev/null 2>&1; then
  echo "python3/python not found - install Python 3 and rerun." >&2
  exit 1
fi
exec "$PY" tools/uninstall_xpp.py "$@"
