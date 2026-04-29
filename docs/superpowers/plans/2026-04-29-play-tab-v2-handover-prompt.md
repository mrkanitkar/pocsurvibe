# New-session handover prompt — Play Tab v2 parallel execution

> Paste the block below into a fresh Claude Code session, in this worktree.

---

We are executing **Play Tab v2 (Riyaz Recorder)** in parallel using the worktree-isolation pattern. The brainstorming, spec, and plan are all complete and committed on the current branch. Your job is to orchestrate parallel subagent execution wave by wave, merge each agent's branch back into this worktree's trunk, run verification gates between waves, and stop the moment a gate fails so I can intervene.

## Read these in order before you do anything else

1. **Spec** — `docs/superpowers/specs/2026-04-29-play-tab-v2-design.md` (commit `7e23d3a`)
2. **Base plan (sequential, 16 TDD tasks with full code samples)** — `docs/superpowers/plans/2026-04-29-play-tab-v2.md` (commit `84df16f` plus a follow-up correction commit)
3. **Parallel-execution wave plan (you orchestrate from this)** — `docs/superpowers/plans/2026-04-29-play-tab-v2-parallel-execution.md`

These three docs are self-contained. Project rules in `CLAUDE.md`, `.claude/rules/audio.md`, and `.claude/rules/app-target.md` are also load-bearing.

## Hard constraints

- **Latency invariant**: existing PlayTab v1 has sub-frame MIDI→highlight latency. Task T6 is the only task that touches that wiring; it MUST run as a single sequential agent and verify the latency smoke test (base-plan Task 6 Step 9) before merging. Do not parallelise inside T6.
- **No customers yet**: no schema migration, no file-format back-compat. Greenfield is fine.
- **Keyboard input only**: Play tab records iPad on-screen + external MIDI. No mic. (`memory/play_tab_keyboard_only.md`.)
- **Simplified UI default**: save / takes / export hidden behind progressive disclosure. (`memory/play_tab_simple_ui.md`.)
- **Multi-channel only**: all audio routes through `ProductionMultiChannelEngine`. Slot 0 = touch input. Slot 2 = take playback. Don't spawn ad-hoc samplers.
- **Use Opus 4.7 for subagents** doing real work. (`memory/feedback_subagent_models.md`.)

## Execution protocol

For each wave defined in the parallel-execution doc:

1. **Dispatch all wave tasks in a single message** with multiple `Agent` tool uses, each with `isolation: "worktree"` and `model: "opus"`. Use the per-task prompt template from the parallel-execution doc §"Task prompts (for parallel dispatch)" — the common preamble + the per-task addition. Pass `subagent_type: "general-purpose"`.
2. **Wait for all agents to return.** Each returns a worktree path + branch name + final commit SHA.
3. **Merge in the order specified** for that wave (parallel-execution doc §"File-conflict map / merge order"). For each branch:
   ```bash
   git fetch <agent-worktree-path>
   git merge --no-ff <agent-branch> -m "merge: Tn — <short>"
   ```
4. **Run the wave-end verification gate** (parallel-execution doc §"Verification gates"):
   - `xcodebuild -scheme SurVibe -destination "platform=iOS Simulator,name=iPad Pro 13-inch" build`
   - `xcodebuild test`
   - `swift test` for SVCore and SVAudio packages
   - `/opt/homebrew/bin/swiftlint lint --quiet --config .swiftlint.yml`
   - For Wave 2 only: also run the manual latency smoke test on the iPad simulator using `mcp__XcodeBuildMCP__*` tools if available (boot sim, install build, launch app, screenshot) and report whether the highlight feels parity with v1.
5. **If any gate fails:**
   - Roll back the offending merge (`git reset --hard HEAD~1`).
   - Dispatch ONE fix subagent with the failure log + the original task.
   - Re-run the gate.
   - If it fails twice, stop and report to me — don't loop.
6. **Commit a wave-summary commit** after the gate passes:
   ```bash
   git commit --allow-empty -m "wave: WaveN — <names>; tests + lint clean"
   ```
7. Move to the next wave.

## Worktree dispatch hint

When you call `Agent(...)`, set:
- `isolation: "worktree"` — runtime creates a fresh worktree off the current branch.
- `model: "opus"` — these tasks are non-trivial.
- `subagent_type: "general-purpose"`.
- The prompt body is **self-contained** (see parallel-execution doc). The dispatched agent has zero context from this conversation; it reads the base plan + spec + the named files itself.

## Status at handover

Current branch: `claude/peaceful-hawking-e79eda`
Working dir: this worktree
Spec + base plan + parallel doc all committed.

The trunk is clean. Wave 0 has not started. The next concrete action is to dispatch Wave 0's four agents (T1, T2, T11, T12) in a single message.

## When to stop and ask me

- A wave-end gate fails twice in a row.
- Any task touches a file outside its declared lane and creates a conflict you can't auto-resolve in 1 attempt.
- The latency smoke test after Wave 2 / T6 looks worse than v1.
- iPad sidebar visibly flashes during the tab-change rollback (spec §9-2 fallback condition triggered) — pause and check whether to fall back to a no-veto Save/Discard toast.

## When to keep going without asking

- Per-task tests pass; per-wave gate passes; merges clean; lint clean. Just keep moving.

Once you've read the three docs and understood the wave structure, post a one-paragraph readiness check (what's in Wave 0, your dispatch plan, any concerns) and wait for my "go".

---
