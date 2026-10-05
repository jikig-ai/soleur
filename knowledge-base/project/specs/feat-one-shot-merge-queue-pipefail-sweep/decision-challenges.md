# Decision challenges: feat-one-shot-merge-queue-pipefail-sweep

Persisted by plan-review (headless). None changes the operator's stated scope; each is a design call the plan made where panels disagreed.

## 2026-10-05 Plan review

1. **Deferral list: length pin versus per-row ceilings.** DHH and code-simplicity said cut the pin (it proves consistency, not integrity). The CTO lens said the deferred subtrees (about 950 sites) can grow while their waves are pending. Class: taste. Resolution in the plan: no length pin; each deferral row carries a ceiling, a tracker token and a stale check, and every run prints a `DEFERRED:` line. Challenge: if the ceilings churn on hot test directories, drop them and keep only the stale check.
2. **Producer-side census.** DHH and code-simplicity said cut it from PR-1 (no deliverable in this PR). The brief says "Treat the producer-side form separately". Class: user-challenge risk (touches a stated ask). Resolution: the measured population is posted on #9217 in PR-1 and the production-to-stub join plus stub fixes move to the first phase of wave B, so the ask stays served as a separate item. Challenge: do the join in PR-1 if the operator wants the census before the test-harness wave.
3. **Join pre-pass for continued pipes and extra flag spellings.** Cut (1 site; 0 real flag-order sites), except that the brief names "flag order", so the argument-taking-flag alternative stays in minimal form. Class: taste.
4. **Transformer not committed.** Kept as scratch work in PR-1; committed by the first later wave that needs it. Class: taste.
