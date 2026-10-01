# Decision challenges: zot upload-ceiling probe (#7556)

Taste and User-Challenge items from plan review that were NOT auto-applied. Each is the operator's call;
the plan's current direction is the default.

## 1. Tracker closure on a tripwire-grade PASS (User-Challenge)

- **Operator direction:** the probe's exit 0 auto-closes #7556 and lets ADR-190 flip `adopting -> accepted`.
- **Reviewer challenge (CTO, simplicity):** the absence half has ~24% residual false-clean probability at 18
  pushes/week; consider decoupling tracker closure from the ADR status flip, or holding the PASS path.
- **Default kept:** exit contract unchanged. On today's data the next sweep PASSes and closes #7556.
- **Holding options for the operator:** leave PR #9353 in draft, or push the tracker directive `earliest=` date out
  before merging.

## 2. N3 signal from the heartbeat `zot_last_err` echo (Taste)

- Kieran suggested a third numerator: an echoed `zot_last_err` whose own `time:` is inside the window and which is
  `level:error` + `PatchBlobUpload` + `i/o timeout`. Heartbeats are not cap-limited. Not applied: adds a single-sample
  channel and one more reason for modest gain; n2 already covers the deadline signature.

## 3. Distinct-days floor (Taste)

- DHH noted 12 rows can be 2 pushes. Option: also require PATCH rows on >= 3 distinct days (observed 6 of 7).
  Not applied: adds a reason and a tuning number against one week of data; D2 rewords the floor as a row count instead.

## 4. Bounded-age exempt-lane drop guard (Taste)

- CTO: a single stale non-`rate_cap` drop blocks PASS for up to 7 days. Option: ignore drops older than the newest boot
  or add an escape knob. Not applied: fail-closed on unknown reasons is property P3; the trade-off is written in code.

## 5. Docs-only runbook correction inside this PR (Scope)

- CTO: `betterstack-log-query.md` wrongly implies the `PatchBlobUpload` error line is cap-exempt; fixing it needs no host
  replace. Not applied: the brief limits the PR to probe + tests; carried in the follow-up issue.

## 6. `latency-unparseable` as TRANSIENT vs `other5xx` (Taste)

- CTO would fold it into `other5xx`. Kept TRANSIENT: folding can hide a real cut behind an unparseable latency, and the
  contract says an unestablished state is never a pass.
