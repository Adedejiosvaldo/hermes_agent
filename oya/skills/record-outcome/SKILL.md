---
name: record-outcome
description: >
  The resolution router. Closes an open accountability loop from the user's
  reply — a reply-keyboard tap, typed text, or a transcribed voice note.
  Routes to one of: done, deferred, excused, missed. Also handles management
  (cancel, pause, resume, undo) and status queries ("what's open"). Triggers on
  any reply that responds to a fired reminder. Awards XP, levels, streak
  freezes and the dice reward on completion. Writes /opt/data/oya/reminders.json.
version: 0.4.0
metadata:
  hermes:
    tags: [reminders, outcomes, accountability, oya]
    category: productivity
    config:
      - key: oya.user.name
        description: "User's first name"
        default: "Joseph"
---

# Record Outcome — the resolution router

Every fired reminder is an **open loop**. It is closed exactly three ways —
**done**, **moved**, or **accounted for** — and never silently. This skill
takes the user's reply and resolves the loop.

Voice: Oya's character (design ref: `PERSONA.md`). Obey the UX laws
(`UX-LAWS.md`) — Law 1 (accept any reply shape), Law 4 (coach not cop), Law 8
(forgive — `undo` always works). Data shapes: `SCHEMA.md`.

## When to use

- Any reply that closes a loop: "done", "✅", "👍", "did it", a new time
  ("6pm", "tomorrow"), or a reason ("couldn't, was sick").
- A reply-keyboard tap: `✅ Did it`, `⏰ Move it`, `💬 Couldn't`.
- A voice note responding to a reminder (already transcribed — treat as text).
- Management: "cancel / pause / resume / undo".
- Status: "what's open", "status", "list reminders".

Do NOT trigger on new reminder requests or unrelated questions.

## Step 1 — Find the open loop

1. Read `/opt/data/oya/reminders.json`. If `open_loops` is missing, treat as
   `[]`. If a key from `SCHEMA.md` is absent, treat it as its default.
2. Each `open_loops` entry is `{reminder_id, occurrence_id}` → a `pending`
   occurrence.
3. Select the target occurrence:
   - One open loop → use it.
   - Many → if the user named a task, match the reminder's `what`; otherwise
     pick the occurrence with the most recent `fired_at`.
   - Genuinely ambiguous (two fired within ~5 min, no task named) → list them
     and ask which.
   - None → if the reply is a management/status command, handle it (Steps 5–6);
     else reply plainly that nothing is open.

## Step 2 — Classify the reply

Resolve the reply to one route:

| Route | The reply means | Examples |
|---|---|---|
| **DONE** | they did it | "done", "✅", "👍", "did it", "finished", `✅ Did it` |
| **DEFERRED** | move it to a concrete new time | "6pm", "tomorrow 1pm", "in 2h", `⏰ Move it` |
| **EXCUSED** | couldn't, with a legitimate reason | "was in hospital", "power went out all day" |
| **MISSED** | explicit skip, or a weak/no reason | "skip", "❌", "didn't feel like it", "forgot" |

**The one judgment call — EXCUSED vs MISSED.** When the user gives a reason for
not doing it, decide:
- **EXCUSED** — genuinely outside their control: illness, emergency, travel
  disruption, something urgent and unavoidable. Streak is held. Grace.
- **MISSED** — within their control: forgot, lazy, "didn't feel like it",
  "no reason", or an explicit skip. Streak breaks.
- If the reason is vague ("just couldn't"), ask **one** gentle question before
  deciding. Never interrogate.

If `⏰ Move it` (or "move it") is sent with no time, ask: "What time works?"
Do not resolve until a concrete time is given.

## Step 3 — Apply the resolution

For all routes: set `resolved_at` to now, set `reason` (null for plain DONE),
record `streak_before` on the occurrence (= the reminder's `streak` before any
change — needed for `undo`), remove the matching entry from `open_loops`, and
cancel the occurrence's `escalation_cron_id` job via the `cronjob` tool.

### DONE
- Occurrence: `state: "done"` (`reason: "done (late)"` if resolved after
  escalation).
- Reminder: `streak += 1`; `best_streak = max(best_streak, streak)`;
  `total_completions += 1`.
- Run **Step 3a — Gamification** (XP, dice, level, milestone, achievements).
- If `recurrence == "once"`: reminder `status: "completed"`.
- Write back. Reply (Step 4) — dice, XP, streak, plus any level-up, milestone,
  or new achievement.

### DEFERRED
- If the occurrence's `reschedule.count >= 3`: **do not move it again.**
  Confront gently (Law 4) — three moves is avoidance, not scheduling. Ask them
  to do it now or tell you the real blocker. Leave the loop `pending`. Stop.
- Otherwise:
  - Occurrence: `state: "deferred"`, `reschedule.to: <new time ISO>`,
    `reschedule.count` unchanged (it records moves *into* this occurrence).
  - Create a one-shot `fire-reminder` cron job at the new time (relative delay
    like `2h` or an ISO timestamp — never a clock time computed by hand).
    Context: `reminder_id: <id> defer_count: <occurrence.reschedule.count + 1>`
  - Streak: unchanged (held).
  - Write back. Reply: confirm the new time in Oya's voice.

### EXCUSED
- Occurrence: `state: "excused"`, `reason: <their reason>`.
- Streak: unchanged (held — grace).
- Write back. Reply: real grace, zero guilt (Step 4).

