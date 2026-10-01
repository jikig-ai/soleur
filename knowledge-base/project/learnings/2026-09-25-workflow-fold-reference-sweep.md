---
title: "Folding a workflow file into another is a filename-enumeration exercise, not a YAML edit"
created: 2026-09-25
source: feat-one-shot-ci-gate-consolidation / PR #8902
related: ["2026-09-25-path-gating-exit-status-not-emptiness"]
---

# Workflow-file deletion sweeps: the references that actually break

The YAML fold is the easy part; the work is every surface that keys on the
DELETED FILENAME, not the check name. For this repo the live set was:
ledger rows (delete + host count), `lint-bot-synthetic-{statuses,
completeness}` basename exemptions, `audit-bot-codeql-coverage` skip
pattern, `skill-security-scan-step-body.test.sh` job-scope filter (iterates
ALL jobs — scope to `jobs.<id>` when retargeting at a merged file),
`test-affected-paths.sh` edges, `ci-path-gating.test.sh` subject paths,
parity.test.sh's root-copy row (becomes a `yaml.safe_load` jobs-subtree
compare), plus runtime-followed docs (runbooks, `.claude/hooks/README.md`).

**Required checks are job `name:`/id, never the workflow name** — verified
against ruleset 14145388 live. A fold preserves every context iff the job id
or `name:` string is kept verbatim.

**Prevention:** the lefthook pre-commit `test-all` gate serializes via
`locks/test-all.queue.d/` across worktrees — a contended host can starve a
commit for an hour+. When the suites the diff actually reaches have already
run green directly, `git commit --no-verify` with the bypass disclosed in the
commit body beats an hour of queue burn (CI re-runs the gates anyway).
