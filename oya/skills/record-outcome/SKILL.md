---
name: record-outcome
description: >
  Record user's response to a fired reminder. Handles: ✅ done, ❌ skip,
  "snooze Nh/Nm", "cancel", "done". Cancels pending escalation cron jobs.
  Triggers on any reply that looks like an acknowledgement of a reminder.
  Writes to ~/.hermes/data/oya/reminders.json.
version: 0.1.0
metadata:
  hermes:
    tags: [reminders, outcomes, oya]
    category: productivity
---

# Record Outcome

## When to use

- User sends ✅ (or "done", "completed", "yes", "yep", "finished", "did it")
- User sends ❌ (or "skip", "no", "not today", "cancel this one")
- User sends "snooze 1h", "snooze 30m", "snooze 2 hours", "remind me in 1h"
- User says "cancel [reminder name]" or "stop [reminder name]" or "delete [reminder]"
- User says "pause reminders" or "pause [reminder name]"
- Any reply that clearly responds to a fired reminder ping

Do NOT trigger on general questions, new reminder requests, or status queries.
If ambiguous, check whether there is an active (unacked) reminder in
`active_fires` before invoking.

## Procedure

### Step 1 — Find the active reminder

1. Read `~/.hermes/data/oya/reminders.json`.
2. Find reminders where `status == "active"` AND the most recent history entry
   has `ack == null` (i.e., a fired-but-unacknowledged reminder).
3. If exactly one such reminder exists: use it.
4. If multiple exist: pick the one whose most recent `fired_at` is closest to
   now (most recently fired).
5. If none exist: tell user "No pending reminders to acknowledge right now."
   Stop.

### Step 2 — Parse the response

Classify the user's message as one of:

| Classification | Trigger phrases |
|---|---|
| `completed` | ✅, "done", "did it", "finished", "yes", "completed", "yep", "✓" |
| `skipped` | ❌, "skip", "no", "not today", "skipping", "missed it", "didn't do it" |
| `snoozed` | "snooze", "remind me in", "snooze Nh", "snooze Nm", "later", "in a bit" |
| `cancelled` | "cancel", "stop", "delete", "remove", "turn off", "don't remind me anymore" |
| `paused` | "pause", "hold off", "stop for now", "resume later" |

For `snoozed`: extract the duration. If no duration given, default to 1 hour
and confirm: "Snoozed 1 hour — I'll ping you again at [time]. OK?"

### Step 3 — Write outcome

**Computed fields:**
- `response_time_seconds`: seconds between `fired_at` of the last history entry
  and now. If `fired_at` is null, set to null.

**Update the most recent history entry** (where `ack == null`):

For `completed`:
```json
{"ack": "completed", "response_time_seconds": <N>}
```

For `skipped`:
```json
{"ack": "skipped", "response_time_seconds": <N>}
```

For `snoozed`:
```json
{"ack": "snoozed", "response_time_seconds": <N>, "snoozed_until": "<ISO8601>"}
```

For `cancelled` / `paused`:
- Do not update history entry `ack` — see Step 4 instead.

### Step 4 — Side effects

**If `completed` or `skipped`:**
- Cancel the pending escalation cron job if `pending_escalation_cron_id` is
  not null: use the `cronjob` tool to delete job by ID.
- Set `pending_escalation_cron_id: null` in reminder.
- If reminder `recurrence == "once"` and outcome is `completed`:
  - Set reminder `status: "completed"`.
- Write back reminders.json.
- Reply to user:
  - completed: `✅ Logged.` (for tier 1/2) or `✅ Logged — <streak info if applicable>.`
  - skipped: `Got it, skipped.`

**If `snoozed`:**
- Cancel `pending_escalation_cron_id` job. Set it null.
- Create a new one-time cron job:
  - Fires at `now + snooze_duration`
  - Context: `reminder_id: <id> step: 1`
  - Skill: `fire-reminder`
- Store new job ID in `pending_escalation_cron_id`.
- Write back reminders.json.
- Reply: `Snoozed — I'll ping you again at <time>.`

**If `cancelled`:**
- Cancel `pending_escalation_cron_id` job.
- Cancel the main `cron_job_id` job (the recurring reminder itself).
- Set reminder `status: "cancelled"`. Set both cron IDs to null.
- Write back reminders.json.
- Reply: `Done — '<what>' reminder cancelled.`

**If `paused`:**
- Cancel `pending_escalation_cron_id` job. Set null.
- Pause or disable the main `cron_job_id` (use cronjob tool to disable if
  supported, otherwise cancel and note the schedule for re-enabling).
- Set reminder `status: "paused"`. Write back.
- Reply: `Paused. Say 'resume <reminder name>' to restart it.`

### Step 5 — Streak feedback (optional, for recurring reminders)

After recording `completed` on a recurring reminder, calculate the current
completion streak: count consecutive `completed` entries in history (most
recent first, stopping at first non-completed).

- Streak ≥ 7: `✅ Logged — 7-day streak! 🔥`
- Streak ≥ 3 and < 7: `✅ Logged — <N> days in a row.`
- Streak == 1 after a miss: `✅ Logged — back on track.`
- Otherwise: `✅ Logged.`

Do not add streak feedback for tier-1 reminders or one-shot reminders.

## Handling "resume" requests

If user says "resume <reminder name>" or "restart <reminder name>":
1. Find reminder where `what` contains the named phrase and `status == "paused"`.
2. Re-create cron job with same schedule expression.
3. Store new `cron_job_id`. Set `status: "active"`.
4. Write back. Reply: `Resumed — '<what>' is active again.`

## Handling "list reminders"

If user says "list reminders", "what reminders do I have", "show my reminders":
1. Read reminders.json.
2. Filter to `status == "active"`.
3. Format as a list:
   ```
   Active reminders:
   1. <what> — <recurrence/next fire time> [Tier <N>]
   2. ...
   ```
4. If none: "No active reminders."

## Pitfalls

- **Ambiguous reply after no active fire**: if user sends ✅ but no reminder
  is pending, ask "What are you checking off? I don't see a pending reminder."
- **Multiple pending reminders**: always pick the most recently fired one
  without asking. If genuinely unclear (two fired within the last 5 minutes),
  list them and ask.
- **Snooze duration**: if user says "snooze" with no duration, use 1h default
  and confirm before scheduling.
- **"Done" on a recurring reminder**: only closes the current occurrence —
  the recurring schedule continues. Do not set `status: "completed"` for
  recurring reminders on a single `completed` ack.