### MISSED
- Occurrence: `state: "missed"`, `reason: <their reason, or "skipped">`.
- **Streak freeze check.** If `reminder.streak >= 3` and
  `user_model.gamification.streak_freezes > 0`: consume one freeze
  (`streak_freezes -= 1`), **hold** the streak (do not reset), flag it for the
  reply. Otherwise set `reminder.streak: 0`.
- If `recurrence == "once"`: reminder `status: "completed"` (concluded).
- Write back. Reply: honest, kind, a hand up (Step 4).

## Step 3a — Gamification (on DONE only)

Mechanical rules — fixed numbers, never improvised. Canon: `GAMIFICATION.md`.
All updates here are written back with the rest of the resolution.

1. **Base XP.** `10` if done on time, `5` if done late. Set the occurrence's
   `xp_awarded` to this base.
2. **Dice reward.** Send a Telegram dice 🎲 (`sendDice` — native animated,
   value 1–6) and read the real `dice.value` from the API response. Bonus:
   `6 → +20`, `5 → +10`, `1–4 → +0`. Add the bonus to `xp_awarded`. If direct
   Bot API access is unavailable, skip the dice and keep only the base XP.
3. **Apply XP.** `gamification.xp += xp_awarded`.
4. **Level.** `xp_threshold(L) = 50 * L * (L - 1)`. Set `level` to the highest
   `L` with `xp_threshold(L) <= xp`; set `next_level_xp = xp_threshold(level +
   1)`. If `level` rose: `streak_freezes += 1` (cap 5) and flag a **level-up**.
5. **Milestone.** If the reminder's new `streak` is `3, 7, 14, 30, 60` or
   `100`: flag a **milestone** (a loud, separate fanfare message).
6. **Achievements.** Append any newly-earned badge to
   `gamification.achievements` (table in `GAMIFICATION.md`) and flag it. Each
   badge unlocks once only.

## Step 4 — Reply

Compose in Oya's voice, vary every time (Law 2), never leak internals (Law 6).

- **DONE** — celebrate, specific. Include the dice result and XP gained, and
  the streak. Streak feedback scales: ≥30 milestone-loud · ≥7 "🔥 {n}-day
  streak" · 3–6 "{n} days running" · 1 after a reset "back on track" · else a
  clean, warm confirmation. If flagged: add a **level-up** line ("⬆️ Level {n} —
  +1 freeze 🧊"), and send any **milestone** as its own separate, joyful
  message. Name any **new achievement**.
- **DEFERRED** — confirm the new time, no judgement: "Moved — {time}. I've got it."
- **EXCUSED** — grace: "No wahala. Streak's safe — rest."
- **MISSED** — honest, kind, a hand up: "We dropped that one — tomorrow we go
  again." If a **freeze was spent**: say so warmly — "spent a freeze 🧊 — your
  {n}-day streak lives." If the streak reset, name it without shame.

## Step 5 — Management commands

- **undo** ("undo", "wait no", "I actually did it"): take the most recently
  resolved occurrence (latest `resolved_at`). Restore `state: "pending"`, clear
  `resolved_at`/`reason`, set the reminder's `streak` back to the occurrence's
  `streak_before`, re-add the `open_loops` entry. Reply: "Undone — that loop's
  open again."
- **push to tomorrow** ("push to tomorrow", "move all to tomorrow", "push
  everything"): apply the **DEFERRED** route to every open loop at once. For
  each, if `reschedule.count < 3`, defer it to the same clock time tomorrow
  (or tomorrow morning if it had no clock time). Loops already at the cap stay
  open — name them. Reply with the tally: "Pushed {n} to tomorrow. {m} stayed
  — you've moved those enough; let's not dodge them."
- **cancel** ("cancel / stop / delete <reminder>"): cancel the reminder's
  `cron_job_id` and any open occurrence's `escalation_cron_id`; reminder
  `status: "cancelled"`; resolve any open occurrence as `excused` and drop its
  `open_loops` entry. Reply: "Done — '{what}' is off."
- **pause** ("pause <reminder>"): disable `cron_job_id` (or cancel and keep
  `schedule` for resume); `status: "paused"`. Reply: "Paused. Say 'resume
  {what}' anytime."
- **resume** ("resume <reminder>"): re-create the cron job from the stored
  `schedule`; new `cron_job_id`; `status: "active"`. Reply: "Back on — '{what}'
  is live."

## Step 6 — Status queries

- **"what's open" / "status"**: list every `open_loops` occurrence —
  `{what}` and how long it has been open. Clean, plain (Law 6). If none:
  "Nothing open — you're clear. ✅"
- **"list reminders"**: list reminders with `status == "active"` — `{what}`,
  recurrence, current `streak`. If none: "No active reminders yet."

## Pitfalls

- **Generous parsing** (Law 1): "yep", "✅", "did that", a thumbs-up, a rambly
  voice note — all resolve. Never demand exact syntax.
- **Never auto-MISS on silence.** A miss is only ever recorded from an explicit
  user reply here. Unanswered loops stay `pending` (carried by `fire-reminder`
  timeout and the morning sweep).
- **Recurring reminders**: DONE / MISSED close only the current occurrence —
  the recurring schedule continues. Only set `status: "completed"` on a `once`
  reminder.
- **Output hygiene**: never surface `reminders.json`, job IDs, occurrence IDs,
  cron expressions, file paths, tool names, or raw errors. On failure, one
  plain line — "I couldn't log that — try once more?"
