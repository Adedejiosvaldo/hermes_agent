# Oya — Deploy & Test (P1–P4)

One deploy ships everything. Then test gate by gate, in phase order. A gate
fails → fix it before moving to the next.

All commands run on the VPS, in `~/hermes_agent/oya`. Container: `oya-oya-1`.

---

## A. Deploy (once)

**1. Build & start the new image** (bundles all skills + the new entrypoint):
```
docker compose build && docker compose up -d
```

**2. Wipe the old data file.** The existing `reminders.json` is the old schema
plus dead test reminders. Delete it; the entrypoint re-creates a fresh one on
the next start:
```
docker exec oya-oya-1 rm -f /opt/data/oya/reminders.json
docker compose restart
docker exec oya-oya-1 sh -lc 'cat /opt/data/oya/reminders.json'
```
Expect a fresh file with `reminders: []`, `open_loops: []`, and the
`gamification` block.

**3. Config** (hide tool noise, enable reactions, set the city):
```
docker compose run --rm oya hermes config set display.platforms.telegram.tool_progress off
docker compose run --rm oya hermes config set display.platforms.telegram.cleanup_progress true
docker compose run --rm oya hermes config set telegram.reactions true
docker compose run --rm oya hermes config set oya.user.location "Lagos"
```

**4. Reset cron jobs.** List, remove every old Oya job (daily-review, old test
jobs), then add the two ritual crons:
```
docker compose run --rm oya hermes cron list
docker compose run --rm oya hermes cron remove <each old job id>

docker compose run --rm oya hermes cron add "0 21 * * *" "evening review" \
  --skill streak-guard --skill evening-review --skill weather-brief --deliver telegram
docker compose run --rm oya hermes cron add "0 8 * * *" "morning check sweep" \
  --skill morning-check --deliver telegram
```

**5. Home channel** — already set via `/sethome`. Confirm the bot still
replies in that chat.

**6. Restart once more** so the gateway loads the new crons:
```
docker compose restart
docker logs --tail 30 oya-oya-1
```

---

## B. Test gates

Stream logs in one terminal while testing: `docker logs -f oya-oya-1`.

### Gate P1 — the accountability loop

Drive all four resolutions from Telegram:

1. "remind me in 3 minutes to test" → expect a confirmation, then a **contract
   ping** ~3 min later showing the 3 ways to close it.
2. Reply **"done"** → expect a warm confirmation + streak feedback. No leaked
   IDs or JSON.
3. New 3-min reminder → reply **"6pm"** (or "in 5 minutes") → expect it
   confirms a move and re-fires at the new time.
4. New reminder → reply **"couldn't, power was out"** → expect grace, streak
   held.
5. New reminder → reply **"skip"** → expect honest-but-kind, streak reset.
6. Send **"what's open"** → expect a clean list. Send **"undo"** → expect the
   last resolution reopened.

✅ Pass = loops open, all four routes resolve, nothing leaks. This is the
foundation — do not move on until it holds.

### Gate P2 — the follow-up guarantee

1. Set a reminder, let it fire, **do not reply**.
2. Manually trigger a sweep: `docker compose run --rm oya hermes cron list`
   then `... hermes cron run <morning-check or evening job id>`.
3. Expect: a **single digest** naming the open loop; `carry_count` rising on
   each sweep; after 3 carries an **announced** auto-miss (never silent).

✅ Pass = open loops are carried and re-surfaced, never silently dropped.

### Gate P3 — gamification

1. Complete a reminder → expect a 🎲 **dice** animation, XP gained, streak
   shown. (If no dice appears, Bot API access is unavailable — base XP only,
   acceptable.)
2. Send **"my stats"** → expect the progress card (level, XP bar, streaks,
   freezes, badges).
3. Build one habit to a 3-day streak → expect the milestone fanfare.

✅ Pass = XP/level/streak update, stats card renders.

### Gate P4 — planning rituals

1. Trigger the evening job: `... hermes cron run <evening job id>` → expect
   **one combined message**: report card + open loops + tomorrow + weather.
2. Drop a list: "today: gym 6pm, call mom 2pm, buy milk" → expect `plan-intake`
   to parse all three, propose a time for "buy milk", and ask for one
   confirmation.
3. After an evening review with open loops, reply **"push to tomorrow"** →
   expect them all deferred.

✅ Pass = the rituals produce single, clean, combined messages.

---

## C. If something breaks

- Watch `docker logs -f oya-oya-1` — skill errors show there.
- A skill misbehaving → fix its `SKILL.md`, `docker compose build && up -d`,
  re-test that gate only.
- Gateway not firing → confirm it is `running` (`docker inspect`), crons
  loaded (`hermes cron list`), and not inside quiet hours.
- Rollback: `git checkout` the previous commit, rebuild.
