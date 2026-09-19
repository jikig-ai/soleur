---
title: "fix(ci): bring apply-web-platform-infra.yml under GitHub's 500 KB workflow-file limit and gate the size in CI"
type: fix
date: 2026-09-19
slug: fix-ci-workflow-file-size-limit
branch: feat-one-shot-8361-workflow-size-limit
issue: 8361
closes: 8361
priority: p1
domain: engineering
brand_survival_threshold: none
detail_level: minimal
lane: cross-domain
---

# fix(ci): bring `apply-web-platform-infra.yml` under GitHub's 500 KB workflow-file limit and gate the size in CI

## Overview

`.github/workflows/apply-web-platform-infra.yml` is 513,306 bytes at `f64b0ebc2`, above GitHub's 512,000-byte per-workflow-file ceiling ([docs](https://docs.github.com/en/actions/reference/limits)), so every run since that commit is a `startup_failure` with zero jobs and the merge-triggered apply on `main` is dead (runs 35431689935 / 35431766054 / 35431779524). The last green run, 35431644262, was at 510,313 bytes. This blocks the operator-authorized #8294 inngest-host-replace dispatch.

This plan (1) shrinks the file with **no behavior change** by relocating the longest job-header comment essays into one runbook, leaving a one-line pointer plus any comment line a test anchors on; and (2) adds a byte-size gate test so no `.github/workflows/*.yml` can cross 490,000 bytes again without a red suite naming the file and the overage.

Comments are 246,482 of the 513,307 bytes (3,024 comment-only lines in 404 contiguous blocks). The file needs to lose at least 23,307 bytes; the target is **≤ 480,000** (10 KB under the gate, 32 KB under GitHub). Headroom justification: the next-largest workflow is 162 KB, so the gate only ever bites this file; the file grew 495,981 → 513,306 bytes over its last 12 commits (`git log -n 12 -- <file>` + `git show <sha>:<file> | wc -c`), ~1.5 KB/commit on average and ~3 KB on the last three, so the 22 KB from 490,000 down to the ~468 K the reserve reaches buys roughly 7–15 commits of the growth class that caused #8361.

**No prod dispatch from this fix.** The workflow's YAML, jobs, steps, `run:` bodies, `if:` predicates and inputs are byte-identical apart from removed/replaced comment lines; `git diff -w` filtered to non-comment lines must be empty (AC3).

## Research Insights

**Premise validation (Phase 0.6).** #8361 is OPEN (`priority/p1-high`, milestone `Phase 4: Validate + Scale`, no closing PR). #8294 is OPEN. The file is 513,306 bytes on this branch (`wc -c`), last touched by `f64b0ebc2` (+40/-4 lines, all comment prose plus one `fetch-depth: 0` and one interlock step). ADR grep for the mechanism (`workflow.*size`, `512.000`, `500 KB`) hits only ADR-217 (unrelated: deploy-fires-on-CI-completion). No ADR rejects "relocate comments to a runbook" or "byte-size gate"; ADR-116 (content-anchored citations) and ADR-152 (strip rationale comments from injected scripts at render time, leaving pointers) are the nearest precedents and both support the shape.

**Property list (Phase 0.6b).**
- P1: `apply-web-platform-infra.yml` parses and runs on GitHub (size ≤ 512,000 bytes) with identical behavior.
- P2: Every test suite that greps the workflow for a comment anchor stays green.
- P3: A future comment-prose addition that would cross GitHub's limit is refused by CI before merge, naming the file and the overage.
- P4: The relocated rationale remains findable (same prose, one pointer from the workflow).

**Cut list.** Nothing to cut. Functional-discovery (grep over `plugins/soleur/test/`, `scripts/`, `tests/`, `.claude/hooks/`, `.github/workflows/` for `statSync(`, `wc -c`, `512000`, `500 KB`, `workflow.*(limit|size)`) found **no existing workflow-size check**, and actionlint's `docs/checks.md` has no file-size check, so P3 needs the new test. `scripts/lint-skill-body-budget.py` and `scripts/lint-agents-rule-budget.py` are the sibling byte-budget shapes (warn/reject tiers; fail-closed on zero files scanned) and `plugins/soleur/test/cloud-init-user-data-size.test.ts` is the sibling bun test.

