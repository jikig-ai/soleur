# Decision challenges — plan review (2026-09-30)

Plan: knowledge-base/project/plans/2026-09-30-fix-concierge-stop-gate-sentinel-leak-plan.md
Shipped on the planner's defaults; each item below is a Taste or User-Challenge finding from the review panel.

1. **User-Challenge — cut Phase 2 (`stripStopGateMarkup` + runner call + Sentry op).**
   Raised by: DHH reviewer, code-simplicity reviewer ("Phase 1 removes the only producer; ~150-200 lines for a case that can no longer occur").
   Plan default: KEEP. The operator's stated direction was "the `<stop>` markup is stripped/never rendered", and the strip is the only mechanism that covers a model or a future hook producing the tag. Cheaper variant offered by the panel: keep only the markup-only-block drop (~5 lines, no new file) plus a warn-only Sentry event when the text contains `<stop>`.
2. **Taste — shrink Phase 4 (parity guard) to a ~20-line classification check.**
   Raised by: DHH reviewer, code-simplicity reviewer. Opposed by: Kieran and CTO (keep, with fixes, which were applied).
   Plan default: KEEP the behavioural spawn and the six-row matrix; the Guard Contract gate (plan Phase 2.12) requires a matrix and the behavioural anchor is what stops a label-only weakening.
3. **Taste — ship Phase 3 (client idle transition) as its own PR.**
   Raised by: CTO (and DHH: "do not couple it to this incident").
   Plan default: same PR, strictly gated by a failing wire-sequence test with an explicit stop condition; a one-shot pipeline produces one PR.
4. **Taste — one `SOLEUR_RUNTIME=web-concierge` tag instead of per-hook `SOLEUR_DISABLE_*` variables; and fold the `browser-cleanup-hook.sh` opt-out (#9281) into this PR.**
   Raised by: DHH, CTO. Plan default: per-hook variable now (mirrors `SOLEUR_DISABLE_COMPACTION_HOOKS`, doubles as an operator kill switch), `SOLEUR_RUNTIME` recorded as a follow-up; #9281 stays deferred because whether the host-level match can reach other tenants' processes is unverified (pid namespace).
5. **Taste — drop the ADR-093 "Alternatives considered" rows and the e2e assertion.**
   Raised by: DHH, code-simplicity reviewer. Plan default: keep both (ADR corpus requires recording rejected alternatives; e2e is the only layer that exercises the composer's Send/Stop).
