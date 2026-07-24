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

> **BINDING:** the plan's `## Plan Review Revisions` block (R0–R11) supersedes any conflicting task
> below. Where a task references deleted scope (constraint-scaffold, D8 override, `uptime-alerts.tf`
> heartbeat, three-site coupling), follow the R-item instead. Tasks corrected inline are tagged `[R#]`.

## Phase 0 — Preconditions (verify, never assume)

- [x] 0.0 **DONE — `/soleur:plan-review` ran with the full escalated panel BEFORE Phase 1** (7 agents: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, cto-devex, cpo). Verdict: unanimous do-not-proceed-as-written; all findings folded into plan R0–R11. This was formerly task 8.2b, correctly reordered to run first.
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
- [ ] 1.5 File one issue per non-conforming finding (`type/security`, `domain/engineering`, priority per sensitivity). **[R11] Each MUST carry the Phase 4 milestone AND ≥1 `*.tf` path in its body** (else `drain-labeled-backlog` — which queries `--milestone` and clusters by body paths — can never see it). Cross-link `Ref #6588` where in scope — **never `Closes`**.
- [ ] 1.5b **[R11] File the parent claim-unlock issue** "Encryption posture: zero user-data-bearing plaintext exceptions" (Phase 4 milestone, `Ref #6588`) with `inngest_redis`/`registry` as children; note that until it closes, external copy is constrained to the *verifiability* claim, never "encrypted by default from day one".
- [ ] 1.5c **[R9]** Before seeding `provider-managed` rows, `curl -sI` each of the ~7 attestation sources for public reachability; any behind a login routes to a bootstrap script (`hr-multi-step-post-merge-bootstrap-script`) or a named public substitute — do not assert "zero operator steps" for these.
- [ ] 1.6 Confirm no remediation was performed (`git diff` touches no existing `hcloud_volume` body). **AC25 stands — this PR remediates nothing.**

## Phase 2 — Layer A detector (RED first)

