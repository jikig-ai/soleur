# Tasks — fix: two CI guards that structurally cannot fail (#6766, #6774)

Plan: `knowledge-base/project/plans/2026-07-20-fix-ci-guards-that-cannot-fail-plan.md`
Lane: `cross-domain` (no spec.md — TR2 fail-closed default)
Threshold: `single-user incident` → `requires_cpo_signoff: true`, `user-impact-reviewer` at review.

> **Delivery is TWO PRs.** PR A = workflow routing + all of #6774 + ADR. PR B = ruleset
> flip + drift detector, after an empirical gate. Do not collapse them — §Delivery shape.

---

## Phase 0 — Preconditions (PR A, before any edit)

- [ ] 0.1 Deadlock premise holds on main: `git show origin/main:.github/workflows/infra-validation.yml | awk '/^on:/{f=1} f{print} /^jobs:/{exit}'` → `pull_request:` with `paths:`, no `push:`
- [ ] 0.2 Merge-queue-off: `grep -vE '^[[:space:]]*#' infra/github/ruleset-ci-required.tf | grep -cE 'merge_queue[[:space:]]*\{'` → `0`
- [ ] 0.3 Context baseline: `jq length scripts/ci-required-ruleset-canonical-required-status-checks.json` → `20`
- [ ] 0.4 `yaml` importable in bun shard: `grep -n '"yaml"' package.json`
- [ ] 0.5 Read the verdict-script precedent: `scripts/tenant-integration-gate-verdict.sh` + `tests/scripts/test-tenant-integration-gate-verdict.sh`
- [ ] 0.6 Marker precondition: `git grep -lF SOLEUR_WORKSPACES_LUKS_FSCK -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'` → non-empty
- [ ] 0.7 Baseline all four perturbed suites green (see plan Phase 0.7)

## Phase 1 — RED: workflow-routing tests (PR A)

- [ ] 1.1 `plugins/soleur/test/infra-validation-detect.test.sh` — add `detect_event_route()`
  - [ ] 1.1.1 case `pull_request` → diff branch (T2)
  - [ ] 1.1.2 case `workflow_dispatch` → enumerate-all (T3)
  - [ ] 1.1.3 case `push` → enumerate-all, never `origin/...HEAD` (T1)
  - [ ] 1.1.4 case `merge_group` → `[]` + `suite_relevant=false`, never a diff (T19)
- [ ] 1.2 Add `detect_suite_relevant()` mirror
  - [ ] 1.2.1 `restart-inngest-server.yml`-only diff → `true` (T4 — the R3 under-trigger trap)
  - [ ] 1.2.2 docs-only diff → `false` (T5)
- [ ] 1.3 New `tests/scripts/test-infra-validate-gate-verdict.sh` (T13–T17), modelled on `tests/scripts/test-tenant-integration-gate-verdict.sh`
  - Signature under test: `infra-validate-gate-verdict.sh <detect_result> <validate_result> <deploy_result> <directories> <suite_relevant>` (5 args — the precedent takes 2; see plan §Research Insights for the 6-row allow-list table)
  - [ ] 1.3.1 **T14 is load-bearing**: `dirs='[]' suite_relevant=true deploy=failure` ⇒ FAIL
  - [ ] 1.3.2 T17: unenumerated state (e.g. `cancelled`) ⇒ FAIL (allow-list, fail-closed)
  - [ ] 1.3.3 `detect ≠ success` ⇒ FAIL — inherited from the precedent; doubles as the second defence for unrouted `merge_group` (F3)
  - [ ] 1.3.4 Empty-string arg ⇒ FAIL (precedent covers this explicitly)
- [ ] 1.4 Register the new suite via `run_suite` in `scripts/test-all.sh` (`tests/scripts/*.sh` is NOT globbed)

## Phase 2 — GREEN: detect-changes routing + suite_relevant (PR A)

