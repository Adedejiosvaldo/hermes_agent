# Oya — Gamification Rules

The deterministic ruleset behind XP, levels, streak freezes, the dice reward,
milestones, and achievements. **All of this is mechanical** — fixed numbers and
rules, never LLM judgement (the LLM is unreliable at state math; see
`oya-reminder-bugs` memory).

`record-outcome` is the sole writer of these values — it embeds the operative
rules. This file is the human-readable canon; keep the two in sync.

---

## XP

Awarded on resolution, by route:

| Route | XP |
|---|---|
| DONE, on time | **10** |
| DONE, late (resolved after escalation) | **5** |
| DEFERRED | 0 |
| EXCUSED | 0 |
| MISSED | 0 |

Plus the **dice bonus** (below) on any DONE.

XP only ever accumulates. It is never spent or lost.

## Bonus roll — variable reward

On every DONE, Oya rolls 1–6 and adds bonus XP:

| Roll | Bonus XP |
|---|---|
| 6 | +20 |
| 5 | +10 |
| 1–4 | +0 |

This is a **narrated roll**, not a native Telegram dice — Hermes outbound is
text + media files only; it cannot send an animated dice (`sendDice`) or a
sticker (issue #16168). The skill picks the roll and narrates it as text:
"🎲 rolled a 6 — +20 bonus!". The variable bonus is the engagement hook
(Law 7) — the surprise lives in the number, not an animation.

## Levels

Level is derived from cumulative XP:

```
xp_threshold(L) = 50 * L * (L - 1)
```

| Level | XP needed |
|---|---|
| 1 | 0 |
| 2 | 100 |
| 3 | 300 |
| 4 | 600 |
| 5 | 1000 |
| 6 | 1500 |
| 7 | 2100 |

On every XP change, recompute `level` and store `next_level_xp` =
`xp_threshold(level + 1)` so other skills display progress without recomputing.

**Each level-up grants +1 streak freeze** (capped at 5 held).

## Streak freezes

A freeze protects a per-habit `streak` from a MISSED resolution.

On a **MISSED** route:
- If the reminder's `streak >= 3` **and** `streak_freezes > 0`:
  - Consume one freeze (`streak_freezes -= 1`).
  - The habit's `streak` is **held** (not reset).
  - The occurrence is still recorded `missed` (the task was not done) — the
    freeze saves the streak, not the task.
  - Tell the user a freeze was spent.
- Otherwise: the habit's `streak` resets to `0`.

Freezes are earned only on level-up. Starting balance: 2.

## Milestones (per-habit streak)

When a habit's `streak` reaches one of these on a DONE, fire the fanfare:

`3 · 7 · 14 · 30 · 60 · 100`

Fanfare = a loud, joyful, separate message (Law 7), plus the matching
achievement. Milestone GIFs/stickers ship via the `MEDIA:` tag once asset
files exist; until then, fanfare is bold text + emoji.

## Achievements

Unlocked once, appended to `user_model.gamification.achievements`:

| Badge | Unlock |
|---|---|
| 🌱 First Step | first ever DONE |
| 🥉 Week One | any habit streak reaches 7 |
| 🥈 Fortnight | any habit streak reaches 14 |
| 🥇 Monthly | any habit streak reaches 30 |
| 💎 Century | any habit streak reaches 100 |
| ⚡ Powered Up | reach level 5 |
| 🧊 Unbreakable | spend a freeze to save a 14+ streak |

Announce a newly-unlocked achievement in the resolution reply.

## Scope note

P3 covers per-habit streaks, XP, levels, freezes, dice, milestones,
achievements. The daily app-streak (`global_streak`, `daily_goal`, `today`)
needs an end-of-day rollup — wired in P4 via `evening-review`.
