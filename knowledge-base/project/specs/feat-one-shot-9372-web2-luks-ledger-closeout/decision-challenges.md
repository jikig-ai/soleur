# Decision challenges - feat-one-shot-9372-web2-luks-ledger-closeout

Appended by plan on 2026-10-10 (headless pipeline: not asked, persisted for the ship phase to render in the PR body and file as an
`action-required` issue). Where the planner argues for a change to the owner's stated direction, the default taken is named.

## Owner decision needed (not decided here)

1. **#9642: how strict the web-2 emptiness evidence must be.** Surfaced, not decided, as directed.
   - *State on 2026-10-10:* the real (non plan-only) rebirth dispatches ran on 2026-10-06 (runs 37508066236, 37508997529,
     37516716515 succeeded; two earlier runs failed) under the unchanged 1 GiB ceiling and 64 MiB spread. The old plaintext volume
     (id 106466179) now answers 404, and the new volume (id 107059048, raw, created 2026-10-06T18:21Z) is attached to web-2. The
     gating question of #9642 therefore passed before it was decided.
   - *What is still open:* whether the owner accepts that history retrospectively (and closes #9642), keeps it open for a future
     rebirth tool, or wants the thresholds tightened before PR 2 deletes the code that carries them. PR 2 should not start before
     the owner rules, because retiring the workflow removes the constants the decision concerns.
   - *Not claimed:* that the deleted volume was verified empty. The evidence was size (about 16 MB) only; the audit record says so.

## User-Challenge

2. **The brief's "hard deadline: the posture exception expires 2026-10-22" is stale for this row.**
   - *Stated direction:* treat 2026-10-22 as the hard deadline for the flip.
   - *Evidence:* the `hcloud_volume.workspaces` ledger row carries `exception.expires_on: 2026-12-29` (re-scoped by PR #9348, merged
     2026-10-08; #6931 comment of the same date). The rows that expire on 2026-10-22 are other stores (#6897).
   - *Default taken:* the flip proceeds at normal priority, with no exception extension and no edit to the 2026-10-22 rows. If the
     owner prefers the earlier date as a working target, nothing in the plan changes.

## Taste

3. **One PR with two ordered commits rather than two PRs.** The CTO consult preferred the linter change as its own PR first;
   #9572 says both "a separate reviewed change" and "in the same change as the two linter fixes". Default taken: one PR (#9941),
   commit 1 the linter (reviewed as a security-linter change), commit 2 the flip. Split trigger: a second review round on commit 1
   or more than about 800 changed lines moves commit 1 to its own PR by cherry-pick. Re-evaluate at the first review round.
4. **Brand-survival threshold `aggregate pattern`, not `single-user incident`.** No user data can reach web-2 through this change
   and the anti-pooling gate holds it at weight 0; the over-claim risk is record accuracy (Art. 5(2)). A reviewer who reads the flip
   as the green light for web-2 data should challenge this tier, in which case `requires_cpo_signoff` and the user-impact review apply.
5. **Linter scope is three changes plus `multiplicity`, not the two listed in #9572.** The mapper join resolves through web-1's
   apparatus (name-similarity, rejected by ADR-140), so the apparatus pin is added; `multiplicity` replaces the per-host row split,
   which is dissolved because the row is already web-2-only.

## Plan-review taste findings (2026-10-10; three-reviewer panel, not applied)

6. **Slimmer linter design.** Two reviewers (DHH-lens and simplicity-lens) argued the linter is over-built for one ledger row.
   Proposed slim form: indexed binding, apparatus pin, the consumer hop, the secret-to-password hop and one uniqueness guard;
   drop the token/config and secret/config equality hops, and replace `multiplicity` and its one-shape HCL resolver (the most
   fragile new parsing) with a suite assertion that the host-map keys minus web-1 equal `["web-2"]`.
   - *What the slim form stops catching:* a token reading a different Doppler config than the secret holds (caught later by the
     daily `web2_marker` probe going RED, not pre-merge), and an automatic ledger red on a new host key (caught in a test instead).
   - *Default taken:* the CTO-recommended full chain and `multiplicity` stay in the plan, because the config-equality hop is the one
     that distinguishes web-1's and web-class tokens (`server.tf` names that swap as the real hazard) and the ledger linter is
     the gate reviewers read. *Re-evaluate at Phase 1.0:* if the multiplicity resolver exceeds about 40 lines or needs more than
     the one supported shape, switch to the slim form.
7. **Fewer records.** The simplicity lens would cut the runbook row-2 line and the nfr-register pointer (PR 2 rewrites the runbook;
   the nfr sentence is already scoped "pre-flip") and de-duplicate the not-discharged list across four places. Default taken: keep
   both lines (they stop a later reader acting on a falsified sentence) and keep the repetition (each cell is read alone).
