#!/bin/sh
set -e
REPO="bbarni2020/MacOS-External-display-driver"
BRANCH="main"
FOLDER="raspberry-pi-receiver"
DEST="${PWD}/receiver"
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
  if command -v python3 >/dev/null 2>&1; then
    echo "Creating Python virtualenv at $DEST/venv and installing requirements..."
    python3 -m venv "$DEST/venv"
    "$DEST/venv/bin/python" -m pip install --upgrade pip setuptools wheel
    "$DEST/venv/bin/pip" install -r "$DEST/requirements.txt"
  else
    if command -v pip3 >/dev/null 2>&1; then
      echo "python3 not found; installing requirements with pip3 globally..."
      pip3 install -r "$DEST/requirements.txt"
    else
      if command -v apt-get >/dev/null 2>&1; then
        echo "Installing python3 and pip via apt-get..."
        apt-get update
        apt-get install -y python3 python3-venv python3-pip
        python3 -m venv "$DEST/venv"
        "$DEST/venv/bin/python" -m pip install --upgrade pip setuptools wheel
        "$DEST/venv/bin/pip" install -r "$DEST/requirements.txt"
      else
        echo "python3/pip3 not found and apt-get unavailable; please install Python and requirements manually"
      fi
    fi
  fi
  echo "To activate the virtualenv: . \"$DEST/venv/bin/activate\""
fi
echo "Installed $FOLDER to $DEST"