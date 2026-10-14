# Decision challenges — feat-one-shot-9356-luks-followups

Raised by the plan-review panel (headless run; not paused). Each item keeps the operator's stated scope as the default.

1. **User-Challenge — drop or defer the #9358 wrapper (`lb-weight-gate-with-marker.sh`).** DHH and code-simplicity: it has no caller until the flip
   orchestrator exists; ship ADR text and the stale-comment fix, build the wrapper in the orchestrator's PR. Plan default: keep (the issue asks for the sourcing).
2. **User-Challenge — defer the #9356 key-conditional arms to the PR that removes the web-1 refusal.** DHH, code-simplicity, architecture: unreachable
   behind the refusal, and "arms complete" can read as "web-1 safe". Plan default: keep (the issue names the arms), with the three non-plan blockers
   restated in the arm comment and the fixture labelled arms-only.
3. **User-Challenge — drop the #9357 `terraform_data` rehearsal suite.** DHH: it proves state-mv on a stand-in type only. Plan default: keep
   (the issue's live step has no other proof), labelled a state-address rehearsal.
4. **Taste — defer the `case_raw_formats_once` split (and the fork trim).** DHH, code-simplicity: cosmetic, forces floor changes in an area that
   regressed this week. Plan default: keep (the issue names it); fork trim only if Phase 0.2 measures it worthwhile. If cut, `Closes #9378` becomes `Ref #9378`.
5. **Taste — per-host-class passphrase.** CTO, spec-flow: the credential split is partly cosmetic while web-2 reads web-1's passphrase, and fixing it
   after web-2 formats is a re-key. Plan default: explicit go/no-go recorded before #9372 dispatches (follow-up table), not built here.
