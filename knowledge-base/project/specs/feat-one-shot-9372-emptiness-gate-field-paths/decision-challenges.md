# Decision challenges - feat-one-shot-9372-emptiness-gate-field-paths

Appended by plan on 2026-10-06 (headless pipeline: not asked, persisted for the ship phase to render in the PR body and file as an
`action-required` issue). The default taken is named for each; none of them is decided by this PR.

## User-Challenge

1. **The 1 GiB used-bytes ceiling is about 60 times the measured empty baseline (about 16 MB), and the brief says keep every threshold.**
   - *Stated direction:* "keep every threshold (160 of 168 hours, 1800 s newest age, min above zero, max at most 1 GiB, spread at most 64 MiB, total between 15e9 and 21.5e9, the W2R_DETACHED arm)".
   - *Signal:* the architecture and flow reviewers both flagged that a flat 100 to 900 MB of old user data written more than 7 days ago passes the ceiling and the 64 MiB spread, and this PR is what makes PASS reachable for the first time (single-user-incident threshold, irreversible delete).
   - *Default taken:* all thresholds unchanged (AC2 by diff); the measured baseline goes in the PR body so the owner can justify or tighten.
   - *Re-evaluate:* before the real (non-plan-only) dispatch, decide whether to tighten the ceiling to roughly 64 to 128 MiB in a separate reviewed change.

## Taste

2. **Approval precedes evidence.** `environment: web-platform-infra-apply` is a job-level gate, so an apply dispatch's PASS flows into `delete-volume` in the same approved job with no human reading the min/max first; only a plan-only run (also gated, writes nothing) shows the numbers. Default taken: the header, runbook and Observability wording are corrected; no workflow change. Owner decides whether the apply run needs a second gate after the evidence step.
3. **`heal:detach_done` premise is not enforced** (any ext4, pinned, server-less volume qualifies, and after about 6 days detached the 7-day coverage turns RED permanently) and **evidence-to-delete time** (preplan and checks run between the read and the delete with no re-check). Pre-existing design from #9532; out of scope; default taken: untouched and listed in Sharp Edges for a follow-up.
4. **Panel splits on test size.** Two reviewers (DHH, code-simplicity) and the CTO asked for a smaller test than the first draft; the plan adopted a strict path-and-value check without an aggregating evaluator. The `vector.toml` shape-drift canary was CUT (speculative cross-file coupling, detects one literal, deletable by the PR it should stop); the CTO and one reviewer would have kept it as a warning-grade check. Default taken: cut; the header carries the coupling note.
5. **Reason-string split.** RED `used_bytes_absent_or_host_dark` now also means "changed row shape" or "multi-device group". A distinct reason (for example `multiple_devices`) needs a verdict-function change, which conflicts with "keep the thresholds and semantics"; default taken: header note only.
