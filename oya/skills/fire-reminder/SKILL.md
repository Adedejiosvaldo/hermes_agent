---
name: fire-reminder
description: >
  Fire a scheduled reminder: open an accountability loop (a pending occurrence),
  send the contract ping asking the user to close it, and schedule follow-ups.
  Triggered by cron. Job context must include `reminder_id: <id>` and
  `occurrence_id: <id>` (omit occurrence_id on step 1 — it is created here), and
  optionally `step: <1|2|3|timeout>` (default: 1). Step 1 = open loop + ping.
  Steps 2/3 = follow-up nudges. Step timeout = carry the loop forward (never a
  silent miss).
version: 0.2.0
metadata:
  hermes:
    tags: [reminders, escalation, oya, cron]
    category: productivity
    config:
      - key: oya.user.telegram_id
        description: "User's Telegram numeric user ID"
      - key: oya.user.name
        description: "User's first name"
        default: "Joseph"
      - key: oya.quiet_hours.start
        description: "Quiet hours start (24h integer, e.g. 23). Null = disabled."
        default: null
      - key: oya.quiet_hours.end
        description: "Quiet hours end (24h integer, e.g. 7). Null = disabled."
        default: null
---

# Fire Reminder

Opens an accountability loop and pursues it until the user closes it. A reminder
firing is not "done" when the ping sends — it is done when the loop is resolved
by `record-outcome`. This skill never marks a miss silently.

Voice: warm, direct, Oya's character (design ref: `PERSONA.md`). Obey the UX
laws (`UX-LAWS.md`) — especially Law 1 (one-tap close) and Law 3 (earn the
notification). Data shapes: `SCHEMA.md`.

## Execution rules — read first

1. **The user sees exactly ONE message: the contract ping** (step 9), or a
   follow-up nudge (steps 2/3/timeout). Never narrate what you did, never send
   a status report, never write "loop opened / occurrence created / escalation
   scheduled". Never mention occurrence IDs, `reminders.json`, `open_loops`,
   job IDs, or file paths. Steps 6–8 and 10–11 are **silent** — the user sees
   nothing from them. If you catch yourself listing what you did, stop — send
   only the ping.
2. **Do the work with your tools, never the shell.** Read and write
   `reminders.json` with your file-read / file-write tools. Schedule with the
   `cronjob` tool. Never use the terminal, a shell, `python`, or any CLI —
   that is not how this skill works.

## When to use

Called only by cron jobs — the reminder's own job (`parse-reminder` created it)
and the follow-up jobs this skill creates. Never called directly by the user.

Job context format:
```
reminder_id: rem_YYYYMMDD_HHMMSS_NNN occurrence_id: occ_YYYYMMDD_HHMMSS step: 2
```

## Common setup (all steps)

1. Parse `reminder_id`, `occurrence_id`, `step`, `defer_count` from context.
   `step` defaults to `1`. On step 1 there is no `occurrence_id` yet;
   `defer_count` is present only when this firing came from a deferral.
2. Read `/opt/data/oya/reminders.json`. If `open_loops` is missing, treat it as
   `[]`. If a reminder has no `occurrences`, treat it as `[]`.
3. Find the reminder where `id == reminder_id`. If not found, stop silently.
4. If reminder `status != "active"`, stop silently.
5. If `end_date` is set and today > `end_date`: set `status: "completed"`,
   write back, stop.

---

## Step 1 — Open the loop

**6. Quiet hours.**
If `oya.quiet_hours.start` and `.end` are both set and the current hour (user's
timezone) is inside the quiet range, AND `tier <= 2`:
- Do **not** ping now (Law 3 — quiet hours are sacred).
- Still create the occurrence (step 7) so the loop is not lost.
- Schedule a fresh `step: 1` job for this reminder at quiet-hours end, then stop.

**7. Create the occurrence.** Append to the reminder's `occurrences`:
```json
{
  "id": "occ_<now compact: YYYYMMDD_HHMMSS>",
  "due_at": "<scheduled due time, ISO8601>",
  "fired_at": "<now ISO8601>",
  "state": "pending",
  "resolved_at": null,
  "reason": null,
  "reschedule": { "count": 0, "to": null },
  "escalation_step": 1,
  "escalation_cron_id": null,
  "carry_count": 0,
  "xp_awarded": 0,
  "streak_before": null
}
```

If context included `defer_count`, set this occurrence's `reschedule.count` to
that value — this loop was moved here from an earlier deferral.

