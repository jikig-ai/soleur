# An inert-until-dispatched cutover/migration body's verify + gate steps are false-green vectors that only adversarial review catches

**Date:** 2026-07-17
**Issue:** #6604 (PR 2 of #6588 — the /workspaces LUKS cutover)
**Category:** best-practices / review

## Problem

The #6604 cutover ships a large orchestration script (`workspaces-cutover.sh`) that runs ONLY
post-merge, on an operator dispatch, against live sole-copy user data. It has no in-PR execution —
`tsc`, `shellcheck`, and every registered test suite pass on it while its runtime behavior is
entirely unexercised. The whole point of the plan's C1 correction was that the itemized rsync verify
is "the false-green fix." Yet the first implementation reintroduced **five** false-greens into that
very verify path, and a green CI + green `bash -n` said nothing:

1. `sync; echo 3 > drop_caches` ran BEFORE the mutating pass-2 rsync, so the `--checksum` verify read
   the page cache the pass-2 had just refilled — never the dm-crypt round-trip (the exact thing C1
   exists to test).
2. `DIFF_N="$(rsync … --dry-run … | grep -c . || true)"` — a verify-rsync that ERRORS emits no
   stdout, so `grep -c .` returns 0 and `|| true` swallows the pipe failure → a failed verify reads
   as "0 differences."
3. `git fsck --full … || true` — a corrupt object that round-tripped onto the LUKS device did not
   abort; the gate was decorative.
4. A failed `drop_caches` was swallowed by `2>/dev/null || true`, silently re-enabling the cache read.
5. The off-host `luksHeaderBackup` upload was `|| log WARN` then the local copy was shredded — the
   cutover could complete with no header escrow anywhere (the F4 unreadable-forever limb).

Separately, the destroy-guard's four named backstops (`old_volume_touched` etc.) were **mutation-dead**
(deleting each left the 16-fixture suite green, because `out_of_scope`/`resource_deletes` always
co-fired), and the drift **Sentry alert never paged** (`event_frequency value=1` on a cold group needs
≥2 events; a single daily drift is count=1, strict `>`). None of these are catchable by a test on an
un-runnable script — they were caught by 7 parallel review agents.

## Solution

- Move `drop_caches` to AFTER the last write, immediately before the verify, and make it `|| die`.
- Capture the verify-rsync exit EXPLICITLY (`rsync … > "$vlog"; rc; then count`), never `| grep -c . || true`.
- Every verify/gate step aborts (`|| die`) on failure — a `|| true` on a data-integrity gate is a
  false-green by construction. `git fsck` collects failures and dies; the byte-match requires
  non-empty numeric operands; the header upload is blocking + read-back (`head-object`) before shred.
- Sentry cold-group alerts use `event_frequency value=0` ("page on the first event"), not `value=1`
  (which only works for always-hot shared groups like `web_terminal_boot_fatal`).

## Key Insight

**When a PR ships code that cannot execute in-PR (a cutover body, a migration run only post-merge, a
freeze orchestration, a wipe dispatch), the deterministic gates (tsc/shellcheck/unit tests) verify
its SHAPE, never its RUNTIME BEHAVIOR — so multi-agent adversarial review is not optional polish, it
is the only pass that reads the script as an executing program.** Spawn the review with prompts that
name the runtime failure modes explicitly (the false-green class per verify step, the cold-vs-hot
alert-group distinction, the mutation-dead-clause class) so the agents reach them; a generic "review
this" echoes the plan's own framing back. On this PR the review found a RED parity gate, a dead page,
and three converging verify false-greens — every one a silent-data-loss or blind-detection defect that
green CI would have shipped.

Corollary: on any inert script, treat every `|| true` on a step whose exit is the gate's verdict as
guilty until proven a genuine best-effort no-op. `grep -c`/`wc -l` over a piped command masks the
command's own failure — capture the exit separately.

## Session Errors

- **A `fork` subagent delegated to author Phase 2 misfired — it inherited the parent's "I'll delegate
  and wait" orchestration reasoning and authored nothing (4 tool calls, echoed a progress summary).**
  Recovery: verified the worktree was untouched, authored Phase 2 myself. **Prevention:** do not
  delegate *authoring* to a `fork` when the inherited context contains the parent's own
  delegate-and-wait framing — a fork over-identifies with the parent and mirrors its "hold off"
  stance. Use a fresh `general-purpose` agent with a fully self-contained spec, or author directly.
- **First scratchpad write failed (`No such file or directory`) — the session scratchpad dir did not
  exist yet.** Recovery: `mkdir -p`. **Prevention:** `mkdir -p` the scratchpad dir before the first
  write (one-off/environment).
- **cloud-init user-data size budget tripped (+504 B, then +264 B) after adding the mount-pin + DSN
  env file.** Recovery: trimmed comments, then a documented modest re-baseline 21,900→22,200 with the
  KB-scale tripwire intact. **Prevention:** none needed — the budget's own comment doctrine
  anticipates irreducibly-inline additions; this is the sanctioned path (one-off).
- **AC14 sweep grep matched my own explanatory comment's `scsi-0HC_Volume_*` literal.** Recovery:
  reworded the comment to drop the literal. **Prevention:** already the documented
  grep-false-match-own-comment class — anchor assertions on syntax, and keep the forbidden literal out
  of comments in the swept file (recurring, already-covered).

## Recurring-vs-one-off triage

| item | recurring? | disposition |
|---|---|---|
| Inert-script verify false-greens only review catches | recurring | fix-now-inline (done) + this learning; route to one-shot/review |
| fork over-identifies with parent's wait-reasoning | recurring | route to one-shot Sharp Edges |
| scratchpad dir absent on first write | one-off | note only |
| cloud-init size re-baseline | one-off | note only (doctrine anticipates) |
| grep false-match own comment | recurring | already covered (cq-assert-anchor-not-bare-token) |

## Tags
category: best-practices
module: infra / review / one-shot
