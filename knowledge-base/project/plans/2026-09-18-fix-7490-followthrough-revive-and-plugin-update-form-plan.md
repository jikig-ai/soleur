---
title: "fix: revive the #7490 follow-through, align `claude plugin update` docs to the qualified form, and route the version-comparator residual upstream"
date: 2026-09-18
slug: fix-7490-followthrough-revive-and-plugin-update-form
branch: feat-one-shot-7490-followthrough-revive-and-plugin-update-form
issue: 7490
closes: 7490
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

## Overview

_No `spec.md` exists for this branch, so `lane:` defaults to `cross-domain` (TR2 fail-closed)._

Three coupled corrections around the plugin-delivery follow-through tracker #7490, which is OPEN and is the only issue this plan closes.

1. **Docs.** Every operator-facing `claude plugin update` invocation moves to the qualified `<plugin>@<marketplace>` form, and the marketplace half is stated correctly for each install path the docs describe (`soleur-marketplace` on the recommended path, `soleur` when the monorepo was added directly).
2. **Follow-through.** The #7490 tracker is dead for two independent reasons: its directive sits inside a code fence the sweeper deliberately skips, and its probe cites a spec artefact that was archived in the same PR that shipped the probe. Both are fixed, and the class behind each gets a mechanical guard.
3. **Upstream.** The version-comparator no-op residual (a constant `version` short-circuits `plugin update` while a correct `gitCommitSha` sits beside it) gets a scrubbed posting record drafted against the existing upstream home, with the send itself left operator-gated.

## Research Insights

### Premise Validation (Phase 0.6)

Every reference in the brief was probed on 2026-09-18. What held, what moved:

