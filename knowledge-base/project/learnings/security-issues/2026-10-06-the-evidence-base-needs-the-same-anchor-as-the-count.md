---
title: "The evidence base needs the same anchor as the count — a triplicated predicate is the drift vector, and freshness must key on producer-attributable rows"
date: 2026-10-06
category: security-issues
tags: [followthroughs, guard-shape, awk, anchors, freshness, review-panel]
issue: 8278
pr: 9607
related:
  - scripts/followthroughs/zot-log-channel-7440.sh
  - scripts/followthroughs/registry-luks-live-8386.sh
  - scripts/followthroughs/zot-last-err-redact-7500.sh
  - knowledge-base/engineering/architecture/decisions/ADR-184-registry-host-container-log-shipper.md
---

# The evidence base needs the same anchor as the count

## Problem

Rewriting `zot-log-channel-7440.sh` (#8278) to one boot-scoped awk pass, I classified
control rows THREE times — once in the main rule for counting (where I required the
offset-0 `index(m, ctlm) == 1` envelope anchor), and again in each of the two
boundary-derivation loops (where I did not). The `--grep SOLEUR_ZOT_DISK` query is a
substring LIKE: a row merely *mentioning* the marker — a quoted row, a webhook echo, an
injected request header — lands in the channel. Five review seats independently found
the asymmetry and demonstrated both harm directions empirically: a forged mid-line
mention on the newest dt selected `NEWEST_BOOT`, demoting a real in-span credential leak
from exit 1 to exit 3; a mention on an early dt dragged `B0` back, promoting a
dead-generation row into a public FAIL. The predicate was load-bearing in three places
and true in one.

The same review round found the twin class on a gate I had just added: a
`producer_silent` freshness check keyed `ndt` on the newest row of the ENTIRE result
set — including the noise class — so one fresh marker-quoting row kept the gate
permanently open on a dead producer, masking the exact false-PASS it existed to refuse.
The sibling (`registry-luks-live-8386.sh`) scoped its freshness to producer-verified
rows; my port kept the gate and dropped the scoping.

## Solution

**Classify once, read everywhere.** Compute each row's classification in the main awk
rule (`Rcls[]`/`Risctl[]`/`Rhost[]`/`Rboot[]`) and let every END-phase traversal —
boot selection, boundary derivation, counting, freshness — consume the precomputed
answer. A triplicated predicate is a drift vector: the second copy is written
differently and nobody notices because each site looks locally correct. The fix was not
"add the missing anchor in two places"; it was deleting the second and third
classifications.

**Scope every evidence source to what it is evidence OF.** Selection keys on
anchor+host+boot; the boundary on anchor+host+boot+dt; counts on anchor+host; and
freshness on a producer-attributable `pdt` (envelope / host-scoped stamped / same-boot
dropped rows only). The rule: if a row class cannot *qualify* as producer evidence, it
must not be able to *defeat* a gate either — exclusion and refresh are two different
privileges.

**Per-occurrence, never per-message, for negated shapes.** `authleak`'s "an
Authorization value that is not masked" must walk EVERY `Authorization:[…` occurrence
and cut each value at `]` (headers pack comma-separated inside one non-space
`headers:{…}` blob, so a space-bounded read eats `],X-Fwd:[Authorization:` whole and a
decoy mask cancels a real credential on the same row). Same for `shapeleak`: a leading
`dp.st.x` decoy must not end the scan.

**Bash arithmetic on an env seam needs `10#`.** `ZOT_LOG_7440_NOW=09` passed
`^[0-9]+$` then read as octal and aborted under `set -u` at rc 1 — the probe's
reserved FAIL code. `10#$VAR` pins base-10.

## Key Insight

Every consumer of a classification trusts it as though the strictest version applied
everywhere. If a guard's counting path requires an envelope anchor, its selection and
boundary paths need it MORE — they choose the evidence base everything else grades
over. And a freshness/silence gate is only as strong as its scope: keying it on the
result set rather than the producer makes it a gate that noise can hold open.

## Prevention

- For guard-shaped shell/awk code: write the classification ONCE (arrays indexed by
  row), enumerate every phase that consumes it, and review the consumers for
  predicate drift — the structural-enumeration seat's map is the right instrument.
- Fixture the forgery BOTH ways: the non-anchor row that must not select, and the
  non-anchor row that must not bound (S11/S11b in the probe suite).
- A freshness gate's fixture set needs the masking case, not just the stale case
  (S12b: a fresh non-producer row must not pass a dead producer).
- `10#$VAR` in every bash arithmetic read of an env-provided numeric.
- No apostrophes inside single-quoted awk programs — `bash -n` will catch it, but it
  costs a red suite run every time; write comments without `'` instead.

## Session Errors

1. `envelope_row()` hit `$1: unbound variable` under `set -u` (helper default).
   **Prevention:** default every positional (`${1:-$DT0}`) in fixture helpers.
2. Three apostrophes in awk comments broke `bash -n` mid-suite.
   **Prevention:** no `'` inside single-quoted awk; run `bash -n` immediately after
   any awk-comment edit rather than after the suite.
3. A message-format change split the adjacent `envelope=N control=N` token pair an
   assertion greps.
   **Prevention:** grep the suite for the token pair before reordering print fields.
4. `row()`/`control_row()` `${2:-$DT0}` defaults swallowed an explicit empty-dt arg.
   **Prevention:** fixture rows needing a literal empty/malformed field use raw `jq`
   calls, documented inline.
5. Two edit-paste truncations left orphaned `elif`/`else` fragments (caught by
   `bash -n` + read-back).
   **Prevention:** when an `if/elif/else` is being restructured, read the whole
   block after editing — syntax-valid orphans still parse.
6. `gh pr create --arg` is not a flag (the anchor probe needed inline paths).
   **Prevention:** one-off; no rule needed.

## Verification

- `bash tests/scripts/test-zot-log-channel-probe.sh` → `=== 114 passed, 0 failed ===`
  (S11 anchor select+drag, S12/S12b freshness+masking, S13 decoy coexistence,
  S14/S14b dot padding + decoy-first, S15/S15b/S15c empty-dt boundary).
- `bash -n` + `shellcheck` clean; `lint-shell-trace-credential-refusal.py` clean.
- Fix-round seat verification: every prior finding confirmed FIXED on the delta.
