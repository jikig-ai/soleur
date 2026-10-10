# Decision challenges — feat-one-shot-9879-luks-sole-copy-protection

Persisted by plan-review (headless). Each item is a Taste or User-Challenge; the plan's default is stated and stays in force
unless the user says otherwise. None of them changes the stated scope (a), (b), (c) of #9879.

## Taste 1 — extract the lexer from web-1's guard suite, or copy it

- Plan default: extract `strip_comments` / block extraction into `tests/scripts/lib/hcl-effective-text.sh`; edit ONE source line
  in `apps/web-platform/infra/workspaces-luks.test.sh` (web-1's sole-copy guard) to source it; identical pass count and floor.
- Counter-view (DHH review): do not edit web-1's guard for this change; give the new suite a minimal local copy or defer the
  extraction. Cost of the default: the other sole-copy store's guard takes a refactor risk; cost of the counter-view: ~60
  duplicated lines the brief's "extend, do not duplicate" argues against.

## Taste 2 — scratch-volume proof that detach works under delete protection

- Plan default: not done; the first sanctioned host replace after merge is the live proof (stated in the Production Write Gate).
- Counter-view (spec-flow review): create a scratch protected volume, attach, then detach and delete the server, to prove the
  sanctioned replace is safe before relying on it. It is a billable production write and needs its own go-ahead.

## Taste 3 — separate draft CLO audit file and sibling Article 30 cross-references

- Plan default: cut (both simplicity reviewers: inferred, nothing consumes them). Kept: the Article 30 TOM, the (e) pointer, the
  compliance-posture bracket, the new ADR.
- Counter-view (CLO): the PR needs its own attestation file (`knowledge-base/legal/audits/2026-10-counsel-review-9879.md`) and one
  cross-reference in each of the two sibling processing activities. Reinstating is a documentation-only addition.

## Taste 4 — new ADR instead of an ADR-142 addendum

- Plan default (architecture review): a short new ADR with the canonical loss-mode table, plus a pointer addendum in ADR-142 and a
  divergence note in ADR-263. Counter-view: one more addendum to ADR-142 (already seven).

## Taste 5 — rollback recipe executed once vs written only

- Plan default: executed once in a scratch detached worktree and recorded (the plan-skill rule for a plan's rollback section).
- Counter-view (DHH, simplicity): the revert is mechanical; write the recipe without rehearsing it.
