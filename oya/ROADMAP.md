# Oya — Product Roadmap

Oya is a Telegram-based accountability companion built on the Hermes Agent
framework (runs in the `oya-oya-1` Docker container). This document is the
master plan: vision, architecture, feature backlog, and phased delivery.

---

## 0. Vision

Oya is **not a reminder bot**. Reminder bots get muted and abandoned — a
reminder is a nag, and nags get silenced.

Oya is an **accountability companion**: it makes showing up feel like winning
and skipping feel like losing, with Duolingo-grade engagement — streaks, XP,
personality, loss aversion.

Core belief: *setting* a reminder is trivial. **Doing the thing** is the
product. Every reminder is an open loop that must be closed — completed,
accounted for, or rescheduled — and **never silently forgotten**.

---

## 1. Foundation fixes (P0) — patched in source, pending deploy

Bugs found while debugging why reminders never fired:

- **Hermes cron is 5-field** (no seconds). Skills generated 6-field → misparsed.
  Fixed in `parse-reminder` and `deploy.sh`.
- **One-shot reminders must use relative delays** (`5m`/`2h`/`1d`). LLM-computed
  absolute timestamps anchor on the message timestamp and land in the past
  after any gateway downtime. Fixed in `parse-reminder`.
- **Cron jobs are session-less** — delivery needs a Telegram **home channel**
  (`/sethome`). Done.
- **Timezone** — added `TZ=Africa/Lagos` to `docker-compose.yml` so the cron
  engine matches the user. `oya.user.timezone` does not affect the cron engine.
- **Output hygiene** — skills no longer leak `reminders.json`, job IDs, or
  internal errors into chat.

**Pending manual deploy steps:**
1. `docker compose build && docker compose up -d`
2. `config.yaml`: `display.platforms.telegram.tool_progress: off` + `cleanup_progress: true`
3. Recreate the daily-review job as `0 22 * * *` (TZ change shifts the old `0 21`)
4. `telegram: reactions: true`

---

## 2. Core mechanic — the accountability loop ("no silent miss")

A reminder is an **open loop** that stays open until the user closes it, three
ways only:

1. **Did it** ✅
2. **Couldn't** — and accounts for why 💬
3. **Moved it** — reschedules to a concrete new time ⏰

Banned: silently vanishing. Ignore it → it follows you.

### State machine

```
            fire
             │
             ▼
        ┌─────────┐   defer → spawns a
        │ PENDING │   fresh PENDING
        └────┬────┘◄──────────────┐
     ┌───────┼────────┬───────┐   │
     ▼       ▼        ▼       ▼   │
   DONE  DEFERRED  EXCUSED  MISSED│
            └────new occurrence───┘
```

`PENDING` is the only live state. It **never auto-exits to MISSED on silence** —
only an explicit skip, or a hard escalation limit (announced), ends it.

### Resolution router

`record-outcome` classifies the user's reply — a reply-keyboard tap, typed
text, or a voice note (STT → text), all through the same parser:

| Reply | Route | Effect |
|---|---|---|
| "done" / ✅ / 👍 | DONE | full XP, streak +1 |
| "did it at 4" | DONE (late) | reduced XP, streak held |
| "couldn't, was sick" | EXCUSED | LLM judges legit → no XP, streak held |
| "didn't feel like it" | MISSED | streak breaks |
| "move to 6pm" | DEFERRED | spawn new occurrence, old one closed |
| *silence* | stays PENDING | escalates, then carries forward |

The LLM does **one** judgment only — *excused vs missed*. All dates, XP, streak
math are deterministic skill code (the LLM is unreliable at state/time math).

### Reschedule — capped

Moving an item is legitimate, not failure — if a concrete new time is given.
`reschedule.count` is capped at **3**; past the cap, Oya confronts the avoidance.

---

## 3. Follow-ups — the review-extraction chain

A follow-up's job is to **extract a review**, not just re-ping.

| When | Follow-up |
|---|---|
| T+0 | the contract ping (done / move / why) |
| T+30m | nudge 1 — "still open?" |
| T+2h | nudge 2, softer — "what happened?" |
| End of day (`streak-guard`) | "close it before midnight" |
| Next morning (`morning-check`) | "you never closed X — talk to me" |
| After that | auto-mark MISSED, **announced**, still offer to log why |

Spacing widens (relentless, not machine-gun). Every follow-up respects quiet
hours, varies wording, and the chain ends only when the loop closes.

---

## 4. Gamification

- **Streaks** — per-habit + global day streak. The core retention hook.
- **XP / levels** — XP per completion, level curve.
- **Streak freezes** — auto-spent on a miss; earned by leveling up.
- **Badges / achievements** — milestone unlocks.
- **Variable reward** — `sendDice` 🎰; XP bonus gated on the roll.
- **Milestone fanfare** — day 3 / 7 / 30 / 100 → GIF + sticker.

