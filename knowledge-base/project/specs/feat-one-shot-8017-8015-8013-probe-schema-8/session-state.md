# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-10-fix-inngest-probe-schema-8-mount-devid-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verification: `git diff origin/main...HEAD --name-only` listed only
  `knowledge-base/project/{plans,specs}/` + auto-generated `knowledge-base/INDEX.md`.
  No product code touched by the planning subagent.
- Collision re-probe (#7247): plan frontmatter `issue: 8017`, `refs: 8017, 8015, 8013`.
  All three were checked at Step 0a.5 and are OPEN with no linked PRs. No new target
  discovered by planning, so no unchecked ref remains.

### Errors
- Section-splice bug hit twice in the planning subagent's own `replace_section` helper
  (substring index matched inside backticked prose); detected by a heading-outline check,
  repaired line-anchored, verified no duplicate headings and lints green.
- Acceptance-criteria renumbering mangled once by a first-occurrence replace; rebuilt positionally.
- `plugin:github:github` MCP server failed to connect (bad Authorization header).
  Not blocking — all GitHub reads went through the `gh` CLI.
- Nothing dispatched, nothing destructive ran, the authorized FLUSHALL is untouched.

### Decisions
- Emit a resolved by-id alias, not `MAJ:MIN`: measured, `findmnt -no MAJ:MIN` returns `259:3`,
  which cannot be compared against volume id `106261946` at all. Emitter resolves via `lsblk -s`
  then reverse-maps within the `scsi-0HC_Volume_*` namespace; a whole-`by-id` walk measured
  multi-valued, so an `__AMBIGUOUS__` sentinel turns a premise into a measurement.
- The #8013 fix became identifier-aware rather than brace-aware: `estate:<ULID>:runs:1` leaks the
  same ULID through the two-segment reduction with no brace rule involved, so a collapse-only fix
  would have closed the issue for the quoted shape and left the identical leak standing.
- `Ref #`, never `Closes #`. The sweeper lists `--state open`, so closing at merge would make every
  follow-through directive a permanent silent no-op. The delivery gate accepts `registry_fns=0`
  because `INNGEST_DIAGNOSTIC_BOOT` is a Doppler variable that survives a host replace.
- No new ADR: ADR-199 Decision C1 already names the mount pin, so this is an amendment, not a new
  ordinal (also avoids a renumber-sweep hazard).
- Three test harnesses are deliverables because they did not exist: `inngest.test.sh` has no
  mutation helper, the #7674 probe has no suite, and the gate battery runs the gate without
  `set -u` while production runs with it. Six of fifteen guard rows were unrunnable as written.

### Components Invoked
- `soleur:plan`, `soleur:deepen-plan`
- Research: Explore x3 (image-pin sites, dark-gate battery, rules/learnings/ADRs),
  general-purpose x1 (probe_schema consumer sweep)
- Plan-review panel: kieran-rails-reviewer, code-simplicity-reviewer, spec-flow-analyzer
- Deepen panel: security-sentinel, observability-coverage-reviewer, test-design-reviewer
- Gates/lints: lint-guard-contract.py, lint-infra-no-human-steps.py, lint-orphan-test-suites.sh,
  markdownlint-cli2, deepen-plan halts 4.5-4.11
- Live measurement: `gh issue view`, `findmnt`/`lsblk`/`od`/`sh` probes,
  `doppler run -- betterstack-query.sh` against the live warehouse, baseline runs of seven suites
