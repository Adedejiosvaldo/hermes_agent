#!/usr/bin/env bash
# deploy.sh — first-run setup for Oya on Docker
# Run this ONCE after cloning. After that, use docker compose up/down.
set -euo pipefail

if [ ! -f .env ]; then
  echo "Enter your OpenRouter API key:"
  read -r OPENROUTER_API_KEY
  echo "OPENROUTER_API_KEY=$OPENROUTER_API_KEY" > .env
  echo "✓ Saved to .env"
fi

echo "=== Building Oya image ==="
docker compose build

echo ""
echo "=== First-run config (interactive — runs inside container, saves to volume) ==="
echo ""

run_setup() {
  docker compose run --rm oya "$@"
}

echo "Step 1/5 — LLM provider"
echo "  Pick: openrouter | paste OPENROUTER_API_KEY | select google/gemini-2.5-pro"
run_setup hermes model

echo ""
echo "Step 2/5 — Telegram gateway"
echo "  Need: BotFather token + your numeric user ID (get from @userinfobot)"
run_setup hermes gateway setup

echo ""
echo "Step 3/5 — User config"
run_setup hermes config set oya.user.timezone "Africa/Lagos"
run_setup hermes config set oya.user.name "Joseph"
run_setup hermes config set oya.default.tier 2

echo "  What city are you in? (for weather briefs)"
read -r OYA_CITY
run_setup hermes config set oya.user.location "$OYA_CITY"

echo "  Enter your Telegram numeric user ID:"
read -r TELEGRAM_ID
run_setup hermes config set oya.user.telegram_id "$TELEGRAM_ID"
# Add to Telegram allowlist so the gateway doesn't block you
run_setup sh -c "echo 'TELEGRAM_ALLOWED_USERS=$TELEGRAM_ID' >> /opt/data/.env"

# Bind the 'oya' skill to the Telegram DM. Hermes skills do NOT auto-trigger on
# message content — without this binding the bot ignores the oya skill, and
# plain "remind me…" / "done" messages do nothing useful.
echo ""
echo "  IMPORTANT — bind the 'oya' skill to your chat."
echo "  Edit config.yaml and add under platforms.telegram.extra:"
echo ""
echo "      dm_topics:"
echo "        - chat_id: $TELEGRAM_ID"
echo "          topics:"
echo "            - name: Oya"
echo "              skill: oya"
echo ""
read -r -p "  Press Enter once that block is saved (see DEPLOY.md step 4)... " _

echo ""
echo "Step 4/5 — Voice transcription (local, free)"
run_setup hermes config set stt.provider local

echo ""
echo "Step 5/5 — Schedule the daily rituals"
# evening-review: nightly ritual — co-loads streak-guard (open-loop sweep) and
# weather-brief; the three produce one combined message.
run_setup hermes cron add "0 21 * * *" "evening review" --skill streak-guard --skill evening-review --skill weather-brief --deliver telegram
# morning-check: resurface loops left open from previous days
run_setup hermes cron add "0 8 * * *" "morning check sweep" --skill morning-check --deliver telegram

echo ""
echo "=== Optional extras (skip with Ctrl+C, configure later) ==="
echo ""
echo "Tier 4 buddy pings?"
echo "  hermes config set oya.buddy.telegram_id '<buddy ID>'"
echo ""
echo "WhatsApp secondary channel?"
echo "  docker compose run --rm oya hermes gateway setup"
echo "    → Pick WhatsApp, scan QR with secondary number"
echo "  docker compose run --rm oya hermes config set oya.user.whatsapp_number '+234xxx'"
echo ""

echo "=== Starting Oya ==="
docker compose up -d

echo ""
echo "Done. Test: send 'remind me in 2 minutes to test Oya' to your bot."
echo ""
echo "Useful commands:"
echo "  docker compose logs -f          # live logs"
echo "  docker compose restart          # restart gateway"
echo "  docker compose down             # stop"
echo "  docker compose build && docker compose up -d   # deploy skill updates"