### Streak / XP fairness

| Outcome | XP | Streak |
|---|---|---|
| Done on time | full | +1 |
| Done late | partial | held |
| Excused (legit) | 0 | held (freeze) |
| Deferred (within cap) | 0 | held, pending |
| Missed | 0 | reset |

---

## 5. Telegram UX

**Decision: multi-modal ack, NOT buttons or polls.** Closing a loop works three
ways, all routed to one resolution parser (`record-outcome`):

- **Reply keyboard** — preset buttons whose tap sends the label as a normal
  text message (so it routes — unlike inline buttons). The fast default.
- **Free text** — "done", "move to 6pm", "couldn't, was sick".
- **Voice note** — transcribed by Hermes STT, then parsed like text.

Inline buttons and polls are NOT used for ack: their taps produce
`callback_query` / `poll_answer` updates that only route to the blocking
`clarify` tool — a cron-fired reminder can't block waiting. Buttons return only
in the P5 Mini App.

### Access layers

- **A — native via Hermes:** `MEDIA:` tags (GIF/sticker/voice), reactions,
  MarkdownV2 formatting.
- **B — direct Telegram Bot API from a skill** (`curl` + bot token):
  `sendDice`, `sendSticker`, `sendAnimation`, `sendPoll`, `editMessageText`.
- **C — Telegram Mini App:** hosted webview dashboard (P5).

### UI inventory

| Primitive | Use | Layer |
|---|---|---|
| Reply keyboard | one-tap ack — tap sends label as text | B |
| Free text / voice note | ack — always works (voice → STT) | A |
| Emoji reactions (receive) | bonus ack, if Hermes routes it | A* |
| MarkdownV2 + unicode emoji | all messages | A |
| `MEDIA:` GIF / sticker | milestone fanfare | A |
| `sendDice` 🎰 | variable reward | B |
| `editMessageText` | live counters, countdown | B |
| `sendPoll` | non-ack only (vibe / weekly poll) | B |
| Inline buttons / polls for ack | not used — callbacks don't route | — |
| Mini App | dashboard (P5) | C |
| Progress bar | unicode blocks `▓▓▓░░` | A |

\* Reaction-receive depends on Hermes surfacing reaction events; fallback is
text reply (`done`/`skip`), which always works.

---

## 6. Peak UX — the 8 laws

Every skill is written against these. Stored as `UX-LAWS.md`.

1. **One-tap close** — closing a loop never costs more than one word / tap /
   reaction / voice note. Friction is the #1 killer.
2. **Oya is a person** — fixed persona; 8–10 message variants per situation;
   references memory; never the same string twice.
3. **Earn the notification** — nag exactly enough, never more. Quiet hours
   sacred. Adaptive frequency. Consolidate, don't spam.
4. **Coach, not cop** — always on the user's side. Real grace on legit excuses.
   Misses framed as "we", never "you failed".
5. **Instant feedback** — 👀 within ~1s of any message. No dead air.
6. **Always-clear state** — `what's open?` answerable anytime; zero internal
   leakage.
7. **Delight on purpose** — variable reward, milestone fanfare, unprompted
   warmth. Surprise beats schedule.
8. **Forgive everything** — `undo`, streak repair, freezes. A wrong tap is
   never catastrophic.

**The one rule above all:** *Make responding effortless. Make it feel like it
genuinely cares.* Friction and coldness are the only two things that kill the
product.

**Success signals:** loop-close rate → ~100%; median time-to-close shrinking;
mute rate zero; unprompted messages to Oya; voluntary return after a broken
streak; users screenshotting it.

---

## 7. Feature backlog

