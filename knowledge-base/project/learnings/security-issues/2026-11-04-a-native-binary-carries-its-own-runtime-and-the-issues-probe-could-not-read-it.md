# Learning: a native CLI binary carries its own runtime, and the probe in the issue could not read the version

## Problem

#12026 asked for claude-code / agent-sdk to move to a pair whose embedded Bun is >= 1.4.4 (CVE-2026-111497, a Brotli decoder flaw), closing "only once `strings <bin> | grep -m1 '^Bun v'` reports Bun >= 1.4.4". Three things made a package-version bump a weaker answer than it looked:

- A package version says nothing about the runtime inside a Bun single-file executable. The vulnerable runtime lives in the binary, and the SDK and CLI packages shipped one byte-identical binary (sha256 `86dc1fcc...`).
- The issue's own probe cannot report a version: its first hit is the bare string-pool fragment `Bun v` (8 bare hits in 2.1.311), so it prints no version on the old binary and none on the new one. The probe that works is `grep -m1 -E '^Bun v[0-9]+\.[0-9]+\.[0-9]+'` (`Bun v1.4.4 (Linux x64)`).
- The new pair reshaped the vendored bwrap argv builder, so the pins that guard the sandbox moved with it. The bump was a re-proof of isolation, not a one-line version edit.

## Solution

- Pin the pair exactly (2.1.311 / 0.3.311), prove it in a scratch install before any committed pin moves, then land one atomic pin commit with the regenerated canary fixture.
- Add a standing guard (`claude-cli-pin-knows-models.test.ts`, helper in `test/helpers/vendored-bwrap-tail.ts`): both platform binaries must embed a `Bun v<x.y.z> (` banner >= the floor, taking the minimum over all banners, with a bare-fragment positive control and `BINARY_MISSING` instead of a skip under CI. Assert the floor directly in the real-binary row as well as through the helper, or deleting the helper call leaves a vulnerable binary green.
- Re-anchor the builder pins on content (a literal call sequence, a census of literal counts including the mount-table flags 3/9/15/2, bridge-wrapper anchors), never on line numbers or minified identifiers.
- Treat the closing evidence as post-merge: extract the shipped binaries from the released image and run the corrected probe on all three copies. The canary's `sdkVersion` is read from the committed fixture, so it proves the image carries the commit, not that the runtime is fixed.

## Key Insight

For any vendored native executable, ask which runtime it embeds and which instrument can read that runtime's version, then run that instrument against a known-positive and a known-negative before trusting it. A version pin, a lockfile row and a passing suite are all statements about the package.

## Session Errors

1. **A comment-only edit made after the last run of a test file dropped its `//` prefix** (committed in the pin commit; the file collected zero tests, so the new Bun-floor guard never ran; 11 of 13 review seats found it). Recovery: restored the prefix and re-ran (35 passed). **Prevention:** re-run (or at least `esbuild`-transform) every file you edit, including comment and docs-in-code edits, before committing; CI's `test` check also covers this.
2. **First fixture capture failed `creds_absent`** (Doppler `dev` has no Anthropic key). Recovery: CTO ruling F13, use config `ci` only, never `prd`. **Prevention:** the plan task now names `ci` (and tasks.md), after review found it still said `dev`.
3. **Capture projection refused the new `--tmpfs $HOME/.claude/seed-admin`** (`host_path token`). Recovery: a `${CANARY_SEED_ADMIN}` placeholder mirrored from the bridge-spawn handling. **Prevention:** none beyond the new fixture-driven row asserting every fixture placeholder has a replay root.
4. **My own fix rounds wrote new false sentences** ("24 sites" when it is 20; "random UUID and fixed label" fixed in two places and left in a third; a seed-admin comment that called transcripts HOME-only; a classifier caveat contradicting the paragraph below it). Recovery: caught by the fix-round and verification seats, fixed in the next commit. **Prevention:** already covered by the review skill's fix-commit rules; apply them to prose, grep a corrected claim's paraphrases across plan, tasks.md and ADRs in the same edit.
5. **Plan, tasks.md and ADR-079 carried the same claim in three places and each fix reached one or two.** Recovery: swept by claim. **Prevention:** same as 4.
6. **Hooks blocked `sleep`, `pgrep -f`, `git stash list`, and a `gh issue create` without a user-visible consequence line.** Recovery: workarounds, and `--label meta/machinery` for a CI-pin finding. **Prevention:** none needed, hooks working as designed.
7. **I miscounted returned review seats once ("12 of 13" when it was 11) and twice ended a turn naming an action not yet taken** (stop hook). Recovery: corrected the next turn; ended with a `Paused:` sentence. **Prevention:** hook-enforced; count from the report files, not from memory.
8. **A planning subagent stopped at the session interruption** leaving a skeleton. Recovery: resumed with `SendMessage`. **Prevention:** none, one-off.

## Tags

category: security-issues
module: apps/web-platform sandbox, claude-code / agent-sdk pin
