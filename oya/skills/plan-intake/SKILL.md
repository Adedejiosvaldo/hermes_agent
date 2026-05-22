---
name: plan-intake
description: >
  Take a whole to-do list dropped in one message and turn every item into a
  tracked reminder. Items may be time-boxed ("gym 6pm") or floating ("buy
  milk"); floating items get a proposed time. Confirms the batch once, then
  schedules all of them into the accountability loop. Triggers on a message
  containing multiple tasks, "here's my todo list", "my plan for today".
version: 0.1.0
metadata:
  hermes:
    tags: [reminders, planning, intake, oya]
    category: productivity
    config:
      - key: oya.default.tier
        description: "Default escalation tier 1-4"
        default: 2
      - key: oya.user.timezone
        description: "User's IANA timezone"
        default: "Africa/Lagos"
---

# Plan Intake — bulk to-do list

The user drops a list; Oya turns each line into a tracked reminder so the whole
day is accountable. Voice: Oya's character (design ref: `PERSONA.md`). Per-item
parsing rules: the `parse-reminder` skill. Data shapes: `SCHEMA.md`.

## When to use

- A message with **multiple tasks**: bullets, numbered lines, newline- or
  comma-separated items.
- "here's my todo list", "my plan for today", "things to do today: …".
- A voice note listing several tasks.

If the message is a **single** reminder, hand off to `parse-reminder` instead.

## Procedure

### Step 1 — Split the list
Break the message into individual task items. Ignore headers ("todo:", "today")
and empty lines.

### Step 2 — Parse each item
For each item, following `parse-reminder`'s rules:
- `what` — the action, scaffolding stripped.
- `when` — a time if the item gives one ("gym **6pm**"); otherwise the item is
  **floating**.
- `recurrence` — usually `once` (today). Detect "every day" etc. if present.
- `tier` — `oya.default.tier` unless the item implies otherwise.

### Step 3 — Propose times for floating items
Every floating item gets a **proposed** time — spread the floating items
sensibly across the rest of today: never in the past, never inside quiet
hours, reasonably spaced. These are proposals the user can change in Step 4.

### Step 4 — Confirm the batch (once)
Show the whole plan as a numbered list, each with its time, and ask for one
confirmation:
```
Here's the plan — {name}:
1. 09:00  gym
2. 13:00  call Tunde
3. 16:30  buy milk        (I picked the time — change it if you like)
...
Reply ✅ to lock it all in, or tell me what to change.
```
Apply any edits and re-confirm. Never schedule before confirmation.

### Step 5 — Schedule on confirmation
For **each** item, exactly as `parse-reminder` Step 6 does:
1. Build the reminder object (full shape in `SCHEMA.md` — `occurrences: []`,
   `streak: 0`, `best_streak: 0`, `total_completions: 0`, `status: "active"`).
2. Schedule spec (`parse-reminder` Step 4): a **relative delay** or **ISO
   timestamp** for one-shots, a **5-field** cron for recurring — never a
   6-field/seconds expression.
3. Create the cron job via the `cronjob` tool (skill: `fire-reminder`); store
   the returned id in `cron_job_id`.
4. Append the reminder to `reminders` in `/opt/data/oya/reminders.json`.
Write the file back once, with all new reminders.

### Step 6 — Reply
Confirm warmly in Oya's voice — count and the day laid out:
```
🔥 {N} locked in for today. I'll be on each one. Oya — let's go.
```

## Pitfalls

- **Never schedule in the past** — proposed times for floating items must be
  future; if the day is nearly over, propose tomorrow and say so.
- Confirm the whole batch **once** before scheduling — never item by item.
- Reuse `parse-reminder`'s schedule rules exactly — relative delays for
  one-shots, 5-field cron for recurring.
- A single-task message is not a plan — hand off to `parse-reminder`.
- Never leak internals — no IDs, file paths, cron expressions (Law 6).
