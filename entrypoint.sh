#!/bin/sh
set -e

mkdir -p /app/data

# Render's persistent disk is mounted EMPTY over /app/data on first boot,
# which hides the JSON config files (choices.json, guinea_admin.json,
# price_matrix.json) and the default photos/ folder structure that were
# baked into the Docker image via "COPY . .". This restores anything
# missing from the image's snapshot (/app/data_seed) WITHOUT ever
# overwriting real data that already exists on the disk.
if [ -d /app/data_seed ]; then
  for f in /app/data_seed/*; do
    name=$(basename "$f")
    if [ ! -e "/app/data/$name" ]; then
      cp -r "$f" "/app/data/$name"
      echo "[entrypoint] Seeded /app/data/$name from image defaults"
    fi
  done
fi

exec gunicorn -w 2 -b 0.0.0.0:${PORT} --timeout 120 app:app
