# Decision Challenges — feat-one-shot-12666-12583-9340-batch

Date: 2026-11-12
Plan: `knowledge-base/project/plans/2026-11-12-fix-ci-battery-gate-enforcement-followups-plan.md`
Issues: #12666, #12583, #9340

Technical forks are resolved by ruling. One batched CTO spawn (2026-11-12) ruled all 15
pending technical rows; rulings recorded verbatim below. Only money, scope, priority, schedule,
irreversible/production-mutating authorization, legal-risk, and brand may be operator-class;
no technical question is posed as an owner item.

| Item | Class | Ruling |
|------|-------|--------|
| Calibration timeout magnitude (#12583) | technical | Ruled by CTO agent, 2026-11-12: raise per-test timeout 180000→600_000 on both calibration tests in `plugins/soleur/test/skill-security-scan.test.ts` with a #12583 comment each — surgical per-test override is the file's precedent shape (`30_000` citing #4096); shrinking the corpus weakens the 0%-HIGH-RISK coverage guarantee; 600s bounds the measured >4x contention inflation with margin |
| Bypass-merge detection mechanism (#12666 Q4) | technical | Ruled by CTO agent, 2026-11-12: new `.github/workflows/merge-bypass-audit.yml` on push-to-main + workflow_dispatch running `scripts/merge-bypass-audit.sh` — nothing covers per-merge bypass USE today (cron audit does config drift only; `probe-merge-group-coverage.sh` is offline; `admin-merge-ready.sh` is opt-in); the push event carries the merge SHA and covers queue/direct/admin/direct-push landings through one chokepoint |
| Alert surface for bypass detection | technical | Ruled by CTO agent, 2026-11-12: deduped GitHub issue keyed on the merge SHA — the sibling `cron-ruleset-bypass-audit` convention with auto-close-on-green; Slack has no dedupe/closure semantics and no webhook config; a marker alone produces no assignable artifact |
| Bypass actor/mode finding disposition (Q1) | technical | Ruled by CTO agent, 2026-11-12: committed postmortem doc in `knowledge-base/engineering/operations/post-mortems/` plus a `gh issue comment` on #12666 linking it — the convention is active (11 dated postmortems) and the evidence-dense findings need the durable indexed home |
| Restrict `pull_request` bypass for `OrganizationAdmin`/`RepositoryRole(5)` (Q2) | operator (production-mutating) | pending - ACTION: authorize a follow-up Terraform PR editing the bypass-actor list in `infra/github/ruleset-ci-required.tf` — held for the operator; this PR ships the probe + audit only, no ruleset change |
| Public exposure of bypass-actor identity in a public issue | operator (brand) | pending - ACTION: confirm the bypass-actor identity may be published in the public postmortem/issue comment — default records facts without accusation; escalate only if the founder wants the write-up sanitized further |
| Admission-rule class for the six next-tier suites (#9340) | technical | Ruled by CTO agent, 2026-11-12: widen ADR-262 Decision 4 via committed addendum to "verdict is a property of a closed, declarable edge set", keeping the machinery self-test clause and the live-external exclusion — the six suites satisfy the load-bearing property and Guard-2 makes the class enforceable |
| Per-suite admit/decline for the six named suites | technical | Ruled by CTO agent, 2026-11-12: admit all six, each conditional on Guard-2 closure plus a replay-measured arm rate — a suite measuring ~100% arm rate is declined-on-measurement and recorded as such |
| `run-all.sh` gate extension | technical | Ruled by CTO agent, 2026-11-12: admit to `--pr-gated` — the second required home `guard-script-fixture-tests` (pr-quality-guards.yml:313-316) runs it on every PR regardless; the flip adds unconditional non-PR coverage |
| `c4-from-components` gate extension | technical | Ruled by CTO agent, 2026-11-12: admit inside its existing glob-loop special-case — all homes are test-all.sh-mediated, so merge_group/push/6-hourly monitor remain the full-battery authority per ADR-276; the flip strictly increases non-PR coverage |
| `apps/web-platform [unit]` arm gate extension | technical | Ruled by CTO agent, 2026-11-12: admit with merge_group backstop — the `repo-wide+component` arm stays ungated, preserving the containment authority (`repo-wide-containment.test.ts` is never gated by the thing it guards) |
| `.github/workflows` narrowing representation | technical | Ruled by CTO agent, 2026-11-12: committed sorted enumeration `scripts/lint-orphan-consumed-workflows.txt` + completeness arm inside the ungated `lint-orphan-test-suites.sh` — self-healing (editing the .txt arms the battery on the same diff); over-inclusion errs toward arming |
| Probe verdict on green-at-merge→red-later heads | technical | Ruled by CTO agent, 2026-11-12: classify `check_flipped_after_merge`, never BYPASS — green-at-merge must be proven via check-run API ordering; unestablished ordering exits 2 per the unread-answer rule |
| Probe required-set authority | technical | Ruled by CTO agent, 2026-11-12: `scripts/ci-required-ruleset-canonical-required-status-checks.json` — the same canonical file the daily drift audit compares the live ruleset against; the probe inherits the alarm for free |
| Probe substrate: new GHA push workflow vs extending the Inngest cron audit | technical | Ruled by CTO agent, 2026-11-12: GHA push-triggered workflow — same axis as the detection-mechanism ruling; Inngest has no GitHub-push ingress in this repo and the probe is purely git/repo-scoped (no app context/secrets, no memoization benefit); the script stays callable from an Inngest function unchanged if a reviewer prefers consolidation |
| Probe alert label | technical | Ruled by CTO agent, 2026-11-12: `compliance/critical` — verified to exist and already the sibling ruleset-drift audit's route for this defect class; a new `ci/enforcement-gap` label fragments the alert surface |
| Glob-loop `--pr-gated` special-case shape | technical | Ruled by CTO agent, 2026-11-12: c4's `if [[ "$f" == "<path>" ]]` shape with `--pr-gated` inside, one `if` block per glob-registered admit, explicit if/else wraps for explicit registrations, and the `expected >= 6` floor literal bumped to the real derived count — Guard-2 derives gates by the literal pattern, so no indirection survives derivation |

## Verified already-satisfied (records, not decisions)

- Merge-queue bullet (#9340): already live on ruleset 14145388 — dispositioned as issue bookkeeping (comment + check-off), no implementation.
- Reaper battery bullet (#9340): completed by #12619 before this batch; verified in `scripts/test-all.sh` call sites; no implementation.
