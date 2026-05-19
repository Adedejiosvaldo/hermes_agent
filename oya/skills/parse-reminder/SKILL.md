---
name: parse-reminder
description: >
  Parse a free-text or transcribed-voice reminder request into a structured
  reminder object, confirm with user, then schedule it. Triggers on: "remind
  me", "nag me", "every day", "every weekday", "tomorrow", "next [day]", "in
  [N] hours/days", "schedule", "don't let me forget", "ping me". Handles Pidgin
  English phrasings ("abeg remind me say make I…"). Writes to
  ~/.hermes/data/oya/reminders.json and creates a cron job via the cronjob tool.
version: 0.1.0
metadata:
  hermes:
    tags: [reminders, scheduling, oya, parse]
    category: productivity
    config:
      - key: oya.user.timezone
        description: "User's IANA timezone"
        default: "Africa/Lagos"
        prompt: "What timezone should reminders use? (e.g. Africa/Lagos, Europe/London)"
      - key: oya.default.tier
        description: "Default escalation tier 1-4 when not specified"
        default: 2
        prompt: "Default escalation tier? (1=gentle, 2=confirm, 3=phone call, 4=buddy ping)"
      - key: oya.user.name
        description: "User's first name"
        default: "Joseph"
---

# Parse Reminder

## When to use

- User says: "remind me", "nag me", "ping me", "tell me to", "don't let me forget"
- Any message combining an action with a time expression
- User forwards content (URL, text snippet) with a scheduling phrase
- Voice note containing any of the above (already transcribed by Hermes gateway)
- Pidgin variants: "abeg remind me say make I…", "no forget make I…", "tell me make I…"

## Procedure

### Step 1 — Extract fields

**`what`** — the core task. Strip scheduling scaffolding, keep the action:
- "remind me tomorrow to call mom" → `call mom`
- "abeg remind me say make I top up gen Friday evening" → `top up gen`
- Forwarded URL + "read this Sunday" → `Read: [URL]`
- "nag me about the MacBook installment" → `MacBook installment payment`

**`when`** — first fire datetime in ISO 8601, resolved against NOW in `oya.user.timezone`. See time resolution table in Step 2.

**`recurrence`** — one of: `once | daily | weekday | weekend | weekly | monthly | custom`
- "remind me tomorrow" → `once`
- "every day" / "daily" / "each morning" → `daily`
- "every weekday" / "weekdays" / "Monday through Friday" → `weekday`
- "weekends" / "every Saturday and Sunday" → `weekend`
- "every Friday" / "every Tuesday" → `weekly`
- "every 1st of the month" / "monthly" → `monthly`
- "every day for 30 days" → `daily` with `end_date: first_fire + 30d`
- Irregular / complex → `custom` (describe in `what`)

**`end_date`** — ISO date or null:
- "for 30 days" → `first_fire_date + 30d`
- "until June 1st" → `2026-06-01`
- "for 3 weeks" → `first_fire_date + 21d`
- Not specified / forever → `null`

**`tier`** — integer 1–4. Infer from context if not stated:
- Article to read, casual intention, "watch this later" → 1
- Work, meeting, call, deadline, default → 2
- "important", "don't let me miss", "critical", medication, flight → 3
- "accountability", "publicly committed", "tell my buddy if I fail" → 4
- "nag me" alone implies minimum tier 2

**`delivery_channels`** — list. Default `["telegram"]`. Add `"whatsapp"` if user explicitly says so.

### Step 2 — Time resolution

Apply strictly. When in doubt, ask — never guess on time-critical reminders.

| Expression | Resolution |
|---|---|
| "tomorrow" | today + 1 day |
| "today" | today (if time is still in the future) |
| "next [weekday]" | always the following week's occurrence |
| "[weekday]" Mon–Thu, day is later this week | this week |
| "[weekday]" and today is that day or it has passed this week | next week |
| "[weekday]" and today is Fri/Sat/Sun | ASK — this week or next? |
| "in N hours/minutes" | now + N |
| "morning" without a time | ASK: "What time? I'll suggest 8am if that works." |
| "afternoon" without a time | ASK: "2pm? 3pm?" |
| "evening" without a time | ASK: "6pm? 8pm?" |
| "night" without a time | ASK: "9pm? 10pm?" |
| No time given for day-specific reminder | ASK before proceeding |

**Never silently default an ambiguous time.** You may suggest a default and ask for confirmation, but do not schedule without explicit or clearly-implied time.

### Step 3 — Ambiguity check

Ask ONE focused question if any of:
- Time not specified and reminder is day-specific (not "in N hours")
- "Friday"/"Tuesday" etc. and today is Fri–Sun
- "evening"/"morning"/"afternoon"/"night" used without a clock time
- The action is genuinely unclear ("remind me about that thing")
- Recurrence pattern is contradictory or ambiguous

One question per turn. Wait for the answer before continuing.

### Step 4 — Generate ID and cron expression

