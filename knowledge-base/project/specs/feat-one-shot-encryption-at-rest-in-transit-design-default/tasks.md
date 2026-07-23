---
feature: encryption-posture-design-time-default
branch: feat-one-shot-encryption-at-rest-in-transit-design-default
plan: knowledge-base/project/plans/2026-07-23-feat-encryption-posture-design-time-default-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — Encryption posture as a design-time default

Derived from the plan. Phase order is load-bearing: the ledger schema and the audit precede the
detector (the detector's fixtures are shaped by what the audit actually finds), and the detector
precedes its required-check promotion.

## Phase 0 — Preconditions (verify, never assume)

- [ ] 0.1 Re-measure `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>&1` (the `2>&1` is load-bearing) and pin the output in the PR body.
- [ ] 0.2 Re-measure the skill-description budget (`bun test plugins/soleur/test/components.test.ts`); confirm still `2366/2366`.
- [ ] 0.3 Confirm `plugins/soleur/skills/eval-harness/gated-skills.json` still excludes `plan`/`review`/`preflight`.
- [ ] 0.4 Grep the max existing numbers before choosing new ones: `grep -n '^### Check ' plugins/soleur/skills/preflight/SKILL.md | tail -1` (expect 11 → new is 12); same for `deepen-plan` (expect 4.9 → 4.10) and `plan` (expect 2.10 → 2.11).
- [ ] 0.5 Verify every path in the plan's `## Files to Edit` exists; verify every `knowledge-base/` citation resolves.
- [ ] 0.6 Re-verify the next free ADR ordinal against `origin/main` (plan assumes 139, provisional).

## Phase 1 — Ledger schema + the one-time audit (read-only)

- [ ] 1.1 Author `scripts/encryption-posture-ledger.schema.json` — row schema + the extensible `store_classes` table.
- [ ] 1.2 Run the audit. Automated sources ONLY: `terraform show -json` / `terraform state list` against the R2-backed state, provider APIs (Hetzner, Cloudflare, Supabase, Doppler), `git grep` over `*.tf` + connection code, the Better Stack Logs query helper, recorded workflow run output. **No dashboard eyeball. No SSH.**
- [ ] 1.3 Write `knowledge-base/engineering/architecture/encryption-posture-audit-2026-07-23.md` covering every store and connection in the plan's `## One-Time Audit` tables; each row cites its automated source.
- [ ] 1.4 Seed `scripts/encryption-posture-ledger.json` from the **measured** output (never the expected output).
- [ ] 1.5 File one issue per non-conforming finding (`type/security`, `domain/engineering`, priority per sensitivity). Cross-link `Ref #6588` where in scope — **never `Closes`**.
- [ ] 1.6 Confirm no remediation was performed (`git diff` touches no existing `hcloud_volume` body).

## Phase 2 — Layer A detector (RED first)

- [ ] 2.1 Write `scripts/lint-encryption-posture.test.sh` with fixtures TS-1..TS-14. Confirm RED.
- [ ] 2.2 Implement `scripts/lint-encryption-posture.py`: modes `--repo-sweep` (default), `--diff <pathfile>`, `--report`. Fail-closed on every indeterminate outcome. No bypass flag, no env escape, no comment suppression.
- [ ] 2.3 Implement citation resolution for `mechanism: luks` (luksFormat/luksOpen site + key resource + doppler_secret + `/dev/mapper/*` mount; mapper names must match).
- [ ] 2.4 Implement the in-transit require-list / ban-list, with `sslmode=require` in the **ban**-list.
- [ ] 2.5 Implement unknown-store-class fail-closed.
- [ ] 2.6 GREEN: all TS cases pass.
- [ ] 2.6b **Calibration against the real repo (AC33):** the detector must certify `hcloud_volume.git_data_luks` and `hcloud_volume.workspaces_luks` as `mechanism: luks` with all citations resolved. These two files are the detector's contract; a detector that cannot certify them is miscalibrated no matter how many synthetic fixtures pass.
- [ ] 2.7 Register `scripts/lint-encryption-posture.test.sh` in `scripts/test-all.sh`; confirm `bash scripts/lint-orphan-test-suites.sh` passes.
- [ ] 2.8 Run the mutation battery MB-1..MB-7. Diff **per-case verdicts**, not suite pass-counts. Every mutation must red.
- [ ] 2.9 Verify non-vacuity under `git clone --depth 1` — same verdict and store count as the full clone.
- [ ] 2.10 Verify the no-bypass behavioural matrix (AC10).

## Phase 3 — Required-check promotion (three coupled edits, one commit)

- [ ] 3.1 Add the `encryption-posture` job to `.github/workflows/ci.yml`.
- [ ] 3.2 **Read the `#6049` AUTO-FABRICATION GUARD header in `scripts/required-checks.txt` first.** This gate is content-scoped, so adjudicate explicitly: reproduce it in `.github/actions/bot-pr-with-synthetic-checks/action.yml` Phase-4, OR exclude it from synthesis via a non-15368 `integration_id`. Record which arm was taken in the PR body.
- [ ] 3.3 Add the entry to `scripts/required-checks.txt`.
- [ ] 3.4 Add the `required_check` block to `infra/github/ruleset-ci-required.tf`; the context string must be byte-identical to the `ci.yml` job name.
- [ ] 3.5 Assert byte-identity across all three artifacts mechanically (AC13).

## Phase 4 — Layer B live reconciliation

- [ ] 4.1 Implement `tests/scripts/lib/encryption-posture-reconcile.sh` (`--audit`, `--live`), modelled on `tests/scripts/lib/preapply-entrypoint-gate.sh`: default-deny, one fail-closed catch-all, a control probe on a known-good target, and a positive-work floor.
- [ ] 4.2 Make could-not-measure its own **aborting** class evaluated **before** the comparison; make it distinguishable in output from a clean pass.
- [ ] 4.3 Write `tests/scripts/test-encryption-posture-reconcile.sh` incl. the could-not-measure matrix (empty credential, HTTP 000, degraded 200 with empty body, zero-row log query). Register in `scripts/test-all.sh`.
- [ ] 4.4 Add `.github/workflows/scheduled-encryption-posture-reconcile.yml` (daily); auto-files an issue on divergence; emits the heartbeat only on a positive-work clean pass.
  - **The `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` PreToolUse hook WILL DENY this Write** (ADR-033 makes Inngest canonical: 53 Inngest crons vs 10 GH Actions crons). This is expected and pre-decided in plan **D8**. The workflow MUST carry BOTH the literal override comment `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` near the top AND an in-file comment block restating the three-part exemption (infra-scoped credentials only / replay is harmful for a security verdict / **circularity** — the verifier must not run on `hcloud_volume.inngest_redis`, a store it audits). Override without the justification block = review-blocking defect (AC32).
- [ ] 4.5 Add the heartbeat to `apps/web-platform/infra/uptime-alerts.tf`, **count-gated behind the ADR-117 measure-then-arm gate**; `terraform plan` shows no create of an armed beat.
- [ ] 4.6 Write `scripts/followthroughs/encryption-posture-reconcile-soak-<issue>.sh` (3 consecutive green runs, `start=` pinned strictly after the deploy) + the tracker directive + the `follow-through` label; wire `secrets=` into `.github/workflows/scheduled-followthrough-sweeper.yml` if needed.

## Phase 5 — Design-time gates

- [ ] 5.1 Add `## Encryption Posture` to all three templates in `plugins/soleur/skills/plan/references/plan-issue-templates.md`, immediately after `## Observability` in each.
- [ ] 5.2 Add `### 2.11. Encryption Posture Gate` to `plugins/soleur/skills/plan/SKILL.md` (after §2.10), mirroring §2.9's shape.
- [ ] 5.3 Add `### 4.10. Encryption Posture Halt (Conditional)` to `plugins/soleur/skills/deepen-plan/SKILL.md`, mirroring §4.7's four steps, with the full reject list (boilerplate ban-list, `does_not_defend` empty/restatement, exception without `tracking_issue`).
- [ ] 5.4 Verify §4.10 **behaviourally** against three fixture plans (compliant / boilerplate mechanism / exception without issue) — AC4.
- [ ] 5.5 Add `### Check 12: Encryption Posture` to `plugins/soleur/skills/preflight/SKILL.md` plus its §0.1 fast-path SKIP row. SKIP only for "I do not apply", never "I cannot prove it".
- [ ] 5.6 Add the defect-class entry + conditional `security-sentinel` spawn instruction to `plugins/soleur/skills/review/SKILL.md`.

## Phase 6 — Generation-side defaults

- [ ] 6.1 `plugins/soleur/agents/engineering/infra/terraform-architect.md` — Hetzner/Cloudflare section: no `hcloud_volume` encryption attribute; the four-part guest-side LUKS apparatus; the live-volume guard-inversion data-loss trap reproduced verbatim; encrypted by default, named justification otherwise.
- [ ] 6.2 `plugins/soleur/agents/engineering/infra/platform-strategist.md` — encryption posture as a first-class Decision Framework axis.
- [ ] 6.3 Add an "Encryption posture" step to all four `plugins/soleur/skills/provision-*/SKILL.md`.
- [ ] 6.4 Add `references/encryption-posture-gate.template` + `references/encryption-posture-scan.template` to `constraint-scaffold`.
- [ ] 6.5 Teach `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` to emit both, non-destructively (refuse to overwrite), inheriting the agent-owns-gates recovery model.
- [ ] 6.6 Write `plugins/soleur/skills/constraint-scaffold/test/encryption-posture.test.sh` proving non-vacuity; extend `test/parity.test.sh` to cover the new templates.
- [ ] 6.7 Update `plugins/soleur/skills/constraint-scaffold/SKILL.md` body to document the second gate. Do **not** edit its `description:` unless the budget is re-measured and a sibling trim is prescribed.

## Phase 7 — ADR, C4, docs, compliance

- [ ] 7.1 Write the ADR (ordinal per 0.6). If renumbered, sweep `grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/feat-one-shot-encryption-at-rest-in-transit-design-default/` in the same edit.
- [ ] 7.2 Edit `knowledge-base/engineering/architecture/diagrams/model.c4`: correct `workspacesVolume` (cite verify run `30040444418`); add at-rest posture clauses to `inngestRedis`, `gitDataStore`, `sessionStore`, `zotRegistry` **from the audit's measured output**.
- [ ] 7.3 Edit `views.c4`: `include platform.infra.workspacesVolume` in the `containers` view.
- [ ] 7.4 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 7.5 Record the design-time-default principle in `knowledge-base/project/constitution.md`.
- [ ] 7.6 Run `/soleur:gdpr-gate` **inline** against the plan + diff (`wg-plan-prescribed-skills-must-run-inline`).
- [ ] 7.7 Post a note on `#4133` recording that a second template↔gate schema pair now exists.

## Phase 8 — Exit gate

- [ ] 8.1 `bash scripts/test-all.sh` — full-suite green.
- [ ] 8.2 Walk every AC1..AC33; record the verification command and its output.
- [ ] 8.2b **Run `/soleur:plan-review` with agents available BEFORE starting Phase 1.** The deepen-plan pass ran with the `Task` tool unavailable, so the plan has had no adversarial multi-agent read. At `single-user incident` threshold the escalated 5-agent panel (+`architecture-strategist` +`spec-flow-analyzer`) is mandatory, not optional.
- [ ] 8.3 Confirm the PR body has no `Closes #6588`, lists audit findings as `Ref #N`, and pins both budget measurements.
