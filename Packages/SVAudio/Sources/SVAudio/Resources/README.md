# SVAudio Resources

This directory holds resources that ship inside the SVAudio Swift Package
bundle. Files in this directory are exposed to runtime code via
`Bundle.module.url(forResource:withExtension:)`.

## SoundFonts

| File | Bundled in git | Purpose |
|------|----------------|---------|
| `MuseScore_General.sf2` (~206 MB) | **No — gitignored, must be placed manually** | Production General-MIDI bank. Used by `ProductionMultiChannelEngine` for all SF2 playback paths. |

## Placing `MuseScore_General.sf2`

The file is too large to keep in git history (215 MB blob). Each developer
must drop the file at this path manually before building the app:

```
Packages/SVAudio/Sources/SVAudio/Resources/MuseScore_General.sf2
```

### Source

The file is FluidR3-lineage General-MIDI bank shipped with MuseScore. License: MIT.

- Canonical download: <https://github.com/musescore/MuseScore/raw/master/share/sound/MuseScore_General.sf2>
- Or copy from another working SurVibe checkout. Expected size: ~215 MB.

### Verification

After placing, the file should be ~215 MB and detected by `Bundle.module.url(...)`
when SVAudio code runs. Build will succeed without it (resource bundle is
opt-in), but `ProductionMultiChannelEngine.init` will throw
`MultiChannelEngineError.bankLoadFailed` at runtime.

### Why not Git LFS

A Git LFS migration was considered but deferred to keep dependencies minimal
and to avoid LFS-quota costs. If the project gains additional contributors,
revisit.

## Other resources

`Localizable.xcstrings` is the SVAudio-package-scoped string catalog (used by
`Text("...", bundle: .module)` in any UI shipped from this package).
