---
title: The merge-effect classifier is a closed-world allowlist and authorizes nothing
status: active
date: 2026-10-24
supersedes: none
related_adrs: [ADR-289, ADR-084]
tags: [authorization, delegation, merge, production, classifier, ci]
---

# ADR-297: The merge-effect classifier is a closed-world allowlist and authorizes nothing

## Context

During the held-merge session of 2026-10-22 on epic #9757, the question "does merging this pull request change
production?" was answered by agent prose: the CTO-authored `{OUTCOME}` sentence in the operator's merge question,
the ship `Blast Radius:` label, and the infra pull requests' hand-written "merge-effect first line". Three prose
statements, written by the agent that wrote the change, with nothing checking them against what the workflows
actually do. ADR-289 already rejects an act-class label written by the same agent (its Option C); the same
objection applies to the merge-effect sentence, which is the one line a non-technical operator reads before saying
Yes.

Issue #10923 (item P2 of the CTO follow-up list) asked for a script, `merge-effect-class.sh`, that decides from a
pull request's changed-file list whether merging can change production, and optionally a delegation Scope class
"merge changes referencing epic #N". The planning phase read the delegation and hold-evaluator code and re-scoped
the ask on CTO rulings (recorded in `decision-challenges.md` of the feature spec): build the classifier, give it
exactly one consumer, and record the scope class as rejected.

## Considered Options

- **Option A: parse `on.push.paths` at run time inside the shipped script.** Pros: no stored table to drift.
  Cons: a plugin script that parses a repository's workflow YAML ships a YAML-and-glob engine to every customer
  install, and a parsing bug reads as "safe". Rejected: a static allowlist plus a CI parity test gets the same
  freshness where the workflows live.
- **Option B: a multi-valued class (docs, plugin, infra, app, ...).** Rejected: every extra value is a place for a
  consumer to map "unknown" to safe. The verdict is binary and closed-world.
- **Option C: a delegation Scope class "merge changes referencing epic #N".** Pros: fewer operator questions on
  epic work. Cons: the scope binds on a pull-request number; a class keyed on "references epic #N" lets the agent
  that writes the PR body choose its own class (ADR-289 Option C). It widens an irreversible
  production-mutating authorization. Rejected for now; see "Rejected for now" below.
- **Option D: amend ADR-289 with full entries.** Rejected: ADR-289 is `adopting`; this decision extends it and
  changes none of its mechanism, so it gets its own ordinal.
- **Option E: pin execution to `git show origin/main:` of the script.** Rejected: `plugins/soleur/**` is off the
  allowlist (any edit of the classifier is itself effecting) and skills resolve the script through
  `${CLAUDE_PLUGIN_ROOT}`; the pin bought nothing the allowlist does not.
- **Option F (chosen): a read-only, closed-world allowlist classifier, one consumer, parity-tested.**

## Decision

Option F.

