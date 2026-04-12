---
paths:
  - "SurVibe/**"
---

# App Target Rules

## SwiftData
- No `VersionedSchema` — incompatible with CloudKit automatic sync (see Banned Patterns).
- ALL `@Model` fields MUST have explicit default values: `var name: String = ""`.
- ALL relationships MUST be optional.
- Enums stored as `String` rawValue (CloudKit compatibility).
- Arrays and Dictionaries sync as opaque `Transformable` blobs — cannot be queried server-side.
- Schema changes: ADD new fields with defaults ONLY. NEVER delete or rename fields.
- Manual `schemaVersion` integer in UserDefaults (checked on launch).
- For critical writes (session completion, XP award, achievement unlock), call `try modelContext.save()` explicitly in a `do/catch` block. SwiftData auto-saves, but explicit save ensures data is persisted before the user leaves the screen.
- ModelContainer configured with: `ModelConfiguration(cloudKitDatabase: .automatic)`.

## CloudKit
- Conflict strategy: additive-only + max-wins (higher value survives).
- XP, scores, play counts: highwater mark (keep higher).
- Achievements, practice entries: append-only (never delete).
- `unlocked` flags: one-way (false->true, never reverts).
- Required entitlements: iCloud (CloudKit), Background Modes (Remote notifications + Audio), Push Notifications.

## 4-Tab Navigation

| Tab | View | Icon | Purpose |
|-----|------|------|---------|
| Home | `HomeTab` | `house.fill` | Dashboard, quick actions, recent activity |
| Learn | `LearnTab` | `book.fill` | Lessons, sargam notation, guided learning |
| Songs | `SongsTab` | `music.note.list` | Song library, play-along, progress tracking |
| Profile | `ProfileTab` | `person.fill` | XP, achievements, rang level, settings |

## @Model Classes (Main App Target)
SwiftData models live in `SurVibe/Models/` (NOT in SVCore) because CloudKit sync requires models + container in the same module. Packages reference model shapes via protocols in `SVCore/Models/`.

| Model | Purpose | Key Fields |
|-------|---------|------------|
| `UserProfile` | Player identity, XP, rang level | `displayName`, `totalXP`, `currentRang` |
| `RiyazEntry` | Daily practice log (additive-only) | `date`, `durationMinutes`, `notes` |
| `Achievement` | Earned badges (append-only) | `type`, `earnedDate`, `isUnlocked` |
| `SongProgress` | Per-song scores (max-wins) | `songId`, `bestScore`, `timesPlayed`, `isCompleted` |
| `LessonProgress` | Per-lesson completion (one-way flag) | `lessonId`, `isCompleted`, `completedDate` |
| `SubscriptionState` | StoreKit 2 local cache | `tier`, `expirationDate`, `isActive` |

## Localization Rules

### String Catalogs (.xcstrings)
- One `.xcstrings` catalog per package with user-facing strings (NOT centralized).
- Main app target: `SurVibe/Localizable.xcstrings`
- SPM packages: `{Package}/Sources/{Package}/Resources/Localizable.xcstrings`
- `SurVibe/InfoPlist.xcstrings` for privacy strings (NSMicrophoneUsageDescription).

### Localization Patterns

| Context | Pattern |
|---------|---------|
| SwiftUI views (app target) | `Text("Your string")` — auto-extracted |
| SwiftUI views (SPM package) | `Text("Your string", bundle: .module)` |
| Non-SwiftUI (app target) | `String(localized: "key")` |
| Non-SwiftUI (SPM package) | `String(localized: "key", bundle: .module)` |
| Non-localizable display text | `Text(verbatim: value)` |
| Technical/debug strings | Plain string literal (no localization) |

### What NOT to Localize
- Sargam note names: Sa, Re, Ga, Ma, Pa, Dha, Ni (proper nouns across all Indian languages)
- Devanagari labels: सा, रे, ग, म, प, ध, नि
- Western note names: C, D, E, F, G, A, B
- Rang color names: Neel, Hara, Peela, Lal, Sona
- Brand: "SurVibe"
- Analytics events, debug strings, queue labels, logger messages

### Adding a New Language
1. Register ISO 639 code in `knownRegions` (project.pbxproj) — already done for all 22.
2. Add `"xx": { "stringUnit": { "state": "translated", "value": "..." } }` entries in each `.xcstrings` file.
3. No new files, directories, or dependencies needed.

### RTL Support (Urdu, Sindhi, Kashmiri)
- SwiftUI handles RTL automatically when using `.leading`/`.trailing`.
- NEVER use `.left`/`.right` for layout alignment.
- Piano keyboard and music notation MUST be forced LTR: `.environment(\.layoutDirection, .leftToRight)`.

## Design System — Rang Colors

| Level | Name | Hex | WCAG AA | Use |
|-------|------|-----|---------|-----|
| 1 | Neel | #3F51B5 | 4.6:1 | Beginner |
| 2 | Hara | #388E3C | 4.5:1 | Developing |
| 3 | Peela | #F9A825 | 3.1:1 Large only | Intermediate |
| 4 | Lal | #D32F2F | 5.3:1 | Advanced |
| 5 | Sona | #FFB300 | 3.0:1 Large only | Master |
| — | Peela Dark | #C17900 | 4.5:1 | Body text variant |
| — | Sona Dark | #B87700 | 4.5:1 | Body text variant |

**Rules:**
- Peela and Sona: ONLY for backgrounds, large text (18pt+), decorative, icons with labels.
- Body text on light backgrounds: use Peela Dark / Sona Dark.
- ALL colors defined in `SVCore/Theme/RangColorSystem.swift` with `Color` extensions in `SVCore/Extensions/Color+Rang.swift`.
- Dark mode: provide all variants (Asset Catalog with light/dark appearances).
