#!/bin/sh
set -e

# Configuration
REPO="bbarni2020/MacOS-External-display-driver"
BRANCH="main"
FOLDER="raspberry-pi-receiver"
DEST="${PWD}"
DISPLAY_NAME="Office Display"

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
chmod +x "$DEST/receiver.py" "$DEST/run.sh" 2>/dev/null || true

if [ -f "$DEST/requirements.txt" ]; then
  if [ -d "$DEST/venv" ]; then
    echo "Updating Python virtualenv and requirements..."
    "$DEST/venv/bin/python" -m pip install --upgrade pip setuptools wheel
    "$DEST/venv/bin/pip" install -r "$DEST/requirements.txt"
  else
    echo "Setting up virtualenv..."
    python3 -m venv "$DEST/venv"
    "$DEST/venv/bin/python" -m pip install --upgrade pip setuptools wheel
    "$DEST/venv/bin/pip" install -r "$DEST/requirements.txt"
  fi
fi

echo "Update complete. Starting DeskExtend Receiver..."
. "$DEST/venv/bin/activate"
"$DEST/venv/bin/python" "$DEST/receiver.py" --mode hybrid --name "$DISPLAY_NAME"
