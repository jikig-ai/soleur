---
title: "fix: three ship-gate defects — the PIR no-item sentinel vs MD049, adr-ordinals is a required check (#7941), and the bun-test hook on merge commits"
date: 2026-09-11
slug: fix-pir-gate-md049-adr-ordinals-merge-hook
branch: feat-one-shot-7941-pir-gate-md049-adr-ordinals
issue: 7941
closes: 7941
type: bug
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-11
**Sections enhanced:** Design (script, caller, suite), Observability, Guard Contract, Implementation
Phases, Acceptance Criteria, Test Scenarios, Non-Goals, Risks, citations
**Research agents used:** git-history-analyzer (attribution), test-design-reviewer,
architecture-strategist, spec-flow-analyzer, observability-coverage-reviewer, verify-the-negative
sweep (14 claims, 13 confirmed, 1 corrected); plan-review panel before it (DHH, Kieran,
code-simplicity, CTO) and the Step 4.5 advisor consult.

### Key Improvements

1. **The script owns every state, by exit code.** `--branch` exits 3 on "no PIR in diff" (the
   caller's No-match arm) and 2 when `git diff origin/main...HEAD` itself fails (a `master` repo,
   an unfetched clone) — never "no PIR"; `--no-renames --diff-filter=d` so a renamed PIR is
   checked at its new path and a deleted one is excluded; `set -uo pipefail`, because under `-e`
   the row classifier's no-match `grep` aborts the shape-(b) path with no `[FAIL]` line
   (measured). The `ship/SKILL.md` caller drops its own selector line and becomes a four-arm
   `case` with stderr preserved and a `SOLEUR_SHIP_PIR_GATE_HALT` marker.
2. **The shipped entry point is tested.** A fifth suite arm builds a fixture repo
   (`git_fixture_env`, `refs/remotes/origin/main`) and pins every-PIR-over-`head -n1`, rename,
   delete, no-PIR (exit 3) and git-unavailable (exit 2). Fixtures carry a first-line `expect:`
   token that must agree with the `pass-`/`fail-` name; reasons are asserted on stderr; floors
   are hand-measured; the corpus arm parses an anchored summary line and checks
   `selected == examined + skipped` rather than pinning a count.
3. **This PR's own path through the Incident-PIR gate is now honest.** "No signal" is the only
   legal exit — the meta-case cannot apply and every other arm authors a PIR for a non-event —
   so Phase 4 names both regex halves (`OUTAGE_RE`, `PROD_RE`) and the words to keep out of prose.
4. **Observability cites its layers** (7 `cli-stdout-artifact` on the CLI, 1 `sentry-correlation`
   on the hosted `event-ship-merge` path, 6 for the suite), records verdict lines into the PR
   body as the durable artifact, and its `expected_output` is tokenizable by preflight Check 10.
5. **Thread 3 names its one net-less path**: the settle-then-admin-merge hatch's step 2 gains
   "present and green on the current SHA", in the same paragraph this PR already edits.

### New Considerations Discovered

- Citations corrected: the `--pr` input move was issue #7987 / PR #8011; the hatch was issue
  #7553 / PR #7616; `auto-close-scan.sh` (not `net-issue-flow.sh`) is the
  `${CLAUDE_PLUGIN_ROOT}` invocation precedent. Commit `ae44051a8` touched 29 PIR files, nine of
  which carried the sentinel.
- The underscore form was chosen in #5008 purely as the gate's anchor (`^_No`), not for
  rendering — there is nothing to preserve by keeping it.
- Section extraction is not fence-aware (fail-closed; zero corpus instances) — stated, not fixed.
- The producer-side filename convention (`<slug>-postmortem.md`) is unbound to the gate's ERE —
  a named residual.

Three related defects in the ship-time gates and the commit-time hooks, planned together because
each is a pin on a string or a fact that drifted from the thing it pins.

1. **The Incident-PIR gate's no-item sentinel.** The `/ship` Phase 5.5 shape check accepts only
   the underscore-emphasised form of the permitted "no action items" sentence; the PIR template
   prescribes that same form; the pinned linter (MD049 `emphasis-style`, default `consistent`)
   rewrites it to asterisks in any PIR whose first emphasis is an asterisk. Three pins on one
   sentence, two of them now disagree, and the third (the linter) will keep moving whichever one
   it is pointed at. **Fix:** drop emphasis from the mandated sentence (a plain line has nothing
   for MD049 to restyle); make the gate accept an optional leading `_` or `*` so the 21
   already-shipped PIRs still pass; and move the shape check out of prose into a shipped, tested
   script that owns its own input — the pattern #6813 (regexes) and #7987 / PR #8011 (input) established for
   this gate's signal scan, applied to its shape check for the first time.
