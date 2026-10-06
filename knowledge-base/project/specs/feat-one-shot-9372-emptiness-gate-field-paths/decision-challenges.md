# Decision challenges - feat-one-shot-9372-emptiness-gate-field-paths

Appended by plan on 2026-10-06 (headless pipeline: not asked, persisted for the ship phase to render in the PR body and file as an
`action-required` issue). The default taken is named for each; none of them is decided by this PR.

## User-Challenge

1. **The 1 GiB used-bytes ceiling is about 65 to 70 times the observed level (about 16 MB; the volume's own reading, not an independent empty reference), and the brief says keep every threshold.**
   - *Stated direction:* "keep every threshold (160 of 168 hours, 1800 s newest age, min above zero, max at most 1 GiB, spread at most 64 MiB, total between 15e9 and 21.5e9, the W2R_DETACHED arm)".
   - *Signal:* the architecture and flow reviewers both flagged that a flat 100 to 900 MB of old user data written more than 7 days ago passes the ceiling and the 64 MiB spread, and this PR is what makes PASS reachable for the first time (single-user-incident threshold, irreversible delete).
   - *Default taken:* all thresholds unchanged (AC2 by diff); the observed level goes in the PR body so the owner can justify or tighten.
   - *Re-evaluate:* before the real (non-plan-only) dispatch, decide whether to tighten the ceiling to roughly 64 to 128 MiB in a separate reviewed change.

## Taste

2. **Approval precedes evidence.** `environment: web-platform-infra-apply` is a job-level gate, so an apply dispatch's PASS flows into `delete-volume` in the same approved job with no human reading the min/max first; only a plan-only run (also gated, writes nothing) shows the numbers. Default taken: the header, runbook and Observability wording are corrected; no workflow change. Owner decides whether the apply run needs a second gate after the evidence step.
3. **`heal:detach_done` premise is not enforced** (any ext4, pinned, server-less volume qualifies, and after about 6 days detached the 7-day coverage turns RED permanently) and **evidence-to-delete time** (preplan and checks run between the read and the delete with no re-check). Pre-existing design from #9532; out of scope; default taken: untouched and listed in Sharp Edges for a follow-up.
4. **Panel splits on test size.** Two reviewers (DHH, code-simplicity) and the CTO asked for a smaller test than the first draft; the plan adopted a strict path-and-value check without an aggregating evaluator. The `vector.toml` shape-drift canary was CUT (speculative cross-file coupling, detects one literal, deletable by the PR it should stop); the CTO and one reviewer would have kept it as a warning-grade check. Default taken: cut; the header carries the coupling note.
5. **Reason-string split.** RED `used_bytes_absent_or_host_dark` (used series) or `total_bytes_absent` (total series) now also means "changed row shape", "more than one distinct device" or "a missing, empty or non-string tags.device on some row". A distinct reason (for example `multiple_devices`) needs a verdict-function change, which conflicts with "keep the thresholds and semantics"; default taken: header note only.

## Added by review (2026-10-06, PR review round 1)

6. **The 64 MiB spread tolerance is about 140 times the observed spread (471,040 bytes), and an in-window write under it passes as flat.** Decision 1 names old data (older than 7 days); a workspace written inside the 7-day window and smaller than the spread also passes both the ceiling and the spread. *Default taken:* both constants unchanged (the brief says keep every threshold); the script header now says neither bound proves emptiness. *Re-evaluate:* the same pre-dispatch decision as item 1 should cover the spread constant, not only the ceiling.
7. **Evidence identity is hostname plus mountpoint, not the pinned volume id.** `tags.host` is Vector's OS hostname (equal forgery resistance to the old `host_name`, weaker against hostname drift on a re-imaged host, fail-closed except for a same-hostname look-alike with its own flat 20 GB `/mnt/data`). Pre-existing design; the PR body must not claim `tags.host` is "no weaker" than `host_name`.
8. **Credential parity is unproven until the first plan-only dispatch.** The live control ran under Doppler read credentials, the workflow uses repo secrets `BETTERSTACK_QUERY_*`; docs and header now say so.
9. **Owner sign-off on the plan:** the owner answered an interactive question during the work phase on 2026-10-06 with "Sign off, start work" (thresholds unchanged, ceiling decision deferred); this is the owner's own answer to a question put to them, quoted as given, not an agent attribution. The header above ("not asked") describes how the plan phase persisted items 1 to 5; it does not apply to this one. The CPO advisory stays advisory.
10. **Future-dated rows (closed by review).** `dt > now() - INTERVAL 7 DAY` had no upper bound, so one future-dated row (a host clock skewed ahead, or a forged one) kept the newest age below zero and passed the freshness rule. The SQL now adds `AND dt <= now()`; pre-existing and not introduced by this PR, but this PR is what makes PASS reachable.