- [ ] 2.1 Add `suite_relevant` to `detect-changes` `outputs:`
- [ ] 2.2 Event routing, **`merge_group` as the first branch**; then `workflow_dispatch`/`push` → enumerate-all; else diff. Keep the `{ grep -E … || true; }` brace group and the `#4012` comment
- [ ] 2.3 Compute `suite_relevant` from the full `paths:` union; `true` on push/dispatch, `false` on merge_group. **Move the paths rationale comments in verbatim**

## Phase 3 — GREEN: triggers, gating, concurrency, aggregator (PR A)

- [ ] 3.1 `on:` — `+push: branches: [main]`, `+merge_group:`, `pull_request: branches: [main]`, **remove `paths:`**; leave a comment pointing at `detect-changes` + #6480
- [ ] 3.2 Workflow-level `concurrency:` group + `cancel-in-progress: true` + rationale (F7)
- [ ] 3.3 Gate `deploy-script-tests` on `suite_relevant`; leave `check-secrets` **ungated** (F8)
- [ ] 3.4 `plan` job — add `github.event_name == 'pull_request'` to its `if:`
- [ ] 3.5 Create `scripts/infra-validate-gate-verdict.sh` — 5 positional args, fail-closed allow-list per the plan's §Research Insights table, `chmod +x`, mirroring `scripts/tenant-integration-gate-verdict.sh` (loud `::error::` on every unenumerated combination incl. empty string). Have `infra-validate-required` delegate to it, **replacing** the inline early-`exit 0` step (F1). Add `deploy-script-tests` to its `needs:`. Update the stale "DO NOT make this required yet" comment

## Phase 5 — RED: kind fixtures + tests (PR A)

- [ ] 5.1 Create 8 synthetic fixtures (`issue: 9999`) in `plugins/soleur/test/fixtures/preflight-check-10/`: `09-run-log-pass`, `10-run-log-no-marker`, `11-run-log-marker-absent`, `12-unknown-kind`, `13-run-log-ssh`, `14-run-log-command-lacks-marker`, `15-form-b-kind-token`, `16-marker-without-run-log`
- [ ] 5.2 Add a `test(...)` call site per fixture (T8–T11, T18, T20–T22) — **fixtures are loaded by hardcoded filename; an unreferenced one is dead**
- [ ] 5.3 Regression test: a fixture with no `kind:` classifies identically to pre-change (T12, guardrail 1)

## Phase 6 — GREEN: implement kind (PR A)

- [ ] 6.1 `plugins/soleur/test/lib/discoverability-test-parser.ts`
  - [ ] 6.1.1 Split `rejectReason` → `sshRejectReason` (**always**) + `substRejectReason` (live-probe only) (F2)
  - [ ] 6.1.2 Add `parseKind` / `parseMarker` as siblings (no struct refactor)
  - [ ] 6.1.3 Widen `ClassifyInput` with `markerLookup: (marker: string) => boolean` (F4a)
  - [ ] 6.1.4 Widen `ClassificationResult` with `marker?: string`
  - [ ] 6.1.5 Order: sshReject → kind resolution + guardrails 2–7 → substReject (live-probe only) → runner
  - [ ] 6.1.6 SKIP `reason` contains `run-log` + the marker literal
- [ ] 6.2 `plugins/soleur/skills/preflight/SKILL.md` Check 10
  - [ ] 6.2.1 Step 10.4b **after** the 10.4 ssh reject, **before** the 10.5 subst reject
  - [ ] 6.2.2 Guardrail 4 shell form uses `git grep -F` with the `':!knowledge-base/project/plans'` / `specs` exclusions — **not** a grep of `preflight-diff-files.txt` (F4b/F4c)
  - [ ] 6.2.3 Matrix rows 9–12 + updated Result block; cite the skip-vs-fail-defaults learning
  - [ ] 6.2.4 Do NOT touch `SENSITIVE_PATH_RE`, the ssh regex string, `Form A`/`Form B`, or the fast-path SKIP row
  - [ ] 6.2.5 Update the 3 stale "8 states / 8 fixtures" anchors here (F9)

