---
name: daily-review
description: >
  Nightly summary of the day's reminder performance. Runs at 22:00 daily.
  Reports hits and misses, asks about rollovers for missed one-shots, detects
  patterns, and updates the user model in reminders.json. Delivers via Telegram.
  Schedule this with: hermes cron add "0 0 22 * * *" --skill daily-review
version: 0.1.0
metadata:
  hermes:
    tags: [reminders, review, learning, oya, cron]
    category: productivity
    config:
      - key: oya.user.timezone
        description: "User's IANA timezone"
        default: "Africa/Lagos"
      - key: oya.user.name
        description: "User's first name"
        default: "Joseph"
      - key: oya.review.pattern_min_days
        description: "Minimum days of data before pattern suggestions are shown"
        default: 7
---

# Daily Review

## When to use

Triggered by cron at 22:00 daily. Never triggered directly by user messages
(use `record-outcome` for mid-day queries). The cron job should be created
once during setup and run indefinitely.

## Procedure

### Step 1 — Load today's data

1. Read `~/.hermes/data/oya/reminders.json`.
2. Determine today's date in `oya.user.timezone`.
3. Collect all history entries where `fired_at` date == today. Include entries
   from all reminders (active, completed, paused).
4. If no history entries for today: send short message and stop:
   ```
   No reminders fired today. Nothing to review.
   ```

### Step 2 — Compute today's stats

For today's entries, calculate:
- `total_fired`: count of all entries
- `completed`: count where `ack == "completed"`
- `skipped`: count where `ack == "skipped"`
- `missed`: count where `ack == "missed"`
- `snoozed`: count where `ack == "snoozed"`
- `pending`: count where `ack == null` (still awaiting response — only possible if review runs before all escalation windows close, unlikely but handle it)
- `hit_rate`: completed / total_fired (as percentage, exclude pending from denominator)
- `avg_response_time`: mean of `response_time_seconds` across completed entries (ignore nulls)

### Step 3 — Compose and send daily summary

Send to Telegram (`oya.user.telegram_id`). Format:

```
📊 Today's recap — <weekday, date>

✅ <completed>  ❌ <missed>  ⏭ <skipped>  💤 <snoozed>
Hit rate: <hit_rate>%

<one line per reminder that fired today, in time order>
  • <time> — <what>: <ack emoji>
  ...
```

Ack emoji mapping: ✅ completed · ❌ missed · ⏭ skipped · 💤 snoozed · ⏳ pending

Example:
```
📊 Today's recap — Friday, 17 May

✅ 3  ❌ 1  ⏭ 0  💤 1
Hit rate: 75%

  • 06:00 — 20 pushups: ❌
  • 08:55 — Friday team call: ✅
  • 14:00 — MacBook installment check: 💤
  • 20:00 — call dad: ✅
  • 21:00 — read article: ✅
```

Follow with a blank line, then rollover prompt if applicable (Step 4).

### Step 4 — Rollover prompt for missed one-shots

For any `once` reminder that fired today with `ack == "missed"`:
- Ask: `Want me to reschedule '<what>'? Reply with a time, or 'no'.`
- Ask about each missed one-shot separately (one message per, not batched).
- Wait for user reply. If user gives a time, invoke `parse-reminder` logic to
  schedule a new one-shot with the same `what` and new time.
- If user says "no" or ignores: leave it. Don't re-ask tomorrow.

### Step 5 — Pattern detection

Only run this step if total history entries across ALL reminders ≥
`oya.review.pattern_min_days` × (number of active recurring reminders).

Analyze patterns by scanning ALL history (not just today). Look for:

**Time-of-day failure clusters:**
- Group history by hour of `fired_at`. Calculate miss rate per hour.
- If any hour has miss rate ≥ 70% with ≥ 5 data points:
  → Flag: `Your <H>:00 reminders get missed 70%+ of the time.`

**Day-of-week failure clusters:**
- Group history by day of week. Calculate miss rate per day.
- If any weekday has miss rate ≥ 70% with ≥ 4 data points:
  → Flag: `Your <Day> reminders get missed a lot.`

**Time shift suggestion:**
- For a reminder with miss rate ≥ 60%, check if other nearby hours have
  better hit rates in the user's overall history. If yes:
  → Suggest: `'<what>' fires at <time> but you usually respond better around <better_time>. Want me to shift it?`
  → Wait for reply. If yes, update the cron expression and reminder schedule.

**Late-night Sunday pattern:**
- If any reminder created between 00:00–04:00 on Sunday has miss rate ≥ 80%:
  → Add to `user_model.patterns`: `{"rule": "late_sunday_creation", "note": "Reminders created late Sunday night have high miss rate. Warn at creation time."}`
  → Next time `parse-reminder` runs and NOW is between 00:00–04:00 on Sunday,
    it should surface: "Heads up — reminders you set at this hour tend to get missed. Want to schedule this for tomorrow morning instead?"

**Streak recognition:**
- If any reminder has ≥ 5 consecutive `completed` entries: mention it in
  summary: `🔥 <N>-day streak on '<what>'.`

### Step 6 — Update user model

After pattern detection, write any new patterns to `user_model.patterns` in
reminders.json. Each pattern:
```json
{
  "id": "pat_<timestamp>",
  "type": "time_cluster|day_cluster|shift_suggestion|creation_pattern",
  "description": "<human-readable description>",
  "detected_at": "<ISO8601>",
  "applies_to_reminder_id": "<id or null if general>",
  "active": true
}
```

Remove patterns where `active == false` or that contradict new data (e.g., a
time that was flagged as bad but now has a good hit rate for 2+ weeks).

Update `user_model.last_reviewed` to now. Write back reminders.json.

### Step 7 — Closing message

End with one short encouraging line. Keep it plain, no cringe:
- Perfect day: `Clean sweep today.`
- Hit rate ≥ 80%: `Good day.`
- Hit rate 50–79%: `Decent. <pattern insight if any, one line>.`
- Hit rate < 50%: `Rough one. <one actionable note>.`

Do not add sign-offs, emojis beyond what's specified, or motivational quotes.

## Pitfalls

- **Don't nag about missed recurring reminders.** Daily review mentions them
  in the recap but does not reschedule them — they fire again on their own
  schedule. Only ask about rollover for `once` reminders.
- **Pattern detection is suggestion-only.** Never auto-reschedule without
  explicit user confirmation.
- **Empty days are fine.** No reminders fired = no review needed. Send the
  short message and stop — don't manufacture content.
- **Pending acks at 22:00.** If a reminder fired at 21:00 and ack window is
  still open, show it as ⏳ and don't count it in hit rate denominator.
