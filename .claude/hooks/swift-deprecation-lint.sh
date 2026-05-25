#!/bin/bash
# PostToolUse(Write|Edit) hook: flag deprecated/legacy Swift patterns for iOS 26.2.
# On a hit, exits 2 so findings are fed back to Claude to rewrite in the same turn
# (PostToolUse exit 2 surfaces stderr to the model). On no hit, exits 0 silently.
# Pure bash + grep (jq only to read the stdin payload, as the format hook does).
# Wired in .claude/settings.json alongside swift-format-lint.sh.

set -uo pipefail

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only existing Swift files.
case "$file" in
  *.swift) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

findings=""

flag() {
  local pattern="$1" label="$2" hits
  hits=$(grep -nE "$pattern" "$file" 2>/dev/null) || true
  if [ -n "$hits" ]; then
    findings="${findings}
[$label]
${hits}
"
  fi
}

flag ': ObservableObject|@StateObject|@ObservedObject' 'Legacy Observation -> @Observable / @State / @Bindable'
flag 'completion: @escaping|completionHandler:'        'Completion handler -> async/await'
flag 'SKProduct|SKPaymentQueue|SKPaymentTransaction'   'StoreKit 1 -> StoreKit 2 (Product, Transaction)'
flag 'DispatchQueue\.main\.async'                      'GCD main hop -> @MainActor / await MainActor.run'
flag 'NSNotificationCenter|\.addObserver\('            'Selector/KVO observer -> async sequences / @Observable'

# UIKit imported alongside SwiftUI in the same file.
if grep -qE '^import +UIKit' "$file" && grep -qE '^import +SwiftUI' "$file"; then
  findings="${findings}
[import UIKit in a SwiftUI file -> use SwiftUI unless explicitly required]
$(grep -nE '^import +UIKit' "$file")
"
fi

if [ -n "$findings" ]; then
  {
    echo "Deprecated/legacy patterns for iOS 26.2 in ${file}:"
    echo "$findings"
    echo "Query the cupertino MCP for the modern equivalent and rewrite before continuing."
    echo "(If a flagged use is a sanctioned exception per CLAUDE.md -- e.g. NSObject/CoreMIDI"
    echo " delegate interop -- keep it and note the reason.)"
  } >&2
  exit 2
fi

exit 0
