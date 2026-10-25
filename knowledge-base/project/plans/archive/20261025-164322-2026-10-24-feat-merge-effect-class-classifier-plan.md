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

## Enhancement Summary

**Deepened on:** 2026-10-24
**Sections enhanced:** Proposed Solution, Guard Contract, Observability, Acceptance Criteria, Architecture Decision, Risks
**Research agents used:** soleur:engineering:review:architecture-strategist, soleur:engineering:review:security-sentinel, soleur:engineering:review:test-design-reviewer, soleur:engineering:review:observability-coverage-reviewer, soleur:product:spec-flow-analyzer, soleur:engineering:research:best-practices-researcher (GitHub filter-pattern docs), soleur:engineering:research:git-history-analyzer (attribution check); CTO rulings T1-T6.

### Key Improvements

1. Trigger population is closed-world over trigger keys (push, `workflow_run`, `release`, `pull_request: closed`) with a named inert list; the 29-workflow snapshot is no longer the scope.
2. The parity test gains a real-tree sweep (every tracked allowlisted path against every production trigger) and a subtree-aware anti-vacuity direction, closing the single-witness hole.
3. `--pr` binds PR state, base and head sha (twice) and the consumer must merge with `--match-head-commit`; per-object `jq` shape checks catch dropped `previous_filename`; the sentinel is repo-owned and `--repo` must equal the cwd repo.
4. The allowlist excludes `AGENTS*.md`/`CLAUDE.md` by basename at any depth; the ci-only meaning is "not directly gated by the merged file list as a production act".
5. The consumer is a literal bash block with two plain operator sentences and a recorded PR-body verdict line (the layer-7 durable artifact); acceptance criteria repaired (three-dot diffs, no attestations, a temp-repo AC4, PATH-shim AC15).

### New Considerations Discovered

- GitHub forbids `paths` with `paths-ignore` on one event and documents no `paths` filter for `workflow_run`; `?`, `+`, `[` and `\` are refused by the matcher rather than approximated.
- `PJ_TRIPLES` is 288 on `origin/main`; the claim that `merge-effect` appears nowhere was false (it appears in knowledge-base docs only).
- ship `SKILL.md`'s Deploy Pipeline Fix Drift Gate, the `Blast Radius:` label and the infra "merge-effect first line" convention are parallel statements the ADR must rank.

## Research Insights

### Premise Validation (Phase 0.6)

- `#10923` is OPEN with no closing PR; `#9757` is OPEN. The issue title says P2 but carries the label
  `priority/p3-low`; the plan follows the label for `priority:`.
- No file named `merge-effect-class*` exists on `origin/main` (`git ls-tree -r --name-only origin/main`), and no
  "merge changes referencing epic" scope class exists in `plugins/` or `knowledge-base/engineering/`. The term
  `merge-effect` itself appears in knowledge-base docs: the #10873 plan/spec archive that recorded this P2 item and
  an older "merge-effect first line" PR-body convention for infra diffs (plan Sharp Edges). This is a build, not a
  fix, and the convention is a separate agent-authored statement the classifier does not replace.
- ADR corpus (Phase 0.6 item 4): ADR-289 (`status: adopting`) is the parent. It rejects "an act-class label
  written by the same agent" (Option C) and records the shared-identity, unpinned-envelope and
  verifier-trust-base residuals. Nothing in it rejects a read-only path classifier, but its Option C is exactly
  the objection to the optional scope class. ADR-084's operator-only list is amended by ADR-289 and is not
  touched here.
- Next free ordinal is ADR-300 (highest on `origin/main` is ADR-296; no `ADR-300..299` on any `origin/*` ref). It
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
| Delegation Scope class "merge changes referencing epic #N", verifier row, edits to `standing-delegation.md` sections 1-2 | none of 1-4 (it widens authority; optional in the issue) | Cut (CTO F3). Rejected in ADR-300 with flip conditions. ADR-289 Option C already rejects the agent choosing its own class. |
| Multi-valued class | 1 | Cut (CTO F2). Binary closed-world verdict. |
| Run-time parse of `on.push.paths` in the shipped script | 3 | Cut (CTO F1). Static allowlist plus a CI parity test. |
| `git show origin/main:` execution pin and self-edit rule | 1 | Cut (CTO R-a). `plugins/soleur/**` is off the allowlist and skills resolve the script via `${CLAUDE_PLUGIN_ROOT}`. |
| Mode gate from `scripts/ci-e2e-classify.sh` | none | Cut. A names-only list cannot carry modes; push triggers match on names. |
| Cross-check of ship's `Blast Radius:` label | 2 | Cut (CTO R-b). Revisit on a second consumer or a real label/verdict mismatch. |
| Flip of ADR-289 `adopting -> accepted` | none | Not in this PR (CTO F4); tracked by an issue (task 4.3). |
| Registry `gate` column with `runtime-pathspec:<file>#<anchor>` and `chained:` shapes | 3 | Cut (CTO R2, plan review). Flat ci-only list; the only deemed-gated case is a one-entry constant pinned by the existing P3 test. |
| ci-only marker tripwire and exemption baseline | 3 | Cut (CTO R3). It false-reds on substrings, needs a baseline, and cannot loosen the shipped verdict. Every ci-only row carries a reason and ADR-300 names the list as review-owned. |
| sha256 table id on stderr, path echo, `timeout`/`gtimeout` `tool-missing` branch | none | Cut (CTO R5). `sha256sum` is absent on stock macOS; admin-merge-ready.sh has no timeout branch; failure is already fail-closed. |
| `model.c4` description edit and `model.likec4.json` regeneration | none | Cut (CTO R6): the existing `plugin -> github` edge already covers authenticated read-only `gh` reads of the user's own repository. ADR-300 records the cited no-impact check. |
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
- `workflow-patterns/2026-07-05-adr-renumber-must-sweep-planning-docs-and-scripts-glob-orphan.md`: if ADR-300 is
  renumbered at ship, sweep this plan, `tasks.md` and any AC naming the ordinal.

### Open Code-Review Overlap

None. Checked the open `code-review` issues for `operator-holds.md`, ship `SKILL.md`, `admin-merge-ready.sh`,
`scripts/ci-e2e-classify.sh`, ADR-289 and `standing-delegation.md`.

## Research Reconciliation - Spec vs. Codebase

