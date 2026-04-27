# Frameworks/

Pre-built binary frameworks committed into the repo because no SPM upstream provides them.

## FluidSynth.xcframework

- **Source:** https://github.com/FluidSynth/fluidsynth tag `v2.5.4`
- **Build script:** `contrib/ios_build.sh` (uses `leetal/ios-cmake` toolchain)
- **License:** LGPL 2.1+
- **iOS arm64 binary SHA-256:** `c6ab6bfa0ec7f7ff66026c1822e187d6b7eda726ab812b81482daed6286ab931`
- **Built:** 2026-04-27
- **Used by:** `Packages/SVAudio` — DEBUG-only audition pipeline
  (`SurVibe/Diagnostics/AuditionPipelineSection.swift`).
  Not referenced from any Release-shipped code path.

### Rebuilding

If you need to rebuild (e.g. upstream tag bump, security patch):

```bash
mkdir -p /tmp/fs-build && cd /tmp/fs-build
git clone --branch v2.5.4 --depth 1 https://github.com/FluidSynth/fluidsynth.git
cd fluidsynth
bash contrib/ios_build.sh
cp -R build/FluidSynth.xcframework /Users/maheshwar/Developer/SurVibe/Frameworks/
```

Verify the new SHA-256 matches the expected hash above (or update the hash if intentional).

### LGPL acknowledgment

This binary is dynamically linked. Per LGPL 2.1+, users have the right to relink against
a different FluidSynth build. Source: https://github.com/FluidSynth/fluidsynth/tree/v2.5.4
