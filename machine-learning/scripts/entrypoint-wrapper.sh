#!/bin/bash
set -e

CACHE_ROOT="/cache"
PRELOAD_ROOT="/preload-cache"

echo "[Startup] Checking for preloaded models..."

if [ -d "$PRELOAD_ROOT" ]; then
  # Loop over model groups (facial-recognition, clip, etc.)
  for group_dir in "$PRELOAD_ROOT"/*; do
    [ -d "$group_dir" ] || continue
    group_name=$(basename "$group_dir")

    CACHE_GROUP="$CACHE_ROOT/$group_name"

    echo "[Startup] Processing model group: $group_name"

    # Loop over individual models inside group
    for model_dir in "$group_dir"/*; do
      [ -d "$model_dir" ] || continue
      model_name=$(basename "$model_dir")

      target_dir="$CACHE_GROUP/$model_name"

      if [ ! -d "$target_dir" ] || [ -z "$(ls -A "$target_dir" 2>/dev/null)" ]; then
        echo "[Startup] Restoring $group_name model: $model_name"
        mkdir -p "$target_dir"
        cp -r "$model_dir"/* "$target_dir"/ || true
      else
        echo "[Startup] Model '$group_name/$model_name' already exists, skipping."
      fi
    done
  done
else
  echo "[Startup] No preloaded models found in $PRELOAD_ROOT."
fi

# Clean up preload cache to free space
if [ -d "$PRELOAD_ROOT" ]; then
  echo "[Startup] Cleaning up $PRELOAD_ROOT..."
  rm -rf "$PRELOAD_ROOT"
fi

# Hand off to the original command
exec "$@"