**Which comment lines are asserted by tests (the load-bearing finding).** 86 files under `tests/`, `plugins/soleur/test/`, `apps/web-platform/infra/*.test.sh`, `apps/web-platform/test/`, `scripts/` reference the workflow; 49 are runnable suites (list in AC5). A plan-time cross-reference (scratch script `anchors_v3.py`: every ≥8-char string literal and every regex literal from those 86 files, comment lines of the test sources stripped, matched against each of the 3,024 comment lines, keeping only anchors that do NOT also match a non-comment line of the workflow, and dropping structural patterns matching >12 comment lines) finds **116 comment lines carrying an exclusive test anchor**. Three anchor classes recur; they are how the table's **Keep** column was derived (provenance, not a rule the implementer re-applies — AC5 is the gate):
- (a) a comment line that **names a test file** (`terraform-target-parity.test.ts` at L1583/L418/L24/L6293/L1314/L584, `web-probe-envwrite.sh` at L4979) — `terraform-target-parity.test.ts` asserts "the workflow points a reader at what asserts this gate" from the step's own comment header (`armStepWithHeader`, which walks back over `^ {6}#` lines from `- name: Arm web-host probe heartbeats`);
- (b) a comment line matching the budget-arithmetic regex `^\s*#.*\+.*=\s*\d+ min\b` (L454, L1603, L3567 — the test asserts ≥ 3 matches and the `= 47 min` value; L1603 sits inside `notify-apply-failure` after the job key, outside every moved block) asserted by `terraform-target-parity.test.ts`;
- (c) a comment line quoting a resource address, IP, path or shell fragment that a suite greps for anywhere in the file and that occurs nowhere else in the workflow (e.g. `10.0.1.20` L4217, `hcloud_server.git_data.id` L6081, `TF_VAR_ci_ssh_private_key` L6948, `cf-tunnel-ssh-bridge/action.yml` L6949, `# removed` L6569, `contents:read` L5887).

Kieran's independent cross-reference at plan-review (49 suites × every comment line of blocks 1–10) found no assertion reading a moved comment line beyond the Keep column; the only comment-reading assertions in the corpus are `armStepWithHeader` (walks `^ {6}#` above `Arm web-host probe heartbeats`, in no block) and the budget regex at `terraform-target-parity.test.ts` (matches L454, L1603, L3567 — L3567 is kept, the others are outside the moved blocks). Count assertions (`grep -c` / `.length).toBe(N)`) are the class the cross-reference structurally excludes (it drops anchors that also match non-comment lines); spec-flow checked every count assertion in the suites (`^\s*group:`, `CRANE_SHA256=`, `inngest_host_shape_gate`, the rung-2 TRANSIENT phrases) and all are line-anchored or comment-stripped first, so an AC5 red is a new exclusive anchor, not a count drift. Blocks to leave untouched because they are densely anchored: the file header (L1–L65, 4 anchors, read as "the workflow's header" by `terraform-target-parity.test.ts`) and the `apply` job's `BUDGET, RE-DERIVED (#7587, corrected #7657)` block (L400–L459, 7 anchors incl. `the ARM step`, `measurements.md`, `post-gate`).

Behavior-visible prose is out of scope: the single `GITHUB_STEP_SUMMARY` heredoc (L5930–L6004, 4,919 bytes, the `git_data_birth_disclosure` "### 1./2./3." disclosure the approver reads) stays.

**Line-number citations.** 277 `apply-web-platform-infra.yml:NNN` citations exist repo-wide; the four inside test files (`stock-preflight-coverage.test.ts:35`, `check-cloudflare-token-drift.test.sh:1806`, `registry-host-replace-gate.sh:42`, `test-stock-preflight-gate.sh:135`) are comments, not assertions (`W7_PERFILE_EXPECTED` counts `uses:` lines, not comments). Line numbers inside the workflow's own comments (e.g. `(:5148)`) will drift; that is the rot ADR-116 already accepts and not a behavior change.

**Runbook constraints.** `knowledge-base/engineering/operations/runbooks/` is a `SCAN_DIRS` root of `scripts/lint-infra-no-human-steps.py` (CI runs it `--changed`), which flags a human-actor token co-occurring with an infra imperative on the same or adjacent line. Relocated prose that reads "the operator … apply/dispatch" may trip it in the runbook even though it never did in the workflow (the linter does not scan `.github/`). 28 of 76 runbooks have no frontmatter; `scripts/generate-kb-index.sh` regenerates `INDEX.md`, `kb-tags.txt`, `kb-categories.txt` and CI's AC17 runs it `--check`.

