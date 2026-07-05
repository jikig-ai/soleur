# Tasks — feat: CLA Required ruleset drift guard (#6061)

Plan: `knowledge-base/project/plans/2026-07-05-feat-cla-required-ruleset-drift-guard-plan.md`
Lane: cross-domain · Brand-survival threshold: aggregate pattern

## Phase 0 — Preconditions (verify)

- [ ] 0.1 Confirm CLA ruleset identity from `scripts/create-cla-required-ruleset.sh`
  (name "CLA Required"; RSC cla-check/cla-evidence @ 15368; bypass OrgAdmin/pull_request,
  RepoRole:5/pull_request, Integration:1236702/always).
- [ ] 0.2 Confirm `cla-check` (cla.yml) + `cla-evidence` (cla-evidence.yml) producers exist.
- [ ] 0.3 Prove DC-1 premise: `git grep -n 'audit-ruleset-bypass\.sh' -- .github/workflows apps/web-platform/server`
  returns no invocation; no `scheduled-ruleset-bypass-audit.yml`; cron `13 6 * * *` is the daily path. Record grep in PR body.

## Phase 1 — Mint CLA canonicals (create)

- [ ] 1.1 Create `scripts/ci-cla-required-ruleset-canonical-required-status-checks.json` (2 contexts, sorted, both 15368).
- [ ] 1.2 Create `scripts/ci-cla-required-ruleset-canonical-bypass-actors.json` (3 actors == create-script inline).

## Phase 2 — TS Inngest audit (paging fix) [write failing tests first]

- [ ] 2.1 Add CLA constants (names, both canonical paths, CLA drift title).
- [ ] 2.2 Reuse `buildFindings` unchanged (no `buildRscFindings`).
- [ ] 2.3 Extract `auditOneRuleset(...)`; parameterize findOpen/file/close/render by driftTitle + sourceHint; add read-time canonical validation (empty/corrupt → guard-broken, not green).
- [ ] 2.4 Per-ruleset `step.run` isolation + per-step try/catch; convert "RSC rule missing" throw → critical finding; "bypass missing" throw → guard-broken.
- [ ] 2.5 Handler: `ok = (ciCriticalCount + claCriticalCount) === 0`; deterministic per-ruleset return breakdown; heartbeat degrades if either critical.
- [ ] 2.6 Test: source anchors ("CLA Required", both canonical paths, CLA title).
- [ ] 2.7 Test: pure-fn cases (dropped cla-evidence; widened bypass; enforcement disabled; green).
- [ ] 2.8 Test: MANDATORY Octokit-mocked handler test (CLA-only critical ⇒ ok=false + files only CLA issue + CI untouched; CLA-green ⇒ closes only CLA issue; empty canonical ⇒ guard-broken + ok=false).

## Phase 3 — Parity test rewire

- [ ] 3.1 Derive `CLA_EXCLUDE` from RSC canonical via `jq -e`; `>=2` non-empty guard; `assert_file_exists`.
- [ ] 3.2 Add Test 7 (SSOT CLA subset == CLA canonical, ⊆ and ⊇, non-vacuous); exact header anchor `^#…CLA Required ruleset$`, bound to next header/EOF; no CLA_EXCLUDE filter in the Test-7 parser.
- [ ] 3.3 Rewrite comment block (25-36) to the resolved 3-dimension state; reference #6061.

## Phase 4 — CLA canonical↔SSOT sync gates (tests/scripts/test-audit-ruleset-bypass.sh)

- [ ] 4.1 T-cla-1: RSC canonical `(context,integration_id)` pairs == create-script inline; pin `$payload` + `<< 'EOF'` sentinel; `jq -e .` slice first.
- [ ] 4.2 T-cla-1b: bypass canonical triples == create-script inline.
- [ ] 4.3 T-cla-2: shape/count guards (RSC 2 entries; bypass 3 entries).
- [ ] 4.4 Register in dispatch list; do NOT touch T19.

## Phase 5 — Docs / metadata

- [ ] 5.1 `routine-metadata.ts:81` — description names both rulesets + both dimensions.
- [ ] 5.2 `ruleset-bypass-drift.md` — CLA triage subsection incl. contributor-signature-chase remedy.
- [ ] 5.3 `required-checks.txt` header comment — add `cla-evidence`.

## Phase 6 — Deferred (tracked)

- [ ] 6.1 File tracking issue: Terraform-ify CLA ruleset (`ruleset-cla-required.tf`); verify label via `gh label list`.

## Phase 7 — Verify / ship

- [ ] Run full suite: `bash tests/scripts/test-audit-ruleset-bypass.sh`, `bash plugins/soleur/test/required-checks-canonical-parity.test.sh`, vitest (cron audit + registry-count), `tsc --noEmit`.
- [ ] Confirm all Acceptance Criteria (pre-merge) pass.
- [ ] decision-challenges.md (DC-1 + DC-2) surfaced in PR body via ship.
