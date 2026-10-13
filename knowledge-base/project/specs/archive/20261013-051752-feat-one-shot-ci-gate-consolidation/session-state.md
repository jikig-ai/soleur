# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-09-25-feat-ci-gate-consolidation-plan.md`
- Tasks file: `knowledge-base/project/specs/feat-one-shot-ci-gate-consolidation/tasks.md` (this directory)
- Status: planning complete in one pass. No implementation done. Nothing pushed.

### Decisions

- **Host = `pr-quality-guards.yml`, not a new file, not ci.yml.** Its
  `pull_request` types `[opened, synchronize, reopened, edited]` are the
  exact union of all five fold candidates (`edited` only needed by the
  scanner — host already has it); it already declares `merge_group` and
  ci.yml's ADR-217 concurrency block byte-for-byte; keeping the filename
  keeps the ledger row + reaper mapping stable (jobs ceiling 11→16 only).
  ci.yml rejected: `push: main`/`workflow_dispatch` arms + no `edited` type
  (adding it would tax 24 jobs per edit).
- **Fold set (5 → 0 files, −5 runs/push, 23→18):** `dependency-review.yml`,
  `legal-doc-cross-document-gate.yml`, `skill-security-scan-pr-trailer.yml`,
  `constraint-gates.yml`, `pr-auto-close-scanner.yml`.
- **Job-id collision:** two sources use id `scan` → skill-scan becomes
  `skill-security-scan` (required context `skill-security-scan PR gate`
  survives via its `name:` field), scanner becomes `auto-close-scan`.
- **`if:` placement is the correctness lever:** the three required contexts
  (`dependency-review`, `enforce`, `skill-security-scan PR gate`) keep NO
  job-level `if:` so they still report on `merge_group`; the two advisory
  jobs (`constraint-gates`, `auto-close-scan`) gain
  `if: github.event_name == 'pull_request'`. This mirrors the host file's
  own documented convention.
- **Permissions stay minimal via job-level pins:** workflow-level
  `contents: read, pull-requests: read` unchanged; `pull-requests: write`
  pinned per-job on `dependency-review` + `auto-close-scan` only.
- **No ruleset/TF migration:** live `gh api rulesets/14145388` confirms all
  24 contexts are job-level names; preserving ids/names preserves contexts.
- **Rejected merges (documented in plan):** cla+cla-evidence (privileged
  `pull_request_target`, concurrency-model conflict, R2 evidence chain —
  −1 run not worth it); cancel-superseded-pr-runs (`actions: write`
  isolation); secret-scan (schedule + labeled types); all `paths:`-gated
  workflows (trigger-level gating lost); fix-constraints chain (workflow_run
  name-keyed); infra stateful cancel:false trio; claude-code-review
  (ready_for_review + vendor contract).

### Gotchas for /work

- **Biggest hidden surface is filename enumeration, not YAML:** linters and
  tests key on the deleted basenames —
  `lint-bot-synthetic-{statuses,completeness}.sh` basename exemption,
  `ci-path-gating.test.sh` `DEP=`, `skill-security-scan-step-body.test.sh`
  `WF_PR`, `audit-bot-codeql-coverage.sh` ~L85 skip, `test-affected-paths.sh`
  edge table, `constraint-scaffold/test/parity.test.sh` `ROOT_BODY` read.
  Task Phase 2 walks all of them.
- **parity.test.sh is the hardest retarget:** the repo-root dogfood
  constraint-gates file stops existing standalone; extract
  `jobs.constraint-gates` from the merged file via `yaml.safe_load` and
  compare to the template jobs subtree. Template + `apps/web-platform`
  emitted copy stay standalone files.
- **`edited`-event safety:** folded jobs must derive diffs from
  `gh api pulls/N/files` / merge-base (dep-review verified — its detect uses
  `gh api`, never `github.event.before`). Spot-check enforce + skill-scan
  diff steps during implementation.
- **Open-PR collision:** #8878 touches `skill-security-scan-pr-trailer.yml`
  — check merge status at /work time; port its diff if it landed first.
- **No folded job uses `if: always()`** — the force-cancel teardown rule is
  unaffected (verified by grep during planning).
- This PR dogfoods itself: pull_request workflows run from the merge ref, so
  the PR's own check run will exercise the merged file.
