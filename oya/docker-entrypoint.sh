#!/usr/bin/env bash
# Runs on every container start.
# Deploys skills from image into the data volume, then execs the gateway.
set -euo pipefail

HERMES_DATA="${HERMES_HOME:-/opt/data}"
SKILLS_DIR="$HERMES_DATA/skills/oya"
DATA_DIR="$HERMES_DATA/oya"

mkdir -p "$SKILLS_DIR" "$DATA_DIR"

# Overwrite skills on every start so a new image = new skill version.
cp -r /oya-skills/. "$SKILLS_DIR/"

# Initialize reminders.json only on first run.
if [ ! -f "$DATA_DIR/reminders.json" ]; then
  cat > "$DATA_DIR/reminders.json" << 'EOF'
{
  "reminders": [],
  "open_loops": [],
  "user_model": {
    "timezone": "Africa/Lagos",
    "location": null,
    "patterns": [],
    "preferences": {},
    "last_reviewed": null,
    "gamification": {
      "xp": 0,
      "level": 1,
      "next_level_xp": 100,
      "global_streak": 0,
      "longest_streak": 0,
      "last_active_date": null,
      "streak_freezes": 2,
      "achievements": [],
      "daily_goal": 3,
      "today": { "date": null, "completed": 0, "xp": 0 }
    }
  }
}
EOF
  echo "[oya] Initialized reminders.json"
fi

# Symlink /opt/hermes/oya → /opt/data/oya so the agent finds the file
# whether it resolves ~ as /opt/hermes or /opt/data.
mkdir -p /opt/hermes
ln -sfn "$DATA_DIR" /opt/hermes/oya

# Hermes drops to UID 10000 (hermes user). Everything we created as root
# must be owned by that user or Hermes can't write to it.
chown -R 10000:10000 "$HERMES_DATA"

exec /opt/hermes/docker/entrypoint.sh "$@"