- [ ] 2.1 Write `scripts/lint-encryption-posture.test.sh` with fixtures TS-1..TS-8, **TS-15 (R1 false-PASS), TS-16 (R3 expired exception), TS-17 (R5 legal-doc join)**. **[R6: TS-9..TS-13 deleted — in-transit moves to Semgrep.]** Confirm RED.
- [ ] 2.2 Implement `scripts/lint-encryption-posture.py`: modes `--repo-sweep` (default), `--report`, `--check-templates` **[R10]**. **[R6: `--diff` mode deleted.]** Fail-closed on every indeterminate outcome. **[R8: offline + credential-free — no `gh api`.]** No bypass flag, no env escape, no comment suppression.
- [ ] 2.3 Implement `mechanism: luks` resolution **via `device_binding` [R1]** (resource address + `hcloud_volume_attachment` → host's cloud-init/bootstrap/**cutover** `cryptsetup` site → key resource + doppler_secret + `/dev/mapper/*` mount; resolve one level of `${VAR:-default}`; mapper names must match AFTER resolution). **Never a name-similarity join.**
- [ ] 2.4 **[R6: DELETED from this script]** — in-transit ban-list moves to `plugins/soleur/skills/review/references/semgrep-custom-rules.yaml` (`soleur.tls-cert-verification-defeated` + `soleur.postgres-sslmode-unverified`), single shared `references/encryption-posture-banlist.json`. Pre-adjudicate the Supabase pooler self-signed-chain exception with its own tracking issue.
- [ ] 2.4b **[R3]** Implement `expires_on` enforcement (≤90d, offline date arithmetic; expired ⇒ FAIL) and **[R5]** the `disclosed_as` legal-doc join (a `plaintext-exception`/`cert_verification: off` row whose `disclosed_as` resolves to text asserting encryption ⇒ FAIL). Delete `accepted_by`; delete the `does_not_defend` verbatim-restatement rejector (keep the field) **[R10]**.
- [ ] 2.5 Implement the **three-way** resource-type partition **[R7]**: `store_classes` (checked) / `non_store_types` (seeded from the 44-type inventory) / else ⇒ FAIL. Assert a `cloudflare_record` does NOT fail and a novel `*_bucket` DOES.
- [ ] 2.5b **[R8]** Compute the positive-work floor from a repo scan + committed expected-count constant + `non_iac_stores` list (NOT from the ledger row count). **[R9]** enforce `retrieved_on` 365-day max for `provider-managed` rows.
- [ ] 2.6 GREEN: all TS cases pass.
- [ ] 2.6b **Calibration against the real repo (AC33):** the detector must certify `hcloud_volume.git_data_luks` and `hcloud_volume.workspaces_luks` as `mechanism: luks` with all citations resolved. These two files are the detector's contract; a detector that cannot certify them is miscalibrated no matter how many synthetic fixtures pass.
- [ ] 2.7 Register `scripts/lint-encryption-posture.test.sh` in `scripts/test-all.sh`; confirm `bash scripts/lint-orphan-test-suites.sh` passes.
- [ ] 2.8 Run the mutation battery **MB-1..MB-5, MB-8..MB-12** (MB-6/MB-7 deleted with the in-transit engine — R6). Diff **per-case verdicts**, not suite pass-counts. Every mutation must red. Includes MB-10 = a `continue-on-error: true` on the CI job must still red the known-bad fixture PR **[R4]**.
- [ ] 2.9 Verify non-vacuity under `git clone --depth 1` — same verdict and store count as the full clone.
- [ ] 2.10 Verify the no-bypass behavioural matrix (AC10) **and the hermeticity invariant (R8: run with no network → identical verdict).**

## Phase 3 — Required-check promotion (**FIVE** coupled sites, one commit — R4)

- [ ] 3.0 `git grep -ln 'required-checks.txt\|required_status_checks\|required_check' -- scripts infra plugins .github` and pin the SSOT site list in the PR body; do not trust a count of 3.
- [ ] 3.1 Add the `encryption-posture` job to `.github/workflows/ci.yml`. Use its rendered check context (`.jobs.<key>.name` when present, else the key) as the canonical string.
- [ ] 3.2 **Read the `#6049` AUTO-FABRICATION GUARD header first. [R4] Arm B is CodeQL's shape: OMIT the name from `scripts/required-checks.txt` and pin a non-15368 `integration_id`** in the ruleset + canonical JSON (the two arms in the old task were contradictory). Record the arm in the PR body (AC14).
- [ ] 3.3 Update `scripts/ci-required-ruleset-canonical-required-status-checks.json` **[R4: the 4th site — `required-checks-canonical-parity.test.sh` asserts set-equality; skipping it reds AC30]**.
- [ ] 3.4 Add the `required_check` block to `infra/github/ruleset-ci-required.tf` **and amend the ABI-count comment**; context byte-identical to 3.1.
- [ ] 3.5 Assert equality across sites (1)(2)(3)(4) mechanically, and that the ABI-count comment == the `required_check` block count (AC13).

## Phase 4 — Layer B live reconciliation (**R2: measurable-only, Inngest-dispatch, Sentry plane**)

- [ ] 4.1 Implement `tests/scripts/lib/encryption-posture-reconcile.sh` (`--audit`, `--live`), modelled on `tests/scripts/lib/preapply-entrypoint-gate.sh`: default-deny, one fail-closed catch-all, a control probe. **[R2] Shell out to `python3 scripts/lint-encryption-posture.py --report --json` for ALL ledger parsing (single schema owner).** The positive-work floor counts only rows with `live_verification: available` (today: `workspaces_luks`); every `unavailable:<reason>` row carries its own tracking issue.
- [ ] 4.2 Make could-not-measure its own **aborting** class evaluated **before** the comparison; distinguishable in output from a clean pass. Issue filing is **find-or-update-by-title**, never a fresh P1 daily **[R2/arch F10]**.
- [ ] 4.3 Write `tests/scripts/test-encryption-posture-reconcile.sh` incl. the could-not-measure matrix (empty credential, HTTP 000, degraded 200 with empty body, zero-row log query). **[R10/AC28] Register in `scripts/test-all.sh` AND assert the registration (`grep -qE 'tests/scripts/test-encryption-posture-reconcile\.sh' scripts/test-all.sh`) — the orphan-linter only scans `scripts/*.test.sh`.**
- [ ] 4.4 **[R2] Inngest-dispatch hybrid — the `prefer-inngest` hook NEVER fires (no override needed):** write `apps/web-platform/server/inngest/functions/cron-encryption-posture-reconcile.ts` (owns the `0 6 * * *` schedule) that `workflow_dispatch`-es `.github/workflows/scheduled-encryption-posture-reconcile.yml` (`on: workflow_dispatch:` only). **No `<!-- gate-override -->` marker, no justification block, AC32 deleted.** Emits the heartbeat only on a positive-work clean pass; files find-or-update on divergence.
- [ ] 4.5 **[R2] Sentry plane, not Better Stack:** add a `sentry_cron_monitor` (slug `scheduled-encryption-posture-reconcile`) to `apps/web-platform/infra/sentry/cron-monitors.tf`, **count-gated behind the ADR-117 measure-then-arm gate**; `terraform plan` shows no create of an armed monitor. Confirm `sentry-monitor-iac-parity.test.ts` passes. **Do NOT add a `uptime-alerts.tf` Better Stack beat** (evades the parity test + diverges from `data-protection-disclosure.md` §(m)).
- [ ] 4.6 Write `scripts/followthroughs/encryption-posture-reconcile-soak-<issue>.sh` (3 consecutive green runs, `start=` pinned strictly after the deploy) + the tracker directive + the `follow-through` label; wire `secrets=BETTERSTACK_API_TOKEN_READONLY` **(read-only — R2/S2c)** into `.github/workflows/scheduled-followthrough-sweeper.yml` if needed.

## Phase 5 — Design-time gates

- [ ] 5.1 Add `## Encryption Posture` to all three templates in `plugins/soleur/skills/plan/references/plan-issue-templates.md`, immediately after `## Observability` in each.
- [ ] 5.2 Add `### 2.11. Encryption Posture Gate` to `plugins/soleur/skills/plan/SKILL.md` (after §2.10), mirroring §2.9's shape.
- [ ] 5.3 Add `### 4.10. Encryption Posture Halt (Conditional)` to `plugins/soleur/skills/deepen-plan/SKILL.md`, mirroring §4.7's four steps, with the full reject list (boilerplate ban-list, `does_not_defend` empty/restatement, exception without `tracking_issue`).
- [ ] 5.4 Verify §4.10 **behaviourally** against three fixture plans (compliant / boilerplate mechanism / exception without issue) — AC4.
- [ ] 5.4b **[R10]** Add `--check-templates` verification: the three `plan-issue-templates.md` blocks validate against `encryption-posture-ledger.schema.json` (closes the new template↔validator pair and is the generic harness `#4133` wants). **[R10] Add a Failure-Message Contract** to the plan/script: one operator-facing `FAIL: <what> → <exact next command/field>` line per reject branch; TS-2..TS-17 assert the classification **string**, not just the exit code.
- [ ] 5.5 Add `### Check <N>: Encryption Posture` to `plugins/soleur/skills/preflight/SKILL.md` (compute N via `grep -oE '^### Check [0-9]+' … | grep -oE '[0-9]+$' | sort -n | tail -1` **[R10 — file is NOT in numeric order]**) plus its §0.1 fast-path SKIP row. It **shells out to the Layer A script** (no duplicated PASS/FAIL prose contract). SKIP only for "I do not apply", never "I cannot prove it".
- [ ] 5.6 Add the defect-class entry + conditional `security-sentinel` spawn instruction to `plugins/soleur/skills/review/SKILL.md`.

## Phase 6 — Generation-side defaults

- [ ] 6.1 `plugins/soleur/agents/engineering/infra/terraform-architect.md` — Hetzner/Cloudflare section: no `hcloud_volume` encryption attribute; the four-part guest-side LUKS apparatus; the live-volume guard-inversion data-loss trap reproduced verbatim; encrypted by default, named justification otherwise.
- [ ] 6.2 `plugins/soleur/agents/engineering/infra/platform-strategist.md` — encryption posture as a first-class Decision Framework axis.
- [ ] 6.3 Add an "Encryption posture" step to **`provision-hetzner` + `provision-cloudflare` only** (`provision-doppler`/`provision-github` provision identities/repos, not data stores — a mandatory "N/A" step trains boilerplate; simplicity #8). Each: emit the ledger row for anything provisioned, refuse to complete without one.
- [ ] ~~6.4–6.7~~ **[R0] MOVED to the constraint-scaffold follow-up PR.** File that issue in THIS PR's body (Phase 4 milestone, `Ref #6588`) recording the four unresolved design questions from R0 (additive `--gate` emit; captured-baseline/grandfather for a green first run; non-blocking + founder-readable messages + `needs-a-migration` class; Hetzner reachable-verdict). Do NOT implement constraint-scaffold changes in this PR.

## Phase 7 — ADR, C4, docs, compliance

- [ ] 7.1 Write the ADR (ordinal per 0.6). If renumbered, sweep `grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/feat-one-shot-encryption-at-rest-in-transit-design-default/` in the same edit.
- [ ] 7.2 Edit `knowledge-base/engineering/architecture/diagrams/model.c4`: correct `workspacesVolume` element description (cite verify run `30040444418`) **AND the `hetzner -> workspacesVolume` relationship at model.c4:415, which still says "plaintext at rest … #6812" [R10/arch F9]**; add at-rest posture clauses to `inngestRedis`, `gitDataStore`, `sessionStore`, `zotRegistry` **from the audit's measured output**.
- [ ] 7.3 Edit `views.c4`: `include platform.infra.workspacesVolume` in the `containers` view.
- [ ] 7.4 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 7.5 Record the design-time-default principle in `knowledge-base/project/constitution.md`.
- [ ] 7.6 Run `/soleur:gdpr-gate` **inline** against the plan + diff (`wg-plan-prescribed-skills-must-run-inline`).
- [ ] 7.7 Post a note on `#4133` recording that a second template↔gate schema pair now exists.

## Phase 8 — Exit gate

- [ ] 8.1 `bash scripts/test-all.sh` — full-suite green.
- [ ] 8.2 Walk every AC; record the verification command and its output. **[R0] AC20/AC21/AC32 are deleted; [R1] AC33 verified via the `device_binding` join; new ACs cover TS-15/16/17, MB-8..MB-12, the five-site coupling, the Sentry parity test, and the hermeticity invariant.**
- [x] 8.2b **DONE — moved to task 0.0** (plan-review ran with the full escalated panel before Phase 1).
- [ ] 8.3 Confirm the PR body has no `Closes #6588`, lists audit findings as `Ref #N`, pins both budget measurements, **and links the constraint-scaffold follow-up issue + the parent claim-unlock issue [R0/R11]**.

## Completion status (2026-07-24)

**Shipped in this PR (#6885):** Phase 0 (preconditions verified) · Phase 1 (ledger schema + code-sourced audit + seeded ledger, 14 stores/3 connections, sweep green; findings filed #6893-#6897) · Phase 2 (Layer A detector, 35/35 + MB-1..12, independently re-verified) · Phase 3 partial (detector wired as an ADVISORY ci.yml step) · Phase 5 (design-time gates) · Phase 6 (generation-side, R0-narrowed to hetzner/cloudflare + R6 Semgrep) · Phase 7 (ADR-140, C4, constitution pointer).

**Deferred to tracked follow-ups (reviewer-endorsed splits):**
- Required-check PROMOTION (the 5-site coupling, D7/R4) -> **#6901** (measure-then-arm per arch F4; detector runs advisory now).
- Layer B live reconcile (Phase 4, R2) -> **#6902** (Inngest-dispatch + Sentry; needs per-volume probes first — measures only 1 of 6 volumes today).
- constraint-scaffold user-facing gate (deliverable 6, R0) -> its own product-framed PR (CPO F3/F5, spec-flow #8-#14).

**Exit gate:** `bash scripts/test-all.sh scripts` -> 213/213 pass. components.test.ts 1289 pass. c4 23/23 + freshness. Semgrep validated.
