# /clean — Reclaim disk space from build artifacts and stale caches

Aggressively clean up storage consumed by Xcode, simulators, SPM, and Claude Code worktrees.
SurVibe builds can grow to 100GB/hour without cleanup — this command reclaims that space.

## When to use

- Disk space is low (`df -h /` shows <30GB free)
- After a long subagent-driven development session (multiple worktrees + builds)
- After switching branches that touch many packages
- Before a fresh release build (clean baseline)
- Weekly maintenance

## Steps

### 1. Show current usage (BEFORE)

```bash
echo "=== Disk before cleanup ==="
df -h / | tail -1
du -sh /private/tmp/SurVibe-DD /private/tmp/SurVibeDerivedData-* /private/tmp/survibe-* /private/tmp/svtest 2>/dev/null
du -sh ~/Library/Developer/Xcode/DerivedData 2>/dev/null
du -sh ~/Library/Developer/CoreSimulator 2>/dev/null
du -sh ~/Library/Caches/org.swift.swiftpm 2>/dev/null
```

### 2. Remove stale DerivedData in /tmp

```bash
# The shared path used by SurVibe slash commands — safe to nuke (will rebuild)
rm -rf /private/tmp/SurVibe-DD

# Any leftover ad-hoc derived data dirs from past subagent runs
rm -rf /private/tmp/SurVibeDerivedData-* /private/tmp/survibe-dd /private/tmp/svtest /private/tmp/SVAudio-dd

# Stale build / test logs
rm -f /private/tmp/log*.txt /private/tmp/*.log /private/tmp/*.patch /private/tmp/ipad-audio-log*.txt
```

### 3. Clean Xcode DerivedData (default location)

```bash
# Remove only SurVibe DerivedData entries — leaves other projects alone
rm -rf ~/Library/Developer/Xcode/DerivedData/SurVibe-*
```

### 4. Prune unavailable simulator runtimes

```bash
xcrun simctl delete unavailable
```

### 5. Clean up stale git worktrees

```bash
git -C /Users/maheshwar/Developer/pocsurvibe worktree list
git -C /Users/maheshwar/Developer/pocsurvibe worktree prune -v
```

If `worktree list` shows worktrees in `/private/tmp/` or under `.worktrees/` that you no longer need, remove explicitly:
```bash
git -C /Users/maheshwar/Developer/pocsurvibe worktree remove <path> --force
```

### 6. Optional — SPM cache (only if very low on disk)

The shared SPM cache speeds up subsequent builds. Only nuke if reclaiming space is critical:
```bash
# rm -rf ~/Library/Caches/org.swift.swiftpm   # commented out by default — uncomment if needed
```

### 7. Show usage AFTER

```bash
echo "=== Disk after cleanup ==="
df -h / | tail -1
```

## Output format

```
## Cleanup Report
| Source                         | Before  | After   | Reclaimed |
|--------------------------------|--------:|--------:|----------:|
| /private/tmp/SurVibe-DD        | X GB    | 0       | X GB      |
| /private/tmp/SurVibeDerivedData-* | X GB | 0       | X GB      |
| ~/Library/.../DerivedData/SurVibe-* | X GB | 0    | X GB      |
| Unavailable simulators         | X GB    | 0       | X GB      |
| Stale worktrees                | N       | 0       | -         |

Total reclaimed: X GB
Disk free: X GB → Y GB
```

## Notes

- **Never delete `~/Library/Developer/CoreSimulator/Devices/` directly** — use `xcrun simctl delete` so Xcode stays in sync.
- **SurVibe-DD is the canonical shared DerivedData path.** All slash commands write there. Deleting it forces one full rebuild but prevents fragmentation.
- **Subagent worktrees with isolation: "worktree"** are auto-cleaned if no changes were made; otherwise `git worktree prune` removes orphans.