2. **`adr-ordinals` is a required status check** (#7941). `ship/SKILL.md` says in three places
   that it is not, and `plan/SKILL.md` and ADR-156 repeat the claim. The failure model those
   sentences teach is inverted: with the strict up-to-date policy on `main`, a sibling's colliding
   ADR reaches the branch through the BEHIND auto-sync, the re-run `adr-ordinals` job reds on the
   PR, and Phase 7's required-check-failure exit names it — the merge is blocked, nothing lands
   red on `main`. The Phase 5.5 gate stays as defense-in-depth; its rationale and the Phase 7
   recovery paragraph are rewritten. The Phase 4 prose's "tracked separately" claim about
   `infra-validate-required` is true — the tracker is #6480 (open) — and is made to cite it.
3. **The `bun-test` pre-commit hook on merge commits.** The hook runs the full
   `scripts/test-all.sh` battery on any commit that stages a `*.{ts,tsx,js,jsx}` file. A
   conflict-resolved sync merge (`git merge origin/main` → resolve → `git commit`, which is exactly
   what `ship` Phase 7 step 4 prescribes) stages the whole of `origin/main`'s delta, so the glob
   always matches, and the run then queues on the advisory lock behind every sibling battery —
   up to `TC_LOCK_TIMEOUT` (3600 s) before a ~45-minute run begins, inside a Phase 7 poll loop
   budgeted at 15 minutes. The recorded outcome on the Sentry alert-derivation PR (`57c47c8`) was
   four `--no-verify` bypasses, 3861 s spent waiting on one of them before any suite started.
   **Decision:** the battery should not run on a merge commit at all, and lefthook already has
   the primitive — `skip: [merge]`, verified on the installed 2.1.6 in a plain repo and a linked
   worktree. No lock-contention escape is added (on expiry the lock PROCEEDS, so a shorter budget
   is the six-concurrent-runs generator ADR-133 documents; a refusal is what ADR-196 rejected).
   No issue is filed: the fix is inline.

## Research Insights

### Premise Validation (Phase 0.6)

- **#7941** — `gh issue view 7941 --json state`: OPEN. Title: "review: ship/SKILL.md claims
  adr-ordinals is not a required check — it is". Premise holds; this plan closes it.
- **`adr-ordinals` required** — `gh api 'repos/{owner}/{repo}/rules/branches/main' --jq
  '[.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context]'`
  returns 25 contexts including `adr-ordinals`; `strict_required_status_checks_policy` is
  `true` on both the applied ruleset and `infra/github/ruleset-ci-required.tf:87`. The IaC row is
  `ruleset-ci-required.tf:169` (added by #6049/#6050, merged 2026-07-05); `scripts/required-checks.txt:125`
  is the SSOT row. ADR-032 §"`adr-ordinals` reconciliation" records that the applied ruleset
  already carried it when the IaC caught up. The claim in `ship/SKILL.md:1435`, `:1481`, `:2083`,
  `plan/SKILL.md:698` and ADR-156's ordinal note (dated 2026-08-02, after #6050) is false. A
  learning already recorded this on 2026-07-15
  (`2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md`
  §Session Errors 4) — the correction never reached the skill.
- **`infra-validate-required` tracker exists** — `gh issue list --state all --search
  'infra-validate-required'` → **#6480** (OPEN, "infra: make infra-validate-required an actual
  required check"), plus #6473 and #6766 in the same family. The Phase 4 sentence is true but
  uncited; it will cite #6480. The PR body must say the tracker exists (the issue asked for the
  check to be made, not assumed).
- **The 12 / 9 split** — reproduced on this branch's tree:
  `grep -l '^_No action items — incident fully resolved' <PIR dir>/*.md | wc -l` → 12;
  `grep -l '^\*No action items — incident fully resolved' <PIR dir>/*.md | wc -l` → 9. The nine
  asterisk forms were all written by commit `ae44051a8` (#7955, the 2026-09-09 sweep) — verified
  with `git log -S'*No action items'` on one of them.
- **The mechanism** — reproduced with the pinned binary against three one-file fixtures: a file
  whose first emphasis is `*x*` and whose sentinel is `_…_` fails MD049 (two errors, line 7 cols 1
  and 83); the mirror image (`_x_` first, `*…*` sentinel) fails the same way; the plain sentence
  passes in both. So "which form survives" is decided by whatever the author emphasised first,
  not by the template.
- **The prose block is untested** — `grep -rn 'No action items' plugins/soleur/test/ scripts/`
  returns nothing outside the incident skill's own `dry-run.sh`; `ship-incident-pir-gate.sh` and
  its two suites cover the signal scan only. The shape check exists solely as a bash block inside
  `ship/SKILL.md` that the ship agent executes by reading it.
- **Corpus conformance today, measured by the gate's own selector.** The gate's trigger is the
  ERE `^knowledge-base/engineering/operations/post-mortems/.+-postmortem\.md$` over `git diff`
  output; applied to `git ls-files` it selects **119** files (the directory holds 120 `.md`; the
  120th is an RCA whose name does not end in `-postmortem.md` and which the gate therefore never
  examines). Running the current inline block over those 119: **94 pass, 25 fail.** With the
  anchor widened to `^[_*]?No action items…`: **103 pass, 16 fail**, and every one of the 16 has
  no `## Action Items & Follow-ups` heading at all (pre-template files). The nine sweep-converted
  files are exactly the 94→103 delta. These are the two verdict sets Phase 1 must reproduce, in
  that order.
- **lefthook `skip: [merge]`** — probed on the installed `lefthook 2.1.6` with a three-case
  fixture repo, and re-probed by review inside a linked worktree: conflict-resolved merge commit
  (MERGE_HEAD present) → `bun-test (skip) by condition`, commit succeeds; ordinary `.ts` commit →
  command runs; `.md`-only commit → `(skip) no matching staged files`; clean `git merge --no-ff` →
  `pre-commit` does not run at all (only `pre-commit` and `pre-push` are installed, and
  `pre-push` carries no battery). The Thread-3 case is therefore precisely the conflict-resolved
  merge, and `skip: [merge]` covers exactly it.
- **`markdownlint-cli` has no per-directory config** — `node_modules/markdownlint-cli/README.md:112`:
  the CLI looks for a config in the current folder only, and `scripts/markdown-lint.sh` passes
  `--config` explicitly. `markdownlint-configure-file` directives are counted and rejected by the
  sweep's anti-vacuity guard. So "configure MD049 for the PIR directory" has no mechanism short
  of switching linters.
- **Cost of pinning a style corpus-wide** — measured with `{"default": false, "MD049": {"style": …}}`
  over the swept set: `underscore` → 9,130 errors (674 in the PIR directory); `asterisk` → 152
  errors (30 in the PIR directory). `--fix` for MD049 is forbidden by `markdown-lint.sh`'s own
  remediation block ("DO NOT --fix these four: MD037 MD038 MD049 MD050"), so either pin is a
  hand sweep, and neither removes the coupling — it just picks which pin the other two must chase.
- **Where a ship-gate script must live to run at all.** The signal scan is invoked as
  `"${CLAUDE_PLUGIN_ROOT:-.}/../../scripts/ship-incident-pir-gate.sh"` — a repo-root path that
  exists only in this monorepo; `git ls-files plugins/soleur | grep -c ship-incident-pir-gate.sh`
  → 0. The shipped precedent is `plugins/soleur/skills/ship/scripts/` (`net-issue-flow.sh`,
  `auto-close-scan.sh`); `auto-close-scan.sh` is invoked as
  `bash ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/ship/scripts/…` (the form this plan adopts),
  `net-issue-flow.sh` by a hard-coded repo-relative path.
  The new script goes there. (The signal scan's own path is a pre-existing gap outside this
  plan's scope; the PR body names it in one sentence. Review measured it as worse than stated:
  `${CLAUDE_PLUGIN_ROOT:-.}/../../scripts/` is depth-relative, so it resolves only from a cwd
  exactly two levels below the repo root — 127 from the monorepo root and on the hosted path — and
  the `if`/`else` around it read 127 as "no signal"; the caller now branches on `rc` with a HALT arm.)

### Property List and Cut List (Phase 0.6b)

**Properties.**

- P1. The sentence the PIR template prescribes for "no action items" is accepted by the ship gate.
- P2. Running the pinned linter over a PIR cannot change whether it passes the ship gate.
- P3. Every PIR already on `main` that satisfied the gate before the sweep still satisfies it.
- P4. Drift between the template's sentence and the gate's acceptance is caught by a test that
  runs the gate's own code, before it ships.
- P5. A reader of `ship/SKILL.md`, `plan/SKILL.md` or ADR-156 learns the true consequence of an
  ADR-ordinal collision (merge blocked on the PR; Phase 7 names the check).
- P6. Every "tracked separately" in the touched prose names its tracker.
- P7. A conflict-resolved sync merge commit does not start the full battery; an ordinary commit
  that stages a `*.{ts,tsx,js,jsx}` file still does.
- P8. The `fanout-suite-scope.test.sh` hatch guard (ADR-196 decision 6) still sees the
  invocation as hatched.
- P9. Every PIR the branch adds or modifies is checked (the block today checks only the first,
  via `head -n1`).

**Mechanisms proposed by the ask, and what buys each property.**

| Mechanism | Property | Already covered by | Disposition |
|---|---|---|---|
| Configure MD049 for the PIR directory | P2 | nothing — and no per-directory mechanism exists (see above) | **cut** |
| Widen the gate anchor to both emphasis forms | P3 | nothing | **kept**, as `^[_*]?` (accepts plain, `_`, `*`) |
| Change the template to match | P1, P2 | nothing | **kept**, as the plain sentence — the only form MD049 cannot touch |
| Per-file emphasis normalisation (the prior workaround) | P2 for one file | — | **cut**, per the ask: fragile, and MD049 re-decides per file |
| Extract the shape check into a shipped script that owns its input + suite | P4, P9 | `ship-incident-pir-gate.sh` covers the signal scan only | **kept** — same doctrine as #6813 and #7987/PR #8011 ("a harness must execute the shipped runtime, not scrape it out of a document") |
| Pinned list of the 16 heading-less legacy PIRs in the suite | — | no property asks for it; it reds an unrelated PR that retrofits a heading | **cut** at plan review |
| Lock-contention escape in the hook | P7 | — | **cut**: `tc_acquire` proceeds on expiry (never aborts), so a short budget is the ADR-133 six-runs incident; a refusal is the ADR-196 rejected alternative |
| Skip the battery on merge commits | P7 | lefthook's native `skip: [merge]` | **kept** — a two-line YAML change, no shell logic |
| Diff-scoped shards in the hook | P7 (superset) | no mechanical path→shard map exists (`want_*` predicates carry no path information, `work/SKILL.md:905`) | **cut**, not filed: all four recorded bypasses were merge commits; re-evaluate if a non-merge bypass of `bun-test` is ever recorded |
| ADR-196 amendment note | — | ADR-196's statement ("the two git-hook invokers carry the hatch") stays true after the skip; the `lefthook.yml` comment is the record | **cut** at plan review |

### Relevant files (verified on this tree)

- `plugins/soleur/skills/ship/SKILL.md:1108-1150` — Incident-PIR gate; the inline shape block is
  `:1120-1150` (`PIR=$(… | head -n1)` at `:1130` … `grep -qE '^_No action items — incident fully resolved'` at `:1148`).
- `plugins/soleur/skills/ship/SKILL.md:1152-1160` — the meta-case's conjunct-1 path list (the
  new script/suite/fixture dir must join it, or the next PR whose subject is this check cannot
  use the exemption; conjunct 2's contract is unchanged by this).
- `plugins/soleur/skills/ship/SKILL.md:359` — Phase 4 `infra-validate-required` sentence (the
  only `tracked separately` in the file).
- `plugins/soleur/skills/ship/SKILL.md:1435`, `:1481` — Phase 5.5 ADR-Ordinal Collision Gate
  rationale and Why.
- `plugins/soleur/skills/ship/SKILL.md:2083` — Phase 7 "ADR-ordinal collision after a sync";
  `:2159` documents the required-check-failure exit it must now point at.
- `plugins/soleur/skills/ship/SKILL.md:2120` — "all 22 contexts" (stale count; 25 today).
- `plugins/soleur/skills/ship/SKILL.md:1875` — Phase 7 step 4 `git commit -m "Merge origin/main -- resolve conflicts"`.
- `plugins/soleur/skills/plan/SKILL.md:698` — the same false parenthetical.
- `knowledge-base/engineering/architecture/decisions/ADR-156-hook-stdin-is-model-controlled-and-untrusted.md:15-17`
  — ordinal note repeating the claim.
- `plugins/soleur/skills/incident/templates/pir.md:135` — "write exactly `_No action items …_`".
- `plugins/soleur/skills/incident/SKILL.md:224` — placeholder table row, same sentence.
- `plugins/soleur/skills/incident/scripts/dry-run.sh:385` — draft heredoc, same sentence.
- `lefthook.yml:287-296` — the `bun-test` stanza (its `run:` passes no file arguments, unlike
  `markdown-lint`'s `{staged_files}`).
- `scripts/test-all.sh:77-78` — `SUITE_GLOBS` auto-globs `plugins/soleur/test/*.test.sh`, so a
  suite placed there needs no `run_suite` registration and cannot be an orphan.
- `plugins/soleur/skills/ship/scripts/net-issue-flow.sh`, `auto-close-scan.sh` — shipped
  in-skill script precedent; tests at `plugins/soleur/test/net-issue-flow.test.sh`,
  `auto-close-scanner.test.sh`.
- `scripts/ship-incident-pir-gate.sh` — exit-code and `--pr` input-ownership precedent.
- `plugins/soleur/test/fanout-suite-scope.test.sh:504-548` — the hatch guard: strips comments,
  splits on `;`/`&&`/`||`, requires `SOLEUR_ALLOW_FULL_GATE=1` in every segment that invokes
  `test-all.sh` in command position. A `skip:` key is YAML, not a `run:` segment, so it is
  invisible to this guard by construction (P8 holds without any edit there). Review checked the
  other eight scripts that read `lefthook.yml`; none parses the `bun-test` stanza structurally.
- `.markdownlintignore` — `plugins/soleur/test/fixtures/` is excluded, so the new fixture corpus
  is immune to the linter (the #7955 lesson: fixtures are suite input, not documentation).

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-09-09-the-linter-rewrote-the-fixtures-its-own-suites-assert-on.md`
  — a linter rewrites the bytes a suite asserts on; this plan's fixtures sit under the excluded
  fixture root, and the sentinel itself is made linter-invariant rather than lint-exempt.
- `knowledge-base/project/learnings/2026-09-08-a-bounded-edit-costs-the-files-debt-not-your-diff.md`
  — staged-file linting scores the whole file; the nine PIRs were restyled because their first
  emphasis was an asterisk, not because the sentinel was touched.
- `knowledge-base/project/learnings/2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md`
  — already recorded "`adr-ordinals` 'is not a required check' — false"; the skill kept teaching
  the stale model for two months because the learning had no consumer.
- `knowledge-base/project/learnings/best-practices/2026-07-17-adr-ordinal-ship-recheck-and-ss-fail-closed-isolation.md`
  — the ordinal is provisional until merge; the Phase 5.5 gate's value is catching the collision
  one CI cycle earlier, which is the defense-in-depth framing this plan adopts.
- `knowledge-base/project/learnings/2026-08-19-the-budget-was-shorter-than-the-thing-it-was-waiting-for.md`
  — why `TC_LOCK_TIMEOUT` is 3600 s and why it proceeds rather than aborts; the reason a hook-side
  "shorter wait" is not a fix.
- `knowledge-base/project/learnings/workflow-issues/2026-04-02-lefthook-hangs-in-git-worktrees.md`
  — prior `LEFTHOOK=0` workaround history; the merge-commit skip removes one recurring reason to
  reach for it.

### Conventions from AGENTS.md that shape the edits

- `cq-assert-anchor-not-bare-token` — the suite asserts on the gate script's exit code and
  `[FAIL]` line, and the probe asserts on lefthook's exact `(skip) by condition` marker.
- `cq-cite-content-anchor-not-line-number` — code comments added by this PR cite content anchors.
- `hr-verify-repo-capability-claim-before-assert` — the one place that explains the collision
  failure model cites the SSOT it was read from; the other sites point at that place.
- `wg-use-closes-n-in-pr-body-not-title-to` — `Closes #7941` goes in the PR body.
- `wg-defer-only-after-inline-triage` — Thread 3 was triaged inline and fixed inline; nothing
  deferred, nothing filed.

## Research Reconciliation — ask claims vs. codebase

| Claim in the ask | Reality on this tree | Plan response |
|---|---|---|
| Gate accepts only the underscore form (`:~1140`) | True; the grep is at `ship/SKILL.md:1148`, inside an inline block that also uses `head -n1` (only the first modified PIR is checked) | Script owns the branch enumeration and checks every PIR (P9) |
| 12 underscore / 9 asterisk | Reproduced: 12 / 9 | — |
| Root cause MD049 default `consistent` | Reproduced with the pinned binary (see Premise Validation) | — |
| "configure MD049 for the PIR directory" is an option | No per-directory config in `markdownlint-cli`; the sweep rejects `markdownlint-configure-file` | Cut |
| `adr-ordinals` "is not a required check" at `:2038` | The claim is at `:1435`, `:1481` and `:2083` in `ship/SKILL.md`; also `plan/SKILL.md:698` and ADR-156 `:16`. The ask's `:2038` is the Phase 7 loop's neighbourhood | All five sites corrected |
| "tracked separately" may be unbacked | Backed: #6480 (open), plus #6473/#6766 | Cite #6480; state so in the PR body |
| Hook wait "3861 s — past its own timeout" | Consistent with `tc_acquire`: the 3600 s budget PROCEEDS on expiry rather than aborting, so the run was released at ~3600 s and spent the remainder in the runner's pre-suite preamble before the bypass — no suite started, as the ask records | Decision recorded: no timeout change |
| "sync-merge commit that carries no new logic" | A clean merge never runs `pre-commit` (only `pre-commit`/`pre-push` hooks are installed, and `pre-push` has no battery); the case is the conflict-resolved merge, whose only new logic is the resolution — validated by the PR's CI on push and watched by Phase 7 | `skip: [merge]` |

## Design

### Thread 1 — one sentence, one gate, one test

**The sentence.** The permitted no-item form becomes the plain line

```text
No action items — incident fully resolved in the source PR with no residual work.
```

with no emphasis. It is the only form MD049 cannot restyle, so "write exactly" in the template
becomes true again for every PIR regardless of what the author emphasised first. The three
authoring sites (`pir.md:135`, `incident/SKILL.md:224`, `dry-run.sh:385`) change together. They
remain three sites: `dry-run.sh` writes a heredoc draft and `incident/SKILL.md` documents the
placeholder table; making `dry-run.sh` read the sentence out of the template would be the
one-site fix and is out of scope here — the suite asserts the three are byte-equal so the
duplication at least cannot drift silently.

**The gate.** Shape (b) is accepted when a line of the section matches

```text
^[_*]?No action items — incident fully resolved
```

— plain (the new template) or with a single leading `_` or `*` (the 21 shipped PIRs). The
legacy class is closed: once the template changes, no new PIR is written in an emphasised form,
so the character class is frozen — the script's comment says "do not widen (`**`) or narrow
(plain-only breaks 21 files)". The 21 shipped files are **not** edited: normalising them buys
nothing the widened anchor does not (the legacy forms must stay accepted regardless — the skill
runs in repositories this PR cannot sweep), and touching a PIR is not what triggers the gate
(the triggers are the session, the threshold and the signal scan), so leaving them alone also
keeps AC17 trivially true.

**The script.** `plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh` — in the
shipped skill directory, so it exists wherever the skill runs (the `auto-close-scan.sh`
precedent, invoked as `bash ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/ship/scripts/…`). It
owns its input, as `ship-incident-pir-gate.sh --pr` does, so no enumeration is left in prose:

- `--branch` — run `git diff --name-only --no-renames --diff-filter=d origin/main...HEAD` **on its
  own** (never inside a `|| true` pipeline): a non-zero git exit (128 when `origin/main` does not
  resolve — a repo whose default branch is `master`, or one not yet fetched) prints
  `PIR-ACTION-ITEMS: unavailable — git diff origin/main...HEAD failed (rc=128)` and exits 2,
  never "no PIR". `--no-renames` makes a renamed PIR appear as `A` at its new path (checked) and
  `D` at the old one (excluded by `d`); `--diff-filter=d` excludes only deletions. Filter the
  listing through the gate's ERE (`^knowledge-base/engineering/operations/post-mortems/.+-postmortem\.md$`),
  check every match, print one verdict line per file (`[PASS] <path>` or `[FAIL] <path>: <reason>`),
  exit 0 only if every file passes, exit 1 if any fails, and **exit 3** with
  `PIR-ACTION-ITEMS: no PIR in diff` when nothing matches — a distinct code because the ship
  caller branches on it (the "No match" arm), and an arm discriminated by scraping stdout is the
  unpinned-input class #7987 (PR #8011) removed.
- `--corpus` — the same ERE over `git ls-files` (119 today); files without the
  `## Action Items & Follow-ups` heading print `SKIP <path> (no heading — pre-template)` and do
  not count; every other file is checked; the last line is exactly
  `PIR-ACTION-ITEMS: corpus selected=S examined=N skipped=M failed=K`. One selector, one ERE, in
  one file — the arm and the gate cannot disagree because they are the same code path.
- `<path>` — check one file (the fixture arm's mode); exit 2 on a missing/unreadable path.
- Exit codes: 0 pass, 1 at least one verdict FAIL, 2 usage / unreadable path / git unavailable,
  3 no PIR in the diff (`--branch` only). `set -uo pipefail`, **not** `-e`: the row-classifier
  pipeline legitimately exits 1 on a table-free section (a `grep` with no match), and under `-e`
  that is a silent exit 1 with no `[FAIL]` line — measured on the block's own pipelines. All three
  sibling scripts use `set -uo pipefail`. Every exit 0/1 carries at least one verdict line; the
  suite asserts that dual, so an rc with no verdict line is itself a failure.
- Verdict semantics for one file: shape (a) — every table row after the `| Issue |` header and
  the `|---|` divider opens with a `#NNNN` cell — is unchanged from the block; shape (b) is the
  widened anchor above; an absent heading yields an empty section and fails through the same
  else-branch as an empty section, with the `[FAIL]` reason naming the heading so the reader
  knows what to add. `[[:space:]]` not `\s`, for the portability reason the block states. The
  template's own instructional prose (`…write exactly \`No action items …\`…`) cannot satisfy
  (b): the anchor is `^`, and a backticked sentence never starts at column 0 — pinned by a
  fixture. Known limitation, stated in the script's header rather than fixed: the section
  extraction (`/^## Action Items & Follow-ups/{f=1;next} /^## /{f=0} f`) is not fence-aware, so a
  fenced block inside the section containing a `## ` line terminates the section early
  (fail-closed; zero such files in the corpus today).
- The script must not spell the emphasised legacy sentence in its comments (AC3's absence grep
  covers the whole skill tree) and must not use a literal `/tmp` path
  (`scratch-path-collision.test.ts` enumerates `skills/*/scripts/*.sh`).

This is not a refactor: the acceptance set widens for (b), the caller checks every PIR instead of
the first, the message on an absent heading changes, and the no-PIR and git-unavailable states
get their own exit codes. Everything else is the block's semantics, and Phase 1 proves that by
extracting first and widening second.

**The caller.** `ship/SKILL.md` Phase 5.5 drops both its own selector line
(`git diff … | grep -E …`, the `:1122` neighbourhood) and the inline block, and becomes:

```bash
# The script owns the selector, the shape check and the exit codes (#7941 plan). Do NOT re-inline.
bash "${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/ship/scripts/ship-pir-action-items-gate.sh" --branch
rc=$?
case "$rc" in
  0) echo "gate: every added/modified PIR passes the action-items shape check." ;;   # paste the [PASS] lines into the PR body gate record
  1) echo "gate: [FAIL] — fix each listed PIR, then re-run." >&2 ;;                 # table rows: file the issue, record #NNNN; sentence/heading: fix the section
  3) echo "gate: no PIR in the diff — the No-match arm applies." >&2 ;;
  *) echo "SOLEUR_SHIP_PIR_GATE_HALT reason=unavailable rc=$rc" >&2 ;;              # 2 = usage/git; 127 = script missing from the plugin snapshot
esac
```

with stderr never redirected (bash's own `No such file` on 127 and the script's usage line on 2
are what make the two distinguishable in a transcript). The arms map onto the existing prose:
`0` → the Match arm's checks pass (check 1, frontmatter, reads its file list from the `[PASS]`
lines, not from a re-run selector); `1` → the fix-and-rerun instruction that replaces the
`bad`-variable sentence (`:1154`), in both headless and interactive modes; `3` → the existing "No
match" arm (author the PIR, commit, re-run — the loop ends only when the re-run prints a
per-file verdict); anything else → halt and name it. The `SOLEUR_SHIP_PIR_GATE_HALT` marker is
the `SOLEUR_<SKILL>_HALT` precedent (`incident/SKILL.md`), grep-able on a CLI and extractable on
the hosted path if the marker regex is ever extended. The surrounding prose describes the
accepted legacy forms as "an optional leading `_` or `*` marker" — it does not spell the
emphasised sentence — and never writes a backtick-wrapped `scripts/…`-relative path
(`components.test.ts` rejects that form inside SKILL.md bodies; the new paths all begin
`plugins/`). The meta-case conjunct 1 gains the three new paths.

**The suite.** `plugins/soleur/test/ship-pir-action-items-gate.test.sh` (auto-globbed by
`SUITE_GLOBS`; no `test-all.sh` edit). Sources `plugins/soleur/test/test-helpers.sh` (the Guard 3
git-env tripwire, `SKIPPED` accounting, `print_results <floor>`), exports `LC_ALL=C`, captures
every rc with the `set +e; …; rc=$?; set -e` idiom, and writes every synthesised file under
`mktemp -d` (preflight Check 10 runs it with the repo read-only). Arms:

1. *Fixtures* under `plugins/soleur/test/fixtures/ship-pir-action-items/`, named by expected
   verdict (`pass-*` → 0, `fail-*` → 1; any other prefix aborts the suite with exit 2) and
   carrying a first-line `<!-- expect: pass -->` / `<!-- expect: fail/<reason> -->` token that
   must agree with the filename — two independent declarations, so a mis-named fixture cannot
   pass. Floors are hand-measured (`pass_n >= 3`, `fail_n >= 8`), never derived from the
   directory. For `fail-*`, the suite also asserts the `[FAIL]` reason on stderr matches the
   token's reason (rows-without-issue / no-sentence / no-heading), so a broken heading regex reds
   as the wrong reason instead of hiding behind "some fail". Set:
   `pass-table-all-issued.md` (three rows; pipes-in-backticks and trailing whitespace in Action
   cells), `pass-sentence.md` (the plain form; the arm generates the `_…_` and `*…*` variants
   into the temp dir, asserts `! cmp -s` against the source and exactly one marker-prefixed line
   before running the gate, then asserts pass), `pass-subheading-inside-section.md` (a `### `
   sub-heading before the sentence — pins `/^## /` with the space),
   `fail-table-missing-issue.md` (empty Issue cell, `#NNNN` in the Action cell),
   `fail-table-tbd-placeholder.md` (`#TBD` in the Issue cell — named in the SKILL.md prose),
   `fail-header-only-table.md` (header + divider, no rows, no sentence), `fail-bullet-list.md`,
   `fail-empty-section.md`, `fail-no-heading.md`, `fail-sentence-bold.md` (`**…**`, outside the
   frozen class), `fail-instructional-prose-only.md` (the template's sentence inside backticks in
   a prose line), `fail-sentence-in-later-section.md` (empty section, then the sentence under a
   later `## ` heading). A nonexistent path must exit 2.
2. *Template parity*: extract the sentence with
   `grep -oE 'write exactly `[^`]+`' pir.md | sed -E 's/^write exactly `//; s/`$//'`, assert
   exactly one line and that it begins `No action items — ` (pins the plain form — without this,
   reverting all three sites to `_…_` stays green because the gate accepts `_`), synthesise a
   one-section PIR from it with `printf`, run `<path>` mode, assert exit 0; then assert byte-equal
   presence in the other two sites with fixed-string greps (`grep -cxF -- "$SENTENCE"
   dry-run.sh` → 1; `grep -cF -- "\`$SENTENCE\`" incident/SKILL.md` → 1). This is the arm that
   reds on the 2026-09-09 drift shape (producer moved, consumer did not).
3. *Corpus*: `--corpus`; parse the summary line with an anchored regex and treat its absence as
   red; assert `failed=0`, `selected == examined + skipped` (the selector and the loop agree),
   and `selected >= 50` (a selector-vacuity floor with room for archiving, not a corpus size
   pin). SKIP (through `SKIPPED`) only when the repo-identity marker `scripts/test-all.sh` is
   absent from the tree the suite runs in; if the marker is present and the PIR directory is
   not, that is a FAIL, not a skip. Defense-in-depth only — the ship gate examines a PIR only
   when its PR's signal scan fires, so a lint sweep never reaches it; this arm is what would have
   gone red on 2026-09-09.
4. *Branch*: a fixture repo built under the temp dir with `git_fixture_env` (from
   `plugins/soleur/test/lib/git-fixture-env.sh`) **before** `git init`; a base commit with two
   passing PIRs under the gate's directory; `git update-ref refs/remotes/origin/main HEAD`; then
   on a branch: modify PIR A (still passing), add PIR B with an empty Issue cell, rename PIR C
   with an edit, delete PIR D. Assert exit 1; `[PASS]`/`[FAIL]` lines for A, B and C's new path
   (pins every-PIR over `head -n1`, and `--no-renames`); no line for D and no exit 2 (pins
   `--diff-filter=d`). A second branch touching no PIR → exit 3 with the `no PIR in diff` line.
   A third repo with no `refs/remotes/origin/main` → exit 2 with the `unavailable` line. The
   suite never runs `--branch` against the working checkout (that is the one invocation a
   concurrent commit could flip — `cq-ac-must-not-depend-on-concurrent-sessions`).
5. *Wiring*: `ship/SKILL.md` invokes the script in command position with `--branch`, captures
   `rc=$?`, and carries the `case` labels `1)`, `3)` and `SOLEUR_SHIP_PIR_GATE_HALT` (anchored
   greps on those forms, not the bare path); the ERE `-postmortem\.md$` no longer appears
   inside the Incident-PIR section; the three new paths are present in the meta-case conjunct-1
   list.

### Thread 2 — say what the ruleset says

One site explains the failure model and cites the SSOT; the others point at it, so the fact
lives in one place rather than fifteen:

- **Phase 7 paragraph (`:2083`)** — the explaining site. "surfaces only as RED CI on `main`
  post-squash" becomes: `adr-ordinals` is a required check (`scripts/required-checks.txt`;
  applied via `infra/github/ruleset-ci-required.tf`; read the current set with `gh api
  'repos/{owner}/{repo}/rules/branches/main'`), and `main` enforces the strict up-to-date
  policy, so a sibling's colliding ADR enters the branch through the BEHIND auto-sync, the PR's
  `adr-ordinals` job re-runs red, and the required-check-failure exit below names it. Recovery
  steps are unchanged (`check-adr-ordinals.sh` → renumber → sweep → commit → push); the
  paragraph's job is now to say that the loop *will* stop here and that the renumber restarts it.
- **Phase 5.5 gate rationale (`:1435`)** — a collision cannot reach `main` (see Phase 7); the gate
  exists because catching it at PR-ready costs one commit while catching it in Phase 7 costs a
  sync plus a full CI cycle (the ~35-minute figure the settle paragraph measures), and because a
  renumber during the poll loop is the moment most likely to leave the plan/tasks sweep undone.
- **Why (`:1481`)** — keep #5945 → #5952 as the motivating event, written in the positive: the
  IaC-managed required set gained `adr-ordinals` in #6050 (2026-07-05, two days after #5945), and
  ADR-032 records the applied ruleset already carried it at reconciliation time. Replace
  "until/unless that lands" with "that landed (#6049/#6050)". Avoid "not" adjacent to "required"
  in any tense — AC7's grep is the reason.
- **`:2120`** — replace the literal "all 22 contexts" with "every `required_check` context in
  the ruleset (the count is deliberately not written here — read `scripts/required-checks.txt`)".
- **Phase 4 (`:359`)** — "tracked separately" → "tracked as #6480".
- **`plan/SKILL.md:698`** — the parenthetical becomes "(a collision surfaces as a red
  `adr-ordinals` on the PR after a Phase 7 sync — it is a required check — and `/ship` catches it
  earlier at Phase 5.5)".
- **ADR-156 ordinal note** — append one bracketed sentence: the renumber was correct; the stated
  consequence was not — `adr-ordinals` was already required when the note was written (#7941).

### Thread 3 — the battery does not run on a merge commit

```yaml
    bun-test:
      priority: 6
      glob: "*.{ts,tsx,js,jsx}"
      # A conflict-resolved `git merge origin/main` stages the whole of main's delta, so the
      # glob always matches and the full battery queues behind every sibling (measured on one
      # PR: 3861 s before any suite started, four --no-verify bypasses). What the merge adds is
      # the resolution, which the PR's CI runs on push and ship's Phase 7 loop watches; no
      # pre-push battery exists, so CI is the only net for this commit -- by design (ADR-183:
      # no local run is the merge gate). A clean merge never reached this hook anyway: only
      # pre-commit and pre-push are installed. `run:` is unchanged and still carries the
      # ADR-196 hatch.
      skip:
        - merge
      run: SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh
```

`gitleaks-staged`, `markdown-lint`, `lint-fixture-content` and the other pre-commit commands are
**not** given the skip: they are seconds long and the displaced-check list in the four bypass
commit messages is exactly them. `rebase` is deliberately not added (Non-Goals).

`ship/SKILL.md:1875` (Phase 7 step 4) gains one clause on the commit line: the `bun-test` hook
skips merge commits by configuration, so no `--no-verify` is needed; the remaining hooks still
run. Step 5's immediate `git push` is what puts the merge commit under the Phase 7 loop's watch,
and it already follows directly.

**The one path with no net, named.** After the skip, the only execution of a conflict-resolved
merge commit's code is CI on the pushed head. The settle-then-admin-merge hatch (the `:2120`
neighbourhood) bypasses the whole `required_status_checks` rule, and its step 2 reads "no
required check in a `pending` or `fail` bucket" — which an *empty* rollup on a just-pushed SHA
satisfies vacuously. This PR is already editing that paragraph (the stale context count), so
step 2 gains one clause: every required context must be **present and green on the current
SHA**, not merely absent from the fail/pending buckets. Pre-existing, but Thread 3 is what
removes the last local run over that exact commit, so it is named here rather than left
implicit.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Pin MD049 `style: underscore` corpus-wide | 9,130 hand edits (`--fix` is forbidden for MD049); still leaves the sentinel's fate to a lint rule |
| Pin MD049 `style: asterisk` corpus-wide + flip template/gate/12 PIRs to asterisk | 152 hand edits and a 12-file PIR sweep, and the coupling survives — any future style change chases three pins again |
| `<!-- markdownlint-disable-next-line MD049 -->` above the sentinel in the template | Ships a lint directive into every PIR to protect a decoration; the plain sentence needs no protection |
| Keep `_…_` in the template, widen only the gate | "Write exactly" stays false for ~40 % of PIRs; the template keeps prescribing what the linter undoes |
| Normalise the 21 shipped PIRs to the plain form | Edits the PIR corpus on this branch (fires the Incident-PIR gate's Match arm on this PR) for no gain |
| Keep the shape check inline, add a suite that greps the regex out of `SKILL.md` | The pattern #6813 and #7987 (PR #8011) each removed; a suite scraping prose tests the prose, not the runtime |
| Script at repo-root `scripts/` (the signal scan's location) | Does not exist where the skill ships — `${CLAUDE_PLUGIN_ROOT}/../../scripts/` resolves only in this monorepo |
| Pin the 16 heading-less legacy PIRs by name in the suite | Reds an unrelated PR that retrofits a heading or archives a PIR; no property needs it |
| Hook-side shorter lock wait | `tc_acquire` proceeds on expiry — a short wait is a contended run, the ADR-133 incident shape |
| Drop the `SOLEUR_ALLOW_FULL_GATE=1` hatch so the hook refuses under contention | ADR-196 rejected it: no one can commit a `.ts` file while any sibling runs the battery |
| Diff-scoped shards in the hook | No mechanical path→shard map exists; not needed for the recorded case; would be its own design |
| File an issue for Thread 3 | Fixed inline; a filing would be NET-neutral only by spending #7941's close on it |

## Files to Edit

- `plugins/soleur/skills/ship/SKILL.md`
  - `:359` — cite #6480.
  - `:1120-1150` — remove the `:1122` selector line and the inline block; insert the `--branch`
    invocation with `rc=$?` and the four-arm `case` ("The caller"); keep the surrounding
    "(a) table / (b) sentence" prose, quoting the plain sentence and describing the legacy forms
    as an optional leading marker; replace the `bad`-variable sentence at `:1154` with the
    exit-1 fix-and-rerun instruction; note that check 1 reads its file list from the `[PASS]`
    lines; map exit 3 onto the existing "No match" arm.
  - `:1152-1160` — meta-case conjunct 1: add
    `plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh`,
    `plugins/soleur/test/ship-pir-action-items-gate.test.sh`,
    `plugins/soleur/test/fixtures/ship-pir-action-items/`.
  - `:1435`, `:1481` — rationale + Why, per Thread 2.
  - `:1875` — one clause on the merge-commit skip.
  - `:2083` — the explaining paragraph, per Thread 2.
  - `:2120` — replace the literal context count; add "present and green on the current SHA" to
    the settle-then-admin-merge hatch's step 2.
- `plugins/soleur/skills/plan/SKILL.md:698` — the parenthetical.
- `plugins/soleur/skills/incident/templates/pir.md:135` — plain sentence.
- `plugins/soleur/skills/incident/SKILL.md:224` — plain sentence.
- `plugins/soleur/skills/incident/scripts/dry-run.sh:385` — plain sentence.
- `lefthook.yml:287-296` — `skip: [merge]` + comment.
- `knowledge-base/engineering/architecture/decisions/ADR-156-hook-stdin-is-model-controlled-and-untrusted.md:15-17`
  — bracketed correction.

No `description:` field of any `SKILL.md` changes (Phase 1.8 budget check not applicable).
`scripts/test-all.sh` is not edited (the suite is auto-globbed).

## Files to Create

- `plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh` — the shape check with
  `--branch` / `--corpus` / `<path>` modes (≈100 lines, `set -uo pipefail`, exit 0/1/2/3,
  executable bit like its siblings, header comment citing this plan and the two prior
  extractions, the frozen-class comment on the anchor, the fence-unaware limitation stated, no
  literal `/tmp`, no emphasised sentence in comments).
- `plugins/soleur/test/ship-pir-action-items-gate.test.sh` — five arms (≈160 lines; sources
  `test-helpers.sh`; `print_results` with a measured floor; exits non-zero on any fail or on
  `0 passed`).
- `plugins/soleur/test/fixtures/ship-pir-action-items/` — the twelve fixtures named in the
  Design, each with a first-line `expect:` token.

## Open Code-Review Overlap

- `#4133` (follow-through #4116: schema parity test for `## Observability` block) touches
  `plan/SKILL.md` — **acknowledge**: a different section of the file (Phase 2.9), unrelated to the
  one-parenthetical edit here; remains open.
- `#7942` (two `*.mutation.sh` batteries run in no gate) names `scripts/test-all.sh` —
  **acknowledge**: this plan no longer edits that file; the new suite is `*.test.sh` under the
  auto-globbed directory, the shape #7942 asks for.
- No open code-review issue names `ship/SKILL.md`, `pir.md`, `incident/SKILL.md`, `dry-run.sh`,
  `lefthook.yml` or ADR-156.

## Architecture Decision (ADR/C4)

### ADR

No new ADR and no amendment beyond ADR-156's one-sentence factual correction. Thread 1 changes a
gate's acceptance set and where its code lives, not a decision any ADR records; Thread 2 corrects
prose to match a decision ADR-032 already records; Thread 3 narrows one invoker's trigger set —
ADR-196 decision 6 ("the two git-hook invocations carry the hatch") and ADR-183 (no local run is
the merge gate) both remain true as written, and the `lefthook.yml` comment is the record of the
narrowing.

### C4 views

No C4 impact. Checked against `model.c4`, `views.c4`, `spec.c4`: the change touches no external
human actor, no external system or vendor, no container or data store, and no actor↔surface
access relationship. The Hook Engine container (`model.c4`, `hooks = container "Hook Engine"`)
describes `.claude/hooks/` and the `.openhands/` mirrors — `lefthook.yml` is a repo-local git
hook, not that container, and its description does not enumerate individual lefthook commands.
The plugin container (`model.c4`, the `plugins/soleur/` description) already covers "shared bash
primitives shipped for execution on an installed user's machine", which is what the new script
is. `c4-count-parity.test.sh` is in the scripts shard and runs in the Phase 2 exit for this diff.

## User-Brand Impact

- **If this lands broken, the user experiences:** a `/ship` run in their own repository that
  rejects a valid PIR (the new script fails a shape the old block accepted), or a pre-commit that
  silently skips the battery on an ordinary commit (a `skip:` typo that matches every commit). Both
  are visible at the moment they happen — a `[FAIL]` line naming the shape, or lefthook's
  `(skip) by condition` line — and neither reaches a user's data.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the change
  reads PIR files already in the user's own repository and a git merge-state flag; no credential,
  network call, or new data path.
- **Brand-survival threshold:** `none`

## Observability

Two execution surfaces run the same file: an operator's CLI (layer 7, `cli-stdout-artifact`)
and the hosted `/soleur:ship --headless` path (`event-ship-merge` Inngest function, layer 1
`sentry-correlation` on the run). The suite is this repository's own regression net (layer 6, the
PR `test` check's workflow-run log).

```yaml
liveness_signal:
  what: "plugins/soleur/test/ship-pir-action-items-gate.test.sh runs in the scripts shard of every CI `test` required check and every local full battery; its corpus arm asserts selected == examined + skipped, selected >= 50 and failed == 0 — layer 6 (workflow run log, PR test check)"
  cadence: "per PR (CI `test` context) and per local test-all.sh run"
  alert_target: "the PR's required `test` check goes red; ship Phase 7 required-check-failure exit names it"
  configured_in: "scripts/test-all.sh SUITE_GLOBS (plugins/soleur/test/*.test.sh is auto-globbed)"

error_reporting:
  destination: "layer 7 (cli-stdout-artifact): [PASS]/[FAIL] verdict lines and the SOLEUR_SHIP_PIR_GATE_HALT marker on the ship transcript, with the verdict lines pasted verbatim into the PR body's gate record (the customer-owned durable artifact); hosted path: layer 1 sentry-correlation on the event-ship-merge run — no Sentry call inside the script itself"
  fail_loud: "[FAIL] <path>: <reason> per file; exit 1 halts PR-ready; exit 2/127/other prints SOLEUR_SHIP_PIR_GATE_HALT reason=unavailable rc=N and halts; stderr is never redirected by the caller"

failure_modes:
  - mode: "script accepts a shape the block rejected, or rejects one it accepted"
    detection: "layer 6 — fixture arm (twelve fixtures, both directions, reason-tagged) + corpus arm (103 files pass today) + the Phase 1 step-A parity oracle"
    alert_route: "CI test check red on the PR that changes it"
  - mode: "template sentence and gate anchor drift apart again"
    detection: "layer 6 — template-parity arm synthesises a PIR from pir.md's backticked sentence, asserts the plain form, and runs the gate on it"
    alert_route: "CI test check red"
  - mode: "gate unavailable at ship time: script missing from the plugin snapshot (127), invocation drifted from the CLI (2), or origin/main unresolvable in the repo (2)"
    detection: "layer 7 — the caller's case arm prints SOLEUR_SHIP_PIR_GATE_HALT reason=unavailable rc=N with bash's own stderr preserved; branch arm pins the git-unavailable exit"
    alert_route: "the ship run halts before PR-ready and names it; hosted: the event-ship-merge run's failure"
  - mode: "bun-test skip matches ordinary commits, or the glob is dropped"
    detection: "layer 6 — AC11 parses lefthook.yml and asserts skip == [merge] on exactly bun-test and glob unchanged; the Phase 3 probe records four cases including a linked worktree"
    alert_route: "the implementer's own commit on this branch; CI does not run lefthook"

logs:
  where: "the ship transcript (Phase 5.5 output) and the PR body gate record (verdict lines); lefthook's pre-commit summary; CI job log for the scripts shard"
  retention: "PR body: lifetime of the repository; CI logs per GitHub retention (90 days); local transcripts per session"

discoverability_test:
  command: "bash plugins/soleur/test/ship-pir-action-items-gate.test.sh"
  expected_output: "`0 failed ===` and `failed=0`"
```

The suite writes only under `mktemp -d`; preflight Check 10 executes it with the repo read-only
and a tmpfs `HOME`, and the corpus pass measures 1.4 s on this host against the 15 s cap.

## Guard Contract

### Guard 1 — the PIR action-items shape check (`ship-pir-action-items-gate.sh`)

**Property.** For a PIR file, exit 0 if and only if its `## Action Items & Follow-ups` section is
either (a) a table whose every item row opens with a `#NNNN` Issue cell, or (b) a table-free
section containing, at column 0, the permitted no-item sentence with at most one leading `_` or
`*` — and no prose that merely mentions the sentence, and no content outside that section, can
satisfy (b). In `--branch` mode the property holds for every PIR the diff adds, modifies or
renames-to; a diff with no PIR is exit 3 and a git that cannot resolve `origin/main` is exit 2 —
neither is ever reported as a pass.

**Assembly.** The property quantifies over exactly one chokepoint — the script — and every caller
of it: `ship/SKILL.md` Phase 5.5 (`--branch`, the only in-skill caller) and the suite's arms. The
inputs it quantifies over are: the file selector (one ERE, shared by `--branch` and `--corpus`),
the section extraction (heading to next `## `), the row classifier (table row minus header minus
divider), the first-cell anchor, and the sentence anchor. The three authoring sites of the
sentence are the producer side; the template-parity arm binds `pir.md` to the gate and asserts the
other two byte-equal to it.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Replace the per-file verdict with `return 0` | The guard's own dispatch — every `fail-*` fixture exits 0 and the fixture arm reds on each |
| 2 | Drop the `?` from `^[_*]?` (require a marker) | `pass-sentence.md` and the template-parity arm red — the template prescribes the plain form |
| 3 | Drop the `^` anchor from the sentence regex | `fail-instructional-prose-only.md` reads green — the anchor is what separates instruction from declaration |
| 4 | Make the section extraction stop only at EOF instead of the next `## ` | `fail-sentence-in-later-section.md` (empty section, sentence under a later heading) reads green — the second-member row |
| 5 | Accept rows whose Issue cell contains `#NNNN` anywhere rather than as the cell's opening token | `fail-table-missing-issue.md` (empty Issue cell, `#NNNN` in the Action cell) reads green |
| 6 | Change `pir.md`'s "write exactly" sentence by one character | A prefix edit reds the template-parity arm through the gate; a suffix edit (the anchor is prefix-only) reds it through the three-site equality assertion — either way the arm reds while every fixture stays green: the 2026-09-09 shape |
| 7 | Convert one corpus file's sentence to bold `**…**` | Corpus arm reds (`failed=1`), and `fail-sentence-bold.md` reds hermetically — bold is outside the frozen class |
| 8 | In `--branch`, drop `--diff-filter=d` | The branch arm's deleted PIR D makes the script exit 2 (unreadable path) where the arm expects exit 1 with verdicts for A, B and C only |
| 9 | In `--branch`, drop `--no-renames` | **EQUIVALENT, measured at review** — `--name-only --diff-filter=d` lists a rename at its NEW path whether or not rename detection runs (listing byte-identical with and without the flag, incl. `-c diff.renames=copies`); the flag was dropped from the script and the branch arm's rename case pins the new-path verdict directly |
| 10 | In `--branch`, return 0 instead of 3 on an empty selection | The branch arm's no-PIR branch expects exit 3; and the caller's `case` would route "no PIR" to the Match-pass arm — the class the exit code exists to prevent |
| 11 | In `--branch`, wrap the `git diff` in `\|\| true` | The no-`origin/main` repo yields exit 3 ("no PIR") instead of exit 2 ("unavailable"); the branch arm reds |
| 12 | Change `set -uo pipefail` to `set -euo pipefail` | `pass-sentence.md` reds: the row classifier's no-match `grep` aborts the script at exit 1 with no verdict line, and the suite's "every exit carries a verdict line" dual reds on the same run |

**Harness rows.**

- *Suite mutation:* rename `fail-empty-section.md` to `pass-empty-section.md` → the suite must
  red twice over (the file exits 1 while the name demands 0, and the in-file `expect:` token now
  disagrees with the name); a suite that ignores either declaration is thereby shown vacuous.
  Second harness row: replace the corpus arm's anchored summary parse with `grep -c failed=0` →
  an empty stdout (script crashed) must still red, which the anchored form does and the count
  form does not.
- *Must-PASS non-canonical inputs:* the generated `_…_` and `*…*` variants of `pass-sentence.md`,
  and `pass-table-all-issued.md` with pipes-in-backticks and trailing whitespace in Action cells.

### Guard 2 — the `bun-test` merge-commit skip (`lefthook.yml`)

**Property.** The full battery runs on every commit that stages a `*.{ts,tsx,js,jsx}` file
except a merge commit (MERGE_HEAD present, including under a linked worktree's
`.git/worktrees/<name>/`), where it does not run at all; every other pre-commit command's trigger
set is unchanged.

**Assembly.** One stanza (`bun-test`) in one file; the skip is evaluated by lefthook itself from
the git merge state, so there is no shell to enumerate. The callers are any `git commit` in a
checkout with hooks installed, and specifically `ship/SKILL.md:1875`. AC11's YAML parse is the
standing check; the Phase 3 probe is the one-time behavioural confirmation.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Move `skip: [merge]` from the `bun-test` command to the `pre-commit:` hook level | AC11 reds: `pre-commit.commands.bun-test.skip` is no longer `["merge"]` (the parse reads the command, not the hook) |
| 2 | Change `merge` to `rebase` | AC11 reds on the exact value; the Phase 3 probe's merge case shows `PROBE-RAN` instead of `(skip) by condition` |
| 3 | Delete the `glob:` line | AC11 reds (`glob` no longer equals `*.{ts,tsx,js,jsx}`); behaviourally the battery now starts on every commit (`run:` takes no file arguments, so there is no usage guard to trip) and the Phase 3 probe's `.md`-only case shows `PROBE-RAN` |

**Harness rows.**

- *Suite mutation:* loosen AC11's assertion from `== ["merge"]` to "a `skip` key exists" → it
  must still fail row 2, which it cannot; so the exact-value form is the one that stays.
- *Must-PASS non-canonical input:* a merge commit whose conflict resolution stages only a `.md`
  file — the glob would not have matched anyway; the skip must not turn that into an error. The
  Phase 3 probe includes this case and records whichever marker lefthook prints (the skip
  condition is evaluated before the glob, so `(skip) by condition` is expected; the ordinary
  `.md`-only commit prints `(skip) no matching staged files`, and the probe asserts the exact
  marker per case rather than a bare `skip`).

## Implementation Phases

### Phase 1 — Thread 1: extract, prove parity, then widen (RED first)

1. Create the twelve fixtures (three `pass-*`, nine `fail-*`), each with its first-line `expect:` token.
2. Write the suite with all five arms; run it — RED (the script does not exist: `bash` exits 127
   on every fixture and the fixture arm counts each as a fail; the branch arm sees 127 where it
   expects 1/3/2; the wiring arm fails on the absent invocation).
3. **Step A — extract without widening.** Write the script (`set -uo pipefail`; `--branch` /
   `--corpus` / `<path>`; exit 0/1/2/3) with the block's original anchor (`^_No action items…`);
   run `--corpus`; it must report `selected=119 examined=103 skipped=16 failed=9`
   and the nine failing paths must be exactly the nine asterisk files
   (`grep -l '^\*No action items' <dir>/*.md`). This is the parity oracle: the extracted code
   reproduces the block's verdicts (94 pass / 25 fail over the 119-file selector, 16 of the 25
   being the skipped heading-less files). If any other file fails here, that is a semantic
   divergence to resolve before step B, not a regression to find at some future ship.
4. **Step B — widen.** Change the anchor to `^[_*]?…`; `--corpus` must now report `failed=0`,
   `examined=103`. Fixture, corpus and branch arms GREEN; template-parity arm still RED (the
   template still says `_…_`).
5. Edit the three authoring sites to the plain sentence; template-parity arm GREEN.
6. Mutation rows Guard 1 #2, #3, #6, #10 and #12 executed once each on the working tree and
   observed RED, then reverted (a one-time RED-side check of the suite; the PR body records the
   five observations in one line each).
7. Rewire `ship/SKILL.md` Phase 5.5 per "The caller": remove the `:1122` selector line and the
   inline block, add the `case` block, map the four arms onto the surrounding prose, replace the
   `bad`-variable sentence, note that check 1 reads paths from the `[PASS]` lines, describe the
   legacy forms as an optional marker, extend conjunct 1; wiring arm GREEN.

### Phase 2 — Thread 2: five prose sites

8. `ship/SKILL.md` `:2083` (the explaining site, cites the SSOT), then `:359`, `:1435`, `:1481`,
   `:2120`; `plan/SKILL.md:698`; ADR-156 note. History written in the positive.

### Phase 3 — Thread 3: the skip

9. `lefthook.yml` — add `skip: [merge]` with the comment; `ship/SKILL.md:1875` clause.
10. One-time probe in the scratchpad against a copy of the repo's `bun-test` stanza with `run:`
    replaced by `echo PROBE-RAN && exit 1`, five cases: conflict-resolved merge commit in a plain
    repo → commit succeeds, output carries `bun-test (skip) by condition`; the same in a linked
    worktree → same; a conflict-resolved merge commit whose resolution stages only `a.md` →
    commit succeeds, record the exact marker printed; ordinary commit staging `a.ts` → commit
    rejected, `PROBE-RAN`; ordinary commit staging only `a.md` → commit succeeds,
    `(skip) no matching staged files`. The five lines go in the PR body. (Review measured the
    skip's boundary: lefthook keys `merge` on MERGE_HEAD, so a squash-merge commit, an amended
    merge commit and a cherry-pick/revert `--continue` still run the battery — recorded in the
    stanza comment; AC11 is now a standing suite, `plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh`.)
11. `bash plugins/soleur/test/fanout-suite-scope.test.sh` and
    `bash plugins/soleur/test/hook-git-env-coverage.test.sh` — both green.

### Phase 4 — gates this PR trips on its own vocabulary

12. `bash scripts/ship-incident-pir-gate.sh --pr <N>` (body + the plan this body cites) must exit
    1 with no `INCIDENT-SIGNAL` line — **and that is the only legal exit for this PR.** The
    meta-case exemption cannot apply (Thread 2's edits fall outside Phase 5.5; conjunct 1's
    paths are untouched — the new script is a new path), and every other arm of a fired gate is
    "author a PIR" (headless) or "author / defer with a `deferred-automation` issue" (interactive
    — which this `feat-one-shot-*` branch reaches, since one-shot runs ship attended), both of
    which are fiction for a change with no real event and the second of which also breaks
    AC15/AC16. So: if `--pr` signals, reword the PR body until it does not; there is no other
    path. The scan needs BOTH halves of its regex pair (`OUTAGE_RE` and `PROD_RE` in
    `scripts/ship-incident-pir-gate.sh`) to match. The first half's terms stay inside fenced
    blocks or backticks (the scan strips both): the PIR directory name, `post-incident`,
    `outage`, `went down`, `stopped working`, `releases behind`. The second half's terms stay out
    of prose entirely: `prod`, `production`, `deployed`, `live`, `customer` — write "operator's
    own CLI", "the ruleset as applied", "tenant repos". This plan file itself scans as no-signal,
    verified at plan time and re-verified after the deepen pass.
13. The PR body also carries: `Closes #7941`; "the `infra-validate-required` tracker exists —
    #6480"; the Thread 3 decision paragraph; the `head -n1` → every-PIR fix as its own line; one
    sentence noting the signal scan's repo-root path has the same shipped-location gap (out of
    scope); the `:2120` count fix as a one-line note. No `Filed:` line.
14. `bash plugins/soleur/skills/ship/scripts/net-issue-flow.sh <PR>` → Closing 1 (#7941), Filing
    0, NET −1.

## Acceptance Criteria

- [x] **AC1** — `bash plugins/soleur/test/ship-pir-action-items-gate.test.sh` exits 0; its summary
  reads `Passed: N` / `Failed: 0` / `ALL TESTS PASSED` (amended at review: the plan quoted a
  `=== N passed, 0 failed ===` line that `print_results` never prints); its corpus line matches
  `^PIR-ACTION-ITEMS: corpus selected=[0-9]+ examined=[0-9]+ skipped=[0-9]+ failed=0$` with
  `selected == examined + skipped` and `selected >= 50`; it reports the branch arm's three
  outcomes (exit 1 with verdicts for A/B/C-new, exit 3 on the no-PIR branch, exit 2 on the
  no-`origin/main` repo).
- [x] **AC2** — `for f in plugins/soleur/test/fixtures/ship-pir-action-items/*.md; do bash plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh "$f" >/dev/null 2>&1; rc=$?; echo "$(basename "$f") rc=$rc"; done`
  (amended at /work: the original `echo "… rc=$?"` reported `basename`'s status — the
  command-substitution trap `work/SKILL.md` names — and printed `rc=0` for every fixture)
  → every `pass-*` line ends `rc=0`, every `fail-*` line ends `rc=1`;
  `bash plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh /nonexistent; echo $?` → `2`;
  every `fail-*` run prints exactly one `[FAIL] <path>: ` line on stderr whose reason matches
  the fixture's `expect:` token (the first line AFTER the frontmatter fence — moved there at
  review so every fixture is a well-formed document);
  `for f in plugins/soleur/test/fixtures/ship-pir-action-items/*.md; do awk 'NR>1 && $0=="---"{getline; print; exit}' "$f"; done | grep -c 'expect: '` → 23
  (amended at review from 12 first-line tokens: the two legacy marker forms are committed
  fixtures and nine shapes the panel found unpinned — bullets beside a table or the sentence,
  `#0`, duplicate heading, heading only inside a fence, sentence under a later h1, heading
  mentioned in prose, fenced sentence copy, a fence inside the section — gained fixtures);
  `grep -c '^set -uo pipefail$' plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh` → 1.
- [x] **AC3** — `grep -c 'write exactly `No action items — incident fully resolved in the source PR with no residual work.`' plugins/soleur/skills/incident/templates/pir.md`
  → 1; `grep -c '^No action items — incident fully resolved in the source PR with no residual work.$' plugins/soleur/skills/incident/scripts/dry-run.sh` → 1;
  `grep -c '`No action items — incident fully resolved in the source PR with no residual work.`' plugins/soleur/skills/incident/SKILL.md` → 1;
  `grep -rn '_No action items\|\*No action items' plugins/soleur/skills/` → no lines.
- [x] **AC4** — `grep -cE 'bash "\$\{CLAUDE_PLUGIN_ROOT\}/skills/ship/scripts/ship-pir-action-items-gate\.sh" --branch' plugins/soleur/skills/ship/SKILL.md` → 1
  (amended at review: ADR-179 mandates the bare anchor for customer-facing executable paths; the
  `:-plugins/soleur` form the plan copied from `auto-close-scan.sh` is an unmigrated site, #7453);
  `grep -c 'ship-pir-action-items-gate.sh' plugins/soleur/skills/ship/SKILL.md` ≥ 2 (invocation + conjunct 1);
  `awk '/^### Incident-PIR Gate/{f=1} /^### /&&!/Incident-PIR/{f=0} f' plugins/soleur/skills/ship/SKILL.md | grep -cE 'rc=\$\?|^\s*3\)|SOLEUR_SHIP_PIR_GATE_HALT'` → 8
  (amended at /work from 3 and twice at review: the marker appears in the shape-check `case` arm
  and its prose bullet, AND — since review found the signal scan's `if`/`else` collapsed exit 127
  into "no signal" — in the signal scan's own `case` and its prose bullet, both blocks capturing
  `rc=$?`; the suite's wiring arm asserts each construct individually, so this count is a
  derivation, not a contract);
  `awk '/^### Incident-PIR Gate/{f=1} /^### /&&!/Incident-PIR/{f=0} f' plugins/soleur/skills/ship/SKILL.md | grep -c 'postmortem\\.md\$'` → 0 (the selector lives in the script only);
  `grep -c "grep -qE '\^_No action items" plugins/soleur/skills/ship/SKILL.md` → 0;
  `awk '/^### Incident-PIR Gate/{f=1} /^### /&&!/Incident-PIR/{f=0} f' plugins/soleur/skills/ship/SKILL.md | grep -c 'head -n1'` → 0.
- [x] **AC5** — `bash scripts/lint-orphan-test-suites.sh` exits 0 and
  `git diff --name-only origin/main...HEAD | grep -c '^scripts/test-all.sh$'` → 0 (auto-globbed,
  not registered).
- [x] **AC6** — Phase 1 step 3's parity line (`selected=119 examined=103 skipped=16 failed=9`, nine paths
  equal to the `grep -l '^\*No action items'` set) and step 4's (`failed=0`) are quoted in the PR
  body; the second is re-runnable on the merged tree as `--corpus`.
- [x] **AC7** — `grep -n 'adr-ordinals' plugins/soleur/skills/ship/SKILL.md plugins/soleur/skills/plan/SKILL.md`
  returns no line containing `not a required`, `non-required`, `not required`, `not yet required`
  or `until/unless that lands`; the Phase 7 explaining paragraph (the `:2083` neighbourhood)
  cites `scripts/required-checks.txt`.
- [x] **AC8** — `grep -c '#6480' plugins/soleur/skills/ship/SKILL.md` ≥ 1;
  `grep -c 'tracked separately' plugins/soleur/skills/ship/SKILL.md` → 0.
- [x] **AC9** — `grep -c 'all 22 contexts' plugins/soleur/skills/ship/SKILL.md` → 0, and the
  settle-then-admin-merge hatch's step 2 (same neighbourhood) says every required context must be
  present and green on the current SHA: `grep -c 'present and green' plugins/soleur/skills/ship/SKILL.md` ≥ 1.
- [x] **AC10** — `grep -c '#7941' knowledge-base/engineering/architecture/decisions/ADR-156-hook-stdin-is-model-controlled-and-untrusted.md` → 1, inside the ordinal note.
- [x] **AC11** — `python3 -c 'import yaml,sys; d=yaml.safe_load(open("lefthook.yml")); c=d["pre-commit"]["commands"]; assert c["bun-test"]["skip"]==["merge"], c["bun-test"]; assert c["bun-test"]["glob"]=="*.{ts,tsx,js,jsx}"; assert [k for k,v in c.items() if isinstance(v,dict) and "skip" in v]==["bun-test"]; assert "skip" not in d["pre-commit"]; print("ok")'`
  prints `ok`; `git diff origin/main...HEAD -- lefthook.yml | grep -c '^[-+] *run:'` → 0
  (the `run:` line is untouched).
- [x] **AC12** — `bash plugins/soleur/test/fanout-suite-scope.test.sh` and
  `bash plugins/soleur/test/hook-git-env-coverage.test.sh` both exit 0.
- [x] **AC13** — `grep -c 'skips merge commits' plugins/soleur/skills/ship/SKILL.md` ≥ 1 in the
  Phase 7 step-4 neighbourhood (`awk '/Stage resolved files and commit the merge/,/Push and re-verify/'`).
- [x] **AC14** — `bash scripts/markdown-lint.sh --repo-sweep` exits 0 (the edited skill files,
  template and ADR are in scope; the fixtures are not).
- [x] **AC15** — `bash scripts/ship-incident-pir-gate.sh --pr <N>; echo $?` → `1`, with no
  `INCIDENT-SIGNAL` line on stdout; the PR body carries `Closes #7941`, the `#6480` statement,
  the Thread 3 decision paragraph, the five Phase 3 probe lines, the `[PASS]`-line convention
  note, and no `Filed:` line.
- [x] **AC16** — `bash plugins/soleur/skills/ship/scripts/net-issue-flow.sh <PR>` → `Net: -1`
  (or `0`), exit 0.
- [x] **AC17** — `! git diff --name-only origin/main...HEAD | grep -q '^knowledge-base/engineering/operations/'`
  (no PIR is modified, so the Incident-PIR gate's Match arm has nothing to examine on this branch).

## Test Scenarios

- Fixture arm: twelve fixtures, both verdict directions, reason-tagged, three sentence variants
  with instrument checks, exit 2 on a missing path, unknown prefix aborts the suite.
- Template parity: sentence extracted from `pir.md` (cardinality 1, plain form asserted); a PIR
  synthesised from it passes; `incident/SKILL.md` and `dry-run.sh` carry it byte-equal.
- Corpus: `--corpus` summary parsed by anchored regex; `failed=0`, `selected == examined +
  skipped`, `selected >= 50`; SKIP only outside this repository; step A's `failed=9` parity
  reading recorded once.
- Branch: fixture repo (A modified, B unbacked, C renamed, D deleted) → exit 1 with verdicts for
  A, B, C-new only; no-PIR branch → exit 3; no-`origin/main` repo → exit 2.
- Wiring: the `--branch` invocation, `rc=$?`, the `3)` arm and the `SOLEUR_SHIP_PIR_GATE_HALT`
  marker present in `ship/SKILL.md`; the ERE absent from the Incident-PIR section; the three new
  paths in conjunct 1.
- Hook probe (Phase 3): merge / merge-in-worktree / merge-md-only / ordinary-ts / ordinary-md.
- Existing guards: `fanout-suite-scope`, `hook-git-env-coverage`, `lint-orphan-test-suites`,
  `markdown-lint --repo-sweep`, `c4-count-parity` (scripts shard) — all green.

## Non-Goals

- Sweeping the 21 shipped PIRs to the plain form (see Alternatives).
- Retrofitting the heading onto the 16 pre-template PIRs; `--corpus` skips them by name of the
  condition, not by a pinned list.
- Making `dry-run.sh` read the sentence from the template (one-site fix; noted, not done).
- Relocating the signal scan (`scripts/ship-incident-pir-gate.sh`) into the shipped skill
  directory — same gap, separate change; named in the PR body.
- Binding the producer-side filename convention (`<slug>-postmortem.md` in `incident/SKILL.md`
  and `dry-run.sh`) to the gate's ERE: after this plan the ERE has one consumer, but a future
  rename of the suffix on the incident side would make new PIRs invisible to the gate. Named as
  a residual; not guarded here.
- Making the section extraction fence-aware (a `## ` line inside a fenced block ends the section
  early — fail-closed, zero corpus instances).
- Default-branch detection for `origin/main` in the ship skill (50 hard-coded occurrences today);
  the script's exit 2 makes the failure visible where the old block was silent.
- Adding `rebase` to the skip list: `ship` syncs by merge, `work` Phase 0.5's rebase precedes
  implementation, and no bypass on a rebase commit is on record. Re-evaluate on the first one.
- Promoting `infra-validate-required` (#6480) — a ruleset change with its own issue.
- Changing `TC_LOCK_TIMEOUT`, the refusal, or the shard map.
- Touching anything under `knowledge-base/project/` for lint reasons (excluded by design, #7927).

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| The extracted script diverges from the block for some shipped PIR | Phase 1 step A: extract with the old anchor first and reproduce the block's verdict set exactly (failed=9, the nine asterisk files) before widening |
| An operator-repo PIR carries the sentence with trailing text or a different dash | Out of scope by the same rule as today (the block was already anchored on the exact prefix); the widened anchor only adds the marker class |
| `skip: [merge]` behaves differently on an older lefthook | Verified on 2.1.6 (the installed binary) in a plain repo and a linked worktree; the Phase 3 probe runs against the binary that will execute the hook |
| The Incident-PIR signal scan fires on this PR's own prose | Phase 4 step 12: vocabulary discipline + the `--pr` scan before PR-ready; the meta-case is known not to apply |
| A future reader restores the inline block "for convenience" | The Phase 5.5 comment mirrors the signal scan's "do NOT re-inline" note and cites this plan |
| A future reader "tidies" `[_*]?` to plain-only or widens it | The frozen-class comment on the anchor names both directions and the 21-file consequence |
| The caller treats exit 3 ("no PIR") as a pass, or a git failure as "no PIR" | Distinct exit codes, the `case` block in SKILL.md, the branch arm pinning both, and Guard 1 rows 10-11 |
| The corpus floor reds an unrelated PR that archives PIRs | Floor is `selected >= 50` against 119 with a relative `selected == examined + skipped` check, not a count pin |
| A bad conflict resolution merges through the admin hatch with an empty rollup | Hatch step 2 gains "present and green on the current SHA" (same paragraph as the `:2120` edit) |

## References & Research

- #7941 (the issue), #6480 (`infra-validate-required` tracker), #6049/#6050 (adr-ordinals
  reconciliation), #7927/#7955 (the markdownlint sweep), #6813 and #7987/PR #8011 (prior gate extractions),
  #5945/#5952 (the motivating ADR collision), #7553/PR #7616/ADR-196 (the hatch), ADR-133 (the lock),
  ADR-183 (full suite at ship), ADR-032 (ruleset as IaC).
- `node_modules/markdownlint-cli/README.md:112` — single-config lookup.
- lefthook `skip` conditions: verified by probe on the installed 2.1.6 (Premise Validation).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (skill prose, a git-hook
stanza, a shipped bash gate and its suite).

## Plan Review — consolidated (2026-09-11)

Panel: DHH, Kieran, code-simplicity (per-mechanism), CTO (devex), plus the Step 4.5 advisor
consult. Agreements applied as Mechanical: the script ships in
`plugins/soleur/skills/ship/scripts/` and owns its input (`--branch`/`--corpus`); the corpus
count is 119/103/16 by the gate's own selector and no count literal remains in an AC; the pinned
16-name legacy list, the SELFTEST row, the distinct no-heading branch and the ADR-196 note are
cut; extract-then-widen with a parity oracle; Guard 1 row 4 and row 6, Guard 2 rows 1/3/4 and the
`(skip) by condition` marker corrected; AC3's absence grep reconciled with the SKILL.md prose
instruction; AC15 uses `--pr`; the linked-worktree probe case added; the lefthook comment states
there is no pre-push net; `:2120` kept as the same defect class. Taste findings (recorded in
`specs/<branch>/decision-challenges.md`): keep vs drop the one-clause step-4 note (kept as a
clause); the three authoring sites left as three (named in Non-Goals).
