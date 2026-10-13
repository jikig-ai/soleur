# Plan: Consolidate tiny PR gate workflows into `pr-quality-guards.yml`

Item 4 of 5 in the CI-fan-out workstream (#8854 K=7 sharding, #8891
concurrency-cancel, #8897 path-gating all merged). PR: #8902 · Branch:
`feat-one-shot-ci-gate-consolidation`.

## Goal

Each PR push currently queues **23 workflow runs** (one per
`scripts/pr-fanout-ledger.txt` row). The prize is run-fan-out (queue slots +
webhook/dispatch overhead), not job-minutes. Fold five single-job
`pull_request` gate files into `pr-quality-guards.yml` → **18 runs per push
(−5, −22%)** with zero required-check renames and zero new workflow files.

## Why `pr-quality-guards.yml` is the host (not a new file, not ci.yml)

- Its `pull_request` types are `[opened, synchronize, reopened, edited]` —
  the **exact union** of all five sources. `edited` is the only non-default
  type needed (by pr-auto-close-scanner) and the host already has it.
- It already carries `merge_group` and documents the file's own convention:
  required-context jobs get **no** `if:`; PR-scoped jobs get
  `if: github.event_name == 'pull_request'`.
- Its concurrency block is byte-for-byte ci.yml's ADR-217 block — identical
  to what dep-review / legal-doc / skill-scan / constraint-gates already use.
- Keeping the **filename** keeps the ledger row and the reaper mapping
  unchanged; only the jobs ceiling moves 11 → 16.
- ci.yml rejected as host: `push: main` + `workflow_dispatch` arms would fire
  folded PR jobs on every main push; adding `edited` to ci.yml's trigger
  would tax all 24 jobs per body edit; the row's consequence text is already
  the ledger's largest.
- A brand-new `pr-gates.yml` rejected: adds a workflow *name* surface,
  requires a new ledger row + reaper onboarding, and duplicates a trigger
  block that already exists. Folding into the existing guards file is
  strictly less machinery.

## Consolidation map

| Source file (deleted) | Job id → host id | Check context emitted | Required? | Delta needed on fold |
|---|---|---|---|---|
| `dependency-review.yml` | `dependency-review` → `dependency-review` | `dependency-review` (job id, no `name:`) | YES (ruleset 14145388) | Add job-level `permissions: {contents: read, pull-requests: write}`; keep NO job `if:` (merge_group steps already handle both events); keep in-job `id: detect` step verbatim incl. the `.github/workflows/` self-trigger regex |
| `legal-doc-cross-document-gate.yml` | `enforce` → `enforce` | `enforce` (job id, no `name:`) | YES | Verbatim; NO job `if:`; merge_group base-sha logic unchanged |
| `skill-security-scan-pr-trailer.yml` | `scan` → **`skill-security-scan`** (id collides with scanner's `scan`) | `skill-security-scan PR gate` (`name:` field — survives id rename) | YES | Rename id; keep `name:` byte-identical; NO job `if:`; merge_group checkout/diff branches unchanged |
| `constraint-gates.yml` | `constraint-gates` → `constraint-gates` | `L1 import-boundary gate` (`name:`) | advisory | ADD `if: github.event_name == 'pull_request'` (never had merge_group; PR-only per host convention); runs `apps/web-platform/scripts/constraint-gates.sh` — script untouched |
| `pr-auto-close-scanner.yml` | `scan` → **`auto-close-scan`** | job id `auto-close-scan` (no `name:` today; advisory so context name is free) | advisory | ADD `if: github.event_name == 'pull_request'`; add job-level `permissions: {contents: read, pull-requests: write}`; gains `reopened` firing (harmless rescan) |

Host workflow `name: PR quality guards (#2905)` — keep as-is (nothing keys
on the display name; renaming is cosmetic churn). Workflow-level
`permissions:` stays `contents: read, pull-requests: read`; the two
write-needing jobs pin `pull-requests: write` at **job level** (job
permissions replace, not intersect, the workflow default — so the union does
not widen sibling jobs). Concurrency block: untouched.

## Required-check preservation

Verified against `gh api repos/jikig-ai/soleur/rulesets/14145388` (live) +
`infra/github/ruleset-ci-required.tf` + `scripts/required-checks.txt`:
contexts are the **job `name:` or job id**, not the workflow name. All 24
contexts unchanged; **no Terraform/ruleset migration needed**.

| Context | Lives in (before → after) | Preserved by |
|---|---|---|
| `dependency-review` | dependency-review.yml → pr-quality-guards.yml | job id kept |
| `enforce` | legal-doc-cross-document-gate.yml → pr-quality-guards.yml | job id kept |
| `skill-security-scan PR gate` | skill-security-scan-pr-trailer.yml → pr-quality-guards.yml | `name:` kept verbatim |
| `markdown-lint`, `Bash fixture tests for guard scripts` | pr-quality-guards.yml (unchanged) | n/a |
| other 19 contexts (incl. `CodeQL` @57789, `cla-check`, `cla-evidence`) | untouched files / separate ruleset | n/a |

## Semantics verification per candidate (done during planning)

- **Trigger sets**: all five sources are `pull_request` (never
  `pull_request_target` — the PR/PR_target mixing ban is trivially
  satisfied). dep-review `pull_request: {}`, legal-doc bare `pull_request:`,
  skill-scan `[opened, synchronize, reopened]` are all the default-type set;
  constraint-gates same; scanner `[opened, edited, synchronize]`. Host union
  already covers all. merge_group: dep-review/legal-doc/skill-scan already
  declare it and handle `merge_group.{base_sha,head_sha}` — jobs must keep
  their existing event-branching and must NOT gain a PR-only `if:`.
- **`edited` widening**: the four non-scanner jobs now fire on PR body edits.
  Each derives its diff from `gh api pulls/N/files` or merge-base SHAs (NOT
  `github.event.before/after`, which is empty on `edited`) — verified for
  dep-review's detect step; verify the same for enforce + skill-scan diff
  steps during implementation. Cost: ~4 sub-minute jobs per edit.
- **Concurrency**: merged group key is `PR quality guards (#2905)-refs/pull/N/merge`
  on PR events — coalesces synchronize+edited per PR (scanner's old
  per-number group was equivalent). `cancel-in-progress` stays PR-only, so
  merge_group runs never cancel. All five files are stateless lint/scan —
  mid-run cancel writes nothing.
- **Reaper/ledger**: `cancel-superseded-pr-runs.sh` reaps by ledger basename;
  `pr-quality-guards.yml` row persists → its runs (now carrying the folded
  jobs) are still reaped correctly on supersede. Five rows deleted;
  `pr-quality-guards.yml` jobs ceiling 11 → 16 with named consequence.
  None of the five folded jobs uses `if: always()` — the force-cancel rule
  is unaffected.
- **workflow_run consumers**: none key on any of the five display names
  (consumers watch only `CI`, `Version Bump and Release`,
  `fix-constraints-stage-a`, `Apply web-platform infra…`). Safe.
- **Aggregation/cancellation of required checks**: each folded required job
  still posts its own context on both `pull_request` and `merge_group`; a
  failed folded job fails only its own context (job conclusions are
  independent). No weakening.

## Rejected candidates (honest negatives)

- **`cla.yml` + `cla-evidence.yml`** (both `pull_request_target` — legally
  mergeable, saves 1 run): rejected. cla.yml has NO concurrency block;
  cla-evidence's per-issue `cancel-in-progress: false` group would serialize
  cla-check on noisy PRs or vice-versa. Permission union lands
  `contents: write` + `statuses: write` on the privileged-trigger file, and
  the evidence job drops content-addressed R2 tombstones — highest-stakes
  file pair in the repo for a −1-run prize.
- **`cancel-superseded-pr-runs.yml`**: holds `actions: write` + the
  default-branch-checkout security model; folding it into a file whose other
  jobs process untrusted PR text blurs the audited privilege boundary for a
  −1-run prize. Keep isolated.
- **`secret-scan.yml`**: weekly `schedule` arm + load-bearing
  `labeled`/`unlabeled` types (#3160/#3323) — unioning triggers either fires
  15+ jobs on a cron or drops label-retrigger semantics. Reject.
- **paths-gated rows** (`gdpr-gate-self-test`, `infra-validation`,
  `rls-authz-fuzz`, `sentry-audit-gate`, `skill-security-scan-corpus`,
  `validate-vector-config`, `fix-constraints-stage-a`): filters differ —
  merging into an ungated host makes them fire on every push (ledger `paths`
  column is trigger-level only). Net-negative. Reject.
- **`fix-constraints-stage-a/b`**: stage-b's `workflow_run.workflows:` keys
  on the literal name `fix-constraints-stage-a`. Name-bound chain. Reject.
- **`apply-sentry-infra` / `tenant-integration` / `vendor-pin-verify`**:
  deliberate `cancel-in-progress: false` (#5585 R3), stateful/secrets.
  Reject.
- **`claude-code-review.yml`**: `ready_for_review` type + third-party action
  contract. Leave.

## Filename-reference sweep (the real work — every hit must move)

Blocking updates (tests/lints enumerate the file, not just the check name):

1. `scripts/pr-fanout-ledger.txt` — delete the five rows; raise
   `pr-quality-guards.yml` row 11→16 with consequence text naming the fold.
2. `plugins/soleur/test/ci-path-gating.test.sh` — `DEP=` retargets to
   `pr-quality-guards.yml`; asserts A1 (`id: detect`), A3 (no job-level
   `if:` on `dependency-review`), A5 (workflows/ self-trigger in the regex,
   but must now exclude only the file's own detect regex context), A6
   (gh-api exit-status gating) all still hold in the merged file.
3. `scripts/skill-security-scan-step-body.test.sh` — `WF_PR` retarget; check
   whether its extraction assumes a single-job file (may need a
   job-section extraction tweak).
4. `scripts/lint-bot-synthetic-statuses.sh` + `scripts/lint-bot-synthetic-completeness.sh`
   — the basename exemption `skill-security-scan-pr-trailer.yml` must become
   `pr-quality-guards.yml` (the folded step body still carries the string
   that trips the predicate; the exemption moves with it). Keep the
   lookalike-hardening property (`evil-pr-quality-guards.yml` NOT exempt).
5. `plugins/soleur/test/lint-bot-synthetic-{statuses,completeness}.test.sh`
   — rename fixture basenames in Tests 9/10 and (e) accordingly.
6. `scripts/audit-bot-codeql-coverage.sh` ~L85 — `*skill-security-scan-pr-trailer*`
   skip pattern → `*pr-quality-guards*` (or match the new basename exactly).
7. `scripts/lib/test-affected-paths.sh` — declared edges (~L668–721, ~918):
   repoint the three deleted filenames at `pr-quality-guards.yml`; add edges
   for legal-doc/scanner coverage if the merged file should trigger them.
8. `plugins/soleur/skills/constraint-scaffold/test/parity.test.sh` — the
   `ROOT_BODY` read of `.github/workflows/constraint-gates.yml` must instead
   extract `jobs.constraint-gates` (python `yaml.safe_load`) from
   `pr-quality-guards.yml` and compare against the template's jobs subtree
   modulo `__TARGET_DIR__`. The template and the `apps/web-platform` emitted
   copy stay standalone files — only the repo-root dogfood folds.

Doc/reference updates (non-blocking but sweep at the end):

9. `plugins/soleur/skills/skill-security-scan/references/override-mechanism.md`
   L134, `plugins/soleur/skills/ship/SKILL.md` (scanner mention),
   `plugins/soleur/skills/constraint-scaffold/SKILL.md` + test comments,
   `scripts/lint-workflow-install-sites.sh` L17 comment,
   `scripts/lint-workflow-issue-write-scope.py` L88 comment,
   `plugins/soleur/scripts/grok-pre-push-gate.sh` L13 comment,
   `knowledge-base/engineering/operations/runbooks/lint-bot-statuses.md`,
   ADR-071 / ADR-216 load-bearing filename mentions. Historical
   specs/tasks files: leave.
10. `.github/enforcement-contracts.json` — verified: no entries name the
    five files (sweep-completeness gate unaffected).

Final guard: `rg -l
'dependency-review\.yml|legal-doc-cross-document-gate\.yml|skill-security-scan-pr-trailer\.yml|constraint-gates\.yml|pr-auto-close-scanner\.yml'`
— every hit updated or annotated historical.

## Collisions

- **PR #8878** (open) touches `skill-security-scan-pr-trailer.yml` —
  coordinate landing order; if it merges first, port its diff into the
  folded `skill-security-scan` job.
- PR #6778 touches `infra-validation.yml` — not in merge set.
- #8897's `test-affected-paths.sh` is the newest machinery here — its edge
  table must be edited in the same commit as the file deletions.

## Fan-out estimate

| Event | Before | After |
|---|---|---|
| PR push (`synchronize`) | 23 runs | **18** (−22%) |
| `merge_group` candidate | 4 (dep-review + legal + skill-scan + guards) | **1** |
| PR body `edited` | 2 (guards + scanner) | **1** |

## Acceptance criteria

1. `gh api repos/jikig-ai/soleur/rulesets/14145388` — all 24 contexts +
   integration_ids unchanged; no `infra/github/` diff.
2. `bash plugins/soleur/test/pr-fanout-ledger.test.sh` green (five rows
   gone, guards row at 16).
3. `ci-path-gating.test.sh`, `skill-security-scan-step-body.test.sh`,
   `lint-bot-synthetic-*.test.sh`, `parity.test.sh` green post-retarget.
4. Required folded jobs carry NO `if:`; `constraint-gates` + `auto-close-scan`
   carry `if: github.event_name == 'pull_request'`; job-level `permissions:`
   pin `pull-requests: write` to exactly the two jobs that need it.
5. Dogfood: this PR's own checks run the merged file (pull_request workflows
   execute from the merge ref) — `dependency-review`, `enforce`,
   `skill-security-scan PR gate` all report under the `pr-quality-guards.yml`
   run.
6. `git diff origin/main -- .github/workflows/` shows exactly five deletions
   + one modification.
