# Decision Challenges — feat-one-shot-11897-declare-trusted-verdict-edge

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Declare vs accept for `scripts/inngest-a5-a6-owner-ask-10136` ↔ `scripts/lib/trusted-verdict.sh` | technical | Ruled by CTO agent, 2026-11-02: declared edge via `AFFECTED_SCRIPTS_INNGEST_A5_A6_OWNER_ASK_10136_PATHS` - the suite executes the real lib through the probe in every arm except the three forced-rc iterations (probe:177 `source "$libdir/trusted-verdict.sh"`; test.sh:8-10 documents the design), so an accept row's `false-positive:` certification would be factually false and would cement the derivation's coverage gap; consistent with the audit's remedy rule (ci-pr-affected-replay.py:98-100) and #11771/#11781 precedent. Dissent: none material — the PR's own ratchet run will announce `oracle-inputs-changed:` once (expected) and the array comment must record the `$libdir` indirection rationale |
