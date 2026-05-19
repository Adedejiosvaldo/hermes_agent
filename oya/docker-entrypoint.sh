#!/usr/bin/env bash
# Runs on every container start.
# Deploys skills from image into the data volume, then execs the gateway.
set -euo pipefail

HERMES_DATA="${HERMES_HOME:-/opt/data}"
SKILLS_DIR="$HERMES_DATA/skills/oya"
DATA_DIR="$HERMES_DATA/data/oya"

mkdir -p "$SKILLS_DIR" "$DATA_DIR"

# Overwrite skills on every start so a new image = new skill version.
cp -r /oya-skills/. "$SKILLS_DIR/"

# Initialize reminders.json only on first run.
if [ ! -f "$DATA_DIR/reminders.json" ]; then
  cat > "$DATA_DIR/reminders.json" << 'EOF'
{
  "reminders": [],
  "user_model": {
    "timezone": "Africa/Lagos",
    "patterns": [],
    "preferences": {},
    "last_reviewed": null
  }
}
EOF
  echo "[oya] Initialized reminders.json"
fi

# Hermes drops to UID 10000 (hermes user). Everything we created as root
# must be owned by that user or Hermes can't write to it.
chown -R 10000:10000 "$HERMES_DATA"

exec /opt/hermes/docker/entrypoint.sh "$@"