| Cited premise | Probe | Result |
|---|---|---|
| #7490 is OPEN, `follow-through`-labelled, the only issue to close | `gh issue view 7490 --json state,labels,closedByPullRequestsReferences` | **Holds.** OPEN, labels `follow-through`, `type/chore`, `domain/engineering`, `priority/p2-medium`; no closing PR. |
| The directive in #7490's body sits inside a ```` ```html ```` fence and the sweeper logs `no directive — skipping` | body read; run `35354131746` log | **Holds.** Log line `[14:11:14] issue #7490: no directive — skipping`, and `sweep done (no_directive=33)`. The sweeper's fence skip is deliberate (`scripts/sweep-followthroughs.sh` `parse_directive`, comment block above it, #4200 Gap 3; pinned by test T6). |
| Only #7490 is affected | census of all 56 open `follow-through` issues with the sweeper's own awk | **Stale — it is a class.** Six open trackers carry a directive that exists only inside a fence: **#7490, #7985, #6678, #6617, #6488, #5813**. All six were labelled `follow-through` *after* creation (1 s to 3 days later), i.e. via `gh issue edit`, which the create-time hook `.claude/hooks/follow-through-directive-gate.sh` never sees (it matches `gh issue create` only — its awk is already fence-aware and would have refused). All five sibling probes exist on `main`. |
| The producer of the fence | `git log -S'```html' -- plugins/soleur/skills/ship/SKILL.md` | The ship skill's own follow-through issue-body template (`plugins/soleur/skills/ship/SKILL.md`, the `## Verification` block near the `<!-- soleur:followthrough` lines around line 2604) wraps the directive in a ```` ```html ```` fence inside the four-backtick template — so a body pasted from the template ships fenced. Landed in #4191 on 2026-05-20, the same day #4200 taught the sweeper to skip fences. The convention runbook (`followthrough-convention.md` §Author workflow step 4) shows the same fenced example with no "paste it unfenced" note. Two producer-side enrollment checks are fence-blind and would count a fenced tracker as enrolled: `.claude/hooks/ship-soak-followthrough-gate.sh` (the `grep -q '<!-- soleur:followthrough'` inside its `for n in $REFS` loop) and the same grep in `plugins/soleur/skills/ship/SKILL.md` §Soak-Gated Follow-Through Enrollment Gate. |
| `plugin-delivery-canary-7490.sh` hard-codes the un-archived `REPORTS` path; the file lives under `specs/archive/20260813-114111-…` | `git ls-files`; probe read | **Holds.** `REPORTS=knowledge-base/project/specs/feat-one-shot-7489-7490-marketplace-retire-delivery-followups/upstream-reports.md` at the top of the probe; the only tracked copy is the archived one. The archive happened in the same PR (#7505, 2026-08-13) because `/compound` Auto-Consolidation Step E runs `archive-kb.sh` on the branch before `/ship` opens the PR — so the rot is *visible to PR CI*, which is where the new lint must run. Archived dirs are terminal (`archive-kb.sh` excludes `*/archive/*` from discovery). |
| The canary job is green with both posting slots recorded | archived record §Posting log; `gh run list --workflow scheduled-marketplace-drift.yml` | **Holds.** Both URLs recorded (76882 comment `5273479508`; 77927 comment `5273482066`); no `_pending_` in the archived file. With the path fixed the probe's step 4 passes. |
| Bare `claude plugin update soleur` appears at README.md, plugins/soleur/README.md, getting-started.njk | repo-wide `git grep` excluding plans/specs/learnings/archive | **Under-counted.** Bare form also at `plugins/soleur/commands/sync.md` (the producer-missing remedy message, 3 commands) and **14 echo-string lines across 10 SKILL.md files** (`agent-browser`, `cf-token-scope`, `feature-video`, `incident`×2, `legal-generate`×2, `linear-fetch`×2, `qa`, `reproduce-bug`, `test-browser`, `trigger-cron`×2), plus the bare `claude plugin install soleur` in prose/JSON-LD at `plugins/soleur/docs/pages/claude-code-plugins.njk` (2 lines). `tests/commands/test-sync-producer-reachability.sh` pins the sync remedy with `grep -Fq "claude plugin update soleur"` — a substring the qualified form still satisfies, so the test cannot see a regression to bare. |
| The runbook and changelog "already use the full form — confirm the marketplace name" | reads; published manifest; local `claude plugin marketplace list` | **Two different names, both correct for their path.** `plugins/soleur/docs/pages/changelog.njk` says `soleur@soleur-marketplace`; `plugin-delivery-recovery.md` says `soleur@soleur` (about the operator's own monorepo-sourced install). The marketplace half is the `name` of whichever marketplace was added: the published `jikig-ai/soleur-marketplace` manifest is named **`soleur-marketplace`** (recommended path, README install block), while the in-repo `.claude-plugin/marketplace.json` is named **`soleur`** (the "install from this repository directly" path, and the live operator install: `claude plugin list --json` → `soleur@soleur`). Therefore `claude plugin marketplace update soleur` in README/getting-started/sync.md is *also* wrong on the recommended path — that command takes the marketplace name (`claude plugin marketplace update --help`: `[name]`), which is `soleur-marketplace` there. |
| Anthropic collaborator comment `5310894439` on 76882 says the bare name can fail | `gh api repos/anthropics/claude-code/issues/comments/5310894439` | **Holds.** `bcherny` (COLLABORATOR), 2026-08-17: "on current releases you may need the full `plugin@marketplace` form — the bare plugin name can fail with 'Plugin not found'". Independently reported as upstream **#83947** (OPEN, 2.1.221): `plugin update <name>` fails unless fully qualified, with an error identical to "plugin does not exist". Local CLI is 2.1.273; `claude plugin update --help` documents the argument only as `<plugin>`. |
| Upstream 76882 closed 2026-08-17 as `documentation`; the comparator residual has no open home | `gh issue view 76882`; `gh api search/issues` ×5 phrasings | **Half stale.** 76882 is CLOSED (`completed`, labels include `documentation`). But the search the brief asked for finds an open home: **#93108** (OPEN, `bug`+`has repro`, filed 2026-09-09) — "plugin update / auto-update compare only the version string, so plugins that ship new content without bumping version never refresh" — with two further commenters adding instances (2026-09-10, 2026-09-14). **Part (c) therefore becomes a comment on 93108, not a new issue.** |
| `upstream-ask` deferral tracker filed 2026-09-17 | `gh issue list --search 'upstream-ask'` | **Holds.** #8253 (OPEN, `type/feature`, `priority/p3-low`, `meta/machinery`), re-evaluation criterion: "On the next upstream-ask recurrence (4th)". This plan is that recurrence. |
| §1.9 of `measurements.md` carries the two-arm experiment | read | **Holds** (`## 1.9 — What the version key actually does`): with-version arm records `gitCommitSha` YES + `version 0.0.0-dev`; keyless arm records `gitCommitSha` YES + `version bfc681c7d8c7`. |
| ADR corpus on the proposed mechanisms | grep `followthrough|follow-through|upstream-report|plugin update` over `knowledge-base/engineering/architecture/decisions/` | No ADR decides the directive-in-fence question or the probe-path question; ADR-182 owns the marketplace/identity facts used in (a) and (c) and is not changed by this plan (its `soleur@soleur` example describes the operator's monorepo install and stays). |

No premise was wrong in a way that removes work; two were wrong in a way that *adds* population (six fenced trackers, not one; ~20 bare-form sites, not three) and one re-targets part (c).

### Property List and Cut List (Phase 0.6b)

**Properties** (each is one observable outcome):

- **P1** — An operator who follows the recommended install path and then the "Updating" instructions runs commands that succeed on current CLI releases (qualified plugin id; marketplace name that matches the marketplace they added), and an operator on the direct-repository path can find the right id in one command.
- **P2** — The sweeper honors #7490's directive on its next run.
- **P3** — #7490's probe reaches its evidence record, so a green canary plus recorded postings evaluates to PASS and the sweeper closes the tracker.
- **P4** — A follow-through probe whose cited repo artefact is moved or deleted reddens PR CI before merge, rather than FAILing daily after merge.
- **P5** — A `follow-through`-labelled open tracker whose only directive is inside a code fence is told so on the tracker (not only in a step summary), and the ship template can no longer produce that shape; producer-side enrollment gates agree with the consumer about what "enrolled" means.
- **P6** — The version-comparator residual has a scrubbed, evidence-backed body ready to post at its existing upstream home, and nothing posts it without the operator's word.
- **P7** — The 4th upstream-ask recurrence is recorded where the deferral tracker asked for it.

**Cut List** (mechanism → property → what already covers it):

- *Resolve `REPORTS` via a glob over `specs/` and `specs/archive/`* → P3 → a literal repoint to the terminal archive path buys P3 and stays checkable by the P4 lint (a glob defeats a literal-path lint); **cut**.
- *Extend the create-time hook to `gh issue edit --add-label follow-through` / `--body`* → P5 → the sweeper already enumerates the whole labelled population every day, whatever path the label arrived by; the create hook is one of several producers (`gh issue edit`, `bootstrap-ccla-watch-7922.sh`, the API) and cannot be the chokepoint; **cut** in favour of detection at the sweeper.
- *A new upstream issue on the comparator* → P6 → upstream #93108 is that issue; **cut** in favour of one comment.
- *A `::warning::`-only annotation for fenced directives* → P5 → the no-directive WARN has existed in the step summary since #4200 and #7490 sat in it for 35 days; a step summary is an eyeball surface. The `MISSING_SECRET` path (#7946) already established the loud shape (tracker comment + `::error::` + red run); reuse it; **cut** the quiet variant.
- *A `.pen` wireframe for the getting-started callout* → none → the edit is a copy change inside existing `<code>` elements; `ui-surface-terms.md` §Excluded names "pure copy or style tweaks with no structural/layout change"; **cut** (see Domain Review).
- *Building the `upstream-ask` skill* → P7 → explicitly out of scope by the brief; the recurrence note on #8253 is the deliverable; **cut**.

### Value-proposition measurement (Phase 0.6c)

Not applicable — no cost or performance saving is claimed. The sweeper-side value is a dead-tracker count: six of 56 open follow-through trackers are dead by fence today (measured above with the sweeper's own awk), and #7490 has been in the no-directive summary for 35 days (2026-08-14 → 2026-09-18).

### Relevant files (with the load-bearing lines)

- `scripts/sweep-followthroughs.sh` — `parse_directive()` (awk, `fence` flag; emits `__sweeper_meta__ multi_directive_count N`), the `no directive — skipping` branch with `NO_DIRECTIVE_FILE`, the `MISSING_SECRET=1` branch (tracker comment `### Sweeper run: REQUIRED SECRET MISSING`, `::error::`, `DRY_RUN` short-circuit), and the end-of-`main` `if [[ "$MISSING_SECRET" == "1" ]]` exit.
- `scripts/sweep-followthroughs.test.sh` — `invoke_run_one` helper (returns combined output + `__RC__=<rc>`), T6 `t6_fenced_block_directive_is_skipped`, G3 `t_g3_m1_missing_secret_is_loud` and the G3-M3 dispatch mutation (sed-deletes `MISSING_SECRET=1`, expects the mutant to exit 0).
- `scripts/lint-followthrough-varq-ban.sh` / `.test.sh` — the sibling lint to copy: `[TARGET_DIR]` arg, production floor `MIN_PROBES` (10) with a test-only override env var, exit 0/1/2, `pass()`/`fail()`/`check()` with the ADR-193 accounting identity and a `MIN_ASSERTIONS` floor emitted via `printf`+`exit 1`, never through `fail()`.
- `scripts/test-all.sh` — `run_suite "scripts/followthrough-varq-ban-live" bash scripts/lint-followthrough-varq-ban.sh` and the `.test.sh` line beside it (the `test-scripts` shard).
- `scripts/followthroughs/plugin-delivery-canary-7490.sh` — `REPORTS=` literal; step 4 `[[ ! -r "$REPORTS" ]] → FAIL`.
- `.claude/hooks/follow-through-directive-gate.sh` — create-only trigger regex; fence-aware awk; the `script= is empty` deny reason that a fenced-only body currently receives.
- `.claude/hooks/ship-soak-followthrough-gate.sh` — the enrollment loop's bare `grep -q '<!-- soleur:followthrough'`; a fence-stripping awk already exists earlier in the same file for the PR body.
- `plugins/soleur/skills/ship/SKILL.md` — issue-body template (`## Verification` + fenced directive) and the enrollment-gate bash with the same bare grep.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — §Author workflow step 4 (fenced example) and the `## Directive fields` table.
- Docs sites for (a): `README.md` §Updating; `plugins/soleur/README.md` §Known Issues → "Updating the Marketplace Does Not Update the Installed Plugin"; `plugins/soleur/docs/pages/getting-started.njk` "Updating later?" callout; `plugins/soleur/commands/sync.md` producer-missing remedy; the 14 SKILL.md echo lines; `plugins/soleur/docs/pages/claude-code-plugins.njk` FAQ prose + JSON-LD; `tests/commands/test-sync-producer-reachability.sh` remedy assertions.
- Evidence for (c): `knowledge-base/project/specs/archive/20260813-114111-feat-one-shot-7489-7490-marketplace-retire-delivery-followups/upstream-reports.md` §1; `knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/measurements.md` §1.0 and §1.9; `scripts/upstream-report-scrub.sh`.

### Institutional learnings (Glob-verified)

- `knowledge-base/project/learnings/2026-09-17-followthrough-directive-on-existing-issue-three-silent-traps.md` — the sweeper's failure modes are silent; a directive that is never *verified armed* may as well not exist; the sweeper comments on every non-0/1 verdict with no dedup (so an unfenced long-horizon probe will comment daily — classify each sibling before unfencing). Applies to (b).
- `knowledge-base/project/learnings/2026-05-21-follow-through-template-host-drift-and-qa-spawned-feature.md` — a template defect in `/ship` Phase 7 propagates to every future follow-through issue; fix the template, not one issue. Applies to (b).
- `knowledge-base/project/learnings/2026-03-13-archive-kb-stale-path-resolution.md` — scripts hard-coding spec paths silently skip after a move. Applies to (b) — the lint is the mechanical form.
- `knowledge-base/project/learnings/2026-09-08-the-guard-was-deleted-the-plan-still-cited-it-and-the-linter-validated-the-citation.md` and `knowledge-base/project/learnings/2026-09-11-the-linter-i-cited-as-my-oracle-passed-with-the-guard-deleted.md` — a linter that validates citation *syntax* passes over a missing artefact; the new lint must test existence (`-e`), not shape. Applies to (b).
- `knowledge-base/project/learnings/2026-09-13-the-guard-pinned-the-names-the-plan-listed-and-the-readback-read-every-page-unpinned.md` — specify discovery as a census over the file set with a red unclassified bucket; the plan's enumeration is only the floor. Applies to the lint and to the sweeper census.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` and `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — every guard needs a mutation matrix with a dispatch row and harness rows. Applies to the Guard Contract below.
- `knowledge-base/project/learnings/best-practices/2026-07-07-followthrough-and-shape-gate-silent-falseness.md` — execute every gate against real and failing inputs before trusting it. Applies to (b).
- `knowledge-base/project/learnings/best-practices/2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces.md` — a docs-fix AC grep must span README, runbooks, skills, workflows; exclude only plans/specs/archive. Applies to (a).
- `knowledge-base/project/learnings/2026-06-02-fixture-bare-substring-marker-over-slurp-and-orphan-test-infix.md` — anchor on the full marker form, never the inner token; test files need the `.test.` infix to be discovered. Applies to the new lint and its test.
- `knowledge-base/project/learnings/2026-07-19-a-wall-clock-break-in-a-replayed-body-and-a-plan-premise-that-would-have-overridden-the-operator.md` — read a probe's documented exit semantics before turning its result into a mutation. Applies to unfencing the sibling trackers.

### External references (already read; no further external research needed)

- anthropics/claude-code **#93108** (OPEN) — destination for part (c). **#83947** (OPEN) — bare-name failure, docs citation for part (a). **#76882** (CLOSED) — prior posting home; collaborator comment `5310894439`. **#86700** — `plugin install` does not upgrade (different verb; not a destination).
- `claude plugin update --help` on 2.1.273 (verified 2026-09-18): `Usage: claude plugin update [options] <plugin>`; `-s, --scope <scope>` default `user`. `claude plugin marketplace update --help`: `[name]`, "updates all if no name specified". Published manifest `https://raw.githubusercontent.com/jikig-ai/soleur-marketplace/main/.claude-plugin/marketplace.json` → `"name": "soleur-marketplace"`, plugin entry keyless.

### CLAUDE.md / constitution conventions that bind this plan

- Never use `$VAR`/`$()` in bash blocks inside skill `.md` files (constitution §Code Style) — the SKILL.md echo edits stay literal strings.
- When fixing a pattern across plugin files, search ALL `.md` under `plugins/soleur/` (constitution §Architecture) — done above; the 14-line list is the census.
- PRs touching `plugins/soleur/` carry a `semver:patch|minor|major` label (constitution §Architecture) — this is `semver:patch`.
- `cq-assert-anchor-not-bare-token` — the sync test's remedy assertions move to the qualified form so bare cannot regress.
- `hr-no-dashboard-eyeball-pull-data-yourself` / `hr-observability-layer-citation` — the fenced-directive signal lands on the tracker, not only in a run summary.

### Research decision

Strong local context (the sweeper, its tests, the sibling lint, the scrub script, the runbooks) plus the upstream threads already read. **No external research phase.**

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| Bare form at three doc sites | ~20 sites across README ×2, getting-started.njk, sync.md, 10 SKILL.md files, claude-code-plugins.njk; plus a substring-shaped test | Files to Edit lists every site; AC uses a repo-wide grep with the learning's exclusion set. |
| `claude plugin marketplace update soleur` is the correct first command | The marketplace on the recommended path is named `soleur-marketplace`; `soleur` is the in-repo marketplace's name | Both commands change on the recommended path; a one-line note covers the direct-repository path (`claude plugin list` prints the id). |
| "Runbook and changelog already use the full form — make all sites consistent" | They use *different* marketplace halves, each right for its context | Consistency means "qualified form + the marketplace half that matches the documented path", not one string everywhere. `plugin-delivery-recovery.md` is unchanged. |
| One tracker has a fenced directive | Six do; the ship template produces the shape | Sweeper detection covers the population; template + runbook fixed; the six bodies unfenced (see sequencing). |
| Repoint or glob the `REPORTS` path | Archive path is terminal; a lint needs a literal | Literal repoint + lint. |
| Draft a NEW upstream issue | #93108 already exists and is open | Draft a comment on #93108 (done in this planning session; scrub passed) — see `knowledge-base/project/specs/feat-one-shot-7490-followthrough-revive-and-plugin-update-form/upstream-reports.md`. |

## Problem Statement / Motivation

- **Docs tell users to run a command that can fail.** `claude plugin update soleur` (bare) can return `Plugin not found` on current CLI releases (upstream #83947; collaborator confirmation on #76882). Worse, the first command in the same block — `claude plugin marketplace update soleur` — names a marketplace the recommended install path never created (that path's marketplace is `soleur-marketplace`). A new user who follows README → "Updating" verbatim gets either an error or a no-op with a green checkmark.
- **A tracker that was built to never rot has rotted for 35 days.** #7490 has a probe, a label and a directive, and none of it runs: the directive is inside a fence the sweeper skips, and even unfenced the probe would FAIL on a path that moved in the PR that shipped it. Five sibling trackers are dead by the same fence, because the ship template that authors follow-through bodies emits the fence.
- **The comparator defect has an upstream home nobody has told.** Upstream #76882 closed as docs without touching the version-string comparator; #93108 (open, has-repro) is that defect, and this repo holds the one reading that thread lacks — a record carrying a constant `version` *and* a valid `gitCommitSha` side by side, plus the controlled two-arm experiment.

## Proposed Solution

Three streams, one PR, `semver:patch`.

**Stream A — docs.** Two shapes, chosen by whether the text can know which marketplace the reader added:

- **Docs that state the install path in the same passage** (README §Updating, plugins/soleur/README.md §Known Issues, getting-started.njk, the three blog posts, knowledge-base/project/README.md, ADR-178's example) name it concretely: `claude plugin marketplace update soleur-marketplace` + `claude plugin update soleur@soleur-marketplace`, plus one sentence for the direct-repository path (`claude plugin list` prints the id; there it is `soleur@soleur`).
- **Strings emitted at RUNTIME** (the 14 SKILL.md echo lines and `sync.md`'s producer-missing remedy) cannot know which path the reader took, so they print the generic form `claude plugin update soleur@<marketplace>` together with `claude plugin list` (which prints the exact id). Hardcoding `soleur@soleur-marketplace` there would hand a wrong command to every operator who installed from the repository — including this repo's own operator, whose install is `soleur@soleur`.

The sync-remedy test pins whichever literal `sync.md` ends up carrying, so bare cannot regress. The test does NOT derive the literal from the published manifest: that would make the `test-scripts` shard depend on network. Phase 0 verifies the manifest's `name` once instead.

**Stream B — follow-through.**
1. `plugin-delivery-canary-7490.sh`: `REPORTS` becomes the terminal archive path.
2. New `scripts/lint-followthrough-repo-paths.sh` (+ `.test.sh`, registered in `test-all.sh`): a census over `scripts/followthroughs/*.sh` of assignment-shaped repo-path literals; each must exist from the repo root; a red floor on the census size; a per-line opt-out annotation for artefacts that exist only at runtime.
3. `sweep-followthroughs.sh`: a fenced-only directive **opener** is a new LOUD verdict, mirroring `MISSING_SECRET` — one tracker comment (actor-gated dedup), `::error::` every run, `FENCED_DIRECTIVE=1`, red run, open-mode only. The predicate is unified to CommonMark `^ {0,3}(```|~~~)` across the sweeper and the three producer sites. An unbalanced fence gets its own distinct text. Tests per the Guard 2 matrix, including the must-PASS row for the 19 live trackers that contain fences but no directive.
4. Producers agree with the consumer: the ship template loses its ```` ```html ```` fence; the convention runbook says "unfenced, column 0"; `ship-soak-followthrough-gate.sh` and the ship SKILL.md enrollment grep strip fences before matching; the create-time hook's deny reason names the fence when that is the cause.
5. The six fenced bodies are unfenced (`gh issue edit --body-file`) and, where missing, gain `secrets=GH_TOKEN` — without it a gh-using probe is unauthenticated under `env -i` and TRANSIENTs forever (a silent never-close). #7490's `earliest=` moves to `2026-09-21T00:00:00Z` so the first evaluation happens after this PR's probe fix is on `main`. Two sibling probes are repaired inline rather than enrolled broken: `inngest-doublefire-reading-6617.sh`'s `gh issue view --comments --json` conflict (one line; measured to return PASS once fixed) and `gh-pages-cert-reissue-6657.sh`'s null-`https_certificate` arm, which currently cannot distinguish "Pages not configured" from an API hiccup.

**Stream C — upstream.** The posting record `knowledge-base/project/specs/feat-one-shot-7490-followthrough-revive-and-plugin-update-form/upstream-reports.md` is already drafted (this planning session) and passes `scripts/upstream-report-scrub.sh` (`SCRUB OK: 0 exposures in 1 file`). Sending it is operator-gated: headless, the decision is persisted for `/ship` to render as an `action-required` issue; the record's `_pending_` cells are filled only after a real post and an as-posted re-scrub. A comment on #8253 records the 4th recurrence.

## Technical Considerations

- **Marketplace-name nuance is the whole point of Stream A.** The id's right half is the `name` of the marketplace the user added, not a fixed string; the docs must say which path they are describing. The recovery runbook's `soleur@soleur` (operator's monorepo install) is correct and untouched; the changelog's `soleur@soleur-marketplace` is correct and untouched.
- **A daily comment on a non-PASS tracker is the sweeper's existing steady state, not a new harm.** The 2026-09-18 run commented on #7922, #7437, #7761, #7556 and #7432, all exit 2. So unfencing restores these six to the same regime every other enrolled tracker is already in. What this plan does NOT do is add a *new* unbounded stream: the new fenced verdict carries an actor-gated dedup (Guard 2 rows 10–11) so a fenced tracker is told once, while the `::error::` and the red run repeat every sweep. A general "dedup every verdict" change to the sweeper is a larger contract change and is out of scope (see Not in scope).
- **Ordering vs. the nightly sweep.** The cron is `0 18 * * *` UTC and checks out `main`. Unfencing #7490 with a past `earliest` before the probe fix merges would produce one FAIL comment plus an action-required issue from the old probe. `earliest=2026-09-21T00:00:00Z` avoids that without new machinery; if the PR has not merged by then, the cost is one FAIL comment, not a wrong close.
- **Sibling first verdicts are MEASURED, not predicted.** Each probe was run on 2026-09-18 under the sweeper's own shape (`env -i PATH HOME GH_TOKEN GH_REPO`, with `gh` on PATH):

| Tracker | `secrets=` today | Measured rc | Meaning |
|---|---|---|---|
| #7490 | **none** | 1 with the old path; **0** with the repointed path | PASS → closes, once the repoint is on `main` |
| #7985 | **none** | **1 (FAIL)** — `no release newer than v0.15.7` | a FAIL probe, not a NOT-YET probe; it comments daily until the provider cuts a release containing the fix |
| #6678 | `GH_TOKEN` | **2 (TRANSIENT)** — `empty cert state from API` (`/repos/.../pages` returns `https_certificate: null`) | cannot distinguish "Pages not configured" from an API hiccup; would TRANSIENT daily |
| #6617 | **none** | **2** — `could not read #6617 comments (gh rc=1)`; reproduced: `gh issue view N --comments --json comments` → *"specify only one of --comments or --json"* on gh 2.101 | dead by CLI drift. **With the one-line flag fix it returns rc=0 (PASS)** — measured |
| #6488 | `SUPABASE_ACCESS_TOKEN` | not runnable locally (needs the Supabase token) | expected FAIL until the 14 tables are dropped |
| #5813 | **none** | **0 (PASS)** | closes on the first authenticated run |

Two consequences the earlier draft missed. (i) **`secrets=GH_TOKEN` is missing on four of the six directives** (#7490, #7985, #6617, #5813) and every one of those probes calls `gh`; `followthrough-convention.md` states the rule outright ("MANDATORY for any gh-using probe … a silent never-close") because the sweeper runs probes under `env -i` and CI `gh` authenticates from `GH_TOKEN`, not `~/.config/gh`. Unfencing without adding the clause buys a permanent TRANSIENT, i.e. a tracker that still never closes. Phase 5 adds the clause in the same body edit. (ii) **#6617's probe is broken by CLI drift** and #6678's cannot distinguish a null cert state from an API failure; those are triaged inline below rather than deferred, per `wg-defer-only-after-inline-triage`.
- **Lint scope is assignment-shaped literals, by design.** `VAR=knowledge-base/…`, optionally `${ROOT}/`-prefixed, optionally quoted. Prose mentions in comments are not path claims. A path built by concatenation across lines is a documented blind spot; the matrix has a row for every shape the lint claims.
- **The sweeper's `^<!--` anchor stays column-0.** #7490's directive lines are at column 0 inside the fence; the hook's `^[[:space:]]*` tolerance is a pre-existing difference this plan does not widen.
- **No `$VAR` in skill bash blocks** (constitution): the SKILL.md echo strings are literal.
- **Headless posting gate and archival ordering.** If `decision-challenges.md` is written (headless at Phase 6), `/ship` Phase 6 step 2.5 reads it at the *live* spec path to render `## Model Dissents (informational)` and file the `action-required` issue — so compound's archival of this spec dir is deferred in that run (ship SKILL.md's Phase 7 Step 4 note names this as the legitimate choice). The `upstream-reports.md` record then stays at its live path too; AC18/AC23 already accept either path.
- **Hook edits are exercised by their own `.test.sh`** (`follow-through-directive-gate.test.sh`, `ship-soak-followthrough-gate.test.sh`); the new rows use the existing fixtures.

## User-Brand Impact

- **If this lands broken, the user experiences:** a docs block telling them to run `claude plugin update soleur@soleur-marketplace` when their marketplace is named differently (they added the repository directly) and no sentence telling them how to find the right id — the same "green checkmark, nothing delivered" they came to the docs to escape. On the sweeper side, a red daily run and a comment on six trackers that keeps repeating until someone unfences a body.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the one public write in this plan is the comment body for anthropics/claude-code#93108. It carries no user data; the exposure vectors are the operator's own (absolute home paths, local repository layout, timestamps, machine identifiers) — the four categories `scripts/upstream-report-scrub.sh` enumerates, checked before posting and re-checked as posted.
- **Brand-survival threshold:** `aggregate pattern` — a wrong update instruction degrades every new install's first upgrade, but no single user loses data or money.

## Observability

```yaml
liveness_signal:
  what: "the daily follow-through sweeper run itself (a red run is the fenced-directive and missing-secret signal); the marketplace-drift canary job for the delivery path"
  cadence: "daily 18:00 UTC (sweeper); daily 06:37 UTC (canary)"
  alert_target: "a comment on the affected tracker (every non-PASS verdict) plus a red workflow run for the LOUD verdicts. The sweeper posts comments only -- it never opens an issue; the operator-visible surface for a FAIL is the tracker comment and the red run"
  configured_in: ".github/workflows/scheduled-followthrough-sweeper.yml; .github/workflows/scheduled-marketplace-drift.yml"

error_reporting:
  destination: "GitHub Actions annotations (::error::) + the tracker comment; no Sentry surface exists for this workflow (observability layer 7 — plugin/CLI and repo automation, no server)"
  fail_loud: "'### Sweeper run: DIRECTIVE INSIDE CODE FENCE' comment on the tracker and a red workflow run; the lint prints 'MISSING <file> -> <path>' and exits 1 in the test-scripts CI shard"

failure_modes:
  - mode: "a follow-through tracker's only directive is inside a code fence"
    detection: "sweep-followthroughs.sh parse_directive emits __sweeper_meta__ fenced_directive_count; run_one comments on the tracker and sets FENCED_DIRECTIVE=1; main exits 1"
    alert_route: "issue notification to the tracker's author; red scheduled run"
  - mode: "a probe cites a repo artefact that was moved or deleted (archive-kb, rename)"
    detection: "scripts/lint-followthrough-repo-paths.sh in scripts/test-all.sh (test-scripts shard) reddens the PR"
    alert_route: "PR check failure before merge"
  - mode: "the lint's census resolves zero or too few references (broken glob)"
    detection: "MIN_REFS floor -> exit 2 with 'expected the full set'"
    alert_route: "PR check failure"
  - mode: "#7490's probe PASSes vacuously"
    detection: "unchanged: compared=0 -> FAIL; missing REPORTS -> FAIL; _pending_ in REPORTS -> FAIL"
    alert_route: "sweeper FAIL comment on #7490 + red run (no issue is filed; the sweeper has no gh issue create path)"

logs:
  where: "GitHub Actions run log of scheduled-followthrough-sweeper.yml (job 'sweep'); GITHUB_STEP_SUMMARY no-directive section"
  retention: "90 days (GitHub default)"

discoverability_test:
  command: "bash scripts/lint-followthrough-repo-paths.sh"
  expected_output: "OK: <N> probe file(s) scanned, <M> repo-path reference(s), 0 missing (M >= 5)"
```

## Guard Contract

### Guard 1 — lint-followthrough-repo-paths

**Property.** Every assignment-shaped repo-relative path literal in a follow-through probe under `scripts/followthroughs/` names an artefact that exists on the tree being tested, unless the line carries a `# repo-path: runtime` annotation.

**Assembly.** The chokepoint is the sweeper's working directory: every probe runs from the repo root (`scheduled-followthrough-sweeper.yml` → `bash scripts/sweep-followthroughs.sh` → `env -i … bash <script>`), so a repo-relative literal resolves against the checkout. The census is the file set `scripts/followthroughs/*.sh` **excluding `*.test.sh`** — the same exclusion `lint-followthrough-varq-ban.sh` rule 1 makes, and load-bearing here: `ccla-representative-icla-7922.test.sh` assigns `TSX="$REPO_ROOT/apps/web-platform/node_modules/.bin/tsx"`, a gitignored path that exists locally and not in the `test-scripts` CI shard (which installs no npm dependencies), so judging it would redden CI on a file the lint must not judge. Within each scanned file, the census is every line matching an assignment-shaped repo-path literal — optional `readonly`/`local`/`declare -r`, optional quote, optional `${VAR}/` or `${VAR:-${ROOT}/…}` prefix, then one of `knowledge-base|scripts|apps|plugins|tests|docs|.github` — plus a `source`/`.`-prefixed arm for sourced libraries (a missing sourced lib is a hard crash, strictly worse than a missing data file).

**Measured census (2026-09-18, this regex over `scripts/followthroughs/*.sh`): 32 matches across 22 files, exactly ONE missing** — `plugin-delivery-canary-7490.sh`'s `REPORTS=`. The floor is therefore `MIN_REFS=28` (measured 32, headroom for one probe retirement), and Phase 2 re-measures rather than trusting this sentence. The `:-` arm is not cosmetic: `QUERY="${BETTERSTACK_QUERY_SH:-${REPO_ROOT}/scripts/betterstack-query.sh}"` appears in `betterstack-roundtrip-latency-7855.sh`, `git-data-rung2-evidence-capture.sh` and `inngest-cutover-flip-rollout-7761.sh`, and a regex without it misses all of them.

**Declared blind spots (named in the script header, not silent):** a path built by concatenation across lines or by `printf -v`; a path assembled inside `$(cd … && pwd)`; anything in a `*.test.sh` sandbox.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture probe assigns `REPORTS=knowledge-base/project/specs/nope/upstream-reports.md` (absent) | RED (exit 1, cited as `MISSING <file> -> <path>`) |
| 2 | Point the lint at an empty directory in production mode (no TARGET_DIR arg) | RED (exit 2, "expected the full set") — the guard's own dispatch |
| 3 | Two fixture probes: the first cites an existing path, the second an absent one | RED — the second member is checked |
| 4 | Fixture assigns `X="${REPO_ROOT}/scripts/followthroughs/absent.sh"` | RED — the `${VAR}/` prefix shape |
| 5 | Fixture assigns `Q="${SOME_OVERRIDE:-${REPO_ROOT}/scripts/absent.sh}"` | RED — the `:-` default-expansion arm |
| 6 | Fixture `source "${REPO_ROOT}/scripts/lib/absent.sh"` | RED — the source arm |
| 7 | Fixture cites an absent path with a trailing `# repo-path: runtime` annotation | PASS — the documented exemption (must-PASS, non-canonical) |
| 8 | Fixture cites an existing path inside single quotes | PASS — quoting is permitted |
| 9 | Sandbox containing ONLY a `*.test.sh` that cites an absent gitignored path | PASS — `.test.sh` is outside the census (must-PASS; pins the CI-shard property) |
| 10 | Harness: delete the `check` line for row 1 in the `.test.sh` | RED — `passes+fails != asserted` or the assertion floor trips |
| 11 | Live tree after the repoint: `bash scripts/lint-followthrough-repo-paths.sh` | PASS with refs ≥ 28, 0 missing; before the repoint the same command is RED on `plugin-delivery-canary-7490.sh` |

**Anchor.** The compared value is the filesystem (`-e` at the repo root), which the same commit can move — that is the point: a rename that forgets the probe reddens the PR that renamed. No stored hash; nothing self-certifies.

### Guard 2 — sweeper fenced-only directive is LOUD (and bounded)

**Property.** An OPEN `follow-through`-labelled issue whose body contains a `soleur:followthrough` directive **opener** only inside a code fence receives one comment naming the cause and the fix, and the sweep run exits non-zero — while a body with no directive at all, and a body with a fenced example beside a real directive, are unaffected.

**Assembly.** `scripts/sweep-followthroughs.sh`: `parse_directive` (the single awk every body flows through). The counter increments on a **directive opener seen while inside a fence**, never on the fence delimiter:

```awk
/^ {0,3}(```|~~~)/            { fence = !fence; next }
fence && /^[[:space:]]*<!-- *soleur:followthrough/ { fenced_seen++ }
fence                        { next }
```

`END` emits `__sweeper_meta__ fenced_directive_count N` only when `seen == 0 && fenced_seen > 0`, and `__sweeper_meta__ unbalanced_fence 1` when `fence` is still open at EOF. Then `run_one` (the `__sweeper_meta__` arms; the loud branch inside `[[ -z "${script:-}" ]]`, gated on `mode == "open"`; the dedup readback; `FENCED_DIRECTIVE=1`; the `DRY_RUN` short-circuit; a separate `FENCED_FILE` list so the "missing directive" step-summary section does not double-signal) and `main`'s tail (all three run-level flags evaluated, every annotation printed, then one `exit 1`). Both the open-set and closed-set loops call `run_one`, which is why the mode gate is part of the assembly rather than a caller-side concern.

**Measured population this quantifies over (2026-09-18):** 56 open `follow-through` issues — 6 fenced-only (the target), **19 with no directive at all but at least one fence** (these must stay quiet; they are the exact false-positive the delimiter-increment would produce), 31 with an unfenced directive. Zero bodies where the CommonMark predicate `^ {0,3}(```|~~~)` disagrees with the current `/^```/`, so unifying the predicate changes no live verdict today; three bodies (#6678, #6565, #7674) contain indented fences, which is why the predicate is unified rather than left column-0.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | T6 body (directive opener only inside ```` ```html ````), open mode | RED — comment `### Sweeper run: DIRECTIVE INSIDE CODE FENCE`, `::error::`, `FENCED_DIRECTIVE=1`, probe NOT run, `main` exits 1 |
| 2 | sed-delete the `FENCED_DIRECTIVE=1` assignment (dispatch) | mutant `main` exits 0 on the T6 body — the flag is the mechanism |
| 3 | Move the increment onto the fence-delimiter line (`/^ {0,3}(```|~~~)/ { fenced_seen++; fence = !fence; next }`) | RED — the "fences but no directive" must-PASS row (6) starts failing; this is the 19-tracker false positive pinned as a mutation |
| 4 | Remove the `fence &&` guard from the increment line | RED — row 7 (fenced example beside a real directive) starts failing |
| 5 | Delete the `mode == "open"` gate on the loud branch | RED — row 9 (closed tracker) starts failing |
| 6 | Body with two fenced blocks and **no** directive anywhere | PASS — quiet `no directive — skipping`, no meta, no comment, exit 0 (must-PASS, non-canonical) |
| 7 | Body with a fenced example FIRST and a real unfenced directive AFTER | PASS — directive honored, probe runs, no fenced verdict (must-PASS, non-canonical) |
| 8 | Body whose directive is inside an **indented** fence (3 spaces) | RED — the unified `^ {0,3}` predicate sees it |
| 9 | Fenced-only body, **closed** mode (`run_one … closed`) | PASS — logged, `return 0`, no comment (the closed path's whole design is no-comment) |
| 10 | Fenced-only body on which a sweeper `DIRECTIVE INSIDE CODE FENCE` comment already exists (actor `github-actions`/`github-actions[bot]`) | one `::error::` and a red run, **no second comment** — the dedup readback |
| 11 | Same as row 10 but the prior comment was authored by a non-bot login | RED — comment posted (a forged marker must not silence the guard) |
| 12 | Body with an unbalanced fence (odd count) and a directive after it | RED with the **`unbalanced fence`** text, not the "move it out of the fence" text |
| 13 | `DRY_RUN=1` on the T6 body | comment suppressed, `::error::` still emitted, `FENCED_DIRECTIVE=1` still set |
| 14 | Set `TRUNCATED_SWEEP=1` and `FENCED_DIRECTIVE=1` together | both annotations printed before the single `exit 1` (the pre-existing tail returns on the first) |
| 15 | Harness: delete T6's `assert_contains "DIRECTIVE INSIDE CODE FENCE"` line | the suite's accounting identity / assertion floor reddens |

**Anchor.** Not a stored-value guard. The dedup readback is actor-gated with the same exact-login jq the closed-set precheck uses (`github-actions` or `github-actions[bot]`, never a prefix), so a user-authored comment cannot silence it.

### Guard 3 — producer-side enrollment predicates agree with the consumer

**Property.** No producer-side check (`ship-soak-followthrough-gate.sh`, the ship SKILL.md enrollment gate, the create-time hook's deny reason) counts a fenced-only directive as an enrollment.

**Assembly.** The three sites that read a tracker body for `<!-- soleur:followthrough`: `.claude/hooks/ship-soak-followthrough-gate.sh` (enrollment loop over `$REFS`), `plugins/soleur/skills/ship/SKILL.md` §Soak-Gated Follow-Through Enrollment Gate (the same loop as prose-embedded bash), `.claude/hooks/follow-through-directive-gate.sh` (already fence-aware in its awk; only the deny *reason* changes). All four sites — the three producers and the sweeper — adopt the SAME CommonMark predicate `^ {0,3}(```|~~~)` (the ship-soak gate already carries two different strips today: `/^```/` at its PR-body strip and `/^[[:space:]]*```/` at its plan strip, so "reuse the existing one" is ambiguous and the plan picks one). Measured: no live tracker body changes verdict under the unified predicate.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `ship-soak-followthrough-gate.test.sh`: tracker fixture whose directive is fenced-only | RED — reported UNENROLLED |
| 2 | Same fixture, directive unfenced | PASS — enrolled |
| 3 | `follow-through-directive-gate.test.sh`: `gh issue create --label follow-through --body-file` with a fenced-only directive | deny, and the reason contains `inside a code fence` |
| 4 | Revert the fence strip in the ship-soak gate | row 1 flips to enrolled — the test reddens |
| 5 | Tracker fixture whose directive is inside an **indented** fence | RED — UNENROLLED (this is the row that fails if a site keeps the column-0-only predicate) |
| 6 | Harness: remove row 1's assertion | the suite's own floor/accounting reddens |

### Guard 4 — sync remedy pins the qualified form

**Property.** The `/soleur:sync` producer-missing remedy names `claude plugin marketplace update soleur-marketplace`, `claude plugin update soleur@soleur-marketplace` and `claude plugin uninstall soleur@soleur-marketplace && claude plugin install soleur@soleur-marketplace`, and a regression to any bare form reddens the test.

**Assembly.** `tests/commands/test-sync-producer-reachability.sh` T0m block (three `grep -Fq` lines) over the normalized sync output `$NORM_SYNC`, which is rendered from `plugins/soleur/commands/sync.md`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Edit `sync.md` back to `claude plugin update soleur` (bare) | RED — the assertion is `grep -Fq 'claude plugin update soleur@soleur-marketplace'`, which bare does not satisfy |
| 2 | Edit `sync.md` to `claude plugin marketplace update soleur` | RED |
| 3 | Delete the uninstall/install line from `sync.md` | RED (existing row, kept) |
| 4 | Harness: change the assertion back to the substring `claude plugin update soleur` | row 1 goes green — this is the vacuity the change removes; the plan's AC greps the test file for the qualified literal |

## Acceptance Criteria

### Pre-merge (PR)

_Verification-command note, applying to every AC below that asserts a zero count: `grep -c` and `git grep` **exit 1 when they match nothing**, so under `set -e` a zero-hit assertion aborts the shell before it can be read as a pass. Wrap each such command as `n=$(… || true); [[ "${n:-0}" -eq 0 ]]`. Verified against AC5's own command on an unchanged file: prints `0`, exits 1._

**Stream A — docs**

- [ ] AC1. Operator-surface bare-form census is zero: `git grep -nE "claude plugin (update|uninstall|install) soleur([^@a-z-]|$)" -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/project/learnings' ':!knowledge-base/project/brainstorms' ':!knowledge-base/marketing' ':!knowledge-base/product' ':!**/archive/**' ':!*.pen' ':!feature-request-plugin-update-surfaces-install-divergence.md'` returns no lines. Measured 2026-09-18: the unexcluded command returns 27 hits across 27 files; every exclusion is deliberate and one-line-justified — `plans`/`specs`/`learnings`/`brainstorms` are point-in-time records, `marketing`/`product` are internal audit and validation snapshots (4 files) that quote the old instruction as evidence, `*.pen` is a wireframe fixture, `archive/**` is terminal, and the root `feature-request-…md` is an upstream draft using `<name>` placeholders. **`plugins/soleur/docs/blog` is NOT excluded** — it is published; its three files are in `## Files to Edit`.
- [ ] AC2. `git grep -nE "claude plugin marketplace update soleur([^-]|$)" -- README.md plugins/soleur/README.md plugins/soleur/docs plugins/soleur/commands plugins/soleur/skills` returns no lines (the recommended path's marketplace is `soleur-marketplace`).
- [ ] AC3. Each of README.md §Updating, plugins/soleur/README.md §Known Issues (marketplace-update section) and getting-started.njk "Updating later?" contains the literal `claude plugin update soleur@soleur-marketplace` AND one sentence containing `claude plugin list` for the direct-repository path (`grep -c 'claude plugin list' <file>` ≥ 1 in each of the three).
- [ ] AC4. The sync-remedy assertions pin every command `sync.md` emits, with no bare form left unpinned: each of the marketplace-update, the `soleur@<marketplace>` update, the uninstall AND the install halves of the reinstall fallback appears as its own `grep -Fq` line (4 assertions, or 3 with the uninstall/install pinned as one full `&&` string — state which). `bash tests/commands/test-sync-producer-reachability.sh` passes, and reverting any one command in `sync.md` to the bare form fails it (Guard 4 rows 1–3, executed).
- [ ] AC5. The `getting-started.njk` diff is copy-only: `git diff origin/main -- plugins/soleur/docs/pages/getting-started.njk | grep -E '^\+' | grep -v '^+++' | grep -cE '<(div|section|pre|h[1-6]|ul|ol|li|a |img|script)'` == 0.
- [ ] AC6. Docs build is green: `cd plugins/soleur/docs && npx @11ty/eleventy` (or the repo's documented docs build command from `deploy-docs.yml`) exits 0 and `_site` contains `soleur@soleur-marketplace` in the getting-started page: `grep -c 'soleur@soleur-marketplace' plugins/soleur/docs/_site/getting-started/index.html` ≥ 1.

**Stream B — follow-through**

- [ ] AC7. `grep -n '^REPORTS=' scripts/followthroughs/plugin-delivery-canary-7490.sh` shows `REPORTS=knowledge-base/project/specs/archive/20260813-114111-feat-one-shot-7489-7490-marketplace-retire-delivery-followups/upstream-reports.md` and `test -r "$(sed -n 's/^REPORTS=//p' scripts/followthroughs/plugin-delivery-canary-7490.sh)"` succeeds.
- [ ] AC8. `env -i PATH=<sweeper PATH plus gh's dir> HOME="$HOME" GH_TOKEN="$(gh auth token)" GH_REPO=jikig-ai/soleur bash scripts/followthroughs/plugin-delivery-canary-7490.sh; echo rc=$?` prints `PASS: canary green on run <id> (compared>0), and every upstream posting slot is recorded.` and `rc=0`. Measured at plan time with the repointed path: PASS on run 35361236920. Two notes the work phase must honour: the sweeper's `env -i` PATH is `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`, so a `gh` installed elsewhere (mise, brew) must be added to the probe's PATH locally or the probe reports `gh rc=127` and this AC measures the harness, not the probe; and a local run inherits `HOME`, so `gh` can authenticate from `~/.config/gh` even with no `GH_TOKEN` — that is why AC14b, not a local no-token run, is what pins the `secrets=` clause (on CI `HOME` carries no gh config).
- [ ] AC9. `bash scripts/lint-followthrough-repo-paths.sh` exits 0 and prints files-scanned, refs ≥ `MIN_REFS` (28, from the Phase 0 re-measure; plan-time reading 32 across 22 non-test probes) and missing 0; `bash scripts/lint-followthrough-repo-paths.test.sh` exits 0 with every Guard 1 matrix row present as a named assertion; both are registered in `scripts/test-all.sh` next to the `followthrough-varq-ban` lines (`grep -c 'lint-followthrough-repo-paths' scripts/test-all.sh` == 2).
- [ ] AC10. `bash scripts/sweep-followthroughs.test.sh` exits 0 and contains named assertions for Guard 2 rows 1–6 (grep the test file for `DIRECTIVE INSIDE CODE FENCE` ≥ 3 and `FENCED_DIRECTIVE` ≥ 2).
- [ ] AC11. `grep -c 'FENCED_DIRECTIVE' scripts/sweep-followthroughs.sh` ≥ 4 (init, set, DRY_RUN log, main exit) and `grep -c 'fenced_directive_count' scripts/sweep-followthroughs.sh` ≥ 2 (awk emit + run_one arm).
- [ ] AC12. `grep -c '^\s*```html' plugins/soleur/skills/ship/SKILL.md` == 0 (measured today: 1, the template's fence — the template headings are indented inside a four-backtick block, so an `awk '/^## Verification/,/^## Status/'` range matches nothing and would pass vacuously; do not use it), AND the `<!-- soleur:followthrough` line in the template is preceded by the template's `## Verification` heading with no fence line between them (`awk` over the four-backtick block, or a positive `grep -A2` assertion). `grep -c 'unfenced' knowledge-base/engineering/operations/runbooks/followthrough-convention.md` ≥ 1 in §Author workflow step 4 or the `## Directive fields` table.
- [ ] AC13. `bash .claude/hooks/ship-soak-followthrough-gate.test.sh` and `bash .claude/hooks/follow-through-directive-gate.test.sh` exit 0 and each contains a fenced-only fixture row (grep each test file for `fenced` ≥ 1).
- [ ] AC14. The six issue bodies are unfenced under the SAME predicate the shipped sweeper uses: for N in 7490 7985 6678 6617 6488 5813, `gh issue view $N --json body -q .body | awk 'BEGIN{f=0} /^ {0,3}(```|~~~)/{f=!f; next} f{next} /^[[:space:]]*<!-- *soleur:followthrough/{c++} END{exit !(c>=1)}'` exits 0; and #7490's body carries `earliest=2026-09-21T00:00:00Z`.
- [ ] AC14b. Every unfenced directive whose probe calls `gh` declares `secrets=GH_TOKEN`: for N in 7490 7985 6617 5813 6678, `gh issue view $N --json body -q .body | grep -c 'secrets=.*GH_TOKEN'` ≥ 1 (#6488's probe uses `SUPABASE_ACCESS_TOKEN` and keeps it). Rationale is the convention runbook's MANDATORY rule; without it the probe is unauthenticated under `env -i` and never closes.
- [ ] AC15. The PR body carries a `### Unfenced trackers` table with, per tracker, the MEASURED exit code from the `env -i … GH_TOKEN=… ` form (re-measured at work time, not copied from this plan) and the expected first sweeper verdict. Any tracker whose measured rc is 2 for a reason inside this repo's control (a broken CLI invocation, an unhandled null field) is repaired in this PR before its body is unfenced — #6617 and #6678 are the two known instances.
- [ ] AC16. One comment exists on #7985 pointing at `knowledge-base/project/learnings/2026-09-17-followthrough-directive-on-existing-issue-three-silent-traps.md` and stating the MEASURED behaviour: the probe exits **1 (FAIL)** — not NOT YET — until `jianyuan/terraform-provider-sentry` cuts a release containing the #950 fix, so the tracker will receive a daily FAIL comment while it waits.
- [ ] AC17. Sweeper dry run against the live population from this branch: `gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true` (the workflow exists on the default branch, so `--ref` dispatches it and `actions/checkout` then takes the branch — the branch's probe fix IS exercised), then read the RUN LOG, not the run conclusion: it must show `issue #7490: earliest=2026-09-21T00:00:00Z not yet reached` (never `no directive`), no `DIRECTIVE INSIDE CODE FENCE` line for any of the six, and no such line for any of the 19 directive-less-but-fenced trackers. The conclusion may legitimately be red if some other tracker trips the new guard.

**Stream C — upstream**

- [ ] AC18. `bash scripts/upstream-report-scrub.sh knowledge-base/project/specs/feat-one-shot-7490-followthrough-revive-and-plugin-update-form/upstream-reports.md` prints `SCRUB OK: 0 exposures in 1 file` (or the archived path after compound archives the spec dir).
- [ ] AC19. The record's `## Section-to-posting mapping` names #93108 as the destination and the `## Posting log` row is `_pending_` unless a post has happened; if a post happened, the row carries the comment URL and a `PASS — 0 exposures, <N> bytes as stored` re-scrub line from `gh api <comment-url> --jq .body | bash scripts/upstream-report-scrub.sh -`.
- [ ] AC20. Nothing was posted to anthropics/claude-code by this pipeline without an explicit operator approval recorded in the session (headless: the approval request is persisted to `knowledge-base/project/specs/feat-one-shot-7490-followthrough-revive-and-plugin-update-form/decision-challenges.md` for `/ship` to render as an `action-required` issue; AC19 stays `_pending_`).
- [ ] AC21. A comment on #8253 records the 4th recurrence (this feature, destination #93108, the steps re-derived: search-before-draft, section-to-posting mapping, scrub-on-file, operator gate, posting log) and notes that the tracker's re-evaluation criterion is now met.

**Cross-cutting**

- [ ] AC22. `bash scripts/test-all.sh` full battery is green (the `/ship` Phase 4 checkpoint), including `scripts/followthrough-exec-bit`, `scripts/followthrough-varq-ban-live` (the new lint lives beside it and must not trip rule 2), `scripts/sweep-followthroughs`, and the two hook suites.
- [ ] AC23. Every `knowledge-base/` path cited in this plan resolves: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | sort -u | grep -vE 'specs/feat-one-shot-7489-7490-marketplace-retire-delivery-followups/|specs/nope/|decision-challenges\.md' | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'` prints nothing (checked before compound archives the spec dir). The three exclusions are, in order: the pre-fix `REPORTS` path this plan quotes as the defect, the Guard 1 fixture path, and the conditionally-created headless-gate file.
- [ ] AC24. PR body uses `Closes #7490` (the sweeper is expected to close it anyway once the probe PASSes on/after 2026-09-21; either close is correct — the tracker's criteria are met when AC8 holds), carries `semver:patch`, and lists the diff scope: the files in `## Files to Edit` / `## Files to Create`, plus `knowledge-base/INDEX.md`, `knowledge-base/project/specs/<branch>/{tasks.md,session-state.md,upstream-reports.md,decision-challenges.md}` and this plan (which compound archives).

### Post-merge (automated)

- [ ] AC25. The first sweeper cron run on or after 2026-09-21 logs `issue #7490: directive found (script=scripts/followthroughs/plugin-delivery-canary-7490.sh …)` and a PASS verdict that closes #7490 (if this PR's `Closes` already closed it, the closed-set loop's `CLOSED_LOOKBACK_DAYS` re-evaluation must not reopen it — the probe PASSes, so it will not). Automation: read by `gh run list --workflow scheduled-followthrough-sweeper.yml` + `gh run view --log`; no operator action.

## Files to Edit

- `README.md` — §Updating block: both commands qualified for the recommended path + one sentence for the direct-repository path.
- `plugins/soleur/README.md` — §Known Issues → "Updating the Marketplace Does Not Update the Installed Plugin": same.
- `plugins/soleur/docs/pages/getting-started.njk` — "Updating later?" callout: three `<code>` strings + the `claude plugin list` sentence (copy only).
- `plugins/soleur/docs/pages/claude-code-plugins.njk` — FAQ prose and JSON-LD `text`: `claude plugin install soleur@soleur-marketplace` (both copies must stay byte-identical; check the page's existing JSON-LD ↔ prose parity convention).
- `plugins/soleur/docs/blog/2026-03-16-soleur-vs-anthropic-cowork.md`, `plugins/soleur/docs/blog/2026-03-17-soleur-vs-notion-custom-agents.md`, `plugins/soleur/docs/blog/2026-04-30-best-claude-code-plugins-2026.md` — published operator surfaces carrying the bare install/update form (4 lines total).
- `knowledge-base/project/README.md` and `knowledge-base/engineering/architecture/decisions/ADR-178-shared-bash-primitives-ship-in-plugin.md` — one bare-form line each; ADR-178's is prose inside an argument about delivery, so the qualified form is the point.
- `plugins/soleur/commands/sync.md` — producer-missing remedy message: three commands qualified.
- `plugins/soleur/skills/{agent-browser,cf-token-scope,feature-video,incident,legal-generate,linear-fetch,qa,reproduce-bug,test-browser,trigger-cron}/SKILL.md` — the 14 `Run 'claude plugin update soleur'` echo lines → `Run 'claude plugin update soleur@soleur-marketplace' (or the id 'claude plugin list' prints, if you added the repository directly)`; the `incident`/`legal-generate` variants keep their scope sentence.
- `tests/commands/test-sync-producer-reachability.sh` — the three `grep -Fq` remedy assertions → qualified literals (Guard 4).
- `scripts/followthroughs/plugin-delivery-canary-7490.sh` — `REPORTS=` → archive path; header comment gains one line naming the lint that now protects it.
- `scripts/followthroughs/inngest-doublefire-reading-6617.sh` — `gh issue view "$ISSUE" --comments --json comments` → `gh issue view "$ISSUE" --json comments` (gh ≥ 2.101 rejects both flags together; measured rc 2 → rc 0 PASS after the fix).
- `scripts/followthroughs/gh-pages-cert-reissue-6657.sh` — distinguish a null/absent `https_certificate.state` (Pages not configured for HTTPS) from an API failure, so the probe stops reporting a permanent TRANSIENT; keep TRANSIENT for the genuine API-error arm.
- `scripts/sweep-followthroughs.sh` — Guard 2 (awk `fenced_seen`; `__sweeper_meta__ fenced_directive_count`; `FENCED_DIRECTIVE` flag, comment, `::error::`, main exit).
- `scripts/sweep-followthroughs.test.sh` — T6 re-pinned; new rows per Guard 2; `MIN_ASSERTIONS`-style floor re-measured if the suite has one.
- `scripts/test-all.sh` — two `run_suite` lines for the new lint and its test, beside `followthrough-varq-ban`.
- `plugins/soleur/skills/ship/SKILL.md` — (i) follow-through issue-body template: drop the ```` ```html ```` fence around the directive, add "unfenced, column 0 — the sweeper skips fenced blocks"; (ii) §Soak-Gated Follow-Through Enrollment Gate bash: strip fences before the directive grep (Guard 3).
- `.claude/hooks/ship-soak-followthrough-gate.sh` — enrollment loop strips fences before `grep -q '<!-- soleur:followthrough'` (Guard 3).
- `.claude/hooks/ship-soak-followthrough-gate.test.sh` — fenced-only tracker fixture row + its inverse.
- `.claude/hooks/follow-through-directive-gate.sh` — when the raw body has the marker but the fence-stripped parse yields no `script=`, the deny reason says the directive is inside a code fence.
- `.claude/hooks/follow-through-directive-gate.test.sh` — one fenced-only row asserting the reason text.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — §Author workflow step 4: "paste it unfenced (column 0); the example below is fenced only so it renders here"; `## Directive fields` gains a "Placement" row.
- `knowledge-base/project/specs/feat-one-shot-7490-followthrough-revive-and-plugin-update-form/upstream-reports.md` — posting log cells filled only after a real post (else untouched).

## Files to Create

- `scripts/lint-followthrough-repo-paths.sh` — Guard 1 (sibling of `lint-followthrough-varq-ban.sh`: `[TARGET_DIR]` arg, `MIN_REFS` production floor with a `REPO_PATHS_MIN_REFS` test-only override, exit 0/1/2, one `MISSING <file> -> <path>` line per miss, a final `OK:`/`FAIL:` summary naming files scanned, refs found, misses).
- `scripts/lint-followthrough-repo-paths.test.sh` — Guard 1 matrix as named assertions, mktemp sandbox, `pass()`/`fail()`/`check()` with the ADR-193 accounting identity and a measured `MIN_ASSERTIONS` floor (`printf` + `exit 1`, never via `fail()`).
- `knowledge-base/project/specs/feat-one-shot-7490-followthrough-revive-and-plugin-update-form/decision-challenges.md` — only if the pipeline is headless at the posting gate. Shape is constrained by its consumer: `/ship` Phase 6 step 2.5 folds the file's CONTENT into the PR body under `## Model Dissents (informational)`, and the `ship-operator-step-gate` PreToolUse hook then denies `gh pr ready` on bullets beginning `Operator`/`Post-merge`/`Follow-up` and on `T+<N>` / `Within <N>h of merge:` shapes. So the file uses the 5-line frame from `decision-principles.md` (What you said / What both signals recommend / Why / What context we might be missing / If we're wrong, the cost is) as **informational statements**, never an operator-action bullet. The branch segment in the path must match `git branch --show-current` exactly, and compound's archival of this spec dir must be deferred until after Phase 6 or step 2.5 reads nothing.

## Not in scope (with reasons)

- **A new upstream issue** — #93108 exists (see Research Reconciliation).
- **Building `upstream-ask`** — #8253 tracks it; this plan is its 4th-recurrence trigger, recorded there.
- **Extending the create-time hook to `gh issue edit`** — the sweeper is the population's chokepoint (Cut List).
- **A general per-verdict dedup for the sweeper** (skip a comment when the previous sweeper comment carried the same exit code) — it would quiet the ~20 trackers that comment daily today, but it changes the contract for every enrolled probe and needs its own matrix (what re-notifies after a verdict flips back? how does an operator tell "still failing" from "stopped running"?). The new fenced verdict carries its own bounded dedup (Guard 2 rows 10–11) because it is a *new* comment path and shipping it unbounded would be a regression this plan introduced. A tracking issue is filed for the general case.
- **De-duplicating daily NOT-YET/FAIL comments on long-horizon probes (#7985's shape)** — same class as above; the 2026-09-17 learning names the drift-watcher shape if the owner wants quiet.
- **Changing `plugin-delivery-recovery.md`'s `soleur@soleur`** — correct for the operator's monorepo install.
- **`feature-request-plugin-update-surfaces-install-divergence.md`** at the repo root — a placeholder-form upstream draft from #7474, not a docs surface; left as is.
- **Annotating `scripts/followthroughs/ccla-representative-icla-7922.acknowledged` as a runtime path** — an earlier draft of this plan proposed it; the file is **tracked** (`git ls-files` lists it and it exists), so annotating it would exempt a real rot target from Guard 1 on a false premise. Dropped.

## Implementation Phases

Order matters only where a contract changes before its consumer (Guard 2's awk before its test rows; the lint before its registration).

### Phase 0 — Preconditions (measure, do not assume)

1. `claude --version` (record); `claude plugin update --help | head -3` and `claude plugin marketplace update --help | head -3` pasted into the PR body (CLI-verification gate #2566).
2. `curl -fsSL --max-time 15 https://raw.githubusercontent.com/jikig-ai/soleur-marketplace/main/.claude-plugin/marketplace.json | jq -r .name` → must print `soleur-marketplace` (the docs' marketplace half).
3. Re-run the fenced census over open `follow-through` issues (the awk in AC14 inverted) and confirm the set is still exactly `{7490, 7985, 6678, 6617, 6488, 5813}`; if it grew, the new member joins Phase 5.
4. `bash scripts/lint-followthrough-varq-ban.sh` and `bash scripts/sweep-followthroughs.test.sh` green on the untouched tree (baseline).
5. Re-measure the Guard 1 census on the current tree (files scanned, refs found, misses) and set `MIN_REFS` from it; plan-time reading was 32 refs / 22 files / 1 miss → floor 28.
6. Census the directive-less-but-fenced population (expected 19 open) and record it: that number is the false-positive blast radius the Guard 2 increment placement must keep at zero.

### Phase 1 — Stream A docs (RED → GREEN)

1. RED: change the three `grep -Fq` lines in `tests/commands/test-sync-producer-reachability.sh` to the qualified literals; run it; T0m must fail on the current `sync.md`.
2. GREEN: edit `sync.md`; re-run; green.
3. README.md, plugins/soleur/README.md, getting-started.njk, claude-code-plugins.njk, the 14 SKILL.md lines. Run AC1/AC2/AC3/AC5, then the docs build (AC6).

### Phase 2 — Guard 1 lint (RED → GREEN)

1. Write `scripts/lint-followthrough-repo-paths.test.sh` first, with every Guard 1 matrix row as a named assertion (rows 1–7); it must fail because the lint does not exist.
2. Write `scripts/lint-followthrough-repo-paths.sh`; the live-tree row (row 8) must be RED on the untouched probe.
3. Repoint `REPORTS=` in `plugin-delivery-canary-7490.sh`; the live-tree row goes GREEN (the only miss in the 32-reference census). No `# repo-path: runtime` annotation is needed on the current tree — the one candidate, `ccla-representative-icla-7922.acknowledged`, is tracked.
4. Register both in `scripts/test-all.sh`; run `bash scripts/test-all.sh` for the `scripts/` group (or the full battery if that is the only entry point).
5. AC8: run the repointed probe with the `env -i` form and record the output.

### Phase 3 — Guard 2 sweeper (RED → GREEN)

1. Re-pin T6 to the loud shape and add rows 2–6 as new named tests in `sweep-followthroughs.test.sh` (mirror `t_g3_m1_missing_secret_is_loud` and the G3-M3 sed-mutation harness); run: RED.
2. Edit `parse_directive` (count `fenced_seen` in the fence branch; `END` emit), `run_one` (meta arm, loud branch mirroring the `MISSING_SECRET` block: heading `### Sweeper run: DIRECTIVE INSIDE CODE FENCE (<ts>)`, body naming the fix "move the `<!-- soleur:followthrough … -->` block out of the code fence, column 0; the sweeper skips fenced blocks by design (#4200)", `::error::`, `FENCED_DIRECTIVE=1`, `DRY_RUN` short-circuit), and `main` (exit 1 when set). Keep the `NO_DIRECTIVE_FILE` append so the summary stays complete.
3. GREEN; then run the G3 suite to confirm `MISSING_SECRET` behaviour is unchanged.

### Phase 4 — Guard 3 producers

1. `ship-soak-followthrough-gate.test.sh` fenced-only row (RED) → gate edit (GREEN). Mirror the same strip into ship SKILL.md's prose-embedded bash.
2. `follow-through-directive-gate.test.sh` fenced-only row asserting the new reason (RED) → hook edit (GREEN).
3. Ship template: remove the fence; convention runbook: placement row + "unfenced" sentence.

### Phase 4.5 — Repair the two broken sibling probes (before enrolling them)

1. `inngest-doublefire-reading-6617.sh`: `--comments --json comments` → `--json comments`. Measure before (rc 2) and after (rc 0, PASS) with the `env -i` form. Add the invocation to the probe's header note so the next CLI bump has a reason to look.
2. `gh-pages-cert-reissue-6657.sh`: give the null/absent `https_certificate.state` its own arm (Pages HTTPS not configured) distinct from the API-error TRANSIENT, and record the measured `gh api /repos/jikig-ai/soleur/pages` response in the header. If the correct verdict for a null state is genuinely "cannot establish", say so with exit 3 (`CANNOT ESTABLISH` in the sweeper's static rc→word map) rather than 2, so the tracker's comment names the state instead of implying a transient network fault.

### Phase 5 — Unfence the six bodies (live mutation, measured first)

For each of 7985, 6678, 6617, 6488, 5813, then 7490:
1. Run the probe under the `env -i` form (AC8's PATH note applies) and record rc + last line.
2. `gh issue view N --json body -q .body > body.md`; edit `body.md` to (a) remove only the fence line immediately before `<!-- soleur:followthrough` and the fence line immediately after the closing `-->`, (b) add `secrets=GH_TOKEN` to the directive where the probe calls `gh` and the clause is absent (#7490, #7985, #6617, #5813), (c) for #7490 only, `earliest=2026-08-14T08:00:00Z` → `earliest=2026-09-21T00:00:00Z`. `diff` before/after and confirm no other line changed; `gh issue edit N --body-file body.md`.
3. Re-run the AC14 + AC14b checks on the live body.
4. #7985: post the AC16 comment with the measured FAIL semantics.
5. AC17 dry run from the branch with `--ref`; read the log, not the conclusion.

### Phase 6 — Stream C

1. AC18 scrub on the record (already green at plan time; re-run after any edit).
2. Operator gate: interactive → present the composed body verbatim and ask "Post this comment to anthropics/claude-code#93108 from your account? (yes / no / edit)"; on yes: `gh api repos/anthropics/claude-code/issues/93108/comments -f body=@<body-file>` → record URL → `gh api <comment-url> --jq .body | bash scripts/upstream-report-scrub.sh -` → fill both `_pending_` cells. Headless → write `decision-challenges.md` with the request and leave `_pending_`.
3. Comment on #8253 (AC21).

### Phase 7 — Cross-cutting

Full battery (AC22); plan-path check (AC23); PR body per AC24.

## Open Code-Review Overlap

One open `code-review` issue names a planned file:

- #7942 (`scripts/test-all.sh` — two `*.mutation.sh` batteries under `plugins/soleur/test/` run in no gate). **Acknowledge:** different concern; this plan adds two `run_suite` lines for the new lint beside the `followthrough-varq-ban` lines and does not touch the `plugins/soleur/test/*.test.sh` glob. The new test file carries the `.test.` infix (`lint-followthrough-repo-paths.test.sh`) so it is not a new instance of #7942's class. #7942 stays open.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (planner-inline; the CTO lens was applied to the two forks that carry engineering risk)
**Assessment:** (1) The sweeper change adds a LOUD verdict class in the exact shape of the existing `MISSING_SECRET` path (#7946), so the operator sees one new heading, not a new mechanism; a red daily run until a body is unfenced is the accepted cost, and this plan removes all six known instances before the change lands. (2) The lint's scope (assignment-shaped literals) is narrow on purpose; its blind spots are stated in the script header and the matrix has a row per covered shape. (3) The `earliest` bump on #7490 uses the sweeper's designed "not before" knob rather than new sequencing machinery. (4) Stream A's nuance — the marketplace half depends on which marketplace the user added — is the fact the brief missed; the docs must say it, or the qualified form fails on the direct-repository path exactly as the bare form fails on the recommended one.

### Product/UX Gate

**Mechanical UI-surface override, evaluated:** the glob superset in `plugins/soleur/skills/brainstorm/references/ui-surface-terms.md` (`**/*.njk`) matches `plugins/soleur/docs/pages/getting-started.njk` and `plugins/soleur/docs/pages/claude-code-plugins.njk` in `## Files to Edit`. The same file's `## Excluded (no wireframe required)` list names "Pure copy or style tweaks with no structural/layout change" and "Docs / knowledge-base … changes". Both edits are text inside existing `<code>`/`<p>` elements and a JSON-LD string — no new element, layout or flow (AC5 pins this mechanically: zero added structural tags in the diff). The term list is the single source of truth all four enforcement layers cite; under it this change does not touch a UI surface.

