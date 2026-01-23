#!/bin/sh
set -e
REPO="bbarni2020/MacOS-External-display-driver"
BRANCH="main"
FOLDER="raspberry-pi-receiver"
DEST="/opt/DeskExtend-receiver"
for arg in "$@"; do
  case "$arg" in
    branch=*) BRANCH="${arg#branch=}" ;;
    dest=*) DEST="${arg#dest=}" ;;
  esac
done
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
if [ ! -d "$DEST" ]; then
  mkdir -p "$DEST"
fi
cp -a "$SRC/." "$DEST/"
chmod +x "$DEST/receiver.py" 2>/dev/null || true
chmod +x "$DEST/run.sh" 2>/dev/null || true
if [ -f "$DEST/requirements.txt" ]; then
  if command -v pip3 >/dev/null 2>&1; then
    pip3 install -r "$DEST/requirements.txt"
  else
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update
      apt-get install -y python3-pip
      pip3 install -r "$DEST/requirements.txt"
    else
      echo "pip3 not found and apt-get unavailable; please install Python requirements manually"
    fi
  fi
fi
echo "Installed $FOLDER to $DEST"