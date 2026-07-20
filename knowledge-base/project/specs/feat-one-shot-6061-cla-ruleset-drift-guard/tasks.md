# Tasks — feat: CLA Required ruleset drift guard (#6061)

Plan: `knowledge-base/project/plans/2026-07-05-feat-cla-required-ruleset-drift-guard-plan.md`
Lane: cross-domain · Brand-survival threshold: aggregate pattern

## Phase 0 — Preconditions (verify)

- [x] 0.1 Confirm CLA ruleset identity from `scripts/create-cla-required-ruleset.sh`
  (name "CLA Required"; RSC cla-check/cla-evidence @ 15368; bypass OrgAdmin/pull_request,
  RepoRole:5/pull_request, Integration:1236702/always).
- [x] 0.2 Confirm `cla-check` (cla.yml) + `cla-evidence` (cla-evidence.yml) producers exist.
- [x] 0.3 Prove DC-1 premise: `git grep -n 'audit-ruleset-bypass\.sh' -- .github/workflows apps/web-platform/server`
  returns no invocation; no `scheduled-ruleset-bypass-audit.yml`; cron `13 6 * * *` is the daily path. Record grep in PR body.

## Phase 1 — Mint CLA canonicals (create)

- [x] 1.1 Create `scripts/ci-cla-required-ruleset-canonical-required-status-checks.json` (2 contexts, sorted, both 15368).
- [x] 1.2 Create `scripts/ci-cla-required-ruleset-canonical-bypass-actors.json` (3 actors == create-script inline).

## Phase 2 — TS Inngest audit (paging fix) [write failing tests first]

- [x] 2.1 Add CLA constants + a `RulesetAuditConfig` object (name, both canonical paths, drift title, sourceHint) — one config threaded, not 4 separate params.
- [x] 2.2 Reuse `buildFindings` unchanged (no `buildRscFindings`); do NOT widen `AuditFinding.kind`.
- [x] 2.3 Extract `auditOneRuleset(octokit, config)` returning `{findings, criticalCount, guardBroken}`; route CI through it too (both inherit read-time canonical validation — fixes latent CI hole). Parameterize findOpen/file/close/render by config.
- [x] 2.4 ONE try/catch around the whole audit body (both fetchCanonicalJson + shape validation + fetchRulesetDetail + buildFindings). Real drift (incl. RSC-rule-missing signalled as `requiredStatusChecks: null`) → critical finding → files issue. Guard fault (corrupt/empty canonical, token scope, network) → `guardBroken=true` → reportSilentFallback(Sentry) + ok=false, NO drift issue. Separate `step.run` per ruleset.
- [x] 2.5 Handler: `ok = (sum criticalCount === 0) && !anyGuardBroken`; top-level scalars = sums; per-ruleset detail under ci/cla.
- [x] 2.6 Test: source anchors ("CLA Required", both canonical paths, CLA title).
- [x] 2.7 Test: pure-fn cases (dropped cla-evidence; widened bypass; enforcement disabled; green).
- [x] 2.8 Test: MANDATORY Octokit-mocked handler test — CLA-only critical ⇒ ok=false + files only CLA issue + CI untouched; CLA-green ⇒ closes only CLA issue; empty canonical ⇒ guardBroken (ok=false + reportSilentFallback, NO issue filed).

## Phase 3 — Parity test rewire

- [x] 3.1 Derive `CLA_EXCLUDE` from RSC canonical via `jq -e`; `>=2` non-empty guard; `assert_file_exists`.
- [x] 3.2 Add Test 7 (SSOT CLA subset == CLA canonical, ⊆ and ⊇, non-vacuous); exact header anchor `^#…CLA Required ruleset$`, bound to next header/EOF; no CLA_EXCLUDE filter in the Test-7 parser.
- [x] 3.3 Rewrite comment block (25-36) to the resolved 3-dimension state; reference #6061.

## Phase 4 — CLA canonical↔SSOT sync gates (tests/scripts/test-audit-ruleset-bypass.sh)

- [x] 4.1 T-cla-1: RSC canonical `(context,integration_id)` pairs == create-script inline + no-dup contexts; pin `$payload` + `<< 'EOF'` sentinel; `jq -e .` slice first.
- [x] 4.2 T-cla-1b: bypass canonical triples == create-script inline + no-dup rows.
- [x] 4.3 (Shape/count folded into 4.1/4.2 + the jq-shape AC; no standalone T-cla-2.)
- [x] 4.4 Register in dispatch list; do NOT touch T19.

## Phase 5 — Docs / metadata

- [x] 5.1 `routine-metadata.ts:81` — description names both rulesets + both dimensions.
- [x] 5.2 `ruleset-bypass-drift.md` — CLA triage subsection incl. contributor-signature-chase remedy.
- [x] 5.3 `required-checks.txt` header comment — add `cla-evidence`.

## Phase 6 — Deferred (tracked)

- [x] 6.1 File tracking issue: Terraform-ify CLA ruleset (`ruleset-cla-required.tf`); verify label via `gh label list`. → **#6072** (`type/chore` + `domain/engineering`, milestone Post-MVP / Later).

## Phase 7 — Verify / ship

- [x] Run full suite: `bash tests/scripts/test-audit-ruleset-bypass.sh`, `bash plugins/soleur/test/required-checks-canonical-parity.test.sh`, vitest (cron audit + registry-count), `tsc --noEmit`.
- [x] Confirm all Acceptance Criteria (pre-merge) pass.
- [x] decision-challenges.md (DC-1 + DC-2) surfaced in PR body via ship.
