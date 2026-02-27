#!/bin/bash
# feature-video dependency checker
# No set -e: soft dependency checks must not abort the script

echo "=== feature-video Dependency Check ==="
echo

# Hard dependency -- cannot record without this
if command -v agent-browser >/dev/null 2>&1; then
  echo "  [ok] agent-browser"
else
  echo "  [MISSING] agent-browser (required)"
  echo "    Install: npm install -g agent-browser && agent-browser install"
  echo
  echo "Cannot proceed without agent-browser."
  exit 1
fi

# Soft dependency: ffmpeg (video/GIF conversion)
if command -v ffmpeg >/dev/null 2>&1; then
  echo "  [ok] ffmpeg"
else
  echo "  [skip] ffmpeg not installed (optional)"
  echo "    Install: sudo apt install ffmpeg (Linux) or brew install ffmpeg (macOS)"
fi

# Soft dependency: rclone (cloud upload)
if command -v rclone >/dev/null 2>&1; then
  echo "  [ok] rclone"
  REMOTES=$(rclone listremotes 2>/dev/null || true)
  if [ -z "$REMOTES" ]; then
    echo "  [skip] rclone: no remotes configured (see rclone skill)"
  else
    REMOTE_COUNT=$(echo "$REMOTES" | wc -l | tr -d ' ')
    echo "  [ok] rclone: $REMOTE_COUNT remote(s) configured"
  fi
else
  echo "  [skip] rclone not installed (optional)"
  echo "    Install: sudo apt install rclone (Linux) or brew install rclone (macOS)"
fi

echo
echo "=== Check Complete ==="
