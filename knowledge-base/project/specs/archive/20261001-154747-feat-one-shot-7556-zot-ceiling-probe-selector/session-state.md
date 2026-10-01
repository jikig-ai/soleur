# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-01-fix-zot-upload-ceiling-probe-selector-plan.md
- Status: complete

### Errors
None.

### Decisions
- Root cause is wider than the selector: the old span guard can never pass over a 7d window, the real PatchBlobUpload error line is not in the shipper's cap-exempt classes, and the shared error-payload check greps raw text.
- Sample floor counts PATCH /blobs/uploads HTTP API rows pinned to the SOLEUR_ZOT_LOG envelope; failure numerator has two signals (error rows, and a 5xx at ~1800 s latency).
- Span guard replaced by a heartbeat coverage-anchor read plus a drop-rows read (only reason=rate_cap is benign); every read goes through one fetch helper that flags truncation.
- MIN_SAMPLES=12 and the 7d window stay; the shipper-drop caveat is guarded and disclosed in the PASS text.
- On today's data the next sweep returns PASS and auto-closes the tracker (ADR-190 flip follows): PR body uses `Ref`, not `Closes`, and decision-challenges.md records the six calls.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; read-only betterstack-query.sh.
