#!/bin/bash
# PostToolUse(Write|Edit) hook: auto-format (swift-format) + lint (swiftlint)
# Swift files right after Claude edits them. Wired in .claude/settings.json.
# Always exits 0 so a tooling hiccup never blocks the edit.

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

case "$file" in
  *.swift) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

# Format in place, using the project's .swift-format config when present
fmt_config="${CLAUDE_PROJECT_DIR:-.}/.swift-format"
if [ -f "$fmt_config" ]; then
  xcrun swift-format format --in-place --configuration "$fmt_config" "$file" 2>/dev/null
else
  xcrun swift-format format --in-place "$file" 2>/dev/null
fi

# Lint (report only, surfaced to Claude via stderr)
if command -v swiftlint >/dev/null 2>&1; then
  lint_config="${CLAUDE_PROJECT_DIR:-.}/.swiftlint.yml"
  if [ -f "$lint_config" ]; then
    swiftlint lint --quiet --config "$lint_config" "$file" 2>&1 | head -20 >&2
  else
    swiftlint lint --quiet "$file" 2>&1 | head -20 >&2
  fi
fi

exit 0
