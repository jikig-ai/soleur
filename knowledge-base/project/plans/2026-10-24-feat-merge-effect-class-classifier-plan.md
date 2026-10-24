---
title: "P2: merge-effect-class.sh classifier for production-effecting merges"
date: 2026-10-24
slug: merge-effect-class-classifier
branch: feat-one-shot-10923-merge-effect-class
issue: 10923
ref: 9757
closes: none
type: feat
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# P2: merge-effect-class.sh classifier for production-effecting merges

## Overview

Issue #10923 (item P2 of the CTO follow-up list on umbrella #9757) asks for a script that decides, from the
files a pull request changes, whether merging it to main can change production, plus the architecture
decision record that says how that verdict may be used. The decision record is written and committed first;
code follows it.

The planning phase read the existing delegation and classifier code, as the issue directs, and re-scoped the
ask on the CTO's rulings (section "Rulings"): the script is a read-only, closed-world classifier whose one
consumer only adds a warning to the operator's merge question. The optional "merge changes referencing epic
#N" delegation Scope class is recorded as rejected, with flip conditions, and is not built.

Umbrella #9757 stays open. The PR body carries `Ref #9757` and no closing keyword. The merge goes through the
merge queue with `gh pr merge <N> --squash --auto`, never `--admin`. The PR edits neither
`.github/workflows/apply-web-platform-infra.yml` nor anything under `apps/**`, and leaves
`scripts/registry-restore-from-ghcr.sh` and the apply-workflow restore-step annotations alone, so no
production apply is fired by this merge and no operator authorization is needed.

## Research Insights

### Premise Validation (Phase 0.6)

- `#10923` is OPEN with no closing PR; `#9757` is OPEN. The issue title says P2 but carries the label
  `priority/p3-low`; the plan follows the label for `priority:`.
- `merge-effect-class` exists nowhere on `origin/main` (`git ls-tree -r --name-only origin/main`), and no
  "merge changes referencing epic" scope class exists in `plugins/` or `knowledge-base/engineering/`. This is a
  build, not a fix.
- ADR corpus (Phase 0.6 item 4): ADR-289 (`status: adopting`) is the parent. It rejects "an act-class label
  written by the same agent" (Option C) and records the shared-identity, unpinned-envelope and
  verifier-trust-base residuals. Nothing in it rejects a read-only path classifier, but its Option C is exactly
  the objection to the optional scope class. ADR-084's operator-only list is amended by ADR-289 and is not
  touched here.
- Next free ordinal is ADR-297 (highest on `origin/main` is ADR-296; no `ADR-297..299` on any `origin/*` ref). It
  is provisional: ship's ADR-ordinal gate re-verifies it.
- Git identity prints `Jean Deruelle` / `jean.deruelle@jikigai.com` (checked before planning).
- Measured (PyYAML over `.github/workflows/*.yml`, 2026-10-24): 29 workflows have an `on.push` that can run on
  main or a `workflow_run` arm with no branch filter or one matching main: 18 with a path-filtered push (two of
  them, web-platform-release and deploy-docs, also carry a `workflow_run` arm), 7 with an unfiltered push (ci,
  codeql-main-alert-gate, secret-scan, skill-security-scan-corpus, skill-security-scan-postmerge,
  tenant-integration, vendor-pin-verify) and 4 `workflow_run`-only (apply-delivery-gap-follower,
  fix-constraints-stage-b, npm-publish, post-merge-monitor). The count is a snapshot; the parity test, not this
  paragraph or the ADR, is the source of truth. PyYAML parses the `on:` key as the boolean `True`.

### Property List (Phase 0.6b)

1. Given a PR's changed-file list, a caller can tell whether merging could fire a push-to-main production
   workflow (infra apply, release, deploy). Unknown, empty, unreadable or incomplete input reads as "could".
2. The operator's interactive merge question says "may change production" from a machine verdict, not from
   agent prose.
3. The verdict cannot silently drift from the workflows' real triggers: adding a main-push workflow, or
   widening a production trigger over an allowlisted path, turns CI red.
4. The decision, including the rejected authority widening and its flip conditions, is on record before code.

### Cut List (Phase 0.6b and plan review)

| Mechanism | Property it would buy | Disposition |
|---|---|---|
| Delegation Scope class "merge changes referencing epic #N", verifier row, edits to `standing-delegation.md` sections 1-2 | none of 1-4 (it widens authority; optional in the issue) | Cut (CTO F3). Rejected in ADR-297 with flip conditions. ADR-289 Option C already rejects the agent choosing its own class. |
| Multi-valued class | 1 | Cut (CTO F2). Binary closed-world verdict. |
| Run-time parse of `on.push.paths` in the shipped script | 3 | Cut (CTO F1). Static allowlist plus a CI parity test. |
| `git show origin/main:` execution pin and self-edit rule | 1 | Cut (CTO R-a). `plugins/soleur/**` is off the allowlist and skills resolve the script via `${CLAUDE_PLUGIN_ROOT}`. |
| Mode gate from `scripts/ci-e2e-classify.sh` | none | Cut. A names-only list cannot carry modes; push triggers match on names. |
| Cross-check of ship's `Blast Radius:` label | 2 | Cut (CTO R-b). Revisit on a second consumer or a real label/verdict mismatch. |
| Flip of ADR-289 `adopting -> accepted` | none | Not in this PR (CTO F4); tracked by an issue (task 4.3). |
| Registry `gate` column with `runtime-pathspec:<file>#<anchor>` and `chained:` shapes | 3 | Cut (CTO R2, plan review). Flat ci-only list; the only deemed-gated case is a one-entry constant pinned by the existing P3 test. |
| ci-only marker tripwire and exemption baseline | 3 | Cut (CTO R3). It false-reds on substrings, needs a baseline, and cannot loosen the shipped verdict. Every ci-only row carries a reason and ADR-297 names the list as review-owned. |
| sha256 table id on stderr, path echo, `timeout`/`gtimeout` `tool-missing` branch | none | Cut (CTO R5). `sha256sum` is absent on stock macOS; admin-merge-ready.sh has no timeout branch; failure is already fail-closed. |
| `model.c4` description edit and `model.likec4.json` regeneration | none | Cut (CTO R6): the existing `plugin -> github` edge already covers authenticated read-only `gh` reads of the user's own repository. ADR-297 records the cited no-impact check. |
| Phase 4.0 simulated-revert task | none | Cut (CTO R8). The PR holds no state; rollback is one `git revert`. |
| Full ten-mutant executable harness | 3 | Reduced to at most six executable mutants (CTO R4); the rest are table rows. |