| Claim (issue / brief / earlier plan text) | Reality | Plan response |
|---|---|---|
| "infra, migration or main-push-triggered production workflow paths mean production-effecting" implies a path-to-class mapping | Migrations under `apps/web-platform/supabase/migrations/` are covered by `apps/web-platform/**` in `web-platform-release.yml`; infra by the apply workflows. The verdict needs only the complement: an allowlist of paths that fire nothing. | Closed-world allowlist (`knowledge-base/` prefix, root-level `*.md`); everything else, including unknown, is effecting. |
| "Optionally add a delegation Scope class ... and edit sections 1-2 of standing-delegation.md" | Scope binding (V2) is a whole-token match on a PR number; a class keyed on "references epic #N" lets the agent that writes the PR body choose its own class (ADR-289 Option C). | Not built. ADR-300 records it rejected with four flip conditions. |
| (earlier plan text) "a stale installed copy only over-warns" | False (Kieran P1-2): a lagging allowlist can under-warn after a later PR widens a trigger over an allowlisted path. | Withdrawn. ADR-300 states the true residual: that PR itself edits `plugins/soleur/**` or a workflow, so it is effecting and seen; the window is the plugin update lag, bounded and accepted. Flip: a lag actually observed adds skew detection. |
| (earlier plan text) 25 listed push workflows | 29 enumerated, including `workflow_run` arms with no branch filter (npm-publish, post-merge-monitor, fix-constraints-stage-b, apply-delivery-gap-follower) | Enumeration rule widened; the test derives the population. |
| (earlier plan text) "exit 0 means a verdict was produced" | `if script; then skip-warning` would then read an effecting verdict as safe | Exit 0 only for `not-production-effecting` (CTO R1). |
| The directive says "ship Merge Danger outcome sentence" | `## Merge Danger` has only `Undo:` and `Blast Radius:`; the only outcome sentence is operator-holds.md section 3 step 2. | One consumer edit: operator-holds.md section 3 step 2 (CTO R-b). Ship `SKILL.md` untouched. |
| The plugin is a Soleur-repo tool | It also ships to customer repos whose triggers the allowlist cannot know; a plugin-owned sentinel is forgeable by any install that vendors `plugins/soleur/`, and `--repo OTHER/REPO` would bypass it (architecture and security seats). | `--pr` exits 2 `not-applicable` unless the repo root carries the repo-owned `.github/workflows/web-platform-release.yml` AND the ci-only list tracked at HEAD, and `--repo` equals the cwd repo (CTO T4, supersedes R-c; precedent `deploy-arm.sh` `scope_guard`). |
| (earlier plan text) merge-time workflows are push + workflow_run | `release` (npm-publish, reusable-release), `pull_request`/`pull_request_target` with `closed` (dev-ledger-reconcile, follow-through-closure-guard, cleanup-unmerged-bot-branches, board-status-sync) and `merge_group` also fire around a merge (security seat measurement) | Closed-world trigger-key enumeration with a named inert list (CTO T1); the verdict's meaning narrows to "no path-gated production workflow fires from this file list". |
| (earlier plan text) root `*.md` is harmless | `AGENTS.md`, `AGENTS.rules.md` and `CLAUDE.md` steer every agent session, including scheduled agents that hold secrets | Basename `AGENTS*.md` and `CLAUDE.md` are effecting at any depth (CTO T2). |
| (earlier plan text) the `--pr` verdict stays valid until the merge | A push after classification, a closed/merged PR or a stacked base makes it stale or irrelevant (spec-flow and security seats) | `--pr` reads state, base and head sha (twice); the merge uses `--match-head-commit` with the printed sha (CTO T5). |
| Other prose already states which merges apply production changes | ship `SKILL.md` Deploy Pipeline Fix Drift Gate (hand-maintained trigger array, "auto-fires on push to main"), the `Blast Radius:` label, the infra PRs' "merge-effect first line" convention, the CTO-authored `{OUTCOME}` sentence (architecture and spec-flow seats) | Left in place by design (CTO R-b); ADR-300 records the precedence: the classifier is a coarser, workflow-derived verdict that every `apps/web-platform/infra/**` path already trips, the clause is appended to the `{OUTCOME}` sentence and the stricter reading wins. |

## Rulings

Persisted as rows in `knowledge-base/project/specs/feat-one-shot-10923-merge-effect-class/decision-challenges.md`
(all class `technical`; no operator authorization is required because nothing here grants new authority).

- **F1** Ruled by CTO agent, 2026-10-24: static path table in the script plus a CI parity test that reads the
  workflows' triggers and fails in both directions.
- **F2** Ruled by CTO agent, 2026-10-24: binary closed-world verdict; `plugins/soleur/**` is effecting. Exit
  contract amended by R1.
