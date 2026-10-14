# Decision challenges: feat-one-shot-7843-argv-bearer-to-config-stdin

## 2026-10-06 — Plan review (headless): one PR or three?

**Class:** user-challenge (the stated direction is one pipeline run for one issue; reviewers argue for splitting it).

1. **Operator direction:** implement #7843 as one pipeline run and one PR.
2. **Challenge:** DHH-lens, Kieran-lens, code-simplicity and the CTO all recommend splitting. The plan exceeds every split threshold (7 subsystem roots vs 4, ~85 files vs 25, ~1,600 lines vs 800).
3. **What the plan did instead:** kept one PR, reordered so the detector (Rule E + baseline E) lands first and each phase shrinks the baseline, which removes the "baseline rewritten twice" cost that had been the stated reason for one PR. Pre-agreed fallback boundary: (a) Phases 0-3, (b) Phases 4-6 + Phase 7.
4. **Cost of keeping one PR:** harder bisect and a large review; mitigated by phase-ordered commits (prerequisite commit, conversion commit, per phase).
5. **Default if no answer:** one PR (the operator's direction stands).
