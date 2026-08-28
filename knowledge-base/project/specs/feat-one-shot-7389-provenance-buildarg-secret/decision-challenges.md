# Decision Challenges — feat-one-shot-7389-provenance-buildarg-secret

Headless plan-review surfaced these rather than auto-applying them (ADR-084). `/ship` renders this
into the PR body and files an `action-required` issue.

## UC1 — Split #7389 into two PRs (dhh-rails-reviewer, P0)

**The operator's stated direction:** "Deliverable is a merged PR closing #7389, per the one-shot
contract — not a draft." Singular.

**The challenge:** DHH argued the plan "optimizes the enforcement architecture and pays for it in
credential exposure time" — a live token carrying `project:admin` + `alerts:*` stays valid for as
long as the PR takes, and the PR carries an ADR, a C4 enumeration, two legal documents and 25 ACs.
Proposed PR 1 = channel swap + release gate (mergeable immediately, unblocks rotation); PR 2 =
scanner, rule, ADR, legal records.

**Disposition: DECLINED, because the motivation dissolved.** The exposure window was the whole
argument, and Phase 1 now closes it *pre-merge* and independently of this PR — mint the replacement
under a new secret name, repoint the six consumers, revoke the leaked token. The coupling that forced
serialization was the secret *name*, not the PR boundary. Containment lands same-day and the
operator's single-PR deliverable stands.

**What would reverse this:** if Phase 1.2's mint blocks AND Phase 1.3's in-place scope-narrowing
fallback also fails, the token stays live and the split's argument returns in full force.