**ID format:** `rem_YYYYMMDD_HHMMSS_NNN`
- YYYYMMDD = fire date of first occurrence
- HHMMSS = fire time
- NNN = zero-padded index = current length of `reminders` array in reminders.json

**Cron expression** (6-field: sec min hour dom month dow):

| Recurrence | Cron pattern |
|---|---|
| once | `0 {min} {hour} {dom} {month} *` |
| daily | `0 {min} {hour} * * *` |
| weekday | `0 {min} {hour} * * MON-FRI` |
| weekend | `0 {min} {hour} * * SAT,SUN` |
| weekly (e.g. Friday) | `0 {min} {hour} * * FRI` |
| monthly (1st) | `0 {min} {hour} 1 * *` |
| monthly (15th) | `0 {min} {hour} 15 * *` |

### Step 5 — Confirm with user

Before scheduling, send a plain-language confirmation:

> "Got it: [frequency] at [time] — **'[what]'** [end note if applicable]. Tier [N] ([tier description]).
> Reply ✅ to confirm or tell me what to change."

Tier descriptions for confirmation messages:
- 1 → "one ping, no follow-up"
- 2 → "second ping if no ack in 30 min"
- 3 → "urgent third ping if you ignore two pings"
- 4 → "DM your buddy after 3 consecutive misses"

Example for a recurring work reminder:
> "Got it: every weekday at 8:55am — **'Friday team call'**. Tier 4 (DM your buddy after 3 consecutive misses). Telegram only.
> Reply ✅ to confirm or tell me what to change."

Example for a one-shot:
> "Got it: tomorrow at 9am — **'call Tunde'**. Tier 2 (second ping if no ack in 30 min).
> Reply ✅ to confirm."

### Step 6 — Schedule on confirmation

Wait for ✅ or any clear affirmative ("yes", "yep", "ok", "correct", "go", "do it").

If user requests changes instead, loop back to Step 5 with the corrected fields.

On confirmation:

1. **Read** `~/.hermes/data/oya/reminders.json`. If file missing, create it:
   ```json
   {"reminders": [], "user_model": {"patterns": [], "preferences": {}, "last_reviewed": null}}
   ```

2. **Build reminder object** and append to `reminders` array:
   ```json
   {
     "id": "rem_YYYYMMDD_HHMMSS_NNN",
     "created_at": "<now ISO8601>",
     "created_via": "telegram",
     "source_text": "<original user message verbatim>",
     "what": "<extracted action>",
     "schedule": "<6-field cron expression>",
     "recurrence": "<once|daily|weekday|weekend|weekly|monthly|custom>",
     "first_fire": "<ISO8601>",
     "end_date": "<ISO8601 or null>",
     "tier": 2,
     "delivery_channels": ["telegram"],
     "status": "active",
     "cron_job_id": null,
     "pending_escalation_cron_id": null,
     "history": []
   }
   ```

3. **Write** the updated reminders.json.

4. **Create the cron job** via the `cronjob` tool:
   - Expression: the 6-field cron from Step 4
   - Context message: `reminder_id: <id> step: 1`
   - Skill: `fire-reminder`
   - If `recurrence == "once"`: one-time job (single execution)
   - If `end_date` is set: configure job end date on the cron entry

5. **Store the returned cron job ID** back in the reminder's `cron_job_id` field. Write reminders.json again.

6. **Reply to user:**
   > "Done — **'[what]'** is set. First ping: [first_fire formatted as 'Monday May 18 at 9am']. Say 'list reminders' or 'cancel [reminder name]' any time."

## Pitfalls

- **Never schedule in the past.** If parsing produces a datetime already elapsed (even 1 minute ago), say: "That time has already passed — did you mean [same time tomorrow / next week]?"
- **"Nag me" always means tier ≥ 2.** Never assign tier 1 when user says "nag", "don't let me miss", "keep reminding me".
- **Forwarded URLs** — preserve the URL in `what` so fire-reminder delivers it with the ping.
- **"Every day for N days"** — set `end_date`, not an open-ended recurrence.
- **Pidgin time phrases** — "for evening", "by morning", "before night" are all ambiguous. Always ask.
- **Voice transcription edge cases** — if the transcript looks garbled (repeated words, broken sentence), ask "Did I get this right: [what you parsed]?" before confirming.

## Verification test cases

| Input | Expected |
|---|---|
| "remind me tomorrow 9am to call Tunde" | once, +1d 09:00, tier 2 |
| "every weekday 8:55am Friday team call" | weekday, 08:55 MON-FRI, tier 2 |
| "every day 6am for 30 days 20 pushups" | daily, 06:00, end_date +30d, tier 2 |
| "abeg remind me say make I top up gen Friday evening" | ASK: what time Friday evening? |
| "remind me Friday" (said on Sunday) | ASK: what time? also confirm this Friday or next? |
| "remind me in 5 minutes" | once, now+5m, tier 1 |
| "nag me every Sunday to call dad" | weekly Sun, ASK for time, tier ≥ 2 |
| "critical: remind me to take BP meds 8am daily" | daily 08:00, tier 3 |
