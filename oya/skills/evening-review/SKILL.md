---
name: evening-review
description: >
  The nightly end-of-day ritual. Produces the day's report card, rolls up the
  daily app-streak, invites the user to move open loops to tomorrow, and
  previews tomorrow — all as one message. Co-loaded on the evening cron with
  streak-guard (open-loop sweep) and weather-brief (forecast); the three
  combine into a single nightly message. Replaces the old daily-review.
version: 0.1.0
metadata:
  hermes:
    tags: [reminders, review, ritual, oya, cron]
    category: productivity
    config:
      - key: oya.user.telegram_id
        description: "User's Telegram numeric user ID"
      - key: oya.user.name
        description: "User's first name"
        default: "Joseph"
---

# Evening Review — the nightly ritual

The heartbeat of Oya. Once a night, the day gets closed out together: what got
done, what's still open, what moves to tomorrow, what tomorrow holds.

Voice: Oya's character (design ref: `PERSONA.md`) — evening tone: warm
wind-down, honest report, never a lecture. Numbers canon: `GAMIFICATION.md`.
Data shapes: `SCHEMA.md`.

## Co-loaded skills — one message

This skill runs on a cron that also loads **`streak-guard`** and
**`weather-brief`**. Produce **one** combined message:
- `streak-guard` handles the open-loop sweep, carry-forward, and auto-miss
  valve — do not repeat that work; fold its open-loop section in.
- `weather-brief` produces tomorrow's forecast line — fold it in.
- This skill adds the report card, the daily-streak rollup, the
  move-to-tomorrow prompt, and the tomorrow preview.

## When to use

Cron-triggered only, once nightly (~21:00 user time). Never user-invoked.

## Procedure

**1. Read** `/opt/data/oya/reminders.json`. Treat any missing key as its
`SCHEMA.md` default.

**2. Report card — today** (user's timezone):
- Count occurrences with `state == "done"` and `resolved_at` today → `done`.
- Count occurrences fired today → `fired`. Sum their `xp_awarded` → `xp_today`.
- Note each active reminder's current `streak`, and the user's `level`.

**3. Daily-streak rollup** (`user_model.gamification`):
- Set `today = { "date": <today>, "completed": <done>, "xp": <xp_today> }`.
- If `done >= 1`:
  - If `last_active_date` is yesterday → `global_streak += 1`.
  - Else if `last_active_date` is today → unchanged.
  - Else → `global_streak = 1`.
  - Set `last_active_date = <today>`.
  - `longest_streak = max(longest_streak, global_streak)`.
- If `done == 0`: leave `global_streak` as-is (the next active day with a gap
  resets it to 1).

**4. Open loops** — take the still-open list from `streak-guard`. Present it,
then invite action: the user may close each loop, or move them. State the
shortcut: *reply "push to tomorrow"* to defer them all, or name the ones to
move. (Replies are handled by the `oya` skill.)

**5. Tomorrow preview** — list reminders that will fire tomorrow (recurring
ones whose pattern matches tomorrow; one-shots dated tomorrow). If none, say
the day is open.

**6. Write back** reminders.json (the rollup from step 3).

**7. Compose ONE message** — greeting, report card, open loops + move prompt,
tomorrow preview, the weather line. MarkdownV2; a unicode bar for the day's
goal if useful. Shape (vary the wording, keep the structure — Law 2):
```
🌙 {name} — here's the day.

📊 {done}/{fired} closed · +{xp_today} XP
🔥 {global_streak}-day streak · ⚡ Level {level}

{streak-guard open-loop section}
↪️ Move them? Reply "push to tomorrow", or name the ones to shift.

📅 Tomorrow: {task, task, …}
{weather-brief line}

{a warm, honest sign-off — proud on a strong day, encouraging on a weak one}
```

**8. Send** the combined message to `oya.user.telegram_id`. Attach the reply
keyboard (`✅ Did it` / `⏰ Move it` / `💬 Couldn't`) if supported.

## Pitfalls

- One message only — never separate pings for review / loops / weather (Law 3).
- The rollup math (step 3) is mechanical — fixed rules, never improvised.
- Honest but never harsh on a weak day (Law 4) — disappointment, not contempt.
- Never leak internals — no IDs, file paths, cron expressions, raw errors
  (Law 6). On a read/write failure, still send what you can.