### 7.1 Weather brief
End-of-night next-day forecast so the user can plan. New skill `weather-brief`.
- Free API: Open-Meteo (no key required).
- Config: `oya.user.location` (lat/lon or city).
- Bundled into the evening review message (UX law 3 — don't add a ping).
- Example: *"Tomorrow: 31°C, rain 2–4pm — pack an umbrella ☔."*
- Low dependency — can ship as a quick win any time.

### 7.2 Todo-list bulk intake
User drops a whole todo list in one message — items time-boxed ("gym 6pm") or
floating ("buy milk"). New skill `plan-intake`.
- Time-boxed items → scheduled occurrences.
- Floating items → a "today, unscheduled" bucket, surfaced through the day.
- Parsed list confirmed back before scheduling.
- Each item enters the accountability loop like any reminder.

### 7.3 Evening review / end-of-day discussion
The daily ritual — a single consolidated evening session (~21:00 WAT), not
scattered pings. New skill `evening-review` (absorbs `daily-review`).
- Report card: what closed, XP, streaks, level.
- Open-loop sweep: every unfinished item — close it, excuse it, or **bulk-move
  to tomorrow**.
- Tomorrow preview: shows the queue, lets the user add/adjust.
- Weather brief appended.
- This is the heartbeat of the Oya relationship.

### 7.4 Future ideas (unscheduled)
- Smart timing — shift reminders to when the user actually responds
  (`user_model.patterns`).
- Buddy leagues — extend the tier-4 buddy system into weekly head-to-head.
- Voice-out — Oya replies with voice notes.

---

## 8. Skills

**Skill activation — the key constraint.** Hermes skills do **not**
auto-trigger on message content (verified). Two activation paths only: cron
jobs attach skills explicitly (`--skill`), and a Telegram topic can pre-load
**one** skill via `platforms.telegram.extra.dm_topics`. So all user-facing
logic is **one** skill, `oya`, bound to the chat.

**User-facing skill:**
| Skill | Role | Status |
|---|---|---|
| `oya` | the one chat skill — routes reminder / resolve / plan / stats | ✅ |

**Cron skills** (attached to cron jobs):
| Skill | Role | Status |
|---|---|---|
| `fire-reminder` | open a loop + contract ping + follow-ups | ✅ |
| `streak-guard` | nightly open-loop sweep, carry-forward, auto-miss valve | ✅ |
| `morning-check` | resurface unclosed loops from earlier days | ✅ |
| `evening-review` | nightly ritual — co-loads `streak-guard` + `weather-brief` | ✅ |
| `weather-brief` | next-day forecast (Open-Meteo, no key) | ✅ |

`parse-reminder`, `record-outcome`, `plan-intake`, `oya-stats` are **merged
into `oya`** (its four modes) — their dirs stay in `skills/` for reference,
superseded. `daily-review` is superseded by `evening-review`. XP/streak math
(`GAMIFICATION.md`) and milestone fanfare live inside `oya` mode B.

---

## 9. Data model — `reminders.json`

```json
{
  "reminders": [{
    "id": "...", "what": "...", "schedule": "...",
    "recurrence": "once|daily|...", "tier": 2,
    "streak": 0, "best_streak": 0, "total_completions": 0,
    "occurrences": [{
      "id": "occ_<rem>_<date>",
      "due_at": "ISO", "fired_at": "ISO",
      "state": "pending|done|deferred|excused|missed",
      "resolved_at": "ISO|null", "reason": "string|null",
      "reschedule": {"count": 0, "to": "ISO|null"},
      "escalation_step": 1, "xp_awarded": 0
    }]
  }],
  "open_loops": ["occ_..."],
  "user_model": {
    "timezone": "Africa/Lagos",
    "location": null,
    "patterns": [], "preferences": {},
    "gamification": {
      "xp": 0, "level": 1,
      "global_streak": 0, "longest_streak": 0,
      "last_active_date": null, "streak_freezes": 2,
      "achievements": [], "daily_goal": 3,
      "today": {"date": null, "completed": 0, "xp": 0}
    }
  }
}
```

---

## 10. Phased roadmap

| Phase | Scope |
|---|---|
| **P0 — Foundation** | Deploy the bug fixes (section 1). Mostly done. |
| **P1 — Accountability loop** ✅ built | Occurrence model, `open_loops`, resolution router, one-tap generous parser, persona file, `UX-LAWS.md`. *In source — deploy + test pending.* |
| **P2 — Follow-ups & guarantee** ✅ built | `streak-guard`, `morning-check`, auto-miss valve, digest sweeps, quiet hours. (`undo` + reschedule cap shipped in P1.) *In source — deploy + test pending.* |
| **P3 — Gamification & delight** ✅ built | XP / levels / freezes / dice / milestones (rules in `GAMIFICATION.md`, applied by `record-outcome`), `oya-stats`. `streak-engine` + `celebrate` folded into `record-outcome`. Milestone GIFs need assets; pattern insights → P4. *In source — deploy + test pending.* |
| **P4 — Planning rituals** ✅ built | `plan-intake`, `evening-review` (absorbs `daily-review`, co-loads `streak-guard` + `weather-brief`), `weather-brief`, bulk move-to-tomorrow, daily-streak rollup. *In source — deploy + test pending.* |
| **P5 — Mini App** | Hosted webview dashboard — visual streak rings, XP, leaderboard, open-loop board. |

Weather brief (7.1) is low-dependency and may ship any time as a quick win.

---

## 11. Open questions — verify before relevant phase

1. Can a skill `curl` `api.telegram.org/bot<token>/...` — is the bot token
   readable from skill context? (Needed for Layer B; almost certainly yes.)
2. Does Hermes forward emoji-reaction events to a skill? If not, reply-based
   ack only.
3. Does Hermes surface `poll_answer` updates to skills? (Only affects the
   optional weekly quiz.)
4. Auxiliary LLM provider is currently down — compression only; non-blocking
   for skills, but worth restoring.