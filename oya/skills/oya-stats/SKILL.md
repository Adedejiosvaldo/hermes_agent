---
name: oya-stats
description: >
  Show the user their progress on demand — level, XP, per-habit streaks,
  freezes, achievements, and open loops. A clean read-only stats card.
  Triggers on "my stats", "stats", "how am I doing", "my progress", "my streaks".
version: 0.1.0
metadata:
  hermes:
    tags: [reminders, stats, gamification, oya]
    category: productivity
    config:
      - key: oya.user.name
        description: "User's first name"
        default: "Joseph"
---

# Oya Stats — the progress card

Shows the user where they stand. Read-only — this skill never writes to
`reminders.json`. Voice: Oya's character (design ref: `PERSONA.md`). Numbers
canon: `GAMIFICATION.md`. Data shapes: `SCHEMA.md`.

## When to use

User asks: "my stats", "stats", "how am I doing", "my progress", "my streaks",
"my level", "show my badges". Not for closing loops (that is `record-outcome`).

## Procedure

**1. Read** `/opt/data/oya/reminders.json`. If any key is missing, treat it as
its default from `SCHEMA.md` (do not crash on the old shape).

**2. Gather:**
- From `user_model.gamification`: `level`, `xp`, `next_level_xp`,
  `streak_freezes`, `achievements`.
- Per reminder with `status == "active"`: `what`, `streak`, `best_streak`,
  `total_completions`.
- Count of entries in `open_loops`.

**3. Level progress bar.** The current level's XP floor is
`xp_threshold(level) = 50 * level * (level - 1)`. Progress within the level:
`(xp - floor) / (next_level_xp - floor)`. Render as a 10-cell unicode bar,
filled cells = `round(progress * 10)`:
```
▓▓▓▓▓▓░░░░
```

**4. Compose the card** — Oya's voice, MarkdownV2, glanceable. Shape (vary the
wording, not the structure):
```
📊 {name} — your run

⚡ Level {level}  ·  {xp} XP
{bar}  {xp left} to level {level+1}

🔥 Streaks
 · {what}: {streak} 🔥  (best {best_streak})
 · ...   (list active habits, longest streak first; top ~6)

🧊 {streak_freezes} freezes in the bank
🏆 {count} badges: {achievement emojis}
⏳ {open loop count} open right now
```
- If there are no active reminders yet: encourage starting one, warmly.
- If `achievements` is empty: skip the badge line, or a light "first badge
  loading…".
- Keep it to one tidy message.

**5. Send** the card to the user.

## Pitfalls

- Read-only — never modify `reminders.json`.
- Never leak internals — no IDs, file paths, raw JSON, cron expressions
  (Law 6).
- Keep it one clean card, not a wall of text.
