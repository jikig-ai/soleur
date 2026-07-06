# Learning: a body-hashing guardrail gate has a family of fail-open classes hermetic tests pass over

category: security-issues
module: harness / scripts/lint-rule-bodies.py (ADR-092, #6103)
date: 2026-07-06

## Problem

PR #6101 shipped a "hard-rule body-weakening gate" (`scripts/lint-rule-bodies.py`): it
sha256-hashes every `hr-*`/`wg-*` rule BODY line in `AGENTS.{core,docs,rest}.md`, diffs
each vs the merge-base, and BLOCKS an un-acked change/deletion. The whole point is to
stop a *silently* weakened compliance guardrail (the reward-hackable-classifier lexer
was deliberately deferred to #6038 in favor of "human ack on every body change").

15 hermetic git-fixture tests + a live calibration + semgrep p/python were all GREEN.
Multi-agent review (security-sentinel + user-impact-reviewer, each reproducing end-to-end)
found **three catastrophic false-negatives** the tests passed straight over — plus
architecture-strategist found a CI-only merge-wedge that the local run masked.

## Root cause — the fail-open family

A gate that certifies "the protected artifact did not weaken" by hashing it has a
recurring set of masking/oracle holes. Each one lets `--check` exit 0 while the guardrail
is actually weakened:

1. **Mutable-oracle narrowing.** The gate decided which lines were "rule bodies" by
   importing `SECTIONS` (heading allowlist) from `scripts/_agents_md_sections.py` — a
   file the same PR can edit — and applied it to BOTH base and head parsing. Remove
   `"Hard Rules"` from `SECTIONS` AND weaken an `hr-*` body in one diff → the body is
   invisible to the *base* parse too → never enters the change set → GREEN. **Fix:**
   parse both sides with the UNION of base-side and head-side oracle (read the oracle
   from the tree under check, not the gate's install location), and pin the oracle file
   as gate-control (CODEOWNERS + recursion ∉ list).

2. **Cross-file duplicate-key last-wins.** The gate unioned the 3 sidecars with
   `dict.update()` in fixed order. Weaken the real body in `core`, add a same-id decoy
   with the strong text in `rest` → last-file-wins hashes the decoy → base==head → GREEN,
   while the runtime loads the weakened `core` body. **Fix:** a gated id appearing in >1
   sidecar is a structural anomaly → **fail-closed**, never silently resolve.

3. **Append-only-ack replay.** The WORM ack file unioned *all historical* hashes for an
   id, so any body form ever acked stayed valid forever. Revert a body to a
   previously-acked (weak) form → its hash is still in the ack set → GREEN, no new ack.
   **Fix:** the ack must be NEWLY added in this diff (`head_acks − base_acks` via
   `git show <base>:<ackfile>`), so a pre-existing historical ack cannot satisfy a new
   (reverting) weakening.

4. **All-members additive false-block (the inverse — a fail-CLOSED-too-hard bug).** The
   manifest-integrity check required every head rule to be in the committed manifest, so
   a rule ADDED by a sibling PR (absent from this branch's baseline manifest) would
   false-block the *next* unrelated PR. **Fix:** scope integrity to `head ∩ manifest`
   (change detection is git-based, not manifest-based, so an incomplete manifest never
   weakens the gate); sibling *modifications* rely on `strict_required_status_checks_policy`
   forcing rebase-before-merge.

5. **CI-only test-collection wedge masked by local Doppler.** The recursion test imported
   `TARGET_ALLOW_RE` from a module that transitively loads `server/inngest/client.ts`,
   which throws `INNGEST_SIGNING_KEY missing at startup` at module-eval. Locally I ran it
   under `doppler run` (which injects the key) → 4/4 PASS. CI's `test-webplat` sets no
   `INNGEST_*` → the file errors at *collection* → the required `test` context reds → the
   AC8 invariant is vacuous AND the PR can't merge. **Fix:** the sibling guard
   `vi.hoisted(() => { process.env.NEXT_PHASE = "phase-production-build"; })` BEFORE the
   import (mirrors `cron-compound-promote.test.ts`).

## Key insight

For a gate whose contract is "artifact X did not weaken," **hermetic happy/RED fixtures
that exercise the honest path do not exercise the oracle, the union order, or the
append-only ledger's replay surface** — the three seams where a same-diff adversary
hides a weakening. Adversarial multi-agent review (security-sentinel + user-impact,
prompted to enumerate fail-open inputs and reproduce each to exit 0) is what finds them.
When authoring ANY certify-no-weakening gate, pre-enumerate: (a) is the classifier/oracle
mutable in the same diff it gates? (b) does a duplicate key across the scanned set
silently pick one? (c) can an append-only allowlist entry from history satisfy a *new*
violation? (d) does the "all members present" check false-block on a benign addition?

And: **a webplat test that imports any `server/inngest/*` module needs the
`vi.hoisted NEXT_PHASE` guard; verify it CI-equivalent (without `doppler run`) — a local
Doppler run masks the collection failure.** (Extends the known
`vitest-unstub-does-not-clear-process-inherited-env-vars` / webplat-doppler-false-positive
class.)

## Session Errors

- **`git stash create` in a compound Bash command** — the `hr-never-git-stash-in-worktrees`
  hook denies even `git stash create`, and it took down the preceding `cat`/`--write` in
  the same `&&` chain. Recovery: re-ran without the stash line. Prevention: never put a
  `git stash*` form in a multi-command Bash call; the hook already enforces this (one-off).
- **Recursion test green locally, would red in CI** — see root cause #5. Recovery:
  added the `vi.hoisted NEXT_PHASE` guard; re-ran WITHOUT doppler to confirm. Prevention:
  run new inngest-importing webplat tests CI-equivalent (no doppler) before trusting green.
- **`semgrep --config=p/bash` exit 7** — the `p/bash` registry pack was unavailable.
  Recovery: dropped it, ran `p/python` (the substantive gate source), clean. Prevention:
  for bash-heavy diffs the review skill already prescribes `shellcheck` over semgrep-bash
  (one-off).
- **Three gate fail-opens + one over-strict block** — see root cause #1–4; all found by
  review (or self-analysis for #4) and fixed inline before merge. Prevention: the
  pre-enumeration checklist above, applied at gate-authoring time.

## Tags
category: security-issues
module: harness, lint-rule-bodies, inngest-test-env
related: ADR-092, #6103, #6038
