---
date: 2026-10-28
category: security-issues
issue: 9755
pr: 11455
---

# Census `env_arms()`: expression predicate literals are not environment arms — and the `|| ''` exemption needs a repo-secret backstop

Two defect classes found by the review panel on PR #11455, both in `tests/scripts/test-infra-privileged-tier-census.sh`:

1. **Operand literals.** A `environment: ${{ inputs.op == 'backup' && 'inngest-cutover' || '' }}` expression contains quoted literals that are *predicates* (`'backup'`), not resolvable environment names. `env_arms()` collected every quoted literal → the first Tier-B job using the idiom went RED on G1c/G1j. Fix: strip `==`/`!=` comparison operands before literal collection. Residual fail-GREEN blind spots (documented in-code): function predicates yielding in-set literals (`contains(x,'in-set')`), `&&` without `||` unbound dispatches, and container/service `env:` keys.

2. **The `|| ''` exemption's completeness claim.** Justifying an empty arm as "secrets unreachable on the unbound dispatch" was falsified: REPO-scoped privileged secrets (`DOPPLER_TOKEN_WRITE`, `DOPPLER_TOKEN_GIT_DATA_ROOT`, `DOPPLER_TOKEN_INNGEST_ARM`) resolve on ANY dispatch — reviewer gate or none. A correct `''`-arm backstop must ban those names across the whole step dump (`run:` interpolation counts), job/workflow `env`, `with:`, `secrets:` blocks, `secrets: inherit`, case-insensitively. Mutant-per-escape (g1-2d..j) is the only way to pin the invariant — verdicts, not just assertion counts, or a `[""]` revert silently reinstates the hole.

3. **Unparseable expressions must stay red.** `env_arms` returning `[""]` on a literal-free expression makes an unbounded env invisible to the census — return a sentinel (`__UNPARSEABLE__`) that every consumer treats as refusing.

4. **Fix-round caught a live red:** adding a name to a ban list (`DOPPLER_TOKEN_INNGEST_ARM`) turned an existing unconditional step-env reference on the `''`-armed live job into a violation — the clause shipped mid-review had to also restructure that delivery into an `if:`-gated export step. Widening a ban list changes what's a violation in the LIVE tree, not just fixtures — grep the live tree for every newly-banned name before landing.