### Institutional learnings applied

- `2026-09-22-the-admin-merge-gate-read-ready-from-an-empty-body.md`: decide positively; shape-check API
  bodies with `jq -e`; an incomplete file list (3000 cap, `changedFiles` mismatch) is a refusal; never print
  PR-controlled filenames.
- `2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md`: pathspec `*` crosses `/`, ERE does not;
  every predicate needs an empty-input guard.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`: write the mutation
  matrix from the design before the guard.
- `2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`: an unknown path class returns the stricter
  verdict, never SKIP.
- `2026-10-12-a-guard-parsed-under-one-awk-...`, `2026-09-17-awk-word-boundary-backslash-b-is-backspace.md`: the
  script targets bash 3.2 and mawk.
- `2026-10-05-a-reader-that-exits-early-flipped-three-suites-...`: avoid `| grep -q` pipes in the new tests (the
  pipe-guard table pins their count); capture `rc=$?` from a redirect.
- `workflow-patterns/2026-07-05-adr-renumber-must-sweep-planning-docs-and-scripts-glob-orphan.md`: if ADR-297 is
  renumbered at ship, sweep this plan, `tasks.md` and any AC naming the ordinal.

### Open Code-Review Overlap

None. Checked the open `code-review` issues for `operator-holds.md`, ship `SKILL.md`, `admin-merge-ready.sh`,
`scripts/ci-e2e-classify.sh`, ADR-289 and `standing-delegation.md`.

## Research Reconciliation - Spec vs. Codebase

| Claim (issue / brief / earlier plan text) | Reality | Plan response |
|---|---|---|
| "infra, migration or main-push-triggered production workflow paths mean production-effecting" implies a path-to-class mapping | Migrations under `apps/web-platform/supabase/migrations/` are covered by `apps/web-platform/**` in `web-platform-release.yml`; infra by the apply workflows. The verdict needs only the complement: an allowlist of paths that fire nothing. | Closed-world allowlist (`knowledge-base/` prefix, root-level `*.md`); everything else, including unknown, is effecting. |
| "Optionally add a delegation Scope class ... and edit sections 1-2 of standing-delegation.md" | Scope binding (V2) is a whole-token match on a PR number; a class keyed on "references epic #N" lets the agent that writes the PR body choose its own class (ADR-289 Option C). | Not built. ADR-297 records it rejected with four flip conditions. |
| (earlier plan text) "a stale installed copy only over-warns" | False (Kieran P1-2): a lagging allowlist can under-warn after a later PR widens a trigger over an allowlisted path. | Withdrawn. ADR-297 states the true residual: that PR itself edits `plugins/soleur/**` or a workflow, so it is effecting and seen; the window is the plugin update lag, bounded and accepted. Flip: a lag actually observed adds skew detection. |
| (earlier plan text) 25 listed push workflows | 29 enumerated, including `workflow_run` arms with no branch filter (npm-publish, post-merge-monitor, fix-constraints-stage-b, apply-delivery-gap-follower) | Enumeration rule widened; the test derives the population. |
| (earlier plan text) "exit 0 means a verdict was produced" | `if script; then skip-warning` would then read an effecting verdict as safe | Exit 0 only for `not-production-effecting` (CTO R1). |
| The directive says "ship Merge Danger outcome sentence" | `## Merge Danger` has only `Undo:` and `Blast Radius:`; the only outcome sentence is operator-holds.md section 3 step 2. | One consumer edit: operator-holds.md section 3 step 2 (CTO R-b). Ship `SKILL.md` untouched. |
| The plugin is a Soleur-repo tool | It also ships to customer repos whose triggers the allowlist cannot know. | `--pr` exits 2 `not-applicable` unless the repo root carries the committed ci-only list (CTO R-c; precedent `deploy-arm.sh` `scope_guard`). |

## Rulings

Persisted as rows in `knowledge-base/project/specs/feat-one-shot-10923-merge-effect-class/decision-challenges.md`
(all class `technical`; no operator authorization is required because nothing here grants new authority).

- **F1** Ruled by CTO agent, 2026-10-24: static path table in the script plus a CI parity test that reads the
  workflows' triggers and fails in both directions.
- **F2** Ruled by CTO agent, 2026-10-24: binary closed-world verdict; `plugins/soleur/**` is effecting. Exit
  contract amended by R1.
- **F3** Ruled by CTO agent, 2026-10-24: ship ADR + script + tests + exactly one consumer; the epic-reference
  scope class is out (flip needs a separate ADR and the founder's authorization at that time).
- **F4** Ruled by CTO agent, 2026-10-24: new ADR-297 extending, not amending, ADR-289; no status flip here.
- **F5/R-a, R-b, R-c** Ruled by CTO agent, 2026-10-24: `--files-from` primary and `--pr` a thin wrapper; no
  `origin/main` pin; single consumer edit in operator-holds.md; `--pr` applicability sentinel.
- **R1-R8** Ruled by CTO agent, 2026-10-24 (after the four-seat plan review): exit 0/1/2 mapping; flat ci-only
  list with a derived witness set, small matcher and a one-entry deemed-gated constant; tripwire cut; at most six
  executable mutants; script trimmed; C4 edit cut behind a cited check; both tracking issues kept; simulated
  revert cut and ADR trimmed.

## Proposed Solution

### The verdict

`plugins/soleur/scripts/merge-effect-class.sh`:

```text
merge-effect-class.sh --files-from <path|->      # one path per line; the caller lists BOTH sides of a rename
merge-effect-class.sh --pr <N> [--repo OWNER/REPO]
merge-effect-class.sh --print-witnesses          # one concrete allowlisted path per allowlist entry (for the parity test)
merge-effect-class.sh --self-check               # liveness signal only, not proof of the property
```

- stdout (verdict modes): exactly one line, `production-effecting` or `not-production-effecting`.
- exit 0 ONLY for `not-production-effecting`; exit 1 for `production-effecting`; exit 2 for unusable input or
  usage, where stdout is still `production-effecting`. A caller that reads only the exit status, or only stdout,
  can never read "not" from a failure. The consumer rule is literal: capture `out=$(...)` and `rc=$?`, skip the
  warning only when `rc` is 0 AND `[ "$out" = "not-production-effecting" ]` (whole-line equality, never a grep
  or case glob, because `not-production-effecting` contains `production-effecting`).
- stderr: one line `merge-effect-class: <verdict> reason=<token>`; reason tokens: `allowlisted`,
  `outside-allowlist`, `empty-list`, `bad-path`, `incomplete-list`, `list-unreadable`, `not-applicable`,
  `usage`. No path text is ever echoed; only counts and an entry index.
- Allowlist (the only way to read `not-production-effecting`): the `knowledge-base/` prefix and root-level
  `*.md`. An explicit `*/*` rejection precedes the `*.md` arm so `apps/x/README.md` and `docs/legal/terms.md` are
  effecting. Every listed path, both sides of a rename, must match. `bad-path` (exit 2): empty line, backslash,
  leading `/`, a `..` segment, control characters, a git-quoted path (callers must pass `core.quotePath=false`;
  a quoted path reads effecting). `LC_ALL=C` throughout. The allowlist is one data array consumed by
  `is_allowed()` and by `--print-witnesses`, so a new entry automatically gets a witness in the parity test.
- `--pr`: reuse the shape of `plugins/soleur/scripts/admin-merge-ready.sh` (`gh pr view --json changedFiles`,
  then `gh api --paginate --slurp repos/{owner}/{repo}/pulls/<N>/files?per_page=100`, `jq -e` shape check,
  count FILE OBJECTS not strings so a rename is not double counted, `changed >= 3000 || nfiles != changed` is
  `incomplete-list`), collecting `filename` and `previous_filename` per object. Every `gh` call is a GET with the
  query in the URL (no `-f`/`-F`, which would flip it to POST), reads no stdin, and any failure is
  `list-unreadable`. A concurrent push between the two reads shows as `incomplete-list`: fail-closed, an
  over-warn. Exits 2 `not-applicable` unless `git rev-parse --show-toplevel` (the cwd repo, not the script's own
  directory) carries `plugins/soleur/scripts/merge-effect-class.ci-only.tsv` (precedent `deploy-arm.sh`
  `scope_guard`).
- `--files-from`, `--print-witnesses` and `--self-check` are pure (no `gh`, no repo). `--self-check` classifies
  an embedded probe set (one allowlisted path, one production path, one unknown path, one empty list) and prints
  `self-check ok` (exit 0) or `self-check FAILED` (exit 1); its usage text says it is a liveness signal, because
  probes and allowlist live in the same file and a joint mutation stays green.
- Portability: bash 3.2 and mawk; no `mapfile`, associative arrays, `date -d`, `sed -i`, `readlink -f`,
  `sha256sum`. A NUL byte cannot survive `read`; git paths cannot contain one, so no NUL row exists in the matrix.

What the verdict means, and does not: "no push-triggered production workflow fires on these paths". It is not
"no runtime effect": scheduled crons that read `knowledge-base/` are out of scope, and the verdict judges the PR's
file list, which equals the squash commit's unless main moved in the queue. ADR-297 states both limits and that
the classifier authorizes nothing.

### The ci-only list and the parity test

`plugins/soleur/scripts/merge-effect-class.ci-only.tsv`: `workflow<TAB>reason`, one row per enumerated
main-push or main-`workflow_run` workflow that cannot mutate production. Closed-world: an enumerated workflow
that is not on the list is `production`. Every row needs a non-empty reason; a row naming a workflow that does not
exist, or that is no longer enumerated, fails. The header comment says the file is test data plus the
applicability sentinel and is never consulted for a verdict. Review-owned: ADR-297 names it so.

`plugins/soleur/test/merge-effect-class-parity.test.sh` (python3 -I with PyYAML, test-only; as
`ci-concurrency-key.test.sh` already does; a missing PyYAML fails loudly, never skips):

1. Enumerate: `on.push` whose `branches` is absent or matches main and is not tags-only, plus every
   `workflow_run` arm whose `branches` is absent or matches main. Handle the `True` key and scalar, list and dict
   forms of `on`.
2. Effective trigger of a `production` workflow: its positive `on.push.paths` (and `paths-ignore`); a
   `workflow_run`-only workflow inherits its parent's (by `name:`) effective trigger, transitively; a cycle or an
   unresolved parent fails. A workflow with both its own `push.paths` and an unfiltered `workflow_run` arm is
   deemed gated by its own paths ONLY for the one-entry constant `web-platform-release.yml`, and the test asserts
   `workflow-run-deploy-invariants.test.sh` still contains the P3 assertion; any other such workflow, and any
   production workflow with an unfiltered trigger, fails with "add a ci-only row with a reason or extend the
   constant".
3. Direction 2 (the property): every witness from `--print-witnesses` is matched against every production
   workflow's effective trigger by a small GitHub-glob matcher modelling only `**`, `*`, `!` (negation, last
   match wins) and `paths-ignore`; any other special character fails with "extend the matcher". A witness that
   fires a production workflow fails.
4. Direction 1 (anti-vacuity): for every production workflow, instantiate one positive glob (`**` -> `a/b/c`,
   `*` -> `x`), assert the matcher says it fires AND the real script reads it `production-effecting`. A table
   unit test pins the matcher (`a/**`, `**/x`, `*.md` not crossing `/`, negation, negation-only lists).
5. Every red message is actionable: a paste-ready ci-only row for an unregistered workflow, "workflow X deleted,
   remove this row", "allowlist entry P fires workflow W: remove the entry or narrow W's paths".
6. Test seams so the matrix runs without editing `.github/workflows/`: `MEC_WORKFLOWS_DIR` and `MEC_CI_ONLY_LIST`.

Expect to classify, with deliberate reasons read from each workflow, several unfiltered ones in this PR
(post-merge-monitor, fix-constraints-stage-b, ci.yml and the other unfiltered CI-only workflows). **Stop
condition:** if reading a workflow shows an unfiltered trigger whose firing mutates production on EVERY merge,
the verdict's premise fails for that workflow; stop and take it back to the CTO rather than giving it a ci-only
reason.

### The one consumer

`plugins/soleur/skills/ship/references/operator-holds.md` section 3, step 2 (Ask): replace "when the merge
triggers a production apply or deploy (any workflow that runs on push to main for the changed paths ...) the
outcome sentence says so" with: for each named PR run `out=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-effect-class.sh"
--pr <N>)` and `rc=$?`; leave out the warning only when `rc` is 0 and `[ "$out" = "not-production-effecting" ]`;
otherwise the sentence says the change "may change production". The consumer only adds the warning; it never
relaxes anything and never records a delegation. The plugin-root paragraph at the top of that file already
governs `${CLAUDE_PLUGIN_ROOT}`. No other prose is rewritten (go.md, cto.md and the Merge Danger block stay).

## Architecture Decision (ADR/C4)

### ADR

Create `knowledge-base/engineering/architecture/decisions/ADR-297-merge-effect-classifier-is-a-closed-world-allowlist-and-authorizes-nothing.md`
via `soleur:architecture` (rich shape: trigger 5, teeth-bearing alternatives). `status: active`,
`related_adrs: [ADR-289, ADR-084, ADR-276]`; it extends ADR-289 in prose. Content: Context (the held-merge
session, in a paragraph; no copied trigger table, the parity test is the live source); Considered Options (A
runtime parse, C epic-reference scope class, D amend ADR-289 as full entries; B multi-valued class and E
`origin/main` pin as one line each); Decision (closed-world allowlist, exit 0/1/2 contract, ci-only list plus
parity test with derived witnesses, single consumer, applicability sentinel); Consequences and residuals
(**stale installed copy can under-warn after a later PR widens a trigger over an allowlisted prefix; that PR
itself edits `plugins/soleur/**` or a workflow so it is effecting and seen; the window is the plugin update lag,
bounded and accepted; flip: a lag actually observed adds skew detection**; scheduled crons reading
`knowledge-base/`; queue-moved main; the ci-only list is review-owned and a mislabel only matters if the
workflow fires on an allowlisted witness path, which direction 2 covers; flip: a real mislabel adds a check);
**Rejected for now: the epic-reference scope class**, with flip conditions (1) the classifier runs from
`origin/main`, (2) the scope binds to a PR whose author and file list the verifier fetches itself, with a
human-authored link recorded in the delegation, (3) the #10361 receipt hook exists, (4) ADR-289's two residuals
(envelope not pinned to `origin/main`, verifier trust base) are closed; a flip is a separate ADR and needs the
founder's authorization at that time. Cost Impacts: none. NFR Impacts: none. Principle Alignment: AP-024 (a
verification surface does not actuate), AP-007, AP-011. The ADR is the first commit of the PR (AC1).

### C4 views

No C4 change. All three of `model.c4`, `views.c4`, `spec.c4` in
`knowledge-base/engineering/architecture/diagrams/` were read. Checked and already modeled: (a) external human
actor: the operator is `founder`, unchanged, no new access relationship; (b) external system: GitHub, edge
`plugin -> github`, whose description in `model.c4` already states that, since ADR-289, "the delegation verifier,
the hold evaluator, the ship gate ... and the overlap preflight read the epic's Standing Delegation comment,
receipts, workflow runs and open pull requests of the USER'S OWN repository through the user's own authenticated
gh CLI, read-only; they run on the user's machine and Jikigai receives nothing" - a PR's changed-file list is the
same read class, so the description is not falsified (CTO R6: no edit unless it were); (c) data store: the
ci-only list is plugin-internal static data under `platform.plugin` (no new element); (d) actor-to-surface
access: unchanged. `plugins/soleur/test/c4-count-parity.test.sh` is still run (counts do not move).

### Sequencing

The decision is true as soon as the PR merges (no soak), so there is no `adopting` window; the ADR is authored
first and committed before code.

## Implementation Phases

### Phase 0 - ADR first (no code)

0.1 Re-verify ADR-297 is free (`git fetch origin main`; list `origin/*` refs). 0.2 Write the ADR via
`soleur:architecture`. 0.3 Commit it alone (`docs(adr): ADR-297 ...`). Nothing under `plugins/soleur/scripts/`
or `scripts/` is committed before this commit (AC1).

### Phase 1 - RED tests, then the guard (Guard Contract written before this phase)

1.1 Write `plugins/soleur/scripts/merge-effect-class.test.sh` against the Guard Contract: table-driven rows,
exit/stdout contract, the consumer-rule rows, the minimum-assertion floor, and at most six executable mutants on
a scratch copy (string replacement into a temp file, `mv`, `cmp` proves the mutation landed, each mutant must flip
a named row). Run RED.
1.2 Write the ci-only list and the parity test with its matcher unit table and the `MEC_*` seams; classify each
unfiltered workflow by reading it (stop condition above). Run RED.
1.3 Implement `plugins/soleur/scripts/merge-effect-class.sh`. GREEN.
1.4 Measure the base rate: run `--pr` over the last ~50 merged PRs (read-only `gh`) and record the verdict
distribution in the PR body. If more than about half warn, record that as a follow-up to add an area token to the
stderr line (no third verdict value); do not build it here.

### Phase 2 - consumer

2.1 Edit operator-holds.md section 3 step 2 with the literal `rc` and whole-line rule. 2.2 Run
`plugins/soleur/test/go-hold-routing.test.sh`, `cto-interface-selector.test.sh`, `pr-overlap-preflight.test.sh`
and the hold-evaluator suite (they read operator-holds.md anchors) to confirm none pins the replaced sentence.

### Phase 3 - registration (hazards from the brief)

3.1 Add the `AFFECTED_*` array in `scripts/lib/test-affected-paths.sh` naming `.github/workflows/*.yml`, the
ci-only list AND `plugins/soleur/scripts/merge-effect-class.sh` (editing the allowlist is the exact weakening the
parity test exists to catch; DHH P1). 3.2 Add rows to `scripts/suite-shard-legs.tsv`,
`scripts/suite-durations.tsv` and `plugins/soleur/test/fixture-relative-assert.baseline.txt` only where a linter
reports a gap (precedent commit `cdcbab27cf`). 3.3 Run locally, detached with an rc file where longer than 100 s:
`scripts/lint-orphan-test-suites.sh` (again once the files are tracked), `scripts/markdown-lint.sh --repo-sweep`,
`bash .claude/hooks/grep-q-pipe-guard.test.sh` (the new suites use no `| grep -q` and do not stub `sha256sum`, so
`PJ_TRIPLES` should not move; if it must, rebase on main first, that table conflicts often), the
affected-index ratchet (expect red from main's own drift; advisory), and `plugins/soleur/test/c4-count-parity.test.sh`.
Known cost, stated up front: a new suite for a workflow-YAML subject under `plugins/soleur/test/` needs an
`AFFECTED_*` declaration (the census reports it UNCLASSIFIED otherwise), which degrades the local
`test-all.sh --affected` gate to the full battery (`INDEX-UNBOUND`) and a sibling full run then refuses (rc=4);
the local substitute gate is the consumer suites, the ratchets and CI's full battery. `workflow-run-deploy-invariants.test.sh`
and `ci-concurrency-key.test.sh` are already declared, so the tax is not new. The new stderr line is
`merge-effect-class: ...`, deliberately NOT a `SOLEUR_*` marker, so no `MARKER_RE` telemetry registration is owed.

### Phase 4 - ship hygiene

4.1 `git config user.name; git config user.email` must print `Jean Deruelle` / `jean.deruelle@jikigai.com`
before the first commit (a `t` / `t@t` value is removed from the shared bare-repo config). 4.2 PR body: `Ref
#9757` only, `## Merge Danger` block (`Blast Radius: plugin`), `## Changelog`, the verdict-distribution record,
the suites' final verdict lines. 4.3 File two tracking issues with milestone from
`knowledge-base/product/roadmap.md`: the ADR-289 `adopting -> accepted` flip (its own one-line PR; cite receipts
`issuecomment-6339592687` and `issuecomment-6344903791`) and the epic-reference scope-class revisit (the four flip
conditions). 4.4 Merge via `gh pr merge <N> --squash --auto`; never `--admin`; no operator question is needed
because the PR touches no apply workflow. 4.5 Run `technical-ruling-gate.sh --branch` and `npx markdownlint-cli2`
on the plan, `tasks.md` and `decision-challenges.md` before the first commit of those files.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-297-merge-effect-classifier-is-a-closed-world-allowlist-and-authorizes-nothing.md`
- `plugins/soleur/scripts/merge-effect-class.sh`
- `plugins/soleur/scripts/merge-effect-class.test.sh`
- `plugins/soleur/scripts/merge-effect-class.ci-only.tsv`
- `plugins/soleur/test/merge-effect-class-parity.test.sh`
- `knowledge-base/project/specs/feat-one-shot-10923-merge-effect-class/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10923-merge-effect-class/decision-challenges.md`

## Files to Edit

- `plugins/soleur/skills/ship/references/operator-holds.md` (section 3 step 2 only)
- `scripts/lib/test-affected-paths.sh`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`,
  `plugins/soleur/test/fixture-relative-assert.baseline.txt` (registration, only where a linter reports a gap)

Not touched, by constraint: `.github/workflows/**`, `apps/**`, `scripts/registry-restore-from-ghcr.sh`,
`plugins/soleur/scripts/delegation-verify.sh`, `standing-delegation.md`, ship `SKILL.md`, `model.c4`,
`model.likec4.json`, `AGENTS*.md`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a merge question that says nothing about production changing
  when it can (a false `not-production-effecting`), so the operator answers "Yes" without the warning.
- **If this leaks, the user's workflow is exposed via:** nothing. The script reads a PR's changed-file list with
  the user's own `gh` session, writes nothing, prints no file contents and echoes no path.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the verdict only adds a warning and authorizes nothing (ADR-289 still
  needs a valid delegation or an in-session go for every act), so one wrong verdict cannot cause an unauthorized
  production change; a systematically wrong table would under-warn across many merges, hence `aggregate
  pattern` rather than `none`. No sensitive path (preflight Check 6 regex) is touched.

## Observability

Plugin script executing on the customer's own CLI: observability layer 7 (`cli-stdout-artifact`). It never runs
hosted. The durable artifact is the ci-only list in git plus the verdict lines the consumer records in the PR body.

```yaml
liveness_signal:
  what: per-invocation stdout verdict line, exit status and a stderr line "merge-effect-class: <verdict> reason=<token>" (cli-stdout-artifact); CI parity test result for table drift
  cadence: per merge-question invocation; parity test on every PR that touches .github/workflows, the ci-only list or the script
  alert_target: the operator-visible merge question in-session; a red parity-test check on the PR
  configured_in: plugins/soleur/scripts/merge-effect-class.sh; plugins/soleur/test/merge-effect-class-parity.test.sh
error_reporting:
  destination: stderr reason token and exit 2 (cli-stdout-artifact); the consumer maps any rc other than 0 with the exact line to the "may change production" wording
  fail_loud: stdout is still "production-effecting" on exit 1 and exit 2, so no caller reading stdout or the exit status alone can read "not" from a failure
failure_modes:
  - mode: PR file list unreadable, truncated (>= 3000) or length-mismatched
    detection: cli-stdout-artifact - exit 2 with reason list-unreadable / incomplete-list
    alert_route: operator sees the stricter "may change production" sentence in the merge question
  - mode: a new main-push workflow, or a widened production trigger, is not reflected in the allowlist
    detection: workflow run log - the parity test fails on the PR that introduces it, with a paste-ready fix
    alert_route: red check on that PR (test-scripts shard), named in the failing line
  - mode: script run in a customer repo
    detection: cli-stdout-artifact - exit 2 reason=not-applicable
    alert_route: stricter wording in the consumer; no verdict claimed
logs:
  where: session tool-result stdout/stderr; verdict line recorded in the PR body
  retention: the PR body for the life of the PR; the ci-only list in git
discoverability_test:
  command: bash plugins/soleur/scripts/merge-effect-class.sh --self-check
  expected_output: self-check ok
```

The probe is offline, needs no credentials, contains no shell-active character (preflight Check 10 rejects `|`,
`;`, `&`, `<`, `>`, `$` and backticks anywhere) and finishes well under the 15 s cap. It is a liveness signal,
not proof of the property (the suites are); the suite asserts the literal command prints `self-check ok`.

## Guard Contract

### Guard 1 - the classifier verdict (`merge-effect-class.sh`)

**Property.** No changed-file list that contains a path firing a production workflow, or any path outside the
allowlist, or any unusable input, can produce the line `not-production-effecting` with exit 0.

**Assembly.** One chokepoint: `classify_list()`, reached by `--files-from` and `--pr` (the `--pr` wrapper only
builds a list and calls it). The allowlist is one data array read by `is_allowed()` and `--print-witnesses`. All
input gates (empty, bad-path, incomplete, applicability) run before `is_allowed()`, and every verdict leaves
through one `emit()` that forces stdout to `production-effecting` unless exit is 0; `--self-check` and
`--print-witnesses` are the only other stdout writers and print no verdict line. Members drift; the structural
guarantee is that `emit()` is the only writer of a verdict line.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Widen the allowlist array (`apps/` or `plugins/soleur/docs/`) [executable mutant] | RED (parity witness fires a production workflow; table row fails) |
| 2 | Gut the dispatch to `classify_list` so the script prints a fixed verdict having "checked 0" [executable mutant] | RED (empty-list, unknown-path and exit-2 rows; assertion floor) |
| 3 | List `knowledge-base/a.md` FIRST and `apps/web-platform/x.ts` SECOND, loop stops at the first allowlisted member [executable mutant] | RED (second member after a compliant first) |
| 4 | Map exit 2 to stdout `not-production-effecting` [executable mutant] | RED (contract rows) |
| 5 | Delete the `*/*` rejection before the `*.md` arm [executable mutant] | RED on `apps/x/README.md`, `docs/legal/terms.md`, `plugins/soleur/docs/x.md` |
| 6 | Invert the exit mapping (0 for effecting) [executable mutant] | RED (a consumer idiom `if script; then` row and the whole-line row) |
| 7 | A rename with an allowlisted old side and non-allowlisted new side (and the reverse) | RED when only one side is checked |
| 8 | Empty, 3000-entry, count-mismatched and unreadable lists; `--pr` outside a repo without the ci-only list | RED if any prints `not-production-effecting` or lacks exit 2 |
| 9 | Unknown top-level path; the script's own path; `knowledge-base-evil/x.md` (prefix without the slash) | RED if read as not-effecting |
| 10 | `..`, leading `/`, backslash, a forged newline-and-verdict filename, a git-quoted path | RED if allowlisted or if any raw path text reaches stdout/stderr |

**Harness rows.** (i) Replace the suite's pristine control with a stub that exits 0 with no output: the suite
must go RED (it asserts a minimum assertion count, so `0 passed, 0 failed` cannot exit 0). (ii) A consumer
written with a substring match (`grep production-effecting`) or `case *production-effecting*` reads the safe
verdict as effecting: the suite carries that consumer as a must-detect row, plus the consumer's `rc != 0`
branch. Must-PASS inputs that are NOT the canonical: a deep path with spaces and non-ASCII under
`knowledge-base/`, and `CHANGELOG.md` at the root, both read `not-production-effecting`; a rejecting-everything
stub fails these.

**Anchor.** The allowlist is a stored claim about the workflows' triggers. What outside this commit must also
move for a weakening to pass: the parity test (Guard 2) reads `.github/workflows/*.yml` independently of the
script and derives its witnesses from the script's own data, so widening the allowlist over a production
trigger reds it; and `plugins/soleur/**` is effecting, so any edit of the script or list is itself judged
production-effecting by every consumer.

### Guard 2 - the parity test (`merge-effect-class-parity.test.sh`)

**Property.** Every workflow that can run on a push or `workflow_run` to main is either on the reviewed ci-only
list or treated as production, and no allowlisted path fires a production workflow.

**Assembly.** The population is derived from `.github/workflows/*.yml` (every `on.push` with main or no branch
filter, every `workflow_run` arm with no branch filter or matching main, `True`-key and scalar/list forms
handled), never from the ci-only list, which is the thing under test. Chokepoint: one `effective_trigger(workflow)`
function used for the witness direction and the anti-vacuity direction. Trigger shapes are the whole model:
`push.paths`/`paths-ignore`, unfiltered, chained by `name:` (transitive), and the one deemed-gated constant;
anything else fails.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a new push-to-main workflow with no ci-only row (default production, unfiltered) | RED with a paste-ready ci-only row in the message |
| 2 | Empty or zero-population run ("0 checked": empty workflows dir, empty list) | RED (minimum-population floor plus set identity: derived set equals list plus production set) |
| 3 | Add a SECOND unregistered workflow after a compliant one | RED (loop does not stop at the first) |
| 4 | A `workflow_run` workflow with no `branches` key and no ci-only row | RED |
| 5 | Remove a `paths:` filter from a production workflow | RED (fires on every path, including witnesses) |
| 6 | Widen a production `paths:` glob to cover `knowledge-base/**` or `*.md` | RED |
| 7 | A ci-only row with an empty reason; a row naming a deleted workflow | RED (each) |
| 8 | A chain cycle or an unresolved parent `name:` | RED (each) |
| 9 | A glob using `?`, `+` or `[` | RED "extend the matcher" (never silent) |
| 10 | A second workflow with its own `push.paths` and an unfiltered `workflow_run` arm | RED (only the web-platform-release constant is deemed gated) |

**Harness rows.** Edit the suite so its direction-1 instantiation can no longer fire its workflow: RED. Delete the
P3 assertion text from `workflow-run-deploy-invariants.test.sh` in a scratch copy: RED. Must-PASS non-canonical:
a synthetic fixture with `paths-ignore` covering `knowledge-base/**`, and a negated glob `!knowledge-base/**`
after a positive one, must read as NOT firing the witnesses.

**Anchor.** The ci-only classification is human-reviewed registry data; every row needs a reason; ADR-297 names
the list as review-owned and states the bound (a mislabel matters only if the workflow fires on an allowlisted
witness path, which direction 2 covers). A population floor is paired with set identity, never a count alone.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add `merge-effect-class.sh`: infra, migration or main-push-triggered production workflow paths mean production-effecting; an unknown path means production-effecting (stricter default)." [issue #10923] | Phase 1.3, Guard 1, `plugins/soleur/scripts/merge-effect-class.sh` | mapped |
| 2 | "Optionally add a delegation Scope class \"merge changes referencing epic #N\" with a verifier test row, and edit sections 1-2 of `standing-delegation.md`." [issue #10923] | ADR-297 Considered Options and flip conditions | descoped - justification: optional in the issue; CTO ruled F3 that it widens an irreversible production-mutating authorization and moves class choice to the PR author (ADR-289 Option C); recorded as rejected with four flip conditions |
| 3 | "needs an ADR first, then code" / "The plan must sequence the ADR before any code." [issue #10923, brief] | Phase 0, AC1 | mapped |
| 4 | "the PR starts with a read of the existing delegation and classifier code ... and may re-scope" [issue #10923, brief] | Research Insights, Reconciliation table | mapped |
| 5 | "Spawn soleur:engineering:cto for the design fork (technical ruling; record \"Ruled by CTO agent\")" [brief] | Rulings, decision-challenges.md | mapped |
| 6 | "PR body uses `Ref #9757` only, never a closing keyword." [brief] | Phase 4.2, AC9 | mapped |
| 7 | "Merge through the merge queue with `gh pr merge <N> --squash --auto`, never `--admin`." [brief] | Phase 4.4, AC10 | mapped |
| 8 | "Do not touch the apply-workflow restore-step annotations. Keep apps/** and scripts/registry-restore-from-ghcr.sh unchanged." [brief] | Files to Edit "Not touched", AC8 | mapped |
| 9 | "Any new file a test sources or reads must be registered in the selector arrays, the orphan lint, the pipe-guard table ... and, if a suite names it, the ratchet accept file." [brief] | Phase 3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `merge-effect-class.sh` closed-world verdict | "an unknown path means production-effecting (stricter default)" | asked |
| ADR-297 | "needs an ADR first, then code" | asked |
| operator-holds.md section 3 step 2 consumer | "Add `merge-effect-class.sh`" (a classifier needs a consumer or it is dead code) | inferred - justification: CTO F3(b) ruled exactly one read-only consumer so the verdict replaces agent prose in the operator question; without it the ADR's "informs the sentence" claim has no mechanism |
| ci-only list and parity test | "main-push-triggered production workflow paths mean production-effecting" | asked |
| `--pr` wrapper, applicability sentinel, `--print-witnesses`, `--self-check` | "Add `merge-effect-class.sh`" | inferred - justification: callers hold a PR number, not a list; the plugin ships to customer repos whose triggers the allowlist cannot know (CTO R-c); the parity test must derive its witnesses from the script or a new allowlist entry gets none; Check 10 forbids a piped probe |
| registration edits (selector array, shard legs, baselines) | "Any new file a test sources or reads must be registered ..." | asked |
| tracking issues (ADR-289 flip, scope-class revisit) | "Umbrella #9757 stays open; this is item 1 of its remaining CTO follow-ups." | inferred - justification: a deferral without a tracking issue is invisible (plan deferral-tracking check; CTO R7) |

### Split Assessment

- Subsystems touched: 3 - `plugins/soleur`, `scripts`, `knowledge-base`
- Planned files: 9 | Estimated changed lines: ~700 (ADR ~110, script ~150, tests ~350, list ~30, edits ~60)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (under every threshold; the ADR commit is separable but lands first in the same PR per the issue)

## Acceptance Criteria

### Functional Requirements

- [ ] AC1: after `git fetch origin main`, the commit that adds `ADR-297-*.md` is an ancestor of every commit that touches `plugins/soleur/scripts/merge-effect-class*` or `scripts/` (`git log --reverse --name-only --format=%H origin/main..HEAD` lists the ADR file in an earlier commit than any such path).
- [ ] AC2: `printf 'knowledge-base/a/b.md\nREADME.md\n' | bash plugins/soleur/scripts/merge-effect-class.sh --files-from -` prints exactly `not-production-effecting` and exits 0; the same with `apps/web-platform/x.ts` appended prints `production-effecting` and exits 1; `apps/x/README.md`, `docs/legal/terms.md` and `plugins/soleur/docs/x.md` each print `production-effecting`.
- [ ] AC3: empty input, an unknown top-level path, a rename with one non-allowlisted side, a `..` path and a 3000-entry list each print `production-effecting`; the unusable-input cases (empty, bad-path, incomplete) exit 2, the rest exit 1.
- [ ] AC4: `--pr <N>` run where the cwd repo lacks `plugins/soleur/scripts/merge-effect-class.ci-only.tsv` exits 2 with `reason=not-applicable`.
- [ ] AC5: `bash plugins/soleur/scripts/merge-effect-class.test.sh` and `bash plugins/soleur/test/merge-effect-class-parity.test.sh` pass, with a minimum-assertion floor, and each of the (at most six) executable mutants flips its named row RED (the suite asserts with `cmp` that the mutation landed).
- [ ] AC6: `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-24-feat-merge-effect-class-classifier-plan.md` exits 0 with two entries counted.
- [ ] AC7: operator-holds.md section 3 step 2 names the script and states the literal `rc` plus whole-line rule; `git diff --stat origin/main...HEAD -- plugins/soleur/skills/ship/SKILL.md plugins/soleur/scripts/delegation-verify.sh plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md knowledge-base/engineering/architecture/diagrams` is empty (three-dot, merge-base form).
- [ ] AC8: the suite asserts the literal discoverability command `bash plugins/soleur/scripts/merge-effect-class.sh --self-check` prints `self-check ok` (executed in the suite, not attested).

### Non-Functional / Constraints

- [ ] AC9: `git diff --name-only origin/main...HEAD -- .github/workflows apps scripts/registry-restore-from-ghcr.sh` is empty.
- [ ] AC10: the PR body contains `Ref #9757` and none of `Closes`, `Fixes`, `Resolves`; the PR is armed with `gh pr merge <N> --squash --auto` and no `--admin`.
- [ ] AC11: `git config user.name` prints `Jean Deruelle` and `git config user.email` prints `jean.deruelle@jikigai.com` before the first commit.

### Quality Gates

- [ ] AC12: `scripts/lint-orphan-test-suites.sh`, `scripts/markdown-lint.sh --repo-sweep`, `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh` and `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` pass; the affected-index ratchet result is recorded as advisory.
- [ ] AC13: the parity test fails loudly (non-zero, named reason) when PyYAML is not importable; it never skips.
- [ ] AC14: `rg -n 'ADR-29[0-9]' knowledge-base/project/plans/2026-10-24-feat-merge-effect-class-classifier-plan.md knowledge-base/project/specs/feat-one-shot-10923-merge-effect-class/` shows only the final ordinal (re-checked after any ship-time renumber).
- [ ] AC15: no text in the ADR, the script usage, the tests or operator-holds.md says "exit 0 = verdict produced" or "only over-warns".

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO ruled the design fork (F1-F6), four plan refinements (R-a to R-d) and, after the
four-seat plan review, eight consolidation forks (R1-R8) on 2026-10-24, all class `technical`; no operator
authorization question is required. Product, Marketing, Legal, Finance, Operations, Sales and Support assessed as
not relevant: no UI surface, no user-facing copy beyond one operator-question clause, no regulated data, no
vendor or cost change, no new store or connection. Mechanical UI-surface override: no `components/**`, `app/**`
or `.tsx` path in Files to Create/Edit, so no Product/UX gate.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given only `knowledge-base/**` and root `*.md` paths, then `not-production-effecting`, exit 0.
- Given any path under `apps/`, `infra/`, `.github/`, `plugins/`, `docs/`, `scripts/`, then `production-effecting`, exit 1.
- Given a rename with an allowlisted old path and a non-allowlisted new path (and the reverse), then exit 1.
- Given empty, incomplete, unreadable or bad-path input, then stdout `production-effecting` and exit 2.
- Given a forged filename containing a newline and the text `not-production-effecting`, then the output is one verdict line and no raw path text appears.

### Regression / Edge Cases

- `docs/legal/**` (pinned by SHA-256 in app code) is effecting; `knowledge-base-evil/x.md` is effecting; a root-level file with a space; a dot-file `.md`; CRLF list; a git-quoted path reads effecting.
- Parity: `paths-ignore`-only workflow; negated glob after positive; `workflow_run` arm with and without `branches`; a push workflow with `tags:` only (excluded); `on: push` scalar form; a registry row for a deleted workflow; a chain cycle.

### Integration Verification (for `soleur:qa`)

- **Script:** `bash plugins/soleur/scripts/merge-effect-class.sh --self-check` prints `self-check ok`.
- **Live PR (read-only, user's own gh session):** run `--pr` against a merged docs-only PR and a merged `apps/` PR; expect exit 0 `not-production-effecting` and exit 1 `production-effecting`. No credentials beyond `gh`; no `doppler`.

## Rollback

`git revert` of the squash commit through a revert PR (`ask Soleur "undo PR #N"`). It removes the script, ci-only
list, two suites, the ADR file, the operator-holds.md sentence and the registration rows together; the operator
question returns to agent-judged wording. Nothing is deployed and no data is touched, so there is no state to undo.

## Dependencies & Risks

- **A wrong `not-production-effecting` on a real production path is the one costly failure.** Mitigated by the closed-world allowlist, executable mutants 1-6 and the derived-witness parity test.
- **The parity test is the only drift defense.** An unfiltered production trigger fails by design; expect to classify several workflows with deliberate reasons in this PR (stop condition above).
- **Matcher scope creep:** a matcher modelling GitHub filter semantics wrongly is itself a fail-open source; the "extend the matcher" failure is the safety valve and the matcher stays small enough to read in one sitting.
- **Exit-contract text:** R1 changed F2; no text may still say exit 0 means a verdict was produced (AC15).
- **Queue-moved main:** the verdict judges the PR file list; ADR-297 says it does not claim more.
- **Stale installed copy can under-warn** (see Reconciliation); accepted, bounded by plugin update lag.
- **Dependencies:** PyYAML in the test environment (precedent `ci-concurrency-key.test.sh`, fail loudly if absent); `gh`, `jq` at runtime.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this
  plan fills it (`aggregate pattern`).
- ADR-297 is provisional: if renumbered at ship, sweep this plan, `tasks.md` and `decision-challenges.md`.
- The consumer sentence must stay clear of the phrasing `.claude/hooks/ship-operator-step-gate.sh` and
  `ship-soak-followthrough-gate.sh` match (no bullet-prefixed operator verbs, no "post-deploy verify").
- Do not claim the classifier authorizes anything; do not add a third verdict value.
- `decision-challenges.md` rows are machine-gated: header exactly `| Item | Class | Ruling |`, three cells per
  row, no literal `|` inside a row, a technical ruling starts `Ruled by CTO agent, <date>:`.