**Test runner.** `scripts/test-all.sh` runs `bun test plugins/soleur/` (line 2682), so a new `plugins/soleur/test/*.test.ts` is auto-discovered; sibling tests resolve `REPO_ROOT = resolve(import.meta.dir, "../../..")`.

**Learnings applied.** ADR-116 (content anchors, not line numbers); `2026-04-18-agents-md-byte-budget-and-why-compression.md` (byte budget measured with `wc -c`, threshold above the growth tail); ADR-152 (relocate rationale, leave pointer); `2026-07-28-my-ac-verified-four-paths-while-ci-verified-five.md` (an AC that claims a gate is green must run the gate's own invocation); `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` (mutation matrix before the guard).

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Open Code-Review Overlap

None — no open `code-review` issue body (65 checked) names `.github/workflows/apply-web-platform-infra.yml`, the new test path or the new runbook path.

## Implementation

### Files to Create

- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` — one `## <job_id>` section per relocated block (heading is the job id verbatim so `§<job_id>` is an exact anchor; step-level blocks use `## <job_id>/<step name>` — block 7 is `## apply/Measure the apex origin (ADR-194 Hypothesis Z)` — and a block under `on.workflow_dispatch.inputs` would use `## workflow_dispatch.inputs`), whose first paragraph is the block's original first comment line, then the prose verbatim with the `# ` prefix stripped. Minimal frontmatter (`title`, `date`, `related_issues: [8361]`) so `generate-kb-index.sh` picks up the title. A one-paragraph preamble stating the file exists because of GitHub's 512,000-byte workflow limit and that each section is the design rationale of the named job, and that the workflow's pointer line is the anchor to grep for.
- `plugins/soleur/test/workflow-file-size.test.ts` — the byte-size gate (see Guard 1).

### Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — comment lines only.
- `knowledge-base/INDEX.md`, `knowledge-base/kb-tags.txt`, `knowledge-base/kb-categories.txt` — regenerated by `bash scripts/generate-kb-index.sh`.

### Steps

1. **Write the gate test first (RED).** `plugins/soleur/test/workflow-file-size.test.ts`, per Guard 1. It is red on this branch (513,306 > 490,000) and names `apply-web-platform-infra.yml` with overage `23306`.
2. **Relocate comment blocks in ranked order until `wc -c` ≤ 480,000.** Ranked by bytes, all are job-level or step-level YAML comment headers (not `run:` bodies). Line numbers are as of `f64b0ebc2` for locating only; the **content anchor** is the block's first line. For each block: copy the whole block to the runbook section; in the workflow keep (i) the first line, (ii) every line in the block's **Keep** column (derived at plan time from the test-anchor cross-reference; AC5 is the gate — if a suite reds on a moved line, restore the line, never edit the test), and (iii) add one pointer line directly under the first line: `# Rationale: knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md §<job_id>` (same `§` form as the runbook heading for step-level blocks).

   | # | Block (first line = content anchor) | Precedes | Bytes | Keep (besides first line + pointer) | Net after |
   |---|---|---|---|---|---|
   | 1 | `# --- #7586: a non-green apply run reaches a channel ---` (L1488–L1586) | `notify-apply-failure:` | 7,908 | L1582–L1583 (the `describe("apply-web-platform-infra has a failure channel")` sentence naming `terraform-target-parity.test.ts`) | ~505.7 K |
   | 2 | `# #7542 — deliver a \`vector.toml\` change to web-1 WITHOUT riding unrelated pending drift.` (L6899–L6963) | `vector_redeliver:` | 5,763 | L6924 (`hcloud_ssh_key.default`, `hcloud_placement_group.web_spread`), L6948–L6949 (`TF_VAR_ci_ssh_private_key`, `cf-tunnel-ssh-bridge/action.yml`), L6963 (`teardown`) | ~500.5 K |
   | 3 | `# ── #6977 — the git-data BIRTH path ──` (L6017–L6083, under `git_data_host_create:`) | `if: github.event_name == 'workflow_dispatch' && inputs.a…` | 4,904 | L6053–L6056 (the quoted `grep -vE '^[[:space:]]*#' apps/web-platform/infra/cloud-init-git-data.yml` command with its `#` framing lines); L6081 (`hcloud_server.git_data.id`) | ~496.1 K |
   | 4 | `# Selected by \`-f apply_target=web-host-create -f web_host_key=<key>\` (#6730, ADR-145).` (L4947–L5001) | `web_host_create:` | 4,297 | L4979 (`web-probe-envwrite.sh`) | ~492.0 K |
   | 5 | `# Selected by \`-f apply_target=registry-luks-recut\` (#6929, ADR-096 amendment 2026-07-24).` (L3525–L3576) | `registry_luks_recut:` | 3,977 | L3567 (`preflight 1 + apply 41 + notify 5 = 47 min` — budget regex) | ~488.4 K |
   | 6 | `# ─── inngest Redis AOF volume recut: plaintext ext4 -> LUKS (#7695) ───` (L2253–L2298) | `inngest_volume_recut:` | 3,972 | none | ~484.6 K |
   | 7 | `# Tunnel ingress origin verification (#6594 / ADR-114 I2).` (L1037–L1082) | `- name: Measure the apex origin (ADR-194 Hypothesis Z)` | 3,091 | L1059 (`scheduled-inngest-health`) | ~481.8 K |
   | 8 | `# Selected by \`-f apply_target=git-data-host-replace\` (#6242, ADR-103). git-data.tf +` (L4204–L4234) | `git_data_host_replace:` | 2,730 (net ~1,500: 11 of 31 lines kept) | the 5-target list rows L4215–L4225 (`10.0.1.20`, `git-data.tf:275`, `git-data.tf:296`) | ~480.9 K |
   | 9 | `# ── #7095: re-mint the CF Access ci_ssh service token ──` (L6538–L6572) | `ci_ssh_token_replace:` | 2,530 | L6569 (`# removed`) | ~478.7 K |
   | 10 | `# ── the chained REAL restore (#7277) ──` (L3975–L4005) | `registry_store_restore:` | 2,516 | none | ~476.5 K |
   
   Blocks 1–10 are all required (Kieran's recomputation at plan-review with each block's retained lines plus a ~120-byte pointer: 480,893 bytes after block 8, 476,525 after block 10). If `wc -c` is still above 480,000, take the next-largest untouched job-header block applying the same Keep discipline (next candidates by size: `# ─── registry-host scoped -replace (dispatch-only; re-run cloud-init; ADR-096) ─` keeping the `10.0.1.30` row; `# --- #6767: read-only retrospective entrypoint drift AUDIT ---` keeping the `contents:read` row; `# ── D10 AUTHORIZATION GATE. A SEPARATE JOB, AND THE SEPARATION IS THE POINT (#7277). ──`). Stop at ≤ 480,000 — do not strip further.
3. **Regenerate the KB index:** `bash scripts/generate-kb-index.sh`, then `bash scripts/generate-kb-index.sh --check` is clean.
4. **Lint the runbook:** `python3 scripts/lint-infra-no-human-steps.py knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`. For any flagged line, reword the moved sentence so the actor is the job/dispatch rather than a person (e.g. "the operator dispatches X, which applies" → "an `apply_target=X` dispatch applies"). If the actor token is inside a rule id, resource name or file path (spec-flow's simulation found one such line in the `#6767 audit` reserve block: a rule id ending in `-yourself` adjacent to a sentence saying the job has no apply), reword the imperative side instead (say "has no apply step"); if neither side can change, leave that block in the workflow and pick the next candidate. Never open a `lint-infra-ignore` region for this.
5. **Verify no behavior change and all suites green** (AC3–AC7).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the failure surface is the operator's CI: a workflow that still does not start (size still > 512,000) or a suite that goes red on a moved anchor. Users are already exposed to the *current* state: no infra apply lands on `main` until this merges.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure — the diff removes/relocates comment prose and adds a read-only size test; no secrets, inputs, or `run:` bodies change.
- **Brand-survival threshold:** `none`
- Scope-out override: `threshold: none, reason: the touched workflow path is a CI-orchestration file and only comment lines change; the gate test reads file sizes and no user data.`

## Guard Contract

### Guard 1 — workflow-file byte-size gate

**Property.** No file matching `.github/workflows/*.yml` or `*.yaml` is larger than 490,000 bytes, and the gate constant itself stays at least 20,000 bytes under GitHub's 512,000-byte limit.

**Assembly.** The chokepoint is a single directory walk: `readdirSync(join(REPO_ROOT, ".github", "workflows"))` filtered to `/\.ya?ml$/`, measured with `statSync(path).size` (bytes on disk, the unit GitHub applies). Members are whatever the walk finds — never a hardcoded file list — and the walk must find ≥ 20 files (fail-closed on an empty or mis-resolved directory; the tree has 80 today). The test exposes a pure helper `oversizedWorkflows(dir, gateBytes, minFiles = 1)` returning `{ file, size, over }[]` and throwing `<n> workflow files found, expected ≥ <minFiles>` below the floor; the live call passes `minFiles: 20` and additionally asserts the walk contains `apply-web-platform-infra.yml`; the live assertion fails with the message `<file> is <size> bytes, <over> bytes over the 490,000-byte gate (GitHub refuses workflow files above 512,000 bytes: https://docs.github.com/en/actions/reference/limits)`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture dir with a compliant `a.yml` (100 bytes) and `apply-web-platform-infra.yml` written to 490,001 bytes | RED, message names `apply-web-platform-infra.yml`, size 490001, over 1 |
| 2 | Point the walk at an empty temp dir (guard's own dispatch) | RED: `0 workflow files found` (a passing gate over zero files is vacuous) |
| 2b | Fixture of 19 compliant files with `minFiles: 20` | RED naming the count (`19 workflow files found, expected ≥ 20`) |
| 3 | Fixture dir with a compliant first file `a.yml` (100 bytes) and a SECOND member `zz-mutant.yaml` of 500,000 bytes | RED, names `zz-mutant.yaml` (walk does not stop at the first member; `.yaml` counts) |
| 4 (harness) | Edit the SUITE to raise `WORKFLOW_FILE_GATE_BYTES` to 500_000 | RED: the in-suite assertion `WORKFLOW_FILE_GATE_BYTES <= GITHUB_WORKFLOW_FILE_LIMIT_BYTES - 20_000` fails |
| 5 (must-PASS, non-canonical) | Fixture dir where a file is exactly 490,000 bytes, plus a `.yaml` file of 1 byte and a `README.md` of 600,000 bytes | GREEN: boundary is inclusive, non-YAML files are ignored |

**Anchor.** The stored value is the constant `WORKFLOW_FILE_GATE_BYTES = 490_000`; it is pinned against an external fact (`GITHUB_WORKFLOW_FILE_LIMIT_BYTES = 512_000`, cited to the GitHub docs URL in a comment) by row 4, so weakening the gate past the headroom requires editing the limit constant too — a two-line change a reviewer sees, not a one-number edit.

## Acceptance Criteria

- [ ] AC1 `wc -c .github/workflows/apply-web-platform-infra.yml` ≤ 490,000 (hard), ≤ 480,000 (target); the number is recorded in the PR body.
- [ ] AC2 `bun test plugins/soleur/test/workflow-file-size.test.ts` is green on the branch, and all six mutation-matrix rows are in-suite fixture tests (rows 3 and 5 may share one fixture dir).
- [ ] AC3 No behavior change — the authoritative check is YAML equality (the only check that sees `#` lines inside `run: |` bodies, which are content, not comments; PyYAML 6.0.3 is importable here, `on:` parses to `True` on both sides, ~0.4 s): `python3 -c "import yaml,subprocess,sys; a=yaml.safe_load(subprocess.run(['git','show','f64b0ebc2:.github/workflows/apply-web-platform-infra.yml'],capture_output=True,text=True).stdout); b=yaml.safe_load(open('.github/workflows/apply-web-platform-infra.yml')); sys.exit(0 if a==b else 1)"` exits 0. Diagnostic only (it hides `#` lines inside `run:` bodies): `diff <(git show f64b0ebc2:.github/workflows/apply-web-platform-infra.yml | grep -vE '^\s*#') <(grep -vE '^\s*#' .github/workflows/apply-web-platform-infra.yml)` prints nothing (do not add or remove blank lines — the moved blocks contain none, and the diff runs without `-B`).
- [ ] AC4 `bash scripts/lint-workflows.sh` exits 0 (it exits 0 on findings by design; only a hang or a missing binary fails — CI's actionlint job is the authority). `go` is not on PATH here; if `actionlint` is missing, install the pinned release the way `.github/workflows/ci.yml` step `Install actionlint (pinned, sha-verified)` does (curl of the tarball), not `go install`; `python3 scripts/lint-workflow-run-body-syntax.py`, `scripts/lint-workflow-errexit-capture.py`, `scripts/lint-shell-trace-credential-refusal.py` exit 0 with their default arguments.
- [ ] AC5 All 49 suites that reference the workflow pass, invoked as the suites themselves run: `bash <file>` for each `.test.sh` / `tests/scripts/test-*.sh`, `bun test <file>` for each `plugins/soleur/test/*.test.ts`, and `cd apps/web-platform && ./node_modules/.bin/vitest run test/seo-config-rules.test.ts test/server/inngest/sentry-monitor-iac-parity.test.ts` (`seo-config-rules.test.ts:43` `readFileSync`s the workflow). The list is `git grep -l 'apply-web-platform-infra' -- 'tests/scripts/test-*.sh' 'plugins/soleur/test/*.test.ts' 'plugins/soleur/test/*.test.sh' 'apps/web-platform/infra/*.test.sh' 'apps/web-platform/test/*.test.sh' 'apps/web-platform/test/**/*.test.sh' 'apps/web-platform/test/*.test.ts' 'apps/web-platform/test/**/*.test.ts' 'scripts/*.test.sh' 'scripts/followthroughs/*.test.sh' | sort -u` (49 at plan time — git pathspec `**` does not match zero directories, so the top-level globs are load-bearing). `plugins/soleur/test/terraform-target-parity.test.ts` is explicitly among them.
- [ ] AC6 Every relocated block appears verbatim (modulo the stripped `# ` prefix and any step-4 rewording, each rewording listed in the PR body) in the runbook under a `## <job_id>` heading, every relocated block's first line in the workflow is followed by the pointer line naming the runbook path and `§<job_id>`, and `grep -c '^ *# Rationale: knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md §' .github/workflows/apply-web-platform-infra.yml` equals `grep -c '^## ' <runbook>`.
- [ ] AC7 `python3 scripts/lint-infra-no-human-steps.py knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` exits 0 with no `lint-infra-ignore` marker in the file; `python3 scripts/lint-credential-path-literals.py knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` exits 0; `bash scripts/generate-kb-index.sh --check` is clean.
- [ ] AC8 The PR body says `Closes #8361`, carries the measured AC1 number, and contains no dispatch of any workflow; the only post-merge event is the ordinary merge-triggered apply on `main` (which this fix un-breaks).

## Test Scenarios

- Given the branch after step 2, when `wc -c` runs on the workflow, then the byte count is ≤ 480,000.
- Given the gate test and the tree at `f64b0ebc2`, when `bun test plugins/soleur/test/workflow-file-size.test.ts` runs, then it fails naming `apply-web-platform-infra.yml`, size 513306, over 23306.
- Given a temp dir with `a.yml` (100 B) and `zz-mutant.yaml` (500,000 B), when `oversizedWorkflows(dir, 490_000)` runs, then it returns one entry for `zz-mutant.yaml` with `over: 10000`.
- Given an empty temp dir, when the gate runs, then it throws/fails with a zero-files message rather than passing.
- Given the 49 referencing suites, when each is run by its own invocation, then all pass.
- Given the runbook, when `lint-infra-no-human-steps.py` scans it, then exit 0.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/tooling change (comment relocation plus a size test). Product/UX gate: NONE (no UI-surface file in Files to Create/Edit).

## Context

- Observability gate (Phase 2.9): skipped — no file under `apps/*/server|src|infra`, `plugins/*/scripts`, and no new infrastructure surface; the failure mode of this change (an oversize workflow) is detected by the new CI test, and the workflow's own `notify-apply-failure` channel is untouched.
- Encryption posture (2.11), IaC routing (2.8), GDPR (2.7), ADR/C4 (2.10): skipped — no store, no connection, no infra, no regulated data, no architectural decision (the relocation is the pattern ADR-152 already records).
- Scoped advisor consult (4.5): skipped — single-file comment relocation plus one test; no architecture choice.
- Sharp edge: a plan whose `## User-Brand Impact` section is empty or filled with stub text fails deepen-plan Phase 4.6 — filled above.
- Sharp edge: the Keep column is a plan-time derivation; the mechanical gate is AC5 (run every referencing suite by its own invocation). If a suite reds on a moved line, restore that line in the workflow (do not edit the test) and record it in the PR body.

## References

- Issue #8361; blocked dispatch #8294.
- GitHub limits: https://docs.github.com/en/actions/reference/limits (500 KB per workflow file).
- ADR-116 `knowledge-base/engineering/architecture/decisions/ADR-116-content-anchored-citations-in-code-comments.md`; ADR-152 `knowledge-base/engineering/architecture/decisions/ADR-152-strip-rationale-comments-from-git-data-injected-scripts-at-render-time.md`.
- Sibling byte gates: `plugins/soleur/test/cloud-init-user-data-size.test.ts`, `scripts/lint-agents-rule-budget.py`, `scripts/lint-skill-body-budget.py`.
- Existing runbook for the same workflow: `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md`.
