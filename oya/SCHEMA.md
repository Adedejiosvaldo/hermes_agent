# Oya — Data Schema

Single source of truth for `reminders.json`. Every skill that reads or writes
the file follows these shapes exactly. The file lives at
`/opt/data/oya/reminders.json` (symlinked from `/opt/hermes/oya/`).

---

## Top-level file

```json
{
  "reminders": [ <reminder> ... ],
  "open_loops": [ <open-loop ref> ... ],
  "user_model": {
    "timezone": "Africa/Lagos",
    "location": null,
    "patterns": [],
    "preferences": {},
    "last_reviewed": null,
    "gamification": { <gamification> }
  }
}
```

- **`reminders`** — every reminder the user has, active or not.
- **`open_loops`** — fast index of every occurrence currently in `pending`.
  The user's live accountability debt. Never silently emptied.
- **`user_model`** — who the user is and how Oya adapts to them.

---

## Reminder object

A reminder is the *recurring intent*. Each time it fires it produces an
**occurrence**.

```json
{
  "id": "rem_YYYYMMDD_HHMMSS_NNN",
  "created_at": "<ISO8601>",
  "created_via": "telegram",
  "source_text": "<original user message, verbatim>",
  "what": "<extracted action>",
  "schedule": "<schedule spec: relative delay | ISO timestamp | 5-field cron>",
  "recurrence": "once|daily|weekday|weekend|weekly|monthly|custom",
  "first_fire": "<ISO8601 — display/estimate>",
  "end_date": "<ISO8601 or null>",
  "tier": 2,
  "delivery_channels": ["telegram"],
  "status": "active|paused|completed|cancelled",
  "cron_job_id": null,
  "streak": 0,
  "best_streak": 0,
  "total_completions": 0,
  "occurrences": [ <occurrence> ... ]
}
```

- **`id`** — `rem_` + first-fire date + first-fire time + zero-padded index
  (current length of `reminders`).
- **`schedule`** — see `skills/parse-reminder` Step 4. Relative delay (`5m`,
  `2h`, `1d`) or ISO timestamp for one-shots; **5-field** cron for recurring.
- **`streak` / `best_streak` / `total_completions`** — per-habit progress.
  Maintained by `streak-engine` (P3); seed to `0` now.

---

## Occurrence object

An occurrence is *one firing* of a reminder — the open loop that must be
closed.

```json
{
  "id": "occ_YYYYMMDD_HHMMSS",
  "due_at": "<ISO8601>",
  "fired_at": "<ISO8601 or null>",
  "state": "pending|done|deferred|excused|missed",
  "resolved_at": "<ISO8601 or null>",
  "reason": "<string or null>",
  "reschedule": { "count": 0, "to": "<ISO8601 or null>" },
  "escalation_step": 1,
  "escalation_cron_id": null,
  "carry_count": 0,
  "xp_awarded": 0,
  "streak_before": null
}
```

- **`id`** — `occ_` + the occurrence's due date and time.
- **`state`** — see state machine below. `pending` is the only live state.
- **`reason`** — the user's account when `deferred`, `excused`, or `missed`.
  The honest record; feeds `user_model.patterns`.
- **`reschedule.count`** — capped at **3**. Past the cap, Oya confronts the
  avoidance instead of moving the item again.
- **`escalation_step`** — `1` initial, `2`/`3` follow-ups, `timeout` final.
- **`escalation_cron_id`** — the cron job for the next follow-up, so it can be
  cancelled when the loop closes.
- **`carry_count`** — how many times a sweep (`streak-guard` / `morning-check`)
  has carried this still-open loop forward. At `3` the auto-miss valve fires.
- **`streak_before`** — the reminder's `streak` value captured at resolution
  time, so `undo` can restore it exactly.

### State machine

```
            fire
             │
             ▼
        ┌─────────┐   defer → spawns a fresh
        │ PENDING │   PENDING on a new occurrence
        └────┬────┘◄──────────────┐
     ┌───────┼────────┬───────┐   │
     ▼       ▼        ▼       ▼   │
   DONE  DEFERRED  EXCUSED  MISSED│
            └────new occurrence───┘
```

`PENDING` never auto-exits to `MISSED` on silence. It exits only on an explicit
user resolution, or a hard escalation limit — and that exit is always
announced.

---

## Open-loop reference

Each entry in `open_loops` points at one `pending` occurrence:

```json
{ "reminder_id": "rem_...", "occurrence_id": "occ_..." }
```

- `fire-reminder` **adds** an entry when an occurrence opens.
- `record-outcome` **removes** it when the occurrence is resolved.
- `streak-guard` / `morning-check` **read** it to sweep stale loops.

---

## Gamification block

```json
{
  "xp": 0,
  "level": 1,
  "next_level_xp": 100,
  "global_streak": 0,
  "longest_streak": 0,
  "last_active_date": null,
  "streak_freezes": 2,
  "achievements": [],
  "daily_goal": 3,
  "today": { "date": null, "completed": 0, "xp": 0 }
}
```

Seeded now; actively maintained from P3 (`streak-engine`).

---

## Migration note

`docker-entrypoint.sh` only initialises `reminders.json` on first run. An
existing file from the old schema will be missing `open_loops`,
`user_model.location`, `user_model.gamification`, and per-reminder occurrence
fields.

**Every skill, on read:** if a required key is absent, treat it as its default
from this document and write the upgraded shape back. Never crash on the old
shape. Old `history` arrays may be left in place or converted to `occurrences`.
