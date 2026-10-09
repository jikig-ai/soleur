---
title: "Counsel attestation — #9066 (git-data lock files keep the user id after Art. 17 erasure: retention wording only)"
type: counsel-review
date: 2026-10-09
issue: 9066
pr: 9839
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-10-09
signed_off_by: "soleur:legal:clo (v1 internal attestation authority); operator retains optional veto"
disposition: DISCHARGED
scope: "the wording in PR #9839 only, subject to condition C1 below. NOT a finding that the Art. 17 residue is gone, bounded or measured."
re_evaluation_triggers: "(1) 2026-10-22 passes with hcloud_volume.git_data present (ledger expires_on; re-opens ADR-239, the ledger exception and the CLO before 2026-10-23; date not extended quietly); (2) 2026-10-24 CLO re-ruling on DPD §10.3(b) (issue trigger: the fix and the served-store purge slip); inputs are wipe, purge and flip state; (3) a count or measurement of the residue, or of Hetzner snapshot retention; (4) the .gc-cursor payload fix lands or is declined by the owner; (5) first arms-length user, EEA-out subject, or regulated-industry subject (external counsel)"
supersedes: "the 2026-10-09 first attestation of this file (blanket DISCHARGED, no wording change), withdrawn after the 11-seat review"
---

# Counsel attestation — #9066 (scoped)

Draft material; v1 internal sign-off, not external counsel review. This PR changes no payload, runs no purge and no wipe. DPD and GDPR Policy are not touched. Verdicts below are on prose, checked against ADR-239, the runbook, `git-data-gc.sh` and `decision-challenges.md` DC-4 (cited by name, not line).

## What changed since the first attestation

Withdrawn: "the running host still serves the pre-#9226 wrappers". `git_data_host_replace` ran 2026-10-08 (run 37846545572, head d0b5d2e35b, contains #9226); read from the run, not from the host. Added: the plaintext-volume residue comes from erasures before PR #8564; files written on the LUKS-served store between #8564 and the replace are a separate limb removed only by the unrun freeze-window purge; existence of both is unmeasured (hedged "may"). "no later than 2026-10-22" is now a target (wipe not implemented on main). A second id-bearing file, `.gc-cursor`, is disclosed and unfixed.

## Per-artifact verdicts

| Artifact | Verdict | Note |
|---|---|---|
| Art. 30 PA-36 (f) marker (`knowledge-base/legal/article-30-register.md`) | APPROVED WITH CONDITION C1 | Accurate and appropriately hedged on the two `.<id>.init.lock` limbs, the target, the slip rule and snapshot retention. It omits `.gc-cursor`, so the register still says erasure removes everything "in one operation" while a known id-bearing file survives it. Art. 30 is the controller's record; a known gap in the erasure claim belongs in it. |
| ADR-239 `## Amendment 2026-10-09` | APPROVED WITH EDIT E1 | Neutral, event-bound, "target not a fact", re-ruling inputs correct. One overstatement: `.gc-cursor` "up to a week" is a nominal cadence, not a bound (a failed or skipped run, or no remaining repo, leaves the id). E2: the re-ruling inputs omit the cursor state. |
| Runbook `git-data-luks-cutover-5274.md` | APPROVED WITH EDIT E3 | Opening paragraph now a pointer (date and slip rule in the ADR): fine. `not covered:` line names the cursor: fine. Step (d) states flatly that the host "was replaced onto that payload on 2026-10-08"; the ADR hedges that this was read from the run and its head. Align it. |

## Art. 5(1)(c)/(e) and Art. 17 position (why the `.gc-cursor` limb needs the register sentence)

The cursor holds an erased user's `auth.users.id` (pseudonymous, still personal data). Disclosure in the ADR, runbook, PR body and #9066 is adequate for a single-user-incident threshold ONLY IF the register carries it too, because the register is what an auditor or DSAR responder reads for "is the repository erased". Not fixing it here is acceptable: the file is 0 content beyond a name, reachable only by a holder of the store, and bounded in practice by the next completed run; the owner decision is tracked on #9066 before the first flip. It would not be acceptable to leave the erasure claim unqualified.

## Condition C1 and edits (verbatim wording is in the CLO return message to the caller)

- C1 (register, before merge): insert, inside the bracketed marker before "This marker does not say the files are gone.", a sentence naming `.gc-cursor`, that it sits outside this marker's end event, that it is not fixed by #9839, and that it is tracked on #9066. Check: `grep -c 'gc-cursor' knowledge-base/legal/article-30-register.md` must be at least 1. **If absent, this discharge is void.**
- E1/E2 (ADR): replace "up to a week" with an unbounded-if-runs-fail statement; add the cursor as a fourth re-ruling input.
- E3 (runbook): add "(from the run and its head, not read from the host)" to the 2026-10-08 claim in step (d).

Applied: C1, E1, E2 and E3 were applied in the review follow-up commit (the register now names `.gc-cursor`; checked with a grep for `gc-cursor` in `article-30-register.md`, count 1).

## Open items (named, not discharged)

1. Requirement 2, the served-store freeze-window purge: not run, no date.
2. `.gc-cursor` limb: unfixed; needs a hash-bound payload change (DC-4); tracked on #9066.
3. Existence of the residue: unmeasured on both limbs; Hetzner snapshot retention unmeasured.
4. The DL-2 wipe (and Hetzner volume delete evidence): not implemented; 2026-10-22 is a target.
5. The #5914 dated addendum is PR-body text for the owner, not a rewrite of that record.

## Standing conditions

1. No later wording says the files, the cursor or the volume are "erased" or "purged" without Hetzner delete evidence or a purge count.
2. When the wipe or purge PR lands, its register marker is conditioned on that merge (append-only) and records the evidence.
3. The PR body must repeat the open items above, not just the happy path.
