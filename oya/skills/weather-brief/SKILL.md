---
name: weather-brief
description: >
  Fetch tomorrow's weather for the user's city and write a short, practical
  brief. Used two ways: co-loaded on the nightly evening-review cron (its brief
  is folded into that one message), and on demand when the user asks about the
  weather. Uses the free Open-Meteo API — no key required.
version: 0.1.0
metadata:
  hermes:
    tags: [weather, planning, oya]
    category: productivity
    config:
      - key: oya.user.location
        description: "User's city, for weather briefs (e.g. 'Lagos')"
        default: null
        prompt: "What city should I use for weather? (e.g. Lagos)"
---

# Weather Brief

Tells the user what tomorrow looks like so they can plan. Voice: Oya's
character (design ref: `PERSONA.md`) — short, practical, friendly.

## When to use

- On demand: "weather", "what's the weather", "weather tomorrow", "do I need
  an umbrella".
- Co-loaded on the nightly `evening-review` cron — produce the brief and let it
  be folded into that single evening message (do not send a separate ping).

## Procedure

**1. Location.** Read `oya.user.location`. If it is empty, ask the user once:
"Tell me your city and I'll add weather to your evenings." Then stop.

**2. Geocode the city** (free, no key). HTTP GET via the available web/fetch
tool or `curl`:
```
https://geocoding-api.open-meteo.com/v1/search?name=<city>&count=1&language=en&format=json
```
Take `results[0].latitude`, `results[0].longitude`. If no result, tell the
user the city was not found and ask them to re-check it.

**3. Fetch the forecast:**
```
https://api.open-meteo.com/v1/forecast?latitude=<lat>&longitude=<lon>&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=2
```
Use the **`daily` index 1** = tomorrow.

**4. Read the WMO `weather_code`** → condition word + emoji:
- `0` clear ☀️ · `1–3` partly cloudy ⛅ · `45/48` fog 🌫️
- `51–67` rain/drizzle 🌧️ · `71–77` snow ❄️ · `80–82` showers 🌦️
- `95–99` thunderstorm ⛈️

**5. Compose a short brief** — condition, temp low–high, rain chance, and one
practical tip. Vary the wording (Law 2). Shape:
```
🌤️ Tomorrow in {city}: {condition}, {min}–{max}°. Rain {precip}%.
{tip — e.g. "Pack an umbrella." / "Hot one — hydrate." / "Cool morning — layer up."}
```

**6. Deliver.**
- On demand → send the brief to the user.
- Co-loaded with `evening-review` → contribute the brief text to that skill's
  single combined message; do not send separately (Law 3).

## Pitfalls

- Open-Meteo needs no API key — never ask the user for one.
- If the network call fails, skip the weather quietly — never post a raw error
  (Law 6). On the evening cron, the review still goes out without weather.
- Keep the brief to two lines.
