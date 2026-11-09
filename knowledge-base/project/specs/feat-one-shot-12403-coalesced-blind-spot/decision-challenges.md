---
branch: feat-one-shot-12403-coalesced-blind-spot
issue: 12403
date: 2026-11-09
---

# Decision Challenges — feat-one-shot-12403-coalesced-blind-spot

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| `[skip-web-platform-apply]` reach on a multi-commit push — tip-only vs any-commit (the issue's "semantic sign-off" ask; kill-switch is fail-unsafe today) | technical | pending - assumed: any-commit — fail-safe direction: the token is a veto with no un-skip counterpart; a suppressed apply is recoverable through the `manual-rerun` dispatch, while an apply inside a scoped-retirement window is the harm the token exists to prevent |
| `[ack-destroy]` reach on a multi-commit push — tip-only vs any-commit | technical | pending - assumed: any-commit — parity with `deploy_policy_gate` (#12404): the push's commit set collectively constitutes the merged change the apply operates on, and a buried ack's fail-closed refusal is the same defect class |
| `apply-github-infra.yml` + `apply-sentry-infra.yml` carry the same tip-only readers (`HEAD_MSG` at apply-github-infra.yml:88,290 and apply-sentry-infra.yml:161,802) — widen in this PR or file a follow-up | operator (scope) | pending - assumed: out of scope for #12403 (issue names apply-web-platform-infra.yml only); file a follow-up issue after this PR lands |
| Combined variable name for the shared feed — keep `POLICY_MSGS` vs rename to `ALL_MSGS` | taste | applied: rename to `ALL_MSGS` — the var feeds two gates (deploy_policy + ack-destroy), not just policy; sweep is 3 files already in the edit list (workflow lines ~868-871, deploy-policy-gate.sh comment ~6-8, G11 literal ~line 133) |
