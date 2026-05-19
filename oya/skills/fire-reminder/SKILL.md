---
name: fire-reminder
description: >
  Execute a scheduled reminder: send ping to user, then schedule escalation
  if tier requires it. Triggered by cron. Job context must include
  `reminder_id: <id>` and optionally `step: <1|2|3|timeout>` (default: 1).
  Step 1 = initial ping. Step 2 = follow-up (tier ≥ 2). Step 3 = urgent final
  ping (tier ≥ 3). Step timeout = mark missed, check buddy ping (tier 4).
version: 0.1.0
metadata:
  hermes:
    tags: [reminders, escalation, oya, cron]
    category: productivity
    config:
      - key: oya.user.telegram_id
        description: "User's Telegram numeric user ID"
      - key: oya.user.name
        description: "User's first name (used in buddy messages)"
        default: "Joseph"
      - key: oya.buddy.telegram_id
        description: "Accountability buddy's Telegram ID (tier 4)"
      - key: oya.quiet_hours.start
        description: "Quiet hours start (24h integer, e.g. 23). Null = disabled."
        default: null
      - key: oya.quiet_hours.end
        description: "Quiet hours end (24h integer, e.g. 7). Null = disabled."
        default: null
---

# Fire Reminder

## When to use

Called exclusively by cron jobs created by `parse-reminder` and by escalation
cron jobs created by this skill itself. Never called directly by the user.

The triggering job's context message format:
```
reminder_id: rem_YYYYMMDD_HHMMSS_NNN step: 1
```

## Common setup (all steps)

1. Parse `reminder_id` from context. Parse `step` — default to `1` if absent.
2. Read `/opt/data/oya/reminders.json`.
3. Find reminder where `id == reminder_id`.
4. If not found: log `"[fire-reminder] ERROR: reminder <id> not found"`. Stop.
5. If `status != "active"`: stop silently.
6. If `end_date` is set and today's date > `end_date`:
   - Set reminder `status: "completed"`. Write back. Stop.

---

## Step 1 — Initial ping

**7. Quiet hours check.**
If `oya.quiet_hours.start` and `oya.quiet_hours.end` are both set, and the
current hour (in user's timezone) falls within the quiet range, AND tier ≤ 2:
- Append to history: `{"fired_at": "<now>", "ack": "missed", "escalation_step": 1, "notes": "quiet hours"}`
- Write back. Stop.

**8. Send ping on all delivery channels.**

For each channel in `delivery_channels`:
- `telegram`: send to `oya.user.telegram_id`:
  ```
  ⏰ <what>
  ```
- `whatsapp`: send to `oya.user.whatsapp_number` (same text).

**9. Append to history:**
```json
{
  "fired_at": "<now ISO8601>",
  "ack": null,
  "escalation_step": 1,
  "response_time_seconds": null
}
```

**10. Write back** reminders.json.

**11. If tier ≥ 2: schedule step 2.**
- Create a one-time cron job via the `cronjob` tool:
  - Expression: fires 30 minutes from now (one-shot)
  - Context message: `reminder_id: <id> step: 2`
  - Skill: `fire-reminder`
- Store the returned cron job ID in `pending_escalation_cron_id`. Write back.

Stop.

---

## Step 2 — Second ping

**7. Ack check.**
Look at the most recent history entry. If `ack` is not null, the user already
responded — stop without sending anything.

**8. Send follow-up ping.**
- Telegram to `oya.user.telegram_id`:
  ```
  📌 Still pending: <what>
  Reply ✅ done · ❌ skip · snooze 1h
  ```

**9. Update most recent history entry:** set `escalation_step: 2`.

**10. Write back** reminders.json.

**11. If tier ≥ 3: schedule step 3.**
- Create a one-time cron job:
  - Fires 15 minutes from now (one-shot)
  - Context: `reminder_id: <id> step: 3`
  - Skill: `fire-reminder`
- Update `pending_escalation_cron_id`. Write back.

Stop.

---

## Step 3 — Urgent final ping (tier 3+)

**7. Ack check.** Same as step 2 — if already acked, stop.

**8. Send urgent ping.**
- Telegram to `oya.user.telegram_id`:
  ```
  🚨 Last call: <what>
  Reply ✅ done · ❌ skip — or this gets marked missed.
  ```

**9. Update most recent history entry:** set `escalation_step: 3`.

**10. Schedule timeout.**
- Create a one-time cron job:
  - Fires 60 minutes from now
  - Context: `reminder_id: <id> step: timeout`
  - Skill: `fire-reminder`
- Update `pending_escalation_cron_id`. Write back.

Stop.

---

## Step timeout — Mark missed

**7. Ack check.** If most recent history entry `ack` is not null: stop.

**8. Mark missed.**
- Update most recent history entry: `"ack": "missed"`
- Set `pending_escalation_cron_id: null`
- Write back reminders.json.

**9. Tier 4 buddy check.**
Count the most recent consecutive `"missed"` entries in history (stop counting
when you hit a non-missed entry). If count ≥ 3 AND `oya.buddy.telegram_id` is
configured:
- Send Telegram message to `oya.buddy.telegram_id`:
  ```
  👋 Hey — <oya.user.name> set a reminder for '<what>' and has missed it <count> times in a row. A gentle nudge would help.
  ```

Stop.

---

## Data mutation summary

| Step | Writes to reminders.json | Creates cron job |
|---|---|---|
| 1 | append history entry; set pending_escalation_cron_id | Yes (step 2), if tier ≥ 2 |
| 2 | update last history entry | Yes (step 3), if tier ≥ 3 |
| 3 | update last history entry | Yes (timeout) |
| timeout | update last history entry; clear pending_escalation_cron_id | No |

`record-outcome` handles all ack writes — this skill never writes `ack` values
except for quiet-hours skips and timeout misses.