**The verdict.** `plugins/soleur/scripts/merge-effect-class.sh` reads a list of changed paths (`--files-from`, or
`--pr <N>` which builds the list from the user's own `gh` session and calls the same chokepoint) and prints exactly
one line: `production-effecting` or `not-production-effecting`. Exit 0 only for `not-production-effecting`; exit 1
for `production-effecting`; exit 2 for unusable input, with stdout still `production-effecting`. A caller reading
only the exit status or only stdout can therefore never read "not" from a failure.

**The meaning.** `not-production-effecting` means: no path-gated production workflow fires from this file list,
where "fires" means performs a production act through a path filter. It does not mean "no runtime effect". Out of scope by design: scheduled crons that read `knowledge-base/`,
agent-steering files outside the basename set below, content consumed at build time with no path trigger, and
bookkeeping workflows that fire on every merge (ledger reconcile, board sync).

**The allowlist.** The only way to read `not-production-effecting`: every changed path, both sides of a rename, is
under `knowledge-base/` or is a root-level `*.md`, except that any path whose basename is `AGENTS*.md`, `CLAUDE*.md` or `GEMINI*.md`, in any letter
case and at any depth, is effecting (these files steer every agent session, including scheduled agents that hold
secrets). Everything else, including every unknown path and the classifier's own files, is effecting.
Malformed paths (empty line or segment, backslash, CR, tab, NUL, leading or trailing `/`, `.` or `..` segments,
control characters, a git-quoted path) are exit 2. Only the two verdict modes (`--files-from`, `--pr`) carry the
verdict contract; `--help`, `--print-witnesses`, `--filter-allowed` and `--self-check` print no verdict line.

**Drift defence.** A CI parity test, `plugins/soleur/test/merge-effect-class-parity.test.sh`, derives the
population of workflows that can run on a merge to main from `.github/workflows/*.yml`, closed-world over trigger
keys: `push` to main, `workflow_run`, `release`, and `pull_request`/`pull_request_target` with `closed`. A named
inert list classifies the other keys with a reason each; any other key fails. A workflow in that population is
`production` unless it has a row, with a reason, in `plugins/soleur/scripts/merge-effect-class.ci-only.tsv`. The
test asserts that no allowlisted witness path (derived from the script's own data) and no tracked allowlisted file
fires a production workflow, and, for anti-vacuity, that every production workflow's own globs read
`production-effecting` from the real script. The ci-only meaning is "not directly gated by the merged file list as
a production act", never "harmless". Both the ci-only list and the inert list are review-owned. A mislabel
matters only if that workflow fires on an allowlisted path, which the witness and real-tree directions cover.

**Applicability.** `--pr` exits 2 `reason=not-applicable` unless the repository root carries the repo-owned
`.github/workflows/web-platform-release.yml` and the ci-only list is tracked at HEAD, and `--repo` equals the
current repository. It also binds the pull request's state (OPEN), base (main) and head sha (read twice); the
consumer must merge with `--match-head-commit` and the printed sha. The sentinel prevents misapplication, not
attack: a fork carries the same workflow and is classified by the same table, which is correct.

**One consumer.** `plugins/soleur/skills/ship/references/operator-holds.md` section 3 step 2 (Ask) uses the
verdict to add one clause to the operator's merge question, and records the verdict line in the PR body. The
consumer only adds a warning; it never relaxes anything and never records a delegation. Scope: the merge or ready
of a named open pull request, interactively. Dispatches and not-yet-created revert PRs keep the agent-authored
sentence.

**Never evidence.** The verdict authorizes nothing (AP-024: a verification surface does not actuate). It is never
usable as evidence in an envelope `Gate:` line or a receipt; a `Gate:` kind for it would need a CTO ruling, as
ADR-289 requires for any new kind.

**Precedence.** Four existing statements say, in prose, which merges change production: ship `SKILL.md`'s Deploy
Pipeline Fix Drift Gate (a hand-maintained trigger array), the `Blast Radius:` label, the infra pull requests'
"merge-effect first line" and the `{OUTCOME}` sentence the calling skill writes. They are left in place. The
classifier is a coarser, workflow-derived verdict that every `apps/web-platform/infra/**` path already trips; its
clause is appended to the `{OUTCOME}` sentence and the stricter reading wins.

**Rejected for now: the epic-reference scope class.** It stays out until all four hold: (1) the classifier runs
from `origin/main`; (2) the scope binds to a pull request whose author and file list the verifier fetches itself,
with a human-authored link recorded in the delegation; (3) the receipt hook of #10361 exists; (4) ADR-289's two
residuals (envelope not pinned to `origin/main`, verifier trust base) are closed. A flip is a separate ADR and
needs the founder's authorization at that time. A tracking issue carries these conditions.

## Consequences

- The operator's merge question gets a machine-derived "may change production" clause instead of agent prose; a
  non-technical operator sees the same plain sentence every time.
- `web-platform-release.yml`'s `workflow_run` arm runs after every main CI run, including docs-only merges; it is
  accepted as gated because its inner path check decides whether to deploy. The parity test's coverage for that
  one workflow is the executable P3 and P1 assertions in `workflow-run-deploy-invariants.test.sh`, not the path
  matcher.
- `scripts/ci-e2e-classify.sh` carries a similar `knowledge-base/**` plus root `*.md` allowlist for a different
  purpose (skipping e2e). The two are not kept in step by any check; a change to one should be read against the
  other.
- The consumer text keeps the earlier "production apply or deploy" obligation for every case the classifier does
  not cover (dispatches, revert pull requests that do not exist yet, repositories where `--pr` is not applicable),
  and omitting the classifier clause is not a claim of safety.
- A new workflow, a new trigger kind, or a production trigger widened over an allowlisted path turns CI red on the
  pull request that does it, with a paste-ready fix. Cost: the first time anyone adds a workflow, they classify it.
- Residuals, accepted:
  - **Stale installed copy.** A copy that lags can under-warn after a later PR widens a trigger over an allowlisted
    prefix. That PR itself edits `plugins/soleur/**` or a workflow, so it is effecting and is seen; the window is
    the plugin update lag, bounded and accepted. Flip: a lag actually observed adds skew detection.
  - The verdict judges the PR's file list, which equals the squash commit's unless main moved in the queue.
  - Unknown consumers outside the verdict's meaning above (scheduled crons reading `knowledge-base/`, build-time
    reads of root files, agent-steering files outside the basename set).
  - `--pr` supports one repository (and its forks). The `plugin -> github` enumeration in the C4 model is
    illustrative.
- The script emits `merge-effect-class: <verdict> reason=<token>` on stderr, deliberately not a `SOLEUR_*` marker:
  it runs on the user's own CLI (observability layer 7) and no hosted code calls it.
- The ADR-289 `adopting` to `accepted` flip is not part of this decision; it has its own tracking issue.
- No C4 change: the existing `plugin -> github` edge already covers authenticated read-only `gh` reads of the
  user's own repository, and a PR's changed-file list is the same read class.

## Cost Impacts

None.

## NFR Impacts

None.

## Principle Alignment

- AP-024 (a verification surface does not actuate): Aligned. The classifier prints a verdict and authorizes nothing.
- AP-020 (PR-controlled filenames are hostile input): Aligned. No path text is echoed, control characters are
  rejected, and the verdict leaves through one function that cannot print "not" beside a non-zero exit.
- AP-007 (exhaust automation before manual steps): Aligned. The warning clause comes from a machine check, not
  from an agent's or operator's recollection of which paths fire which workflows. Unknown paths, unreadable lists
  and unknown trigger keys take the stricter outcome.
- AP-011 (decisions recorded before code): Aligned. This ADR is the first commit of the pull request.
