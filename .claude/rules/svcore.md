---
paths:
  - "Packages/SVCore/**"
---

# SVCore Rules

## Analytics — PostHog Events via AnalyticsManager ONLY
- ALL analytics go through `AnalyticsManager.track(event:properties:)`.
- NEVER import PostHog directly outside SVCore.
- Event names: `snake_case` — `song_played`, `achievement_earned`.
- Property names: `snake_case` — `frequency_hz`, `latency_ms`.
- Privacy: no IP collection, no device fingerprinting, no IDFA, privacy mode ON.

### Defined Events (AnalyticsEvent enum)
- `app_scaffolding_loaded` — fires on every app launch
- `audio_poc_pitch_detected` — fires when pitch detection succeeds
- `cloudkit_sync_completed` — fires when CloudKit sync round-trips
- `tab_selected` — fires on tab navigation (property: `tab`)
- `session_started` — fires when practice session begins
- `session_ended` — fires when practice session ends

## Testing
- **Minimum coverage: 90%** for SVCore (80% for other packages).
