# Decision challenges (plan-review, headless)

## Taste: document the single-quoted-only sentinel contract in the runbook
- Source: CTO (devex lens) in plan-review.
- Suggestion: add one line to knowledge-base/engineering/operations/runbooks/supabase-migrations.md
  section 3 ("single-quoted literals only; PR CI guard enforces this").
- Plan default: NOT applied (kept diff minimal per "keep scope small"; the guard's failure message
  documents the rule). Operator may add it in review.
