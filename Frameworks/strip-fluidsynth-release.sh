#!/bin/bash
# Strip FluidSynth.framework from Release builds (Phase 1 POC, DEBUG-only feature).
# This script must be wired as a Run Script build phase on the SurVibe app target,
# placed AFTER "Embed Frameworks" and configured to "Run script only when installing"
# = NO, with the phase activity gated by CONFIGURATION.
set -euo pipefail
if [ "${CONFIGURATION}" = "Release" ]; then
    TARGET="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/FluidSynth.framework"
    if [ -d "$TARGET" ]; then
        echo "Removing FluidSynth.framework from Release build at: $TARGET"
        rm -rf "$TARGET"
    fi
fi