## Phase 7 — GREEN: propagate the schema (PR A)

- [ ] 7.1 `plan-issue-templates.md` — `kind:`/`marker:` as **indented** sub-fields in all 3 blocks (`:36`, `:164`, `:306`)
- [ ] 7.2 `plan/SKILL.md` §2.9 — trailing **comment** only
- [ ] 7.3 `deepen-plan/SKILL.md` §4.7 — guardrail 2/3/6/7 reject bullets; keep `the 5 required top-level fields` verbatim
- [ ] 7.4 `deepen-plan.workflow.js` `:83-84`, `:236` — manual prose sync
- [ ] 7.5 `observability-coverage-reviewer.md` `:106-108` — kind note
- [ ] 7.6 Update the LUKS/fsck plan's Observability block: `kind: run-log`, `marker:`, fix the `>-` scalar, command names the marker
- [ ] 7.7 Update the remaining 2 stale-count anchors in the parser header + test `describe` (F9)

## Phase 8 — ADR, deferral, docs (PR A)

- [ ] 8.1 Write ADR-130 via `/soleur:architecture` (both clauses + the job-vs-step `continue-on-error` caveat; directions 1 and 3 in Alternatives Considered)
- [ ] 8.2 File the follow-through-enrollment deferral issue (labels `chore`, `priority/p3-low`)
- [ ] 8.3 CHANGELOG entry
- [ ] 8.4 PR A body: `Closes #6774`, `Ref #6766`, `Ref #6480`

## Phase 9 — PR A verification (AC1–AC14, AC20–AC23)

- [ ] 9.1 `actionlint .github/workflows/infra-validation.yml` → exit 0 (AC21)
- [ ] 9.2 `bash scripts/test-all.sh` full suite green (AC22)
- [ ] 9.3 Walk every AC in the plan's "Pre-merge — PR A" block

## Phase 10 — Inter-PR gate (after PR A merges)

- [ ] 10.1 AC24 — open a docs-only PR; `gh pr checks <N> --json name,state` shows `infra-validate-required` in a **terminal** state
- [ ] 10.2 AC25 — `gh run list --workflow=infra-validation.yml --branch=main --limit 5 --json event,conclusion` shows an `event: push` row
- [ ] 10.3 **Do not start Phase 4 until both pass.**

## Phase 4 — Ruleset flip + drift detector (PR B)

- [ ] 4.1 `infra/github/ruleset-ci-required.tf` — `+required_check { context = "infra-validate-required" … }`; fix the stale "19 context strings" comment
- [ ] 4.2 `scripts/ci-required-ruleset-canonical-required-status-checks.json` — matching entry (T-rsc-9)
- [ ] 4.3 `tests/scripts/test-audit-ruleset-bypass.sh` — T-rsc-7 literal `"20"` → `"21"`
- [ ] 4.4 `scripts/required-checks.txt` — add the line **with the #6049 `ALLOWED_PATHS` justification comment** (CODEOWNERS @deruelle)
- [ ] 4.5 New `plugins/soleur/test/required-job-suffix-parity.test.ts` (**bun** shard)
  - [ ] 4.5.1 Membership across all 3 surfaces (T6)
  - [ ] 4.5.2 Postability: no `pull_request.paths:`, `merge_group:` present (T7b, F6)
  - [ ] 4.5.3 Non-vacuity floor `≥3` jobs; **no exemption allowlist**
  - [ ] 4.5.4 Mutation controls T7 + T7b
- [ ] 4.6 Walk AC15–AC19; PR B body: `Closes #6766`, `Closes #6480`

## Phase 11 — PR B post-merge (automatable via `gh`, run in `/ship`)

- [ ] 11.1 AC26 — `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '[.rules[].parameters.required_status_checks[].context] '` → 21 entries including `infra-validate-required`
- [ ] 11.2 AC27 — next PR shows `infra-validate-required` as a posted check
- [ ] 11.3 Close #6766 and #6480 if not auto-closed; verify #6774 closed by PR A
