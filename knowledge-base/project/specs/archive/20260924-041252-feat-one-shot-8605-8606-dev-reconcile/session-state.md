# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-23-fix-dev-ledger-closed-unmerged-reconcile-and-migration-gate-cwd-plan.md
- Status: complete
- Plan artifact: recovered (selector=branch). The first planning subagent crashed on a usage-limit error (HTTP 429) and left a stub with only frontmatter and an Overview. The one allowed re-run finished plan and deepen-plan in place.

### Errors
- The first planning subagent stopped on a usage limit (rate_limit 429) and was re-run once.
- The resumed checkpoint had no Research Insights, so Phase 1 research re-ran, one learnings agent plus direct reads.
- markdownlint MD038 and MD032 issues in the plan were fixed before commit.
- Reviews found defects in the plan's own draft, all folded in: the `jq @base64d` decode failed on GitHub's line-wrapped base64; psql runs backslash meta-commands from a `-f` file (P0 on a `pull_request_target` runner holding the dev secret); the refusal regex matched 51 of 95 down files; the fake psql could not see `-f` payloads; and the unattended close path failed silently.

### Decisions
- #8606: both `git ls-tree` pathspecs in `run-migrations.sh` use `:(top,literal)`. Every case is tested from the repo root, which is the prd regression control, and from `apps/web-platform`.
- #8605(a): the classifier reads PR state (`pull-requests: read`, `GITHUB_TOKEN`) only for fresh owner branches. The PR's head SHA must equal the branch tip. A closed PR gives the verdict `closed-grace` (a warning for 24 h), then `closed` (blocking). The classifier stays fail-closed: 401/403/404 are config errors, and a 5xx or 429 gets one retry. DC-5, which would degrade outages to a warning, is recorded but not applied.
- #8605(b), DC-1 accepted by the operator: a separate writer, `dev-ledger-reconcile.sh`, uses the guard as a library. `dev-ledger-reconcile.yml` runs it on a same-repo PR closed unmerged, or on dispatch from main. Dispatch defaults to dry-run. The dev environment is asserted in the workflow and in-process, the dev-suite mutex is held strictly, and there is one compare-and-set transaction per PR. Down files are refused on a backslash, on transaction control, and on `CASCADE` or redefinition while later rows exist. On an open PR only its author can discard rows, and only rows that have a paired down file. Every refusal files an `action-required` issue.
- ADR-061 gets an append-only amendment: DC-1, a bounded relaxation of the "applied migrations are immutable" rule, and a detection ceiling of about 30 h.
- #8521 archive: tick AC11 with run 35891815286 as evidence, run `archive-kb` for each slug, and repoint the test file's plan pointer. DC-1 through DC-5 are in `decision-challenges.md`.

### Components Invoked
- Skills: soleur:plan, soleur:plan-review, soleur:deepen-plan
- Agents: learnings-researcher, advisor (opus), dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, cto, security-sentinel, data-integrity-guardian, architecture-strategist, test-design-reviewer, observability-coverage-reviewer, verify-the-negative sweep (sonnet)
- Planning cost: the resumed subagent used about 522k tokens over 36 min, after the crashed first attempt.
