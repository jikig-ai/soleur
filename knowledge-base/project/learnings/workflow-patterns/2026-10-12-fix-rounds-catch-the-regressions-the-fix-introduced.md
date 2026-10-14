---
module: System
date: 2026-10-12
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "A fix-round hardening (`10#` octal normalization) was verified against the WRONG failure model: the seats and the commit assumed `$((08))` crashes under `set -e`; the actual failure is a silent clamp bypass (the arith-expansion error abandons the `&&`/`||` list AND the next line's clamp, stranding the literal `08` into `find -mmin`)"
  - "A literal-token anchor (`grep -qF '10#'`) matched its own prose mention in the file's comments — anchor laundering, the exact trap the suite's comment-strip step exists to defeat, and it survived a round because the second anchor loop greps raw text"
  - "A fix commit's own P1 report turned out to be a sibling seat's in-place mutation-testing on the live worktree — the phantom regression cost a verification cycle"
root_cause: missing_validation
resolution_type: workflow_improvement
severity: medium
status: resolved
tags: [review, fix-round, mutation-testing, anchor-laundering, find, reap, octal]
issue: '#6760'
---

# Fix rounds earn their cost by catching the regressions the FIX introduced — three from one reap sweep (#6760/PR #10158)

## Problem

PR #10158 added a scratch-orphan sweep to `run-scan.sh` — a `find ... -exec rm -rf` with exclusions, canonicalization, a numeric knob, and a floor clamp. The main panel and two fix rounds produced ~30 raw findings; the instructive part is that the highest-severity findings in each round were defects **introduced by the previous round's fixes**, invisible to the round before:

1. **Round 1's hardening introduced the round-2 defect class.** `! -path` → `! -samefile` (closes string-equality exclusion defeat), `cd -P` canonicalization (closes symlinked-TMPDIR no-op), a numeric-validation guard — all correct individually, but together they added a *new* `set -e` abort (`cd` failure in `$(...)` assignment), an octal trap (`^[0-9]+$` admits `08`, which bash arithmetic reads as octal), and an inert `-mount` (find never descends at `-maxdepth 1`; `rm -rf` crosses mounts regardless).
2. **The verified mechanism was wrong twice over.** Seats assumed `$((08))` would `crash under set -e` — probed false: an arithmetic-expansion error abandons the `&&`/`||` list (the `||` fallback never runs) and is non-fatal, so the literal `08` strands into `find -mmin "+08"` and **silently bypasses the 60-min clamp**. The committed comment had to be corrected to the real mechanism — "strands the literal" not "crashes".
3. **A `10#` anchor laundered itself.** `grep -qF '10#'` matched the comment that documents `10#`. Pinning code-spellings (`10#${_reap_min}`) is the fix; so is comment-stripping before every source anchor, uniformly — the suite already did it for one anchor loop and not the other.

## Environment

- `run-scan.sh` reap block under `set -euo pipefail`, GNU findutils 4.11, bash 5.3
- `meta-dir-reap.test.sh` grew 7 → 40 arms across the panel + two fix rounds

## Root cause

Fix commits are written under the model that produced the defect being fixed — the same blind spots apply, and a guard-shaped diff has the property that **its protections are vacuous until mutation-tested**. Two rounds each caught what the previous round could not see; the cap-2-then-escalate rule (ADR-267) is calibrated right.

## Solution / What shipped

- `-samefile` own-scratch exclusions gated by `[ -e ]` (a dead operand errors the whole find into a silent no-op); exclusion list built as an array expanded via `${_excl[@]+"${_excl[@]}"}` (bash 3.2-safe under `set -u`)
- `cd -P ... && pwd -P || true` canonicalization for BOTH reap roots — a symlinked `meta_base` silently no-oped the shipped #6789 reap as well
- `^[0-9]{1,9}$` + `10#` + a single clamped `_reap_min` feeding both sweeps (`-mmin "+0"` matches any past mtime — verified — so a floor <60 reaps a concurrent peer's live scratch AND meta dir)
- `-mount` dropped and the residual named honestly (rm's own recursion crosses mounts; the flag is a no-op at depth 1)
- stderr warn replaces `|| true` on both finds (rm-race stderr still suppressed)
- Test-side: sealed TMPDIR for every invocation (a floor-0 arm was sweeping the host's real /tmp), discriminating fixtures (30-min entry between the stranded octal floor and the clamp; backdated glob-metachar positional INPUT + reaped sibling control in the same invocation), anchor laundering closed, hook-side producer pin

## Prevention

- **Mutation-test fix commits' protections, not just their behavior.** The discriminating pins that caught the survivors: a fixture sitting *between* the wrong and right floors; a sibling-control reaped in the same invocation (proves the sweep ran); glob-metachar filenames (defeats the mechanism being pinned if it's the wrong mechanism).
- **Probe the failure model, never assume it.** "Crash under set -e" vs "silent bypass" is the difference between P3-comment and P2-guard-defeated; both rounds' empirical probes (`bash -c`, `find` in a scratch dir) were what settled it. `mktemp -d` + real `find`/`touch` beats reasoning about GNU/BSD semantics from memory — seats disagreed on `-mmin +0` semantics and the empirical one won.
- **Comment-strip before EVERY source anchor.** If the anchor is a literal token, grep the comment-stripped stream or pin a spelling that cannot appear in prose (`10#${_reap_min}`, not `10#`).
- **Seats must never mutation-test the live worktree.** A seat's in-place `sed`+restore on `run-scan.sh` produced a phantom P1 ("uncommitted regression, mtime during session") in a sibling seat's report — two seats, one real edit. Mutant work belongs in a scratch copy; the lead should note `git status --porcelain` cleanliness in every fix-round brief.

## Session Errors

- `test-all.sh --affected` queued behind sibling worktrees' full-gate runs (known #9505 capacity trap) — terminated and ran targeted suites. **Prevention:** read the runner's `--capacity` verdict before queueing; targeted suites carry the evidence.
- Two review seats ran `git diff ...HEAD` in the bare root, not the worktree — one reported a stale HEAD, one nearly reviewed an empty diff. **Prevention:** fix-round briefs now open with `cd <worktree> && pwd` verification; a bare-root `git rev-parse --show-toplevel` assertion belongs in the seat preamble too.
- A seat's in-place mutation produced a phantom P1 in a sibling's report (see Prevention above). **Prevention:** scratch-copy mutation only; `git status` cleanliness check per brief.
- Planning subagent reported no Task-spawn capability in the Devin context → research/panel stages ran inline and the plan recorded it; the technical-ruling gate then (correctly) rejected five `pending - assumed` rows until a batched CTO spawn resolved them. **Prevention:** decision-challenges rows should be ruled or flagged at authoring time, not left for the gate.
- `edit` old_string mismatches after earlier `sed -i` passes on the same file. **Prevention:** after any scripted edit, re-read the region before the next manual edit rather than trusting the remembered text.
- A fixture ratchet (`lint-fixture` checks) and `lint-shell-capture-exit` needed manual per-file invocation — both green but easy to forget; they are now in this branch's verification list. **Prevention:** run the full lint set on every touched shell file, not just the suite that owns it.

## Related

- `knowledge-base/project/learnings/2026-10-05-the-advice-i-added-to-the-abort-message-satisfied-the-assertions-written-against-it.md` (affected-shard capacity contention)
- `knowledge-base/project/learnings/workflow-patterns/2026-10-09-an-rc0-verdict-is-not-proof-the-suite-ran-vacuous-green.md`
- ADR-267 (fix-commit targeted rounds); #9448 / #9474 fix-round lessons
- Filed: #10167 (parse-override block-mapping gap, different subsystem)