- **F3** Ruled by CTO agent, 2026-10-24: ship ADR + script + tests + exactly one consumer; the epic-reference
  scope class is out (flip needs a separate ADR and the founder's authorization at that time).
- **F4** Ruled by CTO agent, 2026-10-24: new ADR-300 extending, not amending, ADR-289; no status flip here.
- **F5/R-a, R-b, R-c** Ruled by CTO agent, 2026-10-24: `--files-from` primary and `--pr` a thin wrapper; no
  `origin/main` pin; single consumer edit in operator-holds.md; `--pr` applicability sentinel.
- **T1-T6** Ruled by CTO agent, 2026-10-24 (after the seven-seat deepen review): closed-world trigger enumeration (push, workflow_run, release, pull_request closed) with a named inert list and ci-only meaning "not directly gated by the merged file list as a production act"; `AGENTS*.md`/`CLAUDE.md` basename exclusion at any depth; executable mutant 6 replaced by "drop previous_filename" (still six); repo-owned `--pr` sentinel plus `--repo` equality (supersedes R-c); `--pr` binds state, base and head sha, merge uses `--match-head-commit`; two plain operator sentences and a recorded PR-body verdict line.
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
  can never read "not" from a failure. `emit()` writes stderr first, then stdout, then exits, in one function, so a
  failed stdout write cannot leave `not-production-effecting` beside a non-zero exit.
- stderr: one line `merge-effect-class: <verdict> reason=<token>` plus, for `--pr`, `sha=<head sha>`; reason
  tokens: `allowlisted`, `outside-allowlist`, `empty-list`, `bad-path`, `incomplete-list`, `list-unreadable`,
  `not-open`, `base-mismatch`, `head-moved`, `not-applicable`, `usage`. No path text is ever echoed; only counts
  and an entry index. For `list-unreadable` the message names the class of failure (not found, not logged in,
  network) without any path.
- Allowlist (the only way to read `not-production-effecting`): the `knowledge-base/` prefix and root-level
  `*.md`, EXCEPT any path whose basename is `AGENTS*.md` or `CLAUDE.md` at any depth, which is effecting (these
  files steer every agent session, including scheduled agents that hold secrets; CTO T2). An explicit `*/*`
  rejection precedes the `*.md` arm so `apps/x/README.md` and `docs/legal/terms.md` are effecting. Every listed
  path, both sides of a rename, must match. `bad-path` (exit 2): empty line, backslash, CR, tab, leading `/`, a
  `.`, empty or `..` segment, control characters, a git-quoted path (callers must pass `core.quotePath=false`; a
  quoted path reads effecting). The list is read with `while IFS= read -r l || [ -n "$l" ]` so an unterminated
  final line is still judged. `LC_ALL=C` throughout (no locale ranges, no NFKC: a lookalike must fall to
  effecting). The allowlist is one data array consumed by `is_allowed()` and by `--print-witnesses`, so a new
  entry automatically gets a witness in the parity test.
- `--pr` reuses the shape of `plugins/soleur/scripts/admin-merge-ready.sh` and says so in a comment: `gh pr view
  --json state,baseRefName,headRefOid,changedFiles`, then `gh api --paginate --slurp
  repos/{owner}/{repo}/pulls/<N>/files?per_page=100` into a variable whose `gh` rc is checked BEFORE `jq`. The `jq
  -e` shape check requires, per file object, a non-empty string `filename` and, when `status` is `renamed` or
  `copied`, a non-empty string `previous_filename`; the count compares FILE OBJECTS (not strings) with
  `changedFiles`, and `changed >= 3000 || nfiles != changed` is `incomplete-list`. `state` other than OPEN is
  `not-open`; a base other than main is `base-mismatch`; `headRefOid` is read again after the files fetch and a
  difference is `head-moved` (stale-by-push), all exit 2. Every `gh` call is a GET with the query in the URL (no
  `-f`/`-F`, which would flip it to POST), reads no stdin; any failure is `list-unreadable`.
- `--pr` applicability (CTO T4, supersedes R-c): `git rev-parse --show-toplevel`, run with `GIT_DIR`,
  `GIT_WORK_TREE` and `GIT_CEILING_DIRECTORIES` unset, must resolve a repo whose root carries the repo-owned
  `.github/workflows/web-platform-release.yml` (precedent `deploy-arm.sh` `scope_guard`) AND the ci-only list
  tracked at HEAD (`git cat-file -e HEAD:plugins/soleur/scripts/merge-effect-class.ci-only.tsv`); `--repo` is
  absent or equals the cwd repo's `nameWithOwner` (a failure to obtain it, including offline, is exit 2). Any
  failure is exit 2 `not-applicable`. The sentinel prevents misapplication, not attack: a fork carries the same
  workflow and is classified by the same table, which is correct. Scope of the verdict: only the merge or ready
  of a named OPEN pull request, interactively; dispatches and not-yet-created revert PRs keep the
  agent-authored sentence (said once in the ADR, once in the usage text).
- `--files-from`, `--print-witnesses` and `--self-check` are pure (no `gh`, no repo); the usage text says the
  `--files-from` verdict is meaningful only for the Soleur repository. `--self-check` classifies an embedded
  probe set (one allowlisted path, one production path, one unknown path, one empty list), also reads the
  ci-only list beside the script (it must exist and every row must carry a non-empty reason, so the probe touches
  the durable artifact), and prints `self-check=ok` (exit 0) or `self-check=FAILED` (exit 1); its usage text
  says it is a liveness signal, because probes and allowlist live in the same file and a joint mutation stays
  green.
- Portability: bash 3.2 and mawk; no `mapfile`, associative arrays, `date -d`, `sed -i`, `readlink -f`,
  `sha256sum`. A NUL byte cannot survive `read`; git paths cannot contain one, so no NUL row exists in the matrix.

What the verdict means, and does not: "no path-gated production workflow fires from this file list" (CTO T1).
It is not "no runtime effect": scheduled crons that read `knowledge-base/`, agent-steering files outside the
`AGENTS*.md`/`CLAUDE.md` basename set, content consumed at build time with no path trigger (Eleventy reading a
root file), and bookkeeping workflows that fire on every merge (ledger reconcile, board sync) are out of scope by
design. It judges the PR's file list, which equals the squash commit's unless main moved in the queue. ADR-300
states these limits and that the classifier authorizes nothing and is never usable as evidence in an envelope
`Gate:` or a receipt (a `Gate:` kind for it would need a CTO ruling, as ADR-289 R1 requires for new kinds).

### The ci-only list and the parity test

`plugins/soleur/scripts/merge-effect-class.ci-only.tsv`: `workflow<TAB>reason`, one row per enumerated workflow
that is "not directly gated by the merged file list as a production act" (CTO T1; NOT "harmless": a reason such
as "fires on release publication, downstream of the path-gated release workflow, covered by that row" is valid).
Closed-world: an enumerated workflow that is not on the list is `production`. Every row needs a non-empty reason;
a row naming a workflow that does not exist, or that is no longer enumerated, fails. The header comment repeats
the meaning above, says the file is test data plus the applicability sentinel and is never consulted for a
verdict, and names it review-owned. A second review-owned file, the inert-trigger list (schedule,
workflow_dispatch, repository_dispatch, issues, issue_comment, pull_request without `closed`, merge_group), lives
in the parity test with a one-line reason per entry.

`plugins/soleur/test/merge-effect-class-parity.test.sh` (python3 -I with PyYAML, test-only; as
`ci-concurrency-key.test.sh` already does; a missing PyYAML fails loudly with a named reason, never skips):

1. Enumerate, CLOSED-WORLD over trigger keys (CTO T1): `on.push` whose `branches` is absent or matches main and
   is not tags-only, every `workflow_run` arm whose `branches` is absent or matches main, `release`, and
   `pull_request`/`pull_request_target` whose `types` include `closed`. Keys on the inert list are skipped; ANY
   OTHER trigger key fails with "classify or extend the inert list". Handle the `True` key (`d.get(True,
   d.get("on"))`) and scalar, list and dict forms of `on`.
2. Effective trigger of a `production` workflow: its positive `on.push.paths` (and `paths-ignore`; both on one
   event is a failure, GitHub forbids it; `paths` under `workflow_run` is undocumented and refused); a
   `workflow_run`-only workflow inherits its parent's (by `name:`) effective trigger, transitively; a cycle or an
   unresolved parent fails. A workflow with both its own `push.paths` and an unfiltered `workflow_run` arm is
   deemed gated by its own paths ONLY for the one-entry constant `web-platform-release.yml`, and the test asserts
   `workflow-run-deploy-invariants.test.sh` still contains the EXECUTABLE P3 and P1 assertions (the `fail "P3 ...`
   and `fail "P1 ...` lines, not a bare token that a comment could satisfy). Any other such workflow, any
   production workflow with an unfiltered trigger, and any `pull_request: closed` or `release` workflow not on the
   ci-only list fails with "add a ci-only row with a reason or extend the constant".
3. Direction 2 (the property): every witness from `--print-witnesses` is matched against every production
   workflow's effective trigger by a small GitHub-glob matcher modelling only `**` (including `a/**/b` matching
   `a/b`), `*` (never crossing `/`), `!` (negation, last match wins; a leading negation with no preceding positive
   is refused) and `paths-ignore`. Any other special character (`?`, `+`, `[`, `\`, an unquoted leading `*` `[`
   `!`) fails with "extend the matcher", never silently. The translation is hand-rolled, not `fnmatch`. Plus a
   REAL-TREE sweep: every tracked path the script accepts (`git ls-files knowledge-base/` and root `*.md`, minus
   the basename exclusions) is matched against every production trigger, so a trigger that names specific
   `knowledge-base/` files (infra-validation does) is caught without relying on one generic witness. A path or
   witness that fires a production workflow fails.
4. Direction 1 (anti-vacuity, load-bearing for subtree triggers): for every production workflow, instantiate its
   positive globs (`**` as each of empty, `x`, `knowledge-base/x`, `a/b/c`; `*` as empty and `x`), assert the
   matcher says each fires AND the real script reads each `production-effecting`. A table unit test pins the
   matcher (`a/**`, `**/x`, `*.md` not crossing `/`, negation, negation-only lists, each case pinned to GitHub's
   documented behaviour).
5. Every red message is actionable and names the test file and the command to rerun: a paste-ready ci-only row
   (workflow, reason columns) for an unclassified workflow, "workflow X deleted, remove this row", "allowlist
   entry P fires workflow W: remove the entry or narrow W's paths", "unknown trigger key K: classify or extend the
   inert list". The ci-only meaning is repeated in each message.
6. Test seams so the matrix runs without editing `.github/workflows/`: `MEC_WORKFLOWS_DIR`, `MEC_CI_ONLY_LIST`,
   `MEC_INVARIANTS_TEST` (the P3 file) and `MEC_SCRIPT` (the script under test). A population floor (the snapshot
   count) is pinned separately from set identity, and an empty workflows directory is RED.

Expect to classify, with deliberate reasons read from each workflow, several workflows in this PR (post-merge-monitor,
fix-constraints-stage-b, ci.yml, the other unfiltered CI-only workflows, infra-validation.yml and the
`release`/`pull_request: closed` ones). **Stop condition:** if reading a workflow shows an unfiltered trigger whose
firing mutates production on EVERY merge, the verdict's premise fails for that workflow; stop and take it back to
the CTO rather than giving it a ci-only reason.

### The one consumer

`plugins/soleur/skills/ship/references/operator-holds.md` section 3, step 2 (Ask): replace "when the merge
triggers a production apply or deploy (any workflow that runs on push to main for the changed paths ...) the
outcome sentence says so" with a literal bash block (not prose paraphrase): `out=$(bash
"${CLAUDE_PLUGIN_ROOT}/scripts/merge-effect-class.sh" --pr <N>) && rc=0 || rc=$?` (safe under `set -e`, no `2>&1`,
no pipe); leave out the warning only when `rc` is 0 AND `[ "$out" = "not-production-effecting" ]`; for several
PRs the warning is left out only when it holds for ALL of them. Two plain sentences (CTO T6): for `rc` 1 "this
change can go live on its own"; for everything else (exit 2, exit 0 with any other line, empty output, exit 126
or 127) "I could not check whether this changes production, so I am treating it as if it does". The consumer
records `out`, `rc`, the reason token and the printed sha as one verdict line in the PR body (the existing
operator-holds.md convention "record each hold's verdict line and the command that produced it"), and the merge
it describes must use `--match-head-commit` with the printed sha. One line says that `reason=not-applicable` in
the Soleur repo is itself a bug signal (no automation). The consumer only adds a warning; it never relaxes
anything and never records a delegation. Interactive only; dispatches and revert PRs keep the agent-authored
sentence. Precedence: the `{OUTCOME}` sentence the calling skill writes and the classifier clause are composed (the
clause is appended, the stricter reading wins); the ship `Blast Radius:` label and the infra PRs' hand-written
"merge-effect first line" stay author-judged and are not replaced. No other prose is rewritten (go.md, cto.md and
the Merge Danger block stay).

## Architecture Decision (ADR/C4)

### ADR

Create `knowledge-base/engineering/architecture/decisions/ADR-300-merge-effect-classifier-is-a-closed-world-allowlist-and-authorizes-nothing.md`
via `soleur:architecture` (rich shape: trigger 5, teeth-bearing alternatives). `status: active` (stated in prose as "active, true on merge", not `adopting`),
`related_adrs: [ADR-289, ADR-084, ADR-276, ADR-264]`; it extends ADR-289 in prose. Content: Context (the held-merge
session, in a paragraph; no copied trigger table, the parity test is the live source); Considered Options (A
runtime parse, C epic-reference scope class, D amend ADR-289 as full entries; B multi-valued class and E
`origin/main` pin as one line each); Decision (closed-world allowlist with the `AGENTS*.md`/`CLAUDE.md` basename exclusion, exit 0/1/2 contract,
ci-only list plus parity test with closed-world trigger enumeration and derived witnesses, single consumer with
its literal bash block and plain sentences, repo-owned applicability sentinel, `--pr` state/base/head binding);
the verdict's meaning ("no path-gated production workflow fires from this file list") and the ci-only meaning
("not directly gated by the merged file list as a production act", never "harmless") stated in the Decision
itself; the classifier is never evidence in an envelope `Gate:` or a receipt (a `Gate:` kind needs a CTO ruling);
precedence against the Deploy Pipeline Fix Drift Gate, the `Blast Radius:` label, the infra "merge-effect first
line" and the `{OUTCOME}` sentence; scope limited to the merge or ready of a named open PR, interactively; the
`plugin -> github` enumeration is illustrative and `--pr` supports one repository (and its forks); Consequences and residuals
(**stale installed copy can under-warn after a later PR widens a trigger over an allowlisted prefix; that PR
itself edits `plugins/soleur/**` or a workflow so it is effecting and seen; the window is the plugin update lag,
bounded and accepted; flip: a lag actually observed adds skew detection**; scheduled crons reading
`knowledge-base/`, agent-steering files outside the basename set, build-time consumption of root files, and
bookkeeping workflows that fire on every merge; queue-moved main; the ci-only list is review-owned and a mislabel only matters if the
workflow fires on an allowlisted witness path, which direction 2 covers; flip: a real mislabel adds a check);
**Rejected for now: the epic-reference scope class**, with flip conditions (1) the classifier runs from
`origin/main`, (2) the scope binds to a PR whose author and file list the verifier fetches itself, with a
human-authored link recorded in the delegation, (3) the #10361 receipt hook exists, (4) ADR-289's two residuals
(envelope not pinned to `origin/main`, verifier trust base) are closed; a flip is a separate ADR and needs the
founder's authorization at that time. Cost Impacts: none. NFR Impacts: none. Principle Alignment: AP-024 (a
verification surface does not actuate), AP-020 (PR-controlled filenames: no path echo, control characters
rejected), AP-007, AP-011. The ADR is the first commit of the PR (AC1).

### C4 views

No C4 change. All three of `model.c4`, `views.c4`, `spec.c4` in
`knowledge-base/engineering/architecture/diagrams/` were read. Checked and already modeled: (a) external human
actor: the operator is `founder`, unchanged, no new access relationship; (b) external system: GitHub, edge
`plugin -> github`, whose description in `model.c4` already states that, since ADR-289, "the delegation verifier,
the hold evaluator, the ship gate ... and the overlap preflight read the epic's Standing Delegation comment,
receipts, workflow runs and open pull requests of the USER'S OWN repository through the user's own authenticated
gh CLI, read-only; they run on the user's machine and Jikigai receives nothing" - a PR's changed-file list is the
same read class, so the description is not falsified (CTO R6: no edit unless it were; the enumeration of readers there is illustrative, which ADR-300 says); (c) data store: the
ci-only list is plugin-internal static data under `platform.plugin` (no new element); (d) actor-to-surface
access: unchanged. `plugins/soleur/test/c4-count-parity.test.sh` is still run (counts do not move).

### Sequencing

The decision is true as soon as the PR merges (no soak), so there is no `adopting` window; the ADR is authored
first and committed before code.

## Implementation Phases

### Phase 0 - ADR first (no code)

0.1 Re-verify ADR-300 is free (`git fetch origin main`; list `origin/*` refs). 0.2 Write the ADR via
`soleur:architecture`. 0.3 Commit it alone (`docs(adr): ADR-300 ...`). Nothing under `plugins/soleur/scripts/`
or `scripts/` is committed before this commit (AC1).

### Phase 1 - RED tests, then the guard (Guard Contract written before this phase)

1.1 Write `plugins/soleur/scripts/merge-effect-class.test.sh` against the Guard Contract: table-driven rows,
exit/stdout contract, the consumer-rule rows (both fake-consumer idioms and the `rc != 0` branch), a `gh` fake that
accepts exactly the modelled argv and exits 64 otherwise (two-page `--slurp` fixture), the minimum-assertion floor,
and exactly six executable mutants (`widen`, `gutted`, `first-only`, `exit2-not`, `no-slash-guard`, `drop-prev`) on
a scratch copy: `# mut:<name>` markers with `noop` controls, a pristine-green control, replacement count exactly 1,
string replacement into a temp file then `mv`, `cmp` proves it landed, a crashed mutant is not a killed one, each
mutant flips a named row. A seventh mutant is not allowed: swap, do not add. Run RED.
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
`PJ_TRIPLES` is 288 on `origin/main` today and should not move; if it must, rebase on main first, that table conflicts often), the
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

- `knowledge-base/engineering/architecture/decisions/ADR-300-merge-effect-classifier-is-a-closed-world-allowlist-and-authorizes-nothing.md`
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

Plugin script executing on the customer's own CLI: observability layer 7 (`cli-stdout-artifact`). It is not
invoked by any hosted code path (`grep` of `apps/` finds no caller); an agent session that runs the ship skill
reads the same stdout/stderr as a tool result, and the script emits no `SOLEUR_*` marker, so layers 1-6 are not
engaged. The durable artifact is the verdict line the consumer records in the PR body (token, rc, reason, sha, no
path text) plus the ci-only list in git. A classifier that exits 2 everywhere (broken `gh` auth, a bug) is
detectable later because that verdict line sits in every PR body; in the Soleur repo `reason=not-applicable` is
itself a bug signal.

```yaml
liveness_signal:
  what: per-invocation stdout verdict line, exit status and a stderr line "merge-effect-class: <verdict> reason=<token>" (cli-stdout-artifact); the verdict line recorded in the PR body; CI parity test result for table drift
  cadence: per merge-question invocation; parity test on every PR that touches .github/workflows, the ci-only list or the script
  alert_target: the operator-visible merge question in-session; a red parity-test check on the PR
  configured_in: plugins/soleur/scripts/merge-effect-class.sh; plugins/soleur/test/merge-effect-class-parity.test.sh
error_reporting:
  destination: stderr reason token and exit 2 (cli-stdout-artifact); the consumer maps any rc other than 0 with the exact line to the "I could not check" wording
  fail_loud: stdout is still "production-effecting" on exit 1 and exit 2, so no caller reading stdout or the exit status alone can read "not" from a failure
failure_modes:
  - mode: PR file list unreadable, truncated (>= 3000), length-mismatched, PR not open, base not main, or head moved
    detection: cli-stdout-artifact - exit 2 with reason list-unreadable / incomplete-list / not-open / base-mismatch / head-moved, recorded in the PR body verdict line
    alert_route: operator sees the plain "I could not check" sentence in the merge question
  - mode: a new workflow or trigger kind, or a widened production trigger, is not reflected in the allowlist or ci-only list
    detection: workflow run log - the parity test fails on the PR that introduces it, with a paste-ready fix
    alert_route: red check on that PR (the test-scripts shard of the required test aggregate), named in the failing line
  - mode: script run in a customer repo or a vendored copy
    detection: cli-stdout-artifact - exit 2 reason=not-applicable
    alert_route: the plain "I could not check" sentence in the consumer; no verdict claimed
  - mode: the classifier exits 2 on every call (broken gh auth, a regression)
    detection: cli-stdout-artifact - the verdict line recorded in each PR body shows reason and rc; reviewable in the PR
    alert_route: review of the PR body; the plain "I could not check" sentence tells the operator the warning carries no information
logs:
  where: session tool-result stdout/stderr; verdict line recorded in the PR body
  retention: the PR body for the life of the PR; the ci-only list in git
discoverability_test:
  command: bash plugins/soleur/scripts/merge-effect-class.sh --self-check
  expected_output: self-check=ok
```

The probe is offline, needs no credentials, contains no shell-active character (preflight Check 10 rejects `|`,
`;`, `&`, `<`, `>`, `$` and backticks anywhere) and finishes well under the 15 s cap. It reads the durable
artifact (the ci-only list beside the script) as well as the embedded probes. It is a liveness signal, not proof
of the property (the suites are); the suite asserts the literal command prints `self-check=ok`. The parity test
is registered in the test-scripts shard that feeds the required `test` aggregate (verified by the orphan lint and
the shard map in the work phase, AC14).

## Guard Contract

### Guard 1 - the classifier verdict (`merge-effect-class.sh`)

**Property.** No changed-file list that contains a path firing a path-gated production workflow, or any path
outside the allowlist, or any unusable input, can produce the line `not-production-effecting` with exit 0.

**Assembly.** One chokepoint: `classify_list()`, reached by `--files-from` and `--pr` (the `--pr` wrapper only
builds a list and calls it). The allowlist is one data array read by `is_allowed()` and `--print-witnesses`. All
input gates (empty, bad-path, incomplete, not-open, base, head-moved, applicability) run before `is_allowed()`,
and every verdict leaves through one `emit()` that forces stdout to `production-effecting` unless exit is 0;
`--self-check` and `--print-witnesses` are the only other stdout writers and print no verdict line. Members
drift; the structural guarantee is that `emit()` is the only writer of a verdict line.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Widen the allowlist array (`apps/` or `plugins/soleur/docs/`) [executable mutant `widen`] | RED (table row fails; the parity suite's real-tree sweep, run against the mutated script through `MEC_SCRIPT`, fails too) |
| 2 | Gut the dispatch to `classify_list` so the script prints a fixed verdict having "checked 0" [executable mutant `gutted`] | RED (empty-list, unknown-path and exit-2 rows; assertion floor) |
| 3 | List `knowledge-base/a.md` FIRST and `apps/web-platform/x.ts` SECOND, loop stops at the first allowlisted member [executable mutant `first-only`] | RED (second member after a compliant first) |
| 4 | Map exit 2 to stdout `not-production-effecting` [executable mutant `exit2-not`] | RED (contract rows) |
| 5 | Delete the `*/*` rejection before the `*.md` arm [executable mutant `no-slash-guard`] | RED on `apps/x/README.md`, `docs/legal/terms.md`, `plugins/soleur/docs/x.md` |
| 6 | Drop `previous_filename` in the `--pr` collection [executable mutant `drop-prev`] | RED (a `gh`-fake KB-internal rename must-pass row and an `apps/x.ts` to `knowledge-base/x.md` rename row) |
| 7 | An allowlisted old side with a non-allowlisted new side (and the reverse) via `--files-from` | RED when only one side is checked |
| 8 | Empty, 3000-entry, count-mismatched and unreadable lists; PR not open; base not main; head moved between reads; `--pr` outside the repo-owned sentinel; `--repo` other than the cwd repo | RED if any prints `not-production-effecting` or lacks exit 2 |
| 9 | Unknown top-level path; the script's own path; `knowledge-base-evil/x.md`; `AGENTS.md`, `AGENTS.rules.md`, `CLAUDE.md` and `knowledge-base/x/CLAUDE.md` (all effecting; `README.md` stays non-effecting) | RED if read as not-effecting |
| 10 | `..`, `.`, empty segment, leading `/`, backslash, CR, tab, an unterminated final line holding `apps/x.ts`, a forged newline-and-verdict filename, a git-quoted path | RED if allowlisted or if any raw path text reaches stdout/stderr |

**Harness rows.** (i) The `gh` fake accepts exactly the modelled argv and exits 64 on anything else, with a
two-page `--slurp` fixture; a mutated call shape therefore reds instead of passing against a loose fake.
(ii) The mutant runner has a pristine-green control, `# mut:<name>` markers with `noop` controls, an
occurrence-count of exactly 1 per replacement, `cmp` proof the mutation landed, and a crashed-versus-killed
discrimination (a mutant that fails to parse is NOT counted as killed), as in `delegation-verify.test.sh`.
(iii) Replace the suite's pristine control with a stub that exits 0 with no output (via `MEC_SUT`): the suite must
go RED (minimum assertion count, so `0 passed, 0 failed` cannot exit 0). (iv) A consumer written with a
substring match or `case *production-effecting*` reads the safe verdict as effecting, and a consumer that tests
only `$?` reads an effecting verdict as safe under the OLD exit mapping: the suite carries both as must-detect
rows (written as `[[ ]]`/`case`, never `echo | grep -q`), plus the consumer's `rc != 0` branch, and an anchor
assertion that operator-holds.md step 2 contains the literal `rc` and whole-line rule. Must-PASS inputs that are
NOT the canonical: a deep path with spaces and non-ASCII under `knowledge-base/`, `CHANGELOG.md` and `README.md`
at the root, and a KB-internal rename via the `gh` fake, all read `not-production-effecting`; a
rejecting-everything stub fails these.

**Anchor.** The allowlist is a stored claim about the workflows' triggers. What outside this commit must also
move for a weakening to pass: the parity test (Guard 2) reads `.github/workflows/*.yml` and the tracked tree
independently of the script and derives its witnesses from the script's own data, so widening the allowlist over
a production trigger reds it; and `plugins/soleur/**` is effecting, so any edit of the script or list is itself
judged production-effecting by every consumer.

### Guard 2 - the parity test (`merge-effect-class-parity.test.sh`)

**Property.** Every workflow that can run on a merge to main (push, `workflow_run`, `release`,
`pull_request: closed`) is either on the reviewed ci-only list or treated as production, no unknown trigger key
passes unclassified, and no allowlisted path fires a path-gated production workflow.

**Assembly.** The population is derived from `.github/workflows/*.yml` (every trigger key, closed-world: enumerated
kinds above, a named inert list, anything else a failure; `True`-key and scalar/list forms handled), never from the
ci-only list, which is the thing under test. Chokepoint: one `effective_trigger(workflow)` function used for the
witness, real-tree and anti-vacuity directions. Trigger shapes are the whole model: `push.paths`/`paths-ignore`,
unfiltered, chained by `name:` (transitive), and the one deemed-gated constant; anything else fails.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a new push-to-main workflow with no ci-only row (default production, unfiltered) | RED with a paste-ready ci-only row in the message |
| 2 | Empty or zero-population run ("0 checked": empty workflows dir, empty list) | RED (population floor pinned separately from set identity; empty dir is RED) |
| 3 | Add a SECOND unclassified workflow after a compliant one | RED (loop does not stop at the first) |
| 4 | A `workflow_run` workflow with no `branches` key and no ci-only row; a `release` or `pull_request: closed` workflow with no row | RED |
| 5 | Remove a `paths:` filter from a production workflow | RED (fires on every path, including witnesses) |
| 6 | Widen a production `paths:` glob to cover `knowledge-base/**` or `*.md`; a production trigger naming specific `knowledge-base/` files | RED (witness and real-tree sweep) |
| 7 | A ci-only row with an empty reason; a row naming a deleted workflow | RED (each) |
| 8 | A chain cycle or an unresolved parent `name:` | RED (each) |
| 9 | A glob using `?`, `+`, `[` or `\`; `paths` together with `paths-ignore` on one event; an unknown trigger key | RED "extend the matcher" / "classify or extend the inert list" (never silent) |
| 10 | A second workflow with its own `push.paths` and an unfiltered `workflow_run` arm | RED (only the web-platform-release constant is deemed gated) |

**Harness rows.** Edit the suite so its direction-1 instantiation can no longer fire its workflow: RED. Delete or
comment out the executable P3 or P1 assertion in a scratch copy of `workflow-run-deploy-invariants.test.sh`
(via `MEC_INVARIANTS_TEST`): RED. Run the suite against a mutated script (via `MEC_SCRIPT`) that widens the
allowlist: RED. Must-PASS non-canonical: a synthetic fixture with `paths-ignore` covering `knowledge-base/**`, and
a negated glob `!knowledge-base/**` after a positive one, must read as NOT firing the witnesses.

**Anchor.** The ci-only classification is human-reviewed registry data; every row needs a reason with the
"not directly gated by the merged file list as a production act" meaning repeated in the ADR, the list header and
the failure messages; ADR-300 names both the ci-only list and the inert list as review-owned and states the bound
(a mislabel matters only if the workflow fires on an allowlisted path, which the witness and real-tree directions
cover). A population floor is paired with set identity, never a count alone.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add `merge-effect-class.sh`: infra, migration or main-push-triggered production workflow paths mean production-effecting; an unknown path means production-effecting (stricter default)." [issue #10923] | Phase 1.3, Guard 1, `plugins/soleur/scripts/merge-effect-class.sh` | mapped |
| 2 | "Optionally add a delegation Scope class \"merge changes referencing epic #N\" with a verifier test row, and edit sections 1-2 of `standing-delegation.md`." [issue #10923] | ADR-300 Considered Options and flip conditions | descoped - justification: optional in the issue; CTO ruled F3 that it widens an irreversible production-mutating authorization and moves class choice to the PR author (ADR-289 Option C); recorded as rejected with four flip conditions |
| 3 | "needs an ADR first, then code" / "The plan must sequence the ADR before any code." [issue #10923, brief] | Phase 0, AC1 | mapped |
| 4 | "the PR starts with a read of the existing delegation and classifier code ... and may re-scope" [issue #10923, brief] | Research Insights, Reconciliation table | mapped |
| 5 | "Spawn soleur:engineering:cto for the design fork (technical ruling; record \"Ruled by CTO agent\")" [brief] | Rulings, decision-challenges.md | mapped |
| 6 | "PR body uses `Ref #9757` only, never a closing keyword." [brief] | Phase 4.2, AC12 | mapped |
| 7 | "Merge through the merge queue with `gh pr merge <N> --squash --auto`, never `--admin`." [brief] | Phase 4.4, AC12 | mapped |
| 8 | "Do not touch the apply-workflow restore-step annotations. Keep apps/** and scripts/registry-restore-from-ghcr.sh unchanged." [brief] | Files to Edit "Not touched", AC11 | mapped |
| 9 | "Any new file a test sources or reads must be registered in the selector arrays, the orphan lint, the pipe-guard table ... and, if a suite names it, the ratchet accept file." [brief] | Phase 3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `merge-effect-class.sh` closed-world verdict | "an unknown path means production-effecting (stricter default)" | asked |
| ADR-300 | "needs an ADR first, then code" | asked |
| operator-holds.md section 3 step 2 consumer | "Add `merge-effect-class.sh`" (a classifier needs a consumer or it is dead code) | inferred - justification: CTO F3(b) ruled exactly one read-only consumer so the verdict replaces agent prose in the operator question; without it the ADR's "informs the sentence" claim has no mechanism |
| ci-only list and parity test | "main-push-triggered production workflow paths mean production-effecting" | asked |
| `--pr` wrapper, applicability sentinel, `--print-witnesses`, `--self-check` | "Add `merge-effect-class.sh`" | inferred - justification: callers hold a PR number, not a list; the plugin ships to customer repos whose triggers the allowlist cannot know (CTO R-c); the parity test must derive its witnesses from the script or a new allowlist entry gets none; Check 10 forbids a piped probe |
| `AGENTS*.md`/`CLAUDE.md` basename exclusion; closed-world trigger enumeration (release, pull_request closed) | "an unknown path means production-effecting (stricter default)" | inferred - justification: the stricter-default ask applies to agent-steering files that steer secret-holding scheduled agents, and an enumeration that skips merge-time trigger kinds would report green while a workflow went unclassified (CTO T1, T2) |
| registration edits (selector array, shard legs, baselines) | "Any new file a test sources or reads must be registered ..." | asked |
| tracking issues (ADR-289 flip, scope-class revisit) | "Umbrella #9757 stays open; this is item 1 of its remaining CTO follow-ups." | inferred - justification: a deferral without a tracking issue is invisible (plan deferral-tracking check; CTO R7) |

### Split Assessment

- Subsystems touched: 3 - `plugins/soleur`, `scripts`, `knowledge-base`
- Planned files: 9 | Estimated changed lines: ~700 (ADR ~110, script ~150, tests ~350, list ~30, edits ~60)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (under every threshold; the ADR commit is separable but lands first in the same PR per the issue)

## Acceptance Criteria

Process-only criteria are marked (process): they are checked on the PR branch before merge and by ship's gates,
and cannot be re-derived from `main` after the squash.

### Functional Requirements

- [ ] AC1 (process): after `git fetch origin main`, on the PR branch, the commit that adds `ADR-300-*.md` precedes every commit that touches `plugins/soleur/scripts/merge-effect-class*` or `scripts/` (`git log --reverse --name-only --format=%H origin/main..HEAD`); re-run after any ship-time renumber or history rewrite.
- [ ] AC2: `printf 'knowledge-base/a/b.md\nREADME.md\n' | bash plugins/soleur/scripts/merge-effect-class.sh --files-from -` prints exactly `not-production-effecting` and exits 0; the same with `apps/web-platform/x.ts` appended prints `production-effecting` and exits 1; `apps/x/README.md`, `docs/legal/terms.md`, `plugins/soleur/docs/x.md`, `AGENTS.md`, `AGENTS.rules.md`, `CLAUDE.md` and `knowledge-base/x/CLAUDE.md` each print `production-effecting`.
- [ ] AC3: empty input, an unknown top-level path, a rename with one non-allowlisted side, a `..` path, an unterminated final line holding `apps/x.ts` and a 3000-entry `--pr` list each print `production-effecting`; the unusable-input cases (empty, bad-path, incomplete) exit 2, the rest exit 1.
- [ ] AC4: in temp repos built by the suite (constructed git env), `--pr <N>` exits 2 with `reason=not-applicable` when the repo lacks `.github/workflows/web-platform-release.yml`, when the ci-only list is not tracked at HEAD, and when `--repo` names a different repository.
- [ ] AC5: with the `gh` fake, `--pr` exits 2 `not-open`, `base-mismatch`, `head-moved` and `incomplete-list` for the matching fixtures, and classifies a KB-internal rename (both sides allowlisted) as `not-production-effecting` and `apps/x.ts` renamed to `knowledge-base/x.md` as `production-effecting`.
- [ ] AC6: `bash plugins/soleur/scripts/merge-effect-class.test.sh` and `bash plugins/soleur/test/merge-effect-class-parity.test.sh` pass with a minimum-assertion floor; each of the six executable mutants flips its named row RED (replacement count exactly 1, `cmp` proves it landed, a crashed mutant is not counted as killed).
- [ ] AC7: `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-24-feat-merge-effect-class-classifier-plan.md` exits 0 with two entries counted.
- [ ] AC8: operator-holds.md section 3 step 2 contains the literal bash block with the `rc` and whole-line rule, the two plain sentences and the `--match-head-commit` rule (the suite asserts these by content anchor); `git diff --quiet origin/main...HEAD -- plugins/soleur/skills/ship/SKILL.md plugins/soleur/scripts/delegation-verify.sh plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md knowledge-base/engineering/architecture/diagrams` exits 0 (three-dot, merge-base form).
- [ ] AC9: the suite executes the literal discoverability command `bash plugins/soleur/scripts/merge-effect-class.sh --self-check` and asserts it prints `self-check=ok`, and that `--self-check` fails when a ci-only row has an empty reason.
- [ ] AC10: the parity test fails (RED row) for an unknown trigger key, for a `release` or `pull_request: closed` workflow with no ci-only row, and for an empty workflows directory.

### Non-Functional / Constraints

- [ ] AC11: `git diff --quiet origin/main...HEAD -- .github/workflows apps scripts/registry-restore-from-ghcr.sh` exits 0.
- [ ] AC12 (process): the PR body contains `Ref #9757` and none of `Closes`, `Fixes`, `Resolves`; the PR is armed with `gh pr merge <N> --squash --auto` and no `--admin`.
- [ ] AC13 (process): `git config user.name` prints `Jean Deruelle` and `git config user.email` prints `jean.deruelle@jikigai.com` before the first commit.

### Quality Gates

- [ ] AC14: `scripts/lint-orphan-test-suites.sh`, `scripts/markdown-lint.sh --repo-sweep`, `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh` and `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` pass; the parity test is confirmed to run in the test-scripts shard of the required `test` aggregate; the affected-index ratchet result is recorded as advisory.
- [ ] AC15: with a `python3` shim on `PATH` that cannot import `yaml`, the parity test exits non-zero with a named reason and never skips.
- [ ] AC16: the ADR file's ordinal equals every `ADR-NNN` reference to it in this plan, `tasks.md` and `decision-challenges.md` (`ls knowledge-base/engineering/architecture/decisions/ADR-*-merge-effect-classifier-*.md`, then `grep -o 'ADR-[0-9]*'` on those files, re-run after any renumber).
- [ ] AC17: `git grep -n -E 'exit 0 (means|=) (a )?verdict|only over-warns' -- plugins/soleur/scripts/merge-effect-class.sh plugins/soleur/scripts/merge-effect-class.test.sh plugins/soleur/test/merge-effect-class-parity.test.sh plugins/soleur/skills/ship/references/operator-holds.md 'knowledge-base/engineering/architecture/decisions/ADR-*-merge-effect-classifier-*.md'` prints nothing (the scope excludes this plan, which quotes the retired phrases).
- [ ] AC18 (process): the verdict distribution over the last ~50 merged PRs (task 1.4) and the ci-only classifications are in the PR body.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO ruled the design fork (F1-F6), four plan refinements (R-a to R-d) and, after the
four-seat plan review, eight consolidation forks (R1-R8) and six deepen-review forks (T1-T6) on 2026-10-24, all class `technical`; no operator
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

- `docs/legal/**` (pinned by SHA-256 in app code) is effecting; `AGENTS.md`, `AGENTS.rules.md`, `CLAUDE.md` and `knowledge-base/x/CLAUDE.md` are effecting while `README.md` and `CHANGELOG.md` stay non-effecting; a list whose last line lacks a trailing newline; CR and tab in a path; `knowledge-base-evil/x.md` is effecting; a root-level file with a space; a dot-file `.md`; CRLF list; a git-quoted path reads effecting.
- Parity: an unknown trigger key; a `release` workflow; a `pull_request: closed` workflow; a trigger naming specific `knowledge-base/` files; `paths` together with `paths-ignore`; `paths-ignore`-only workflow; negated glob after positive; `workflow_run` arm with and without `branches`; a push workflow with `tags:` only (excluded); `on: push` scalar form; a registry row for a deleted workflow; a chain cycle.

### Integration Verification (for `soleur:qa`)

- **Script:** `bash plugins/soleur/scripts/merge-effect-class.sh --self-check` prints `self-check=ok`.
- **Live PR (read-only, user's own gh session):** run `--pr` against a merged docs-only PR and a merged `apps/` PR; expect exit 0 `not-production-effecting` and exit 1 `production-effecting`. No credentials beyond `gh`; no `doppler`.

## Rollback

`git revert` of the squash commit through a revert PR (`ask Soleur "undo PR #N"`). It removes the script, ci-only
list, two suites, the ADR file, the operator-holds.md sentence and the registration rows together; the operator
question returns to agent-judged wording. Nothing is deployed and no data is touched, so there is no state to undo.

## Dependencies & Risks

- **A wrong `not-production-effecting` on a real production path is the one costly failure.** Mitigated by the closed-world allowlist, executable mutants 1-6 and the derived-witness parity test.
- **The parity test is the only drift defense.** An unfiltered production trigger fails by design; expect to classify several workflows with deliberate reasons in this PR (stop condition above).
- **Matcher scope creep:** a matcher modelling GitHub filter semantics wrongly is itself a fail-open source; the "extend the matcher" failure is the safety valve and the matcher stays small enough to read in one sitting.
- **Closed-world trigger enumeration goes red the first time anyone adds a workflow or a new trigger type.** Intended; the message is paste-ready (row and columns). Both review-owned lists (ci-only, inert) need a reason on every entry, and the ci-only meaning ("not directly gated by the merged file list as a production act") must appear in the ADR, the list header and the failure messages, or the list drifts back to meaning "harmless".
- **`--repo` equality needs a network call**: an offline run exits 2 (fail-closed, accepted).
- **Exit-contract text:** R1 changed F2; no text may still say exit 0 means a verdict was produced (AC15).
- **Queue-moved main:** the verdict judges the PR file list; ADR-300 says it does not claim more.
- **Stale installed copy can under-warn** (see Reconciliation); accepted, bounded by plugin update lag.
- **Dependencies:** PyYAML in the test environment (precedent `ci-concurrency-key.test.sh`, fail loudly if absent); `gh`, `jq` at runtime.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this
  plan fills it (`aggregate pattern`).
- ADR-300 is provisional: if renumbered at ship, sweep this plan, `tasks.md` and `decision-challenges.md`.
- The consumer sentence must stay clear of the phrasing `.claude/hooks/ship-operator-step-gate.sh` and
  `ship-soak-followthrough-gate.sh` match (no bullet-prefixed operator verbs, no "post-deploy verify").
- Do not claim the classifier authorizes anything; do not add a third verdict value.
- `decision-challenges.md` rows are machine-gated: header exactly `| Item | Class | Ruling |`, three cells per
  row, no literal `|` inside a row, a technical ruling starts `Ruled by CTO agent, <date>:`.