**8. Add the open loop.** Append to top-level `open_loops`:
```json
{ "reminder_id": "<reminder_id>", "occurrence_id": "<occurrence id>" }
```

**9. Send the contract ping** — see "The contract ping" below. Deliver to
`oya.user.telegram_id`.

**10. Write back** reminders.json.

**11. Schedule the follow-up.** If `tier >= 2`, create a one-shot cron job via
the `cronjob` tool:
- Schedule: relative delay `30m`.
- Context: `reminder_id: <id> occurrence_id: <occ id> step: 2`
- Skill: `fire-reminder`
- Store the returned job id in the occurrence's `escalation_cron_id`, write back.

Stop.

---

## Step 2 — Follow-up nudge

**6. Resolved check.** Find the occurrence by `occurrence_id`. If its `state` is
**not** `pending`, the user already closed it — stop silently.

**7. Send a follow-up nudge** — Oya's voice, gently insistent (PERSONA "still
open"). Restate the three ways to close it. Reuse the reply keyboard.

**8. Update** the occurrence: `escalation_step: 2`. Write back.

**9. Escalate if needed.** If `tier >= 3`, schedule a one-shot `step: 3` job
(relative delay `15m`, same context shape), store `escalation_cron_id`, write
back.

Stop.

---

## Step 3 — Urgent nudge (tier 3+)

**6. Resolved check.** Same as step 2 — if not `pending`, stop silently.

**7. Send an urgent nudge** — direct, still kind, still a coach not a cop
(Law 4). Make clear the loop is about to be carried, not erased.

**8. Update** the occurrence: `escalation_step: 3`. Write back.

**9. Schedule timeout.** One-shot `step: timeout` job (relative delay `60m`),
store `escalation_cron_id`, write back.

Stop.

---

## Step timeout — Carry the loop forward

A loop that the user never answered is **not** a silent miss. It stays open.

**6. Resolved check.** If the occurrence is not `pending`, stop silently.

**7. Send a carry-forward line** — calm, no shame: the loop is still open and
Oya will bring it back. Example shape: *"Still open: {what}. I'm holding it —
we'll pick it up. Tell me when you can."*

**8. Update** the occurrence: `escalation_step: "timeout"`, clear
`escalation_cron_id`. Leave `state: "pending"` and leave the `open_loops`
entry in place. Write back.

The occurrence stays in `open_loops`. The user closes it via the `oya` skill;
the morning sweep (`morning-check`) resurfaces it. A miss is only ever
recorded by an explicit user action — never here.

Stop.

---

## The contract ping

The message the user sees on step 1. It must make the contract obvious: the
loop closes three ways, and one tap is enough (Law 1).

Compose in Oya's voice — vary the wording every time (Law 2), never the same
string twice. Include:

- The task (`what`).
- The streak: if `reminder.streak > 0` → "🔥 day {streak}"; if `0` → frame it
  as a fresh start.
- The three ways to close it: **done**, **move it** (a new time), **why** (if
  they couldn't).

Text shape (vary it):
```
⏰ {what} — 🔥 day {streak}
Close the loop — ✅ done · ⏰ a new time · 💬 why, if you couldn't
```

**Reply keyboard.** If the messaging tool supports a reply keyboard
(`reply_markup`), attach one-tap buttons: `✅ Did it`, `⏰ Move it`,
`💬 Couldn't`. Use `one_time_keyboard`. The buttons are a fast path only — the
three options must always be stated in the text too, so the contract holds even
without buttons. Typed text and voice notes are always valid replies.

---

## Data mutation summary

| Step | Writes to reminders.json | Creates cron job |
|---|---|---|
| 1 | append occurrence (pending); add `open_loops` entry | Yes — step 2, if tier ≥ 2 |
| 2 | occurrence `escalation_step: 2` | Yes — step 3, if tier ≥ 3 |
| 3 | occurrence `escalation_step: 3` | Yes — timeout |
| timeout | occurrence `escalation_step: "timeout"`; clear `escalation_cron_id` | No |

This skill never sets occurrence `state` to anything but `pending`.
The `oya` skill (mode B) owns every resolution.

## Output hygiene

Pings are user-facing. Never include `reminders.json`, job IDs, occurrence IDs,
`cron_job_id`, file paths, cron expressions, tool names, or CLI/environment
error text. If a step fails, stay silent or send one plain line — never paste a
raw error or internal state into the chat.
