---
name: morning-check
description: >
  Morning sweep. Resurfaces every accountability loop left open from a previous
  day, carries it forward, and fires the auto-miss valve on loops carried too
  long. Sends one fresh-start digest so nothing is quietly forgotten overnight.
  Cron-triggered (~08:00 user time). Never called by the user.
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

# Morning Check — resurface yesterday's open loops

Runs each morning. Any loop the user never closed on a previous day is brought
back into view — gently, with a fresh-start tone. This is the other half of the
"you can't just forget" guarantee: a loop survives the night and meets the user
again in the morning.

Voice: Oya's character (design ref: `PERSONA.md`) — morning tone: fresh,
hopeful, light (PERSONA "morning"). One digest, never one ping per loop
(Law 3). Data shapes: `SCHEMA.md`.

**Execution:** read/write `reminders.json` with your file tools; manage cron
jobs with the `cronjob` tool. Never shell out — no terminal, `python`, or CLI.
The user sees only the digest — never a status report or internal IDs.

## When to use

Cron-triggered only, once each morning (~08:00 user time). Never user-invoked.

## Procedure

**1. Read** `/opt/data/oya/reminders.json`. If `open_loops` is missing or
empty, stay silent — there is nothing to resurface (Law 3: never ping for
nothing).

**2. Resolve loops.** For each `open_loops` entry, find the reminder and
occurrence. Drop entries whose occurrence is no longer `pending`.

**3. Scope to old loops.** Keep only occurrences whose `fired_at` date is
**before today**. Loops opened today are still inside `fire-reminder`'s own
escalation chain — leave them. If nothing remains, stay silent.

**4. Auto-miss valve.** For each in-scope occurrence where `carry_count >= 3`:
- Set occurrence `state: "missed"`, `reason: "carried forward 3× — never
  closed"`, `resolved_at: <now>`, `streak_before: <reminder.streak>`.
- Set the reminder's `streak: 0`.
- Remove its `open_loops` entry. Cancel any `escalation_cron_id` job.
- Add it to the **auto-missed list** for the announcement.

**5. Carry the survivors.** For every in-scope occurrence still `pending`,
increment `carry_count` by 1.

**6. Write back** reminders.json.

**7. Compose ONE digest:**

- **Auto-missed** — announce plainly, honest but kind (Law 4): it was open too
  long, the streak reset. No shame.
- **Still open** — list them with a fresh-start framing: a new day, let's clear
  what's hanging. Restate the one-tap close: ✅ done · ⏰ move · 💬 why.

Example shape (compose in Oya's voice, vary it — Law 2):
```
☀️ Morning, {name}. Couple of loops still hanging from before —
{task A}, {task B}. Let's clear them: ✅ done · ⏰ move · 💬 why.
{If auto-missed:} "{task C}" I had to let go — open too long. Fresh start today.
```

**8. Quiet hours.** If now is inside the quiet range, do not send (rare at
morning). Data updates in steps 4–6 still happen.

**9. Send** the digest to `oya.user.telegram_id`. Attach the reply keyboard
(`✅ Did it` / `⏰ Move it` / `💬 Couldn't`) if supported; replies are handled by
`record-outcome`.

## Pitfalls

- One digest only — never a separate ping per loop (Law 3).
- Never resurface a loop opened **today** — that is `fire-reminder`'s job.
- The auto-miss valve always announces — never a silent miss.
- Never leak internals — no IDs, file paths, cron expressions, raw errors
  (Law 6). On a read/write failure, stay silent.
