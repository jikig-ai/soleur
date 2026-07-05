# Tasks — fix(infra): cross-pipeline web-1-swap serialization (#6060 item c)

Plan: `knowledge-base/project/plans/2026-07-05-fix-cross-pipeline-web-1-swap-serialization-plan.md`
Lane: cross-domain (no spec.md — defaulted). Threshold: aggregate pattern.
Scope: IMPLEMENT #6060 item (c); DEFER items (a) + (b) with inline re-triage on #6060.

## Phase 0 — Preconditions (verify before editing)

- [ ] 0.1 Re-confirm the load-bearing runtime claim: job-level `concurrency` coexists with
  workflow-level `concurrency` (independent scopes). Docs citation pinned (workflow-syntax
  reference, verified 2026-07-05). Confirm `actionlint` accepts a workflow carrying BOTH
  scopes after the edit. (AC1)
- [ ] 0.2 Re-verify the FOUR web-1-swap sites via grep: `command: deploy web-platform` POST to
  `/hooks/deploy` in — `web-platform-release.yml` (deploy `:572`), `apply-web-platform-infra.yml`
  (web_2_recreate/warm_standby via `deploy-status-fanout-verify.sh`), `apply-deploy-pipeline-fix.yml`
  (apply `:607`). Confirm the routine `apply` job (apply-web-platform-infra.yml) has NO such POST.
- [ ] 0.3 Re-grep `deploy-web-platform` references (expect only `web-platform-release.yml:439,447`).
- [ ] 0.4 Re-run the code-review overlap two-stage check (`gh --json > f.json; jq --arg`) on the
  final Files list; #3220 disposition = Acknowledge (migration jobs, different concern).
- [ ] 0.5 C4 completeness read: read all three of
  `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`; confirm no new
  actor/system/store/relationship (cite the enumeration) → "no C4 impact". (ADR/C4 gate)

## Phase 1 — Core change: shared `web-1-swap` concurrency group

- [ ] 1.1 `web-platform-release.yml` deploy job (`:446-448`): rename job-level
  `concurrency.group` `deploy-web-platform` → `web-1-swap`; keep `cancel-in-progress: false`;
  update companion comment `:439`. (Or, per the diff-minimal alternative, reuse
  `deploy-web-platform` as the shared name — decide with reviewers.)
- [ ] 1.2 `apply-web-platform-infra.yml`: add job-level
  `concurrency: { group: web-1-swap, cancel-in-progress: false }` to `web_2_recreate` (`~:876`)
  and `warm_standby` (`~:647`). Do NOT touch the workflow-level `terraform-apply-web-platform-host`
  group (`:115`). Do NOT add the routine `apply` job.
- [ ] 1.3 `apply-deploy-pipeline-fix.yml`: add the same job-level `web-1-swap` block to its
  `apply` job (`:177`). Do NOT touch its workflow-level group (`:138`).

## Phase 2 — Drift-guard test (allow-list)

- [ ] 2.1 Add an all-members allow-list guard (extend an existing infra/workflow test if one
  parses these YAMLs; else new `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh`).
  Assert: each of the 4 named `(workflow-file, job)` members carries `concurrency.group ==
  web-1-swap` + `cancel-in-progress: false`; total `web-1-swap` count == 4 (not head -1, not >=4);
  workflow-level `terraform-apply-web-platform-host` still present in both apply workflows;
  no stale `deploy-web-platform` remains. (AC2/AC4)
- [ ] 2.2 (Optional, P2) assert each member job has a deploy-status completion-poll step
  (guards the lock-hold-duration invariant).
- [ ] 2.3 `shellcheck` clean on any new `.test.sh`; register it in `infra-validation.yml`
  (`:154` pattern) if new. (AC6/AC7)

## Phase 3 — ADR amendment

- [ ] 3.1 Amend ADR-068 (short paragraph): the cross-pipeline `web-1-swap` serialization
  invariant across the 4 swap jobs; workflow-level R2 serializer unchanged;
  `cancel-in-progress: false` rationale; the lock-hold-duration invariant (members poll to
  terminal); the inngest-flock accepted residual. `Ref #6060`. Amend, not new ADR. (AC8)

## Phase 4 — Lint + verify

- [ ] 4.1 `actionlint .github/workflows/web-platform-release.yml
  .github/workflows/apply-web-platform-infra.yml .github/workflows/apply-deploy-pipeline-fix.yml`
  clean; embedded `run:` snippets via `bash -c` (never `bash -n` on the YAML). (AC5)
- [ ] 4.2 Run the drift-guard `.test.sh` → 0 failed. RED-proof: temporarily divert one member's
  group literal and confirm the guard FAILs; revert.

## Phase 5 — Deferred re-triage (docs)

- [ ] 5.1 Do NOT `Closes #6060` — PR body uses `Ref #6060`. Ship records: item (c) done; items
  (a) and (b) re-triaged (owner + trigger per the plan's Deferred section); the inngest-flock
  named residual. (AC9)
- [ ] 5.2 Post-merge (via ship/automation): comment on #6060 checking item (c), and rewrite
  items (a)/(b) with their re-eval criteria (a → GA owner-side relay / ADR-worthy CF trust path;
  b → GA-cutover orchestrator readyz pre-pool gate). #6060 stays OPEN.

## Notes
- No new infra/secret/vendor (IaC gate skip). No regulated data (GDPR skip). No UI (Product/UX NONE).
- Deferred items (a)/(b) are NOT built here — they are GA-cutover/owner-side-relay scoped.