**Rule text, quoted because it is the decisive authority:** `wg-ui-feature-requires-pen-wireframe` reads *"UI surface = pages, components, modals, banners, nav/layout, flows (list: `skills/brainstorm/references/ui-surface-terms.md`); **excludes copy/style** and backend-only."* The glob superset in that list over-matches by design (it is a superset of the prose list) and the Excluded section of the same file narrows it. So the deepen-plan Phase 4.9 halt does not fire here, and `ux-design-lead` is not a skipped producer — there is no UI surface to produce for. AC5 is the mechanical proof of the "copy/style only" claim: zero structural tags added in the `.njk` diff.

**Tier:** none (copy-only docs text; excluded by the rule's own carve-out)
**Decision:** skipped — not a UI surface
**Agents invoked:** none
**Skipped specialists:** none (no UI feature exists here for `ux-design-lead` to design; this is not a skip of a required producer)
**Pencil available:** N/A (no UI surface)

Other domains (finance, legal, marketing, operations, sales, support): not relevant. The one public write (the #93108 comment) is engineering evidence about a CLI defect, scrubbed by the existing script; no legal-shaped text, no customer data, no spend.

## Test Scenarios

- The T6 body (fenced example only) → loud verdict, probe not run, run red.
- A body with both a fenced example and a real directive → honored, quiet.
- `DRY_RUN=1` on a fenced-only body → no comment, still `::error::` and red.
- Lint on a sandbox with one clean and one missing reference → exit 1 citing the second file.
- Lint on the live tree before/after the repoint → RED/GREEN.
- `sync.md` reverted to bare → T0m RED.
- `getting-started.njk` after edit → Eleventy build green, page text contains the qualified id.
- `plugin-delivery-canary-7490.sh` with the archived path → PASS on the current green canary (recorded output).

## Success Metrics

- Fenced-only trackers among open `follow-through` issues: 6 → 0 (AC14), and the sweeper reddens on the next one.
- Bare-form update instructions on operator surfaces: ~20 → 0 (AC1).
- #7490 closed by its own probe (AC25) or by the PR, with the probe PASSing either way (AC8).

## Dependencies & Risks

- **Risk: the canary is red on the day AC8 runs.** Then the probe's FAIL is correct; record the run URL and do not "fix" the probe to pass. The tracker stays open until the canary is green.
- **Risk: a sibling probe FAILs or TRANSIENTs on its first evaluation and comments daily.** That is the sweeper's existing steady state for every non-PASS tracker (five commented on 2026-09-18), not a new mechanism; the `### Unfenced trackers` table gives the operator the measured prediction to read the first verdict against. The two probes whose non-PASS was caused by a defect inside this repo (#6617's CLI-flag conflict, #6678's null cert state) are repaired in Phase 4.5 rather than enrolled broken.
- **Risk: the new fenced verdict fires on a tracker with no directive at all.** 19 open trackers contain a fence and no directive; the increment must sit on a directive opener seen inside a fence, never on the fence delimiter. Guard 2 rows 3 and 6 pin both directions, and Phase 0 step 6 records the population so the work phase can re-check.
- **Risk: a red sweeper run masks a second run-level signal.** The existing tail returns on the first flag; the plan collects all three (`TRUNCATED_SWEEP`, `MISSING_SECRET`, `FENCED_DIRECTIVE`), prints every annotation, then exits once (Guard 2 row 14).
- **Risk: unfencing before merge with a past `earliest` on #7490.** Mitigated by the `earliest` bump; residual cost one FAIL comment if the PR slips past 2026-09-21.
- **Risk: `ship-soak-followthrough-gate.sh` tightening blocks PR-ready for *this* PR** if its own referenced trackers read as unenrolled. The six are unfenced in Phase 5 before ship; any other tracker this PR references (#8253 is not soak-gated) is unaffected.
- **Risk: the `**/*.njk` glob trips deepen-plan Phase 4.9.** The edit is copy-only (AC5) and `ui-surface-terms.md` §Excluded names "pure copy or style tweaks"; the Domain Review below records the evaluation so the halt's trigger reads it.
- **Dependency:** none external. `gh` auth in-session for the six body edits; Doppler not required.

## References & Research

- Upstream: anthropics/claude-code #93108, #83947, #76882 (comment 5310894439), #86700.
- ADR-182; `plugin-delivery-recovery.md`; `followthrough-convention.md`; `measurements.md` §1.0/§1.9; archived `upstream-reports.md` §1 and posting log.
- Learnings: listed under Research Insights.
- Sweeper defect history: #4200 (fence skip), #7946 (MISSING_SECRET loud shape), #4191 (ship template).

## Plan Review Revisions (2026-09-18)

Two reviews ran at plan time: a SpecFlow flow-and-gap pass (18 findings, most of them **measured against the live tree**) and a scoped strong-model advisor consult. Every finding below was independently re-verified in this session before it was applied; the verification command is named. All are engineering-correctness findings → **Mechanical**, auto-applied.

| # | Finding | Verified how | Revision |
|---|---|---|---|
| R1 | P0 — incrementing `fenced_seen` on the fence delimiter would fire the new verdict on every directive-less tracker that merely contains a fence | census of 56 open trackers: **19** have `raw=0` directives and ≥1 fence | Guard 2 assembly now increments only on a directive opener seen inside a fence; matrix rows 3 (mutation) and 6 (must-PASS) pin both directions |
| R2 | P0 — the loud branch would fire on CLOSED trackers, daily | read of `run_one`: the `[[ -z "$script" ]]` branch precedes the `mode == "closed"` handling | loud branch gated on `mode == "open"`; matrix row 9 |
| R3 | P0 — four of the six directives (#7490, #7985, #6617, #5813) declare no `secrets=`, and all four probes call `gh`; under `env -i` on CI that is a silent never-close | `followthrough-convention.md` line 91 states the rule; live directive bodies read; the 2026-09-18 run shows `#7922 secrets=none → exit=2` | Phase 5 adds `secrets=GH_TOKEN` in the same body edit; new **AC14b** |
| R4 | P0 — Guard 1's census would judge `ccla-representative-icla-7922.test.sh`'s gitignored `node_modules/.bin/tsx` and redden the `test-scripts` shard | the line exists at `:34`; the shard installs no npm deps | census excludes `*.test.sh`; matrix row 9 pins it |
| R5 | P0 — AC12's `awk '/^## Verification/,/^## Status/'` matches nothing (the template headings are indented inside a four-backtick block), so it passed vacuously with the fence present | ran it: range output 0 lines, count 0; `grep -c '^\s*```html'` == 1 | AC12 rewritten to the whole-file anchored grep plus a positive adjacency assertion |
| R6 | P1 — the plan's first-verdict predictions were wrong for four of six trackers | each probe run under `env -i … GH_TOKEN` with `gh` on PATH | prediction bullet replaced by a **measured** table; #6617 (rc 2, `--comments --json` conflict on gh 2.101) and #6678 (rc 2, null `https_certificate`) repaired in a new **Phase 4.5** — #6617 returns **PASS** after the one-line fix, measured |
| R7 | P1 — no dedup on the new comment path, and the `main` tail returns on the first run-level flag | read of `sweep-followthroughs.sh` tail | actor-gated dedup on the fenced verdict only (rows 10–11); all three flags collected before one `exit 1` (row 14); general per-verdict dedup explicitly **out of scope** with a tracking issue |
| R8 | P1 — `MIN_REFS=5` was ~6× too low; the plan's census of "six lines" was wrong | ran the regex: **32 matches across 22 files, 1 missing** | floor 28, re-measured in Phase 0 step 5 |
| R9 | P1 — the census regex misses `${VAR:-${ROOT}/…}` defaults and `source`d libraries | the `:-` form appears in three probes | both arms added; blind spots declared in the script header |
| R10 | P1 — AC1 could not pass: 27 files carry the bare form today, 11 outside `## Files to Edit` | ran AC1's command | three published blog posts + `knowledge-base/project/README.md` + ADR-178 added to Files to Edit; `marketing`/`product`/`brainstorms`/`*.pen` excluded with a one-line reason each; **`plugins/soleur/docs/blog` deliberately NOT excluded** |
| R11 | P1 — producer and consumer fence predicates disagree (`/^```/` vs `/^[[:space:]]*```/`, both already in the ship-soak gate) | read both; censused live bodies | one CommonMark predicate `^ {0,3}(```\|~~~)` in all four sites; verified **zero** live trackers change verdict under it; Guard 3 row 5 pins an indented fence |
| R12 | P1 — `decision-challenges.md` content is folded into the PR body, so an `Operator:`-shaped bullet would trip `ship-operator-step-gate` on `gh pr ready` | ship SKILL.md Phase 6 step 2.5 + the hook's deny groups | file shape constrained to the 5-line informational frame; compound archival deferred until after Phase 6 |
| R13 | P2 — unbalanced / four-backtick / tilde fences would get the wrong advice | live census: 0 unbalanced, 0 four-backtick, 0 tilde today | distinct `unbalanced fence` meta and comment text; matrix row 12; the tilde case is covered by the unified predicate |
| R14 | P2 — the plan claimed the sweeper "files an action-required issue on FAIL"; it has no `gh issue create` path | grep of the script | Observability `alert_target` and the failure-mode routes corrected |
| R15 | P2 — fenced trackers would be counted in the "missing directive" step-summary section as well as commented on | read of the summary block | separate `FENCED_FILE` list and its own summary section |
| R16 | P2 — AC4 pinned only the uninstall half of the reinstall fallback | read of the test's three `grep -Fq` lines | AC4 now pins every command `sync.md` emits |
| R17 | P2 — AC17 hedged on `--ref`, and would have read the run conclusion | `workflow_dispatch --ref` works when the workflow is on the default branch | AC17 states the `--ref` form definitively and reads the log, not the conclusion |
| R18 | P2 — the proposed `# repo-path: runtime` annotation targeted a **tracked** file | `git ls-files` lists `…-7922.acknowledged` | item dropped; recorded in Not in scope so it is not re-proposed |
| R19 | Advisor — runtime strings cannot know which marketplace the reader added, so hardcoding `soleur@soleur-marketplace` in the 14 SKILL.md echo lines and `sync.md` would hand a wrong command to every repository-path installer (including this repo's own operator, whose install is `soleur@soleur`) | `claude plugin list --json` → `soleur@soleur` | Stream A split into two shapes: concrete in docs that state the install path, generic `soleur@<marketplace>` + `claude plugin list` in runtime strings |
| R20 | Advisor — deriving the test's expected literal from the published manifest | — | **Rejected with reason:** it would make the `test-scripts` shard depend on network. Phase 0 step 2 verifies the manifest name once instead |
| R21 | Advisor — "add dedup or don't unfence anything that comments" | the 2026-09-18 run comments on five non-PASS trackers already | **Partially adopted:** bounded dedup for the new path only (R7). Unfencing restores these six to the regime ~20 enrolled trackers are already in, so the "sweepers get muted" cost is pre-existing, not introduced here — and the two probes that were non-PASS for a repo-side defect are repaired first (R6) |

One finding is recorded and **not** applied: the advisor's suggestion to defer Phase 5 wholesale to post-merge. Rejected because `earliest=` already orders #7490 correctly, the five siblings' probes are on `main` today (only #7490's fix is in this PR), and leaving them fenced preserves exactly the rot this change exists to end. The ordering risk that remains is one FAIL comment if the PR slips past 2026-09-21, which is stated under Risks.
