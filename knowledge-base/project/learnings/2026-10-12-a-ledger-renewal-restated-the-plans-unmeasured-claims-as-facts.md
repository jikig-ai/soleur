# Learning: a security-ledger renewal restates the plan's unmeasured claims as facts

## Problem

Renewing the six encryption-posture exceptions that expired 2026-10-22 (PR #10132), the work phase copied the plan's prose into the ledger rows: "the volume is never writable, so there is no growth", "compensating control: not exposed beyond the private network", "measured on this host's image". All three were policy or past measurements, written as current fact while the same rows said `live_verification: unavailable`. Eight review seats converged on that class (security, CLO, user-impact, code-quality); none of it was visible to the lint, which only checks shape and dates.

A second shape: the ADR-068 note announced a lint guard for a future Redis client that did not exist yet, and the first version of that guard read one manifest (`apps/web-platform/package.json`) when a client can be declared anywhere, aliased with `npm:`, or listed in a dev/peer section.

## Solution

- Ledger text distinguishes policy ("by ADR-239 D2 policy the volume is never mounted writable; mount state unverified") from measurement ("as recorded, not re-measured 2026-10-12"). Past measurements carry their date and host.
- `check_redis_client_dependency` scans every `package.json` (skipping vendored dirs), all four dependency sections and `npm:` alias targets, fails loud on a malformed manifest, with fixtures per client name, per section, alias, other-manifest, malformed, and a node_modules skip (RD-1..9, mutation row MB-R1).
- The referral that a published "encrypted in transit with TLS" sentence conflicts with the plaintext in-transit rows was put where the owner reads it (#10136 and #6897), not only in `decision-challenges.md`.

## Key Insight

A renewal is the moment a plan's reasoning becomes a durable record, and a green lint certifies shape, not truth. For every sentence a ledger row ADDS, ask which of {measured, policy, inherited} it is, and write that word into the sentence. `disclosed_as` cannot be used to express a known published-text conflict: citing the sentence makes the lint fail by design, so the conflict has to be carried by an issue with a date.

## Session Errors

1. **Committed with the ruling gate red.** `technical-ruling-gate.sh ... | tail -1` printed FAIL, and the same command went on to `git commit`. Recovery: fixed the ruling grammar in the next commit. **Prevention:** run the gate on its own line and read its rc before committing; a trailing pipe or `;` hides the status (already in work/SKILL.md Sharp Edges, not applied).
2. **Wrote an ADR sentence about a guard before the guard existed** (ADR-068 note: "refuses a Redis dependency"). Recovery: implemented the guard in the same PR. **Prevention:** do not cite a mechanism in prose until its test is green.
3. **First Redis guard read one manifest.** Recovery: scan every manifest plus aliases and sections. **Prevention:** for any "is X present" lint, name where X can be declared before choosing what to read.
4. **A review seat judged #8620 off its title** and rated the tracker wrong; the body lists the token. One-off; verified by reading the body before acting.
5. **The first `git push` after the review commit failed with no readable cause; a plain retry succeeded.** One-off.

## Tags

category: workflow-patterns
module: encryption-posture-ledger
