---
name: streak-guard
description: >
  Nightly sweep of open accountability loops. Carries every still-open loop
  forward, fires the auto-miss valve on loops carried too long, and sends one
  loss-aversion digest before midnight: "close these or your streak is on the
  line." Cron-triggered (~21:00 user time). Never called by the user.
version: 0.1.0
metadata:
  hermes:
    tags: [reminders, accountability, sweep, oya, cron]
    category: productivity
    config:
      - key: oya.user.telegram_id
        description: "User's Telegram numeric user ID"
      - key: oya.user.name
        description: "User's first name"
        default: "Joseph"
      - key: oya.quiet_hours.start
        description: "Quiet hours start (24h integer). Null = disabled."
        default: null
      - key: oya.quiet_hours.end
        description: "Quiet hours end (24h integer). Null = disabled."
        default: null
---

# Streak Guard — nightly loop sweep

Runs late each evening. Nothing the user opened today should slip into
tomorrow unnoticed. This skill is the "you can't just forget" guarantee: it
carries open loops forward, ends loops that have been carried too long, and
gives the user one last, honest nudge before the day closes.

Voice: Oya's character (design ref: `PERSONA.md`) — loss-aversion, but a coach
not a cop (Law 4). One digest, never one ping per loop (Law 3). Data shapes:
`SCHEMA.md`.

**Execution:** read/write `reminders.json` with your file tools; manage cron
jobs with the `cronjob` tool. Never shell out — no terminal, `python`, or CLI.
The user sees only the digest — never a status report or internal IDs.

## When to use

Cron-triggered only, once nightly (~21:00 user time). Never user-invoked.

## Procedure

**1. Read** `/opt/data/oya/reminders.json`. If `open_loops` is missing or
empty, there is nothing to sweep — stop silently.

**2. Resolve loops.** For each `open_loops` entry `{reminder_id, occurrence_id}`,
find the reminder and its occurrence. Drop any entry whose occurrence is no
longer `pending` (stale index) — remove it from `open_loops`.

**3. Auto-miss valve.** For each still-`pending` occurrence where
`carry_count >= 3`:
- Set occurrence `state: "missed"`, `reason: "carried forward 3× — never
  closed"`, `resolved_at: <now>`, `streak_before: <reminder.streak>`.
- Set the reminder's `streak: 0`.
- Remove its `open_loops` entry. Cancel any `escalation_cron_id` job.
- Add it to the **auto-missed list** for the announcement.

**4. Carry the survivors.** For every occurrence still `pending` after step 3,
increment `carry_count` by 1.

**5. Write back** reminders.json.

**6. Compose ONE digest** (skip and stop if there are no auto-missed loops and
no surviving open loops):

- **Auto-missed** — announce plainly, honest but kind (Law 4): name each one,
  say it was open too long and the streak reset. Never shame.
- **Still open** — list them, loss-aversion framing: the day is closing, these
  are still on the user, the streak is on the line. Restate the one-tap close:
  ✅ done · ⏰ move · 💬 why.

Example shape (compose in Oya's voice, vary it — Law 2):
```
🌙 Before the day closes, {name} —
Still open: {task A}, {task B}. Close them — ✅ done · ⏰ move · 💬 why.
{If auto-missed:} I had to let "{task C}" go — open too long. 🔥 reset. Tomorrow we rebuild.
```

**7. Quiet hours.** If `oya.quiet_hours.*` are set and now is inside the quiet
range, do **not** send the digest (Law 3 — quiet hours are sacred). The data
updates in steps 3–5 still happen; `morning-check` will resurface the loops.

**8. Send** the digest to `oya.user.telegram_id`. Attach the reply keyboard
(`✅ Did it` / `⏰ Move it` / `💬 Couldn't`) if supported; the user's reply is
handled by `record-outcome`.

## Pitfalls

- One digest only — never a separate ping per loop (Law 3).
- The auto-miss valve is the **only** place this skill records a miss, and it
  is always announced — never silent.
- Never leak internals — no IDs, file paths, cron expressions, raw errors
  (Law 6).
- If reading or writing fails, stay silent — do not post an error to the chat.
