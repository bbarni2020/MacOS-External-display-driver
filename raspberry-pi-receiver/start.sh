#!/bin/sh
set -e

REPO="bbarni2020/MacOS-External-display-driver"
BRANCH="main"
FOLDER="raspberry-pi-receiver"
DEST="${PWD}"
DISPLAY_NAME="DeskExtend Display"

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


export DISPLAY=${DISPLAY:-:0}
MAX_WAIT=${START_WAIT:-60}
count=0
echo "Waiting up to ${MAX_WAIT}s for X server on ${DISPLAY}..."
while [ $count -lt $MAX_WAIT ]; do
  if [ -e "/tmp/.X11-unix/X0" ] || [ -e "/tmp/.X11-unix/${DISPLAY#:}" ]; then
    if command -v xset >/dev/null 2>&1; then
      if DISPLAY="$DISPLAY" xset q >/dev/null 2>&1; then
        echo "X server is ready"
        break
      fi
    else
      echo "X socket present — assuming X is ready"
      break
    fi
  fi

  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet display-manager; then
    echo "Display manager active"
    break
  fi

  sleep 1
  count=$((count+1))
done

if [ $count -ge $MAX_WAIT ]; then
  echo "Warning: X server did not become ready within ${MAX_WAIT}s — continuing anyway"
fi

if [ -z "$XAUTHORITY" ] && [ -f "/home/pi/.Xauthority" ]; then
  export XAUTHORITY="/home/pi/.Xauthority"
fi

. "$DEST/venv/bin/activate"
env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" "$DEST/venv/bin/python" "$DEST/receiver.py" --name "$DISPLAY_NAME"
