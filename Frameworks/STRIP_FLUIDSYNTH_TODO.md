# Wire strip-fluidsynth-release.sh as a Build Phase

This script must run after "Embed Frameworks" on the SurVibe app target so the
Release IPA does NOT ship FluidSynth.framework (LGPL — DEBUG-only POC).

1. Open SurVibe.xcodeproj in Xcode.
2. Select the SurVibe app target → Build Phases.
3. Click `+` → New Run Script Phase. Drag it BELOW "Embed Frameworks".
4. Name it: "Strip FluidSynth from Release".
5. Shell: `/bin/bash`.
6. Script: `"${SRCROOT}/Frameworks/strip-fluidsynth-release.sh"`.
7. Input Files (one entry): `$(BUILT_PRODUCTS_DIR)/$(FRAMEWORKS_FOLDER_PATH)/FluidSynth.framework`
8. Output Files: leave empty.
9. Uncheck "Based on dependency analysis" so it runs on every build.
10. Save (⌘S).

Verify with:

    cd /Users/maheshwar/Developer/SurVibe
    xcodebuild -workspace SurVibe.xcodeproj/project.xcworkspace -scheme SurVibe \
        -configuration Release clean build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
    RELEASE_APP=$(find ~/Library/Developer/Xcode/DerivedData -name 'SurVibe.app' -path '*Release-iphoneos*' -newer /tmp 2>/dev/null | head -1)
    find "$RELEASE_APP" -iname 'fluidsynth*'   # must be empty
