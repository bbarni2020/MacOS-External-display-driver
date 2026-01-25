#!/bin/sh
set -e

# Configuration
REPO="bbarni2020/MacOS-External-display-driver"
BRANCH="main"
FOLDER="raspberry-pi-receiver"
DEST="${PWD}"

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    branch=*) BRANCH="${arg#branch=}" ;;
  esac
done

echo "Updating DeskExtend Receiver from $REPO (branch $BRANCH)..."

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

ZIP="$TMPDIR/repo.zip"
curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.zip" -o "$ZIP"
unzip -q "$ZIP" -d "$TMPDIR"

EXTRACTED_ROOT=$(find "$TMPDIR" -maxdepth 1 -type d -name "*-$BRANCH" | head -n1)
if [ -z "$EXTRACTED_ROOT" ]; then
  EXTRACTED_ROOT=$(find "$TMPDIR" -maxdepth 1 -type d | grep -v "$TMPDIR" | head -n1)
fi

SRC="$EXTRACTED_ROOT/$FOLDER"
if [ ! -d "$SRC" ]; then
  echo "Folder $FOLDER not found in $REPO (branch $BRANCH)"
  exit 2
fi

cp -a "$SRC/." "$DEST/"
chmod +x "$DEST/receiver.py" 2>/dev/null || true
chmod +x "$DEST/run.sh" 2>/dev/null || true

if [ -f "$DEST/requirements.txt" ]; then
  if [ -d "$DEST/venv" ]; then
    echo "Updating Python virtualenv and requirements..."
    "$DEST/venv/bin/python" -m pip install --upgrade pip setuptools wheel
    "$DEST/venv/bin/pip" install -r "$DEST/requirements.txt"
  else
    echo "Virtualenv not found, installing requirements globally or creating venv..."
    if command -v python3 >/dev/null 2>&1; then
      python3 -m venv "$DEST/venv"
      "$DEST/venv/bin/python" -m pip install --upgrade pip setuptools wheel
      "$DEST/venv/bin/pip" install -r "$DEST/requirements.txt"
    else
      if command -v pip3 >/dev/null 2>&1; then
        pip3 install -r "$DEST/requirements.txt"
      else
        echo "Python not available, please install requirements manually"
      fi
    fi
  fi
fi

echo "Update complete. Starting DeskExtend Receiver..."
exec chmod +x "$DEST/receiver.py" 2>/dev/null || true
exec "$DEST/receiver.py"