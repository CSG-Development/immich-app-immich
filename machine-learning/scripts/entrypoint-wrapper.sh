#!/bin/bash
set -e

FACIAL_CACHE="/cache/facial-recognition"
FACIAL_PRELOAD="/preload-cache/facial-recognition"

echo "[Startup] Checking for preloaded facial-recognition models..."

# Restore all model folders if missing in cache
if [ -d "$FACIAL_PRELOAD" ]; then
  for model_dir in "$FACIAL_PRELOAD"/*; do
    [ -d "$model_dir" ] || continue
    model_name=$(basename "$model_dir")
    target_dir="$FACIAL_CACHE/$model_name"

    if [ ! -d "$target_dir" ] || [ -z "$(ls -A "$target_dir" 2>/dev/null)" ]; then
      echo "[Startup] Restoring model: $model_name"
      mkdir -p "$target_dir"
      cp -r "$model_dir"/* "$target_dir"/ || true
    else
      echo "[Startup] Model '$model_name' already exists in cache, skipping restore."
    fi
  done
else
  echo "[Startup] No preloaded models found in $FACIAL_PRELOAD."
fi

# Clean up preload cache to free space
if [ -d "/preload-cache" ]; then
  echo "[Startup] Cleaning up /preload-cache..."
  rm -rf /preload-cache
fi

# Hand off to the original command
exec "$@"
