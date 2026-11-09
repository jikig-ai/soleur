---
title: "fix: classify and convert the remaining plain --name-only changed-path readers (D7 remainder)"
type: fix
date: 2026-11-09
slug: fix-convert-remaining-changed-path-readers
branch: feat-one-shot-changed-path-readers-remainder
issue: none
closes: none
lane: cross-domain
requires_cpo_signoff: false
---

## Overview

Finish the changed-path reader arc (D7, "brief constraints never reach ship"). PR #12357 converted the `^`-anchored readers in `.github/workflows`, five hooks/scripts and the preflight/ship/review prose to the NUL-delimited, rename-free, submodule-honest form and left about twenty readers on a plain `--name-only` by CTO ruling (Fork 7h: extend the sentinel only after a separate pass over them). This PR is that pass: classify every remaining site first (does a match ALLOW, SELECT or BLOCK; exact-line, prefix or unanchored; which hazard actually bites), convert only the sites that fail open, record a reason for every site left alone, and extend the census sentinel so the remainder cannot regrow silently.

Net issue flow: `Filed: none`. No work-target issue exists (the draft PR #12494 is the only vehicle), so the PR body uses `Ref #12246`, `Ref #12332`, `Ref #6480` and never `Closes`. If a size-driven drop under Fork F6 forces a real deferral, exactly ONE consolidated tracker (`--label meta/machinery`) is filed and declared as `Filed: #N`; otherwise nothing is filed.

## Research Insights

### Premise Validation (Phase 0.6)

- #12246 (arc tracker) MERGED; #12332 CLOSED by PR #12357 (MERGED 2026-11-08); #12326 MERGED; #6480 OPEN and stays out of scope (INFRA_RE untouched). No open issue names this work: the draft PR #12494 is the only vehicle, so there is no `Closes #N` and nothing to close at merge.
- Collision pre-check: no open PR names #12246 or #12332. The two `test-all.sh` processes it reported belong to unrelated worktrees (founder-acceptance, S4 evidence), not duplicate work.
- The brief's list was checked against `origin/main` code and drifted in four places: (1) `preflight:132` already calls the helper, only `preflight:304` is a plain reader and it is NO-CONVERT; (2) ship sites `1299`, `1667` and `2964`, plus three `skills/ship/references/*.md` files, are real plain readers the header list omits; (3) the `ci.yml --raw` classifiers FAIL CLOSED (a rename row or a C-quoted path falls to "run"), so they leave the remainder as justified NO-CONVERT; (4) the header names `postmerge` and `work` as unconverted prose, but only `work:1139/1412` are fail-open; the `postmerge` sites read `gh pr diff`, a different data source the helper cannot take.
- Four fail-open sites exist OUTSIDE the header list and inside the sentinel's own exemption table or neighbours: `pr-quality-guards.yml` worktree-marker reader (its exemption reason, "fixed ASCII prefix", is wrong: git C-quotes the whole name), the two `ci.yml` trigger-canary / trigger-propagation reads (`2>/dev/null || true`), `lint-migration-fk-preconditions.sh`, `rename-guard.sh`, `tier1-scan.ts`, `pr-overlap-preflight.sh`.
- Skill body ceilings (`plugins/soleur/test/skill-body-budget.json`, whole-file bytes, only ratchet down) leave almost no room: review 20 B, ship 18 B, one-shot 9 B, qa 11 B, postmerge 1 B, work 56 B. `preflight`, `test-browser`, `merge-pr` are unbudgeted. A SKILL.md conversion must therefore be byte-neutral or net-negative; reference files and agent bodies cost nothing.
- ADR corpus: no ADR decides the helper's shape (ADR-242 mentions the readers only in passing); this plan makes no architectural decision, so no ADR/C4 deliverable.

### Property List (Phase 0.6b)

1. A reader whose match ALLOWS (satisfies a required item, unlocks a bypass, exempts a gate) cannot be satisfied by a path the PR did not touch or by a fragment of a newline name.
2. A reader whose match SELECTS or BLOCKS lists every path the PR touched, including the OLD path of a rename and a hidden gitlink, as exact bytes.
3. A git or API failure in such a reader reads as "unknown, run or refuse", never "nothing changed".
4. The remaining plain readers are enumerated with a reason, so the remainder cannot regrow silently.

### Cut List (Phase 0.6b)

- A new shared library for hooks/workflows -> property 2/3 -> the inline `-z --no-renames --ignore-submodules=none ... | tr` form already used by the 12 converted sites; hooks and workflows must not depend on a plugin script being present in the checkout they judge.
- Converting advisory readers (`lefthook.yml:486`, `skill-security-scan.sh:64`, `postmerge:322`) -> no property (a miss only changes a stderr line) -> nothing.
- Converting `--diff-filter=U` conflict listings, `ls-tree` readers, and `--name-status` readers whose status letters are load-bearing -> not changed-path readers.
- Moving `INFRA_RE` or its twins; fixing the ship Phase 7 queue-wait gap -> out of scope by standing CTO rulings.

### Site classification (read-only fan-out, four classifiers, 2026-11-09)

Hazards: H1 C-quoted name (non-ASCII/tab/quote/backslash) defeats `^`/exact-line/`$` matches; H2 rename-away invisible; H3 hidden gitlink; H4 git/API failure read as empty; N newline name forges a line for an ALLOW. Consumer: ALLOW / SELECT / BLOCK / ADVISORY. Verdict C = convert, CC = convert-cheap (one-line flag change), NC = no convert.

| # | Site | Consumer / match | Bites | Open? | Verdict | Existing suite |
|---|---|---|---|---|---|---|
| 1 | `scripts/pre-push-ratchet-lane.sh:358,360` (+`:256` quiet diff, `:417/421` name-status) | SELECT, exact-line + suite loop | H1 H2 (H3 at 256) | under-tests | C inline; `--ignore-submodules=none` at 256 | `scripts/pre-push-ratchet-lane.test.sh` |
| 2 | `.claude/hooks/pre-merge-rebase.sh:818-819` | ALLOW (disjoint skip), exact-line vs exact-line, both sides quoted alike | H3 only | narrow | CC append `--ignore-submodules=none` | `pre-merge-rebase.test.sh` T-DJ1..3 (git stub matches ` --name-only ` without `--diff-filter`) |
| 2b | `pre-merge-rebase.sh:532-533` | ALLOW via `git show` per name | none (quoted name fails `git show`, closed); `-z` would CREATE fragment lines | closed | NC (conversion would open it) | same |
| 2c | `pre-merge-rebase.sh:854` | ADVISORY (deny message) | none | no effect | NC | same |
| 3 | `scripts/hooks/pre-push:43` | ALLOW (empty diff skips lane), emptiness only | H3 | narrow | CC append flag | none behavioural |
| 4 | `plugins/soleur/scripts/affected-tests.sh:685,690,703,705` (`-M`, `quotePath=false`) | SELECT; all-inert exits 0 `NO_TESTS_AFFECTED` | H2 (`git mv src/x.ts docs/x.md` reads all-inert), H3, residual H1 | OPEN | C: `-M`->`--no-renames`, `--ignore-submodules=none`; `-z` leg is structural (fork F3) | `affected-tests.test.sh` rename rows ~L1918-1930 |
| 5 | `skills/ship/scripts/pr-overlap-preflight.sh:223,236,321` | BLOCK, `jq IN()` vs raw API names | H1 (own quoted name never equals API raw name -> overlap missed) | OPEN | C structural (`-z` -> jq `split("\u0000")`) | `pr-overlap-preflight.test.sh` (mutation `norenames` ~L1259, text pin ~L1118) |
| 6 | `skills/archive-kb/scripts/archive-kb.sh:150` | SELECT, `case` on `knowledge-base/...`; `AM` drops `R` | H1 H2 H4 | under-archives (ship-kb-archive-gate backstops) | CC: `-z --no-renames --name-status` + `read -d ''` pairs | `archive-kb-partial-run.test.sh` |
| 7 | `plugins/soleur/scripts/merge-effect-class.sh:103` (usage example only) | doc text | H3; `tr` form makes fragments | doc | CC edit the example to the helper/inline form + newline note | `merge-effect-class*.test.sh` |
| 8 | `lefthook.yml:486`, `skill-security-scan.sh:64`, `pre-merge-rebase.sh:854` | ADVISORY | - | no effect | NC | - |
| 9 | `scripts/lint-credential-path-literals.py:328`, `lint-infra-no-human-steps.py:502`, `lint-shell-trace-credential-refusal.py:2487` | SELECT (`--changed`, CI at ci.yml 709/711/737), `endswith`/`startswith` | H1 (quoted name silently skipped) | OPEN | C: argv `-z --no-renames --ignore-submodules=none`, `.split("\0")`; shell-trace also `ls-files` | `scripts/lint-*.test.sh` per lint |
| 10 | `scripts/lint-skill-body-budget.py:169` | ALLOW `changed == {BUDGET_REL}` | extra quoted name only makes set unequal | closed | NC | - |
| 11 | `apps/web-platform/scripts/lint-migration-fk-preconditions.sh:114` | SELECT, `\|\| true`, `AM` drops `R` | H4 H2 | OPEN | C: capture + exit 2, `--no-renames` | `lint-migration-fk-preconditions.test.sh` (no `--from-pr-diff` row) |
| 12 | `lint-migration-api-grants.sh:103`, `lint-migration-immutability.sh:180` | SELECT/BLOCK; quoted name exits 2 (false red) / already `-z` | - / H3 | closed | NC (immutability: optional flag) | - |
| 13 | `apps/web-platform/scripts/allowlist-diff.sh:46` | ALLOW (no match skips widening gate), `grep -Fxq` in `< <()` | H4 | OPEN | C: capture into var, `\|\| exit 2` (pathspec form) | none dedicated (`secret-scan-smoke-gate.test.sh` pins presence) |
| 14 | `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh:175` | SELECT/BLOCK, unanchored | H4 H2 | OPEN | C: pipefail capture, failure sets `capture_trigger=1`; keep `SDK_GATE_CHANGED_FILES` override precedence | `sdk-bump-sandbox-gate.test.sh` (always injects override: git arm unexercised) |
| 15 | `apps/web-platform/scripts/real-sdk-ask-probe.sh:173` | SELECT, `case`+prefix | H1 narrow | narrow | CC `-z ... \| tr` | `real-sdk-ask-probe.test.sh` |
| 16 | `apps/web-platform/scripts/rename-guard.sh:100` | BLOCK, anchored `$` regex on destination | H1 H4 (`\|\| true`) | OPEN | C structural (`log -z --name-status` triples, newline name refuse) | `scripts/rename-guard.test.sh` |
| 17 | `plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts:251` | SELECT, anchored regex, failure -> `[]` | H1 H4 | OPEN | CC `-z` + exit 2 | frontend-anti-slop tests |
| 18 | `.github/scripts/check-pr-body-vs-diff.sh:19` | BLOCK-ish heuristic (`\|\| echo ""` then warn and exit 0) | H4, 300-file cap; H2 gives false RED only | OPEN on gh failure | CC files API `--paginate` + `previous_filename`, exit-status gated | `.github/scripts/test/test-check-pr-body-vs-diff.sh` (derivation untested) |
| 19 | `.github/scripts/check-sweep-completeness.sh:73-81` | ALLOW `grep -Fxq` on API filenames | N (newline/CR name forges a dependent line) | OPEN on hostile name | CC jq sentinel for `[\r\n]` -> fail closed | `.github/scripts/test/test-check-sweep-completeness.sh` (derivation untested) |
| 20 | `.github/workflows/web-platform-release.yml:2224` | SELECT (live-verify), anchored patterns, compare API, no `--paginate`, 300 cap | H2 + cap | under-runs | CC `previous_filename` + cap -> triggered | `apps/web-platform/test/live-verify/trigger.test.ts` re-implements matcher; step not executed |
| 21 | `.github/workflows/registry-host-replace-dispatch.yml:287` | SELECT/ALLOW gating a destructive host replace | H2 | `deliver=false` for a renamed render input | CC `.files[]? \| .filename, (.previous_filename // empty)` | `registry-host-replace-dispatch-verdict.test.sh` (`gcompare` fixture gets `previous_filename`) |
| 22 | `.github/workflows/fix-constraints-stage-a.yml:183` + `constraint-scaffold/references/fix-constraints-stage-a.template:160` | write-set scope allowlist | H2 (rename out of scope INTO scope unseen), H3 | corner | CC add `--no-renames --ignore-submodules=none`; refresh `.emitted.sha256` pin | `emit-fix-constraints.test.sh`, `refresh-stage-a.test.sh` |
| 23 | `ci.yml` `--raw` e2e / shard-totality classifiers (2177, 2713) | SELECT; rename row / quoted path falls to "run" | none | CLOSED | NC; retire from the header remainder | `ci-classify-step-exec.test.sh` |
| 24 | `ci.yml` trigger-canary, trigger-propagation (exempt rows) | SELECT unanchored, `2>/dev/null \|\| true` | H4 | git failure skips paid canary | CC pipefail capture, failure -> run | sentinel exemption rows removed |
| 25 | `pr-quality-guards.yml:493` (`gh pr diff --name-only \| grep '^\.claude/worktrees/' \|\| true`) | BLOCK | H1 (non-ASCII under the marker), H4, 300 cap | OPEN | C files API, exit-status gated; fix the stale exemption reason | `pr-quality-guards` suites + sentinel |
| 26 | sentinel exemptions kept: `reusable-release`, `web-platform-release:595`, `tenant-integration`, `pr-quality-guards` AMRT rows, `skill-security-scan-postmerge` | emptiness / self-guarded | - | closed | NC, reasons re-verified | sentinel |
| P1 | `skills/ship/references/settle-then-admin-merge.md:30` | ALLOW toward admin merge, allowlist | H2 H3 | OPEN, privileged | C (highest value) | prose pins |
| P2 | `ship/SKILL.md:897` (`LEDGER_TOUCHED`, unanchored substring `.` unescaped) | ALLOW exemption | planted `x/.../expenses.md.bak` | OPEN | C (`unknown` must NOT exempt) | pins |
| P3 | `ship/SKILL.md:1299` PIR meta-case exemption | ALLOW containment | H2 H3 H4 (empty vacuously satisfies "every path") | OPEN | C | pins |
| P4 | `ship/SKILL.md:1667` PLAN_REFS | SELECT; skip -> `Closes` closes early | H1 H4 | OPEN | C | pins |
| P5 | `ship/SKILL.md:843,853` CMO gates | SELECT (hook backstops with `-z`) | H2 H4 | open, backstopped | CC | pins |
| P6 | `ship/SKILL.md:344,2665,2938,2964` (`HASH..HEAD`, `--diff-filter=A/AM`) | SELECT (`AM` drops `R`) | H2 H4 | open | CC; needs range-pin loosening | pins |
| P7 | `one-shot/SKILL.md:179` scope check | ALLOW containment, incl. `<base-sha>..HEAD` fallback | H2 H3 H4 | OPEN | C | new pin rows |
| P8 | `work/SKILL.md:1412` + `qa/SKILL.md:87` structural-UI visual gate | SELECT; H4 -> silent skip | H2 H4 | open, CI e2e backstops | C, same predicate; work cites qa to save bytes | new pin rows |
| P9 | `work/SKILL.md:1139` per-suite fallback recipe | SELECT | H1 H2 H4 | open | CC | new pin rows |
| P10 | refs: `ship/references/counsel-review-clo-attestation.md:10` (`^` regex, `main...HEAD`), `adr-ordinal-collision.md:33`, `review/references/risk-tier-and-fix-rounds.md:58` | ALLOW / SELECT | H1 H2 H4 | open | C / CC / CC | none |
| P11 | agents `semgrep-sast.md:12`, `observability-coverage-reviewer.md:29` | SELECT (H4 -> "0 findings across 0 files") | H1 H4 | open | CC; `${CLAUDE_PLUGIN_ROOT}` substitution inside agent bodies must be verified first | none |
| P12 | `review/SKILL.md:393` item 17 (informational) | ADVISORY | H1 H2 | info line only | NC (optional) | - |
| P13 | NC prose: `review:118`, `preflight:304`, `ship:159,318,2034,2042,2134`, `postmerge:215,217,322,399,486,556` (`gh pr diff`; 217 pinned by `deploy-arm.test.sh:676`), `work:197,200`, lesson/example text (`code-quality-analyst`, `git-history-analyzer`, compound/deepen-plan/review lessons) | - | - | closed/advisory | NC | - |

Extra no-convert sites found by the census (no action): `check-backstop-revision.sh`, `ci-oracle-review.sh` (optional flag only), `lint-art30-reverification.sh`, `prepush-secret-scan.sh`, `weakness-miner.sh`, `ci-battery-gate-replay.sh`, `watch-registration-narrowing-9564.sh`, `sync-pr-behind.sh`, `resolve-regenerable-conflicts.sh`, `git-commit-secret-scan.sh:159`, `tweet-eligibility.sh:78` (gh API; operator approves the draft), `parse-override.sh:42` (closed), `founder-check.py:972` (already `-z`).

### Institutional learnings applied

- `2026-11-08-converting-changed-path-readers-...` (the arc learning): C-quoting was an accidental newline defence; an ALLOW reader must match over the NUL stream or refuse a newline name; skill prose callers are the code under test (pin spelling AND failure arm); sentinel failures must fail via process substitution, not a `| while` subshell; a git-census sandbox must be a git repo.
- `2026-11-07-fixing-the-source-of-a-path-list-left-its-classifier-...`: enumerate every CONSUMER of a converted list; `cmd | grep -c || true` turns a git failure into `0`.
- `2026-10-14-c-quoted-names-evade-extension-anchored-list-filters`: `core.quotePath=false` fixes only >= 0x80; fixture `x<TAB>y.test.sh`.
- `2026-10-01-a-grep-q-in-a-pipefail-chain...`: capture into a variable, then match.
- `2026-09-09-the-linter-rewrote-the-fixtures...`: `pulls/N/files` caps at 300 (HTTP 406) for the diff endpoint; the files API paginates to 3000; test the failing direction of every `gh api` capture.
- `2026-10-02-a-subset-replay-proof...`: compare `(filename, status, previous_filename)` multisets, not subsets.
- `2026-10-19-a-fail-closed-gates-tests-asserted-the-safe-verdict...`: each converted reader needs rows asserting the specific path, a deletion row and a type-change row; mutate the anchors.
- `2026-10-31-accept-row-reasons-must-enumerate-real-tree-read-arms`: re-derive accept-row reasons by grepping the suite, not by copying a sibling.
- `2026-04-03-git-env-var-leak-resolve-git-root-test`: unset every `GIT_*` in hook/lint fixtures (use `git_fixture_env`).
- Host `grep` may be ugrep (`2026-05-29-ugrep-as-grep-breaks-grep-z...`): CI runs GNU grep; any local `grep -z` smoke needs a non-zero-count sanity check.

### CTO rulings applied to the table above (2026-11-09; full text in `knowledge-base/project/specs/feat-one-shot-changed-path-readers-remainder/decision-challenges.md`)

Verdict changes from the table: row 6 (`archive-kb.sh`) CC -> NC (backstop `ship-kb-archive-gate.sh` already reads `diff --name-status -z --diff-filter=AMRCT`; the implementer re-reads it and the row reverts to C if the same input defeats it), row 7 (`merge-effect-class.sh` usage text) CC -> NC, row 18 (`check-pr-body-vs-diff.sh`) CC -> NC ("advisory by design: warns and exits 0 on a gh failure"), P5 (ship CMO gates; hook `ship-cmo-content-gate.sh` is on PINNED_Z) CC -> NC, P6 (ship `HASH..HEAD` readers; CI migration/workflow lints backstop) CC -> NC, P8 (work/qa structural-UI gate; CI `e2e` backstop) C -> NC, P9 (work per-suite fallback recipe) CC -> NC. Rows 24, 25 and 19 stay IN although the brief's list did not name them. Final convert set: 25 site groups - rows 1, 2, 3, 4, 5, 9, 11, 13, 14, 15, 16, 17, 19, 20, 21, 22, 24, 25 (code and workflows) and P1, P2, P3, P4, P7, P10, P11 (prose and agents).

## Research Reconciliation - Spec vs. Codebase

| Brief / header claim | Reality (checked 2026-11-09) | Plan response |
|---|---|---|
| "`ci.yml` `--raw` classifiers" are a fail-open remainder | They fail CLOSED: a rename row (`R100\told\tnew`) misses the row grammar and a C-quoted path falls to `emit true` (run); covered by `ci-classify-step-exec.test.sh` | NC; removed from the header remainder with that reason |
| `preflight:132/304` unconverted | `:132` already calls the helper; `:304` is `--name-status` with status letters load-bearing | NC both; recorded in EXEMPT_PROSE |
| Skill-prose remainder is "review (391), preflight, ship, one-shot, postmerge, work, qa" | Lines drifted (review is 393); ship has more sites than named (`1299`, `1667`, `2964`) and three `skills/ship/references/*.md` plus `review/references/risk-tier-and-fix-rounds.md` carry real instructions; `postmerge` reads `gh pr diff` (different source; `:217` text is pinned by `deploy-arm.test.sh`) | Convert ship 897/1299/1667, one-shot 179, the four refs, two agents; everything else an EXEMPT_PROSE row |
| Compare-API readers "destination-only, rename-away invisible" | Confirmed for `web-platform-release.yml` (also no `--paginate`, 300 cap) and `registry-host-replace-dispatch.yml` (cap already handled per-blob there) | Convert both inline with `previous_filename` |
| `fix-constraints-stage-a.yml` is "-z without --no-renames" | Confirmed; it is a write-set scope allowlist, so the hole is a rename from out-of-scope INTO scope | CC flag change on workflow + template, refresh `.emitted.sha256` |
| Header lists ~20 sites | The census found ~35 distinct sites; fail-open sites sit outside the list (rows 11, 16, 17, 24, 25 and `pr-overlap-preflight.sh`) | Include per CTO F1 |
| The sentinel exemption reason for `pr-quality-guards.yml` `gh pr diff --name-only` says "fixed ASCII prefix, safe" | Wrong: git C-quotes the WHOLE name, so `.claude/worktrees/<non-ASCII>` becomes `".claude/...` and misses `^\.claude/worktrees/`; `\|\| true` also masks a gh failure / the 300-file 406 | Convert (row 25), delete the exemption row |
| Brief: the helper is reused "for skill prose; stay inline in hooks and workflows" | Matches the helper header; `plugins/soleur/test/changed-path-readers.test.sh` pins the bare `${CLAUDE_PLUGIN_ROOT}` token (no `:-`) - the arc learning's older `:-` spelling is superseded | Use the bare token everywhere |

## User-Brand Impact

**If this lands broken, the user experiences:** a pre-push lane, a ship gate or a CI check that falsely reds (a converted reader refuses a name it used to accept) and blocks their own merge, or - the worse direction - a converted reader that still reads a failed `git diff` as "nothing changed", so a secret-scan allowlist widening, an admin-merge eligibility check or a destructive registry-host replace is judged without the change it was meant to see.

**If this leaks, the user's workflow is exposed via:** an ALLOW-class reader satisfied by a path the PR did not touch (an expenses-ledger substring, a forged line from a newline-named directory) or a SELECT/BLOCK reader that misses a rename-away or a hidden gitlink, so a gated change ships without its gate. No user data, credentials or payment surface is touched; the exposure is the integrity of the repository's own merge gates.

**Brand-survival threshold:** aggregate pattern

The PR edits paths on the secret-scanning floor (`allowlist-diff.sh`, `rename-guard.sh`, `pr-quality-guards.yml` are CODEOWNERS-listed) but only to make them stricter and with a RED-first row each. No single-user incident is reachable from a mis-conversion (worst case is a false red or an unchanged fail-open), hence no CPO sign-off; `soleur:engineering:review:user-impact-reviewer` is not required.

## Non-Goals

- `INFRA_RE` and its twins; the wider `infra-validation.yml` trigger set (#6480).
- `test-all.sh` / `battery-refusal-wait.sh` beyond the `--ignore-submodules=none` already appended; the ship Phase 7 queue-wait gap.
- Advisory readers, `--diff-filter=U` conflict listings, `ls-tree` readers, `--name-status` readers whose status letters are load-bearing, lesson/example text in prose (recorded as exemption rows, not converted).
- `apps/web-platform/test/claude-pin-lockstep.test.ts` and the stale-accept row for `real-sdk-ask-probe-workflow.test.sh`.
- The post-PR queue (queue-wait evidence, CI download fragility, CVE follow-ups, merge-queue re-measure, Better Stack incidents, leftovers).

## Implementation Phases

Conversion recipes (each already proven by a converted sibling):

- **Hook / script (SELECT, BLOCK, emptiness):** `X="$(set -o pipefail; git -C "$ROOT" diff -z --no-renames --ignore-submodules=none --name-only "$BASE" HEAD | tr '\0' '\n')" || <fail toward running/refusing>`. A newline-named path becomes fragment lines; harmless for SELECT (fragments only add matches), forbidden for an ALLOW reader that looks names up one by one (use the NUL stream or refuse).
- **Pathspec emptiness gates:** keep the pathspec and append `--ignore-submodules=none`; no `-z` needed when only emptiness is tested.
- **Python:** argv gains `"-z", "--no-renames", "--ignore-submodules=none"`, `.split("\0")` with the empty-element filter; a non-zero return stays `sys.exit(2)` (never `[]`).
- **Compare/files API:** `jq -r '.files[] | .filename, (.previous_filename // empty)'` (compare) or `gh api --paginate .../pulls/N/files --jq '.[] | .filename, (.previous_filename // empty)'`; capture gated on exit status; failure or empty-on-error reads as "run"; count >= 300 (compare) or >= 3000 (files) reads as triggered; ALLOW readers add a jq sentinel for `[\r\n]` names and fail closed.
- **Skill prose:** `var=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" --match 'ERE' origin/main...HEAD) || { [ $? -eq 1 ] || var=unknown; }` at column 0, lowercase variable, plus one sentence saying what `unknown` means for THIS gate (fires the gate; never exempts).

Each conversion is RED-first (`cq-write-failing-tests-before`): the suite row is committed failing against the unconverted site, then the site is converted. Fix rounds: two targeted rounds plus one verification pass.

### Phase 1 - Wave 1: hooks, scripts, lints, app scripts

1.1 `scripts/pre-push-ratchet-lane.sh` - the two `git diff --name-only` reads into `$BRANCH_ALL` (`$BASE HEAD`) and `$MAIN_CHANGES` (`$BASE origin/main`) become the pipefail `-z ... | tr` form with the existing `|| abort - "branch-diff-failed"`; the early-PASS `git diff --quiet "$BASE" HEAD` gains `--ignore-submodules=none`; the `--name-status` baseline checks gain `--no-renames`. Suite `scripts/pre-push-ratchet-lane.test.sh`: rename-away from a `KB_CONSUMERS_INPUTS` file (e.g. `ci.yml`) fires the conditional member; a suite file with a tab/non-ASCII name is still selected; a gitlink-only branch does not early-PASS. While here, verify whether `KB_CONSUMERS_INPUTS` entries like `knowledge-base/` or `glob:...` can never match the exact-line `grep -qxF`; a confirmed one-line fix folds in, anything larger is a deferral (the consolidated tracker).
1.2 `.claude/hooks/pre-merge-rebase.sh` disjoint-delta reads (`$MERGE_BASE HEAD` and `$MERGE_BASE "$REMOTE_MAIN"`): append `--ignore-submodules=none` only; keep `--name-only --no-renames` as separate arguments and add no `--diff-filter` (T-DJ3's git stub matches the literal ` --name-only `). The `git log ... -G'code-review' --name-only -- todos/` read stays (NC: a `-z` form creates fragment lines that can point at a real tagged todo) and the `--diff-filter=U` listing stays (advisory). Suite `.claude/hooks/pre-merge-rebase.test.sh`: both sides change the same gitlink under `ignore=all` -> overlap, so the sync runs.
1.3 `scripts/hooks/pre-push` - append `--ignore-submodules=none` to the emptiness diff. Add a gitlink-only-push case in a suite that can run the hook against a scratch repo; if the hook cannot be driven there, pin the flag via PINNED_Z and execute the extracted line in the `steps`-style harness.
1.4 `plugins/soleur/scripts/affected-tests.sh` (four `-c core.quotePath=false diff --name-only -M ...` legs): `-M` -> `--no-renames`, append `--ignore-submodules=none`. No `-z` (CTO F3: residual C-quote fails closed because a quoted path ends in `"` and cannot match an inert glob). Suite `plugins/soleur/scripts/affected-tests.test.sh`: `git mv src/x.ts docs/x.md` must not exit `NO_TESTS_AFFECTED`; a gitlink row; the existing rename rows (around lines 1918-1930, 2186, 2290) stay green.
1.5 `plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh` (`OWN_FILES`, the `--numstat` read, the `own_pid` pathspec): feed jq the NUL stream (`git diff -z --no-renames --ignore-submodules=none --name-only ... | jq -R -s 'split("\u0000") | map(select(length>0))'`), parse `--numstat -z` records per record, keep the `# mut:norenames` marker and update the suite's mutation string and text pin in the same commit. Suite `plugins/soleur/test/pr-overlap-preflight.test.sh`: an own file with a non-ASCII/tab name that another PR also touches reports the overlap.
1.6 `scripts/lint-credential-path-literals.py`, `scripts/lint-infra-no-human-steps.py`, `scripts/lint-shell-trace-credential-refusal.py`: the diff and `ls-files --others` argv gain the Python recipe; the shell-trace lint gets a `git_out_z` helper (it shares `git_out` with `merge-base`) and its non-`--changed` `ls-files "*.sh"` path uses it too. Each lint's `.test.sh` gains a non-ASCII-named `.md`/`.sh` row driven through `--changed` (must be scanned) and a failing-git row (exit 2).
1.7 `apps/web-platform/scripts/lint-migration-fk-preconditions.sh`: capture the diff into a variable with `|| rc` -> exit 2, `--no-renames` with `--diff-filter=AM` (a rename becomes D+A and the new file is linted), `-z ... | tr` inside a pipefail scope; the suite gains the missing `--from-pr-diff` rows (failing diff -> 2; rename -> linted).
1.8 `apps/web-platform/scripts/allowlist-diff.sh`: replace `grep -Fxq '.gitleaks.toml' < <(git diff --name-only ...)` with a pathspec read `cfg="$(git diff --no-renames --ignore-submodules=none --name-only "${BASE_SHA}..${HEAD_SHA}" -- .gitleaks.toml)" || { echo ...; exit 2; }` and an emptiness test (the 0/1/2 exit contract is preserved; 2 = required input unusable). New suite `apps/web-platform/scripts/allowlist-diff.test.sh` (no dedicated suite exists): bad SHA -> 2, rename of `.gitleaks.toml` -> detected, unchanged -> 0 with "skipping". A new suite means meta-guards and registry rows (Phase 5). The file is on the secret-scanning floor (CODEOWNERS here is routing text only - no `require_code_owner_review` - so no extra approver is needed).
1.9 `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh`: `CHANGED="${SDK_GATE_CHANGED_FILES-...}"` keeps the unset-vs-empty override precedence (`${VAR+x}` test); its git arm becomes the pipefail `-z ... | tr` capture whose failure sets `capture_trigger=1` (fail toward running the canary). Suite `sdk-bump-sandbox-gate.test.sh` always injects the override today, so the git arm is unexercised: add scratch-repo rows (unresolvable `BASE_REF` -> trigger; rename away from a gated file -> trigger). This file triggers the `sandbox-canary-capture-gate` check - read it by hand (operator constraint).
1.10 `apps/web-platform/scripts/real-sdk-ask-probe.sh` (drop-first, F6): one-line `-z ... | tr` in the existing `if !` capture; suite row: a non-ASCII `plugins/soleur/hooks/...` file with a lockfile-only change runs the probe.
1.11 `apps/web-platform/scripts/rename-guard.sh`: structural - `git log -z --name-status ...` parsed as status/source/destination NUL triples (`founder-check.py` `_history` is the precedent), drop the `|| true` that turns a git failure into "no renames", refuse any name containing a newline (the later `grep -qP ... <<<"$path"` is line-based), keep the 5% thresholds and `--diff-merges=first-parent`. Suite `scripts/rename-guard.test.sh`: a laundering rename whose destination holds `"` or a tab is seen; a failing `git log` exits non-zero.
1.12 `plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts` (drop-first): `-z`, split on `"\0"`, non-zero exit -> exit 2 instead of `[]`; the frontend-anti-slop suite gains a quoted-name row.

### Phase 2 - Wave 2: workflows and `.github/scripts`

2.1 `.github/workflows/web-platform-release.yml` live-verify trigger step: the compare jq becomes `.files[] | .filename, (.previous_filename // empty)` and `files >= 300` sets `triggered=1`; the step joins the suite's `steps` section (the TS matcher re-implementation in `trigger.test.ts` does not execute it).
2.2 `.github/workflows/registry-host-replace-dispatch.yml` render-input read: `.files[]? | .filename, (.previous_filename // empty)`. The verdict suite executes the real run bodies (PyYAML extraction), so only its `gcompare` fixture builder changes: a rename row with `previous_filename` for each of `zot-registry.tf`, `variables.tf`, `cloud-init-registry.yml` (rename away -> the render-input flag is set, never `deliver=false`).
2.3 `.github/workflows/fix-constraints-stage-a.yml` and `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.template` (plus the `.emitted.sha256` pin, refreshed in the same commit): `git diff --cached --name-only -z` gains `--no-renames --ignore-submodules=none`. Drop-first candidate. Suites: `emit-fix-constraints.test.sh`, `refresh-stage-a.test.sh`.
2.4 `.github/workflows/ci.yml` trigger-canary and trigger-propagation steps (`CHANGED="$(git diff --no-renames --name-only origin/main...HEAD 2>/dev/null || true)"`): pipefail-scoped `-z ... | tr` capture; a git failure sets `hit=1` (run), never `hit=0`. Both exemption rows leave `EXEMPT_TABLE`; the steps join `steps` (named scenarios: git failure -> run; unrelated diff -> skip). ci.yml is high-traffic: confirm no mirror suite slices these steps by a fragile marker (the arc learning: `infra-validation-detect.test.sh` sliced a step at its first column-10 `fi`).
2.5 `.github/workflows/pr-quality-guards.yml` stray-worktree-marker step: `gh api --paginate "repos/$GH_REPO/pulls/$PR_NUMBER/files" --jq '.[].filename'` gated on exit status (a failure fails the step closed), then `grep -cE '^\.claude/worktrees/'` over the captured list; its exemption row is deleted; the step joins `steps`.
2.6 `.github/scripts/check-sweep-completeness.sh`: a jq sentinel emits `::NL-IN-PATH::` for a `[\r\n]` name and the script fails closed on it; new derivation rows in `.github/scripts/test/test-check-sweep-completeness.sh` using a stub `gh` (newline-name row; forged-dependent row).

### Phase 3 - Wave 3: skill prose, references, agents

3.1 `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` hatch-eligible classifier (highest value): the capture becomes `files="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" origin/main...HEAD)"`; the existing `&&` chain already prints `NOT eligible` on rc 2, so the "fails closed" paragraph becomes true (and newline names are covered).
3.2 `plugins/soleur/skills/ship/references/counsel-review-clo-attestation.md` (`legal_touch`): `--match '^(docs/legal/|plugins/soleur/docs/pages/legal/|knowledge-base/legal/)' origin/main...HEAD` with the unknown arm (also fixes `main...HEAD` -> `origin/main...HEAD`). `ship/references/adr-ordinal-collision.md` (sweep loop reads the helper list) and `review/references/risk-tier-and-fix-rounds.md` (`files=$(...) || files=unknown   # unknown: spawn the full class panel`) use the same idiom.
3.3 `plugins/soleur/skills/ship/SKILL.md` (three sites, headroom 18 B - net-zero or net-negative bytes): the vendor-cost ledger check -> `ledger_touched=$(... --match '^knowledge-base/operations/expenses\.md$' origin/main...HEAD) || { [ $? -eq 1 ] || ledger_touched=unknown; }` and its Rule/comment text (`ledger_touched` empty or `unknown` never exempts the gate); the PIR meta-case conjuncts 1-2 read the list through the helper ("exit 2/127 = unknown = the meta-case is NOT available, run the PIR gate"); the Closes-after-verification gate -> `plan_refs=$(... --match '^knowledge-base/project/(plans|specs)/' ...) || { ...; plan_refs=unknown; }` with "unknown => use `Ref #N`". Trim candidates (content anchors; measure with `wc -c`): the "Why conjuncts 2 and 3 exist" verification paragraph, the "Why this lives here and not only in `work`" paragraph, redundant comment lines in the ledger block. Grep the plugin for other uses of `LEDGER_TOUCHED` and `PLAN_REFS` before renaming (only ship/SKILL.md carries them today).
3.4 `plugins/soleur/skills/one-shot/SKILL.md` scope check (headroom 9 B): both `git diff ... --name-only` forms (`origin/main...HEAD` and the `<base-sha>..HEAD` fallback) become the helper; "exit 2/127 = scope unverified: treat as a breach and re-diff, never as in scope". Pay with a trim of the `#4587` Why sentence.
3.5 Agents: `plugins/soleur/agents/engineering/review/semgrep-sast.md` (`--diff-filter=ACMR origin/main...HEAD` via the helper; exit 2/127 aborts, consistent with its hard-gate rule) and `observability-coverage-reviewer.md` (exit 2/127 = "inventory unknown", all categories in scope). `${CLAUDE_PLUGIN_ROOT}` in an agent body has precedent in `agents/engineering/cto.md`.
3.6 Pins in `changed-path-readers.test.sh`: add `one-shot` to the three SKILL.md pin loops (spelling, range, handler) with a `skill_fixture` and a DEFECTS self-test row; extend the handler pin's hard-coded variable list (`gdpr_gate_touch diff_match dpf_match`) with `ledger_touched plan_refs` (column 0, lowercase) and keep the `calls -ge N` check exact; add a ref/agent spelling-plus-failure-arm pin (every `changed-paths.sh` mention in a converted ref or agent is the whole call form and sits next to the unknown / 2-127 arm).

### Phase 4 - Wave 4: sentinel, census, header, registries

4.1 Code census in `changed-path-readers.test.sh` `section_sentinel` (CTO F2): scan tracked non-test `*.sh *.py *.ts *.mjs` under `.claude/hooks`, `scripts`, `plugins/soleur/scripts`, `plugins/soleur/skills/*/scripts`, `apps/web-platform/scripts`, `.github/scripts` for `git diff|log|show ... --name-only|--name-status`, `gh pr diff ... --name-only` and `gh api .../files|.../compare` readers; every site is NUL-delimited or has an `EXEMPT_CODE_TABLE` row (`file<TAB>content anchor<TAB>reason`, one row per site, anchors never line numbers); an API reader carries `previous_filename` or an exempt row; stale rows fail via process substitution (never a `| while` subshell); file and site floors set to the exact current count as multi-line `if [ "$X" -lt "$MIN_X" ]` blocks with an adjacent literal bound.
4.2 Bounded prose census: the SKILL.md files of ship, one-shot, work, qa, review, preflight, postmerge plus the converted refs and agents; each plain `git diff|log ... --name-only|--name-status` / `gh pr diff --name-only` mention is converted or has an `EXEMPT_PROSE` row (anchor + reason). Lesson/example text elsewhere is out of the census by construction (the closed file list).
4.3 Every converted file joins `PINNED_Z`; the python lints pin the `"-z"` argv token, the workflows pin the `previous_filename` jq. Rewrite the header's NOT COVERED / KNOWN REMAINDER block as a reasoned table (no "about twenty unconverted sites" prose left) and update `MIN_HELPER_ROWS`, `MIN_STEP_ROWS`, `MIN_TOTAL` and the `SELFTESTS` count to the exact new values.
4.4 Exemption maintenance: delete the two `ci.yml` rows and the `pr-quality-guards.yml` `gh pr diff` row; re-verify the remaining rows (`reusable-release`, `web-platform-release:595`, `tenant-integration`, the two AMRT rows); record "advisory by design" for `check-pr-body-vs-diff.sh`.
4.5 Registries LAST: re-derive `scripts/ci-pr-affected-audit.accept.tsv` rows for the edited suites (the existing rows for `changed-path-readers.test.sh` key on content anchors that move with every edit; re-derive from a grep of the suite's real-tree read arms, never by copying a sibling row's reason), then add the new `allowlist-diff.test.sh` to the suite registries in sorted position (`scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, and the `apps/web-platform/infra/` pair if that suite is registered there - decided by how `apps/web-platform/scripts/*.test.sh` is discovered); each accept row is one of the six typed kinds.

### Phase 5 - verification (CI is the gate; no local affected-battery run)

5.1 Targeted local runs only, one suite at a time (the arc learning: never run pin suites in parallel): the edited suites named above plus `changed-path-readers.test.sh` sections individually.
5.2 Pre-push meta-guards, on the new and edited suites: `bash scripts/guard-vacuity-floor.test.sh`; `bash plugins/soleur/test/fixture-relative-assert.test.sh` (scratch roots via `mktemp -d -t <prefix>`); `python3 scripts/lint-trap-tempfile-ownership.py`; `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` (the converted scripts add no findings; the baseline is not edited); `bash scripts/test-affected-kb-consumers.test.sh`; `bash .claude/hooks/grep-q-pipe-guard.test.sh`; `bash scripts/battery-tag-authorship.test.sh`; `cd apps/web-platform && npx vitest run test/plugin-root-anchoring.test.ts` (the edited prose and agent bodies use the bare token). Also `python3 scripts/lint-skill-body-budget.py --base origin/main` and `bun test plugins/soleur/test/components.test.ts` (description budget untouched).
5.3 Mutation battery for the extended guard (Guard Contract rows) in a scratch copy that IS a git repo (`git init && git add -A`), lead-unique file names under the session scratchpad, a green unmutated control first, and a mutation-landed check per row.
5.4 Push (check the real exit code), mark ready, wait for the required checks (`test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required`); read `infra-validation` and `sandbox-canary-capture-gate` by hand when they appear. Never push to a PR in the merge queue; never `--admin`; ruleset untouched. After merge: `deploy-arm.sh find --wait <sha>`, `served <sha>` = CONTAINS, `/health` ok.

## Files to Edit

- Wave 1: `scripts/pre-push-ratchet-lane.sh`, `scripts/pre-push-ratchet-lane.test.sh`, `scripts/hooks/pre-push`, `.claude/hooks/pre-merge-rebase.sh`, `.claude/hooks/pre-merge-rebase.test.sh`, `plugins/soleur/scripts/affected-tests.sh`, `plugins/soleur/scripts/affected-tests.test.sh`, `plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh`, `plugins/soleur/test/pr-overlap-preflight.test.sh`, `scripts/lint-credential-path-literals.py`, `scripts/lint-credential-path-literals.test.sh`, `scripts/lint-infra-no-human-steps.py`, `scripts/lint-infra-no-human-steps.test.sh`, `scripts/lint-shell-trace-credential-refusal.py`, `scripts/lint-shell-trace-credential-refusal.test.sh`, `apps/web-platform/scripts/lint-migration-fk-preconditions.sh`, `apps/web-platform/scripts/lint-migration-fk-preconditions.test.sh`, `apps/web-platform/scripts/allowlist-diff.sh`, `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh`, `apps/web-platform/scripts/sdk-bump-sandbox-gate.test.sh`, `apps/web-platform/scripts/real-sdk-ask-probe.sh`, `apps/web-platform/scripts/real-sdk-ask-probe.test.sh`, `apps/web-platform/scripts/rename-guard.sh`, `scripts/rename-guard.test.sh`, `plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts` (and its suite).
- Wave 2: `.github/workflows/web-platform-release.yml`, `.github/workflows/registry-host-replace-dispatch.yml`, `plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh`, `.github/workflows/fix-constraints-stage-a.yml`, `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.template` (and its `.emitted.sha256` pin), `.github/workflows/ci.yml`, `.github/workflows/pr-quality-guards.yml`, `.github/scripts/check-sweep-completeness.sh`, `.github/scripts/test/test-check-sweep-completeness.sh`.
- Wave 3: `plugins/soleur/skills/ship/SKILL.md`, `plugins/soleur/skills/one-shot/SKILL.md`, `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`, `plugins/soleur/skills/ship/references/counsel-review-clo-attestation.md`, `plugins/soleur/skills/ship/references/adr-ordinal-collision.md`, `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md`, `plugins/soleur/agents/engineering/review/semgrep-sast.md`, `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`.
- Wave 4: `plugins/soleur/test/changed-path-readers.test.sh`, `scripts/ci-pr-affected-audit.accept.tsv`, and (only if the new suite needs rows) `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, all in sorted position.

## Files to Create

- `apps/web-platform/scripts/allowlist-diff.test.sh` - new suite; the only unit that exercises the allowlist-diff gate's git arm.
- `knowledge-base/project/specs/feat-one-shot-changed-path-readers-remainder/tasks.md` (derived from this plan) and `decision-challenges.md` (already written).

## Open Code-Review Overlap

Checked the planned paths against the 200 open `code-review` issues (two-stage `gh issue list --json` then `jq --arg`). Three bodies mention a planned file by name only: #3220 (`web-platform-release.yml`, postmerge verification of trigger-bearing migrations), #8881 and #2965 (`ci.yml`, a shard rebalance and a critical-CSS extractor). Disposition: **Acknowledge** all three - different concerns, none touches the changed-path reader steps; they remain open. No other overlap.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Seven technical forks (cut line, sentinel extension, `affected-tests.sh` depth, SKILL.md body budget, compare-API form, PR shape, tracking) went to the CTO agent and were ruled in full; rulings and amended verdicts are recorded in `decision-challenges.md` and the `CTO rulings applied` note above. No operator-class item arose (no money, scope, priority, schedule, legal-risk or brand question).

No product, marketing, legal, finance, operations or support implications: internal gate machinery, no user-facing surface, no regulated-data surface, no new store or connection, no new autonomous task, and no architectural decision (so no ADR/C4 deliverable).

## Observability

```yaml
liveness_signal:
  what: the census sentinel in plugins/soleur/test/changed-path-readers.test.sh runs inside the required `test` check on every PR and goes RED when a plain name-listing reader appears or an exemption row goes stale
  cadence: every pull_request and merge_group run (scripts/test-all.sh auto-discovers plugins/soleur/test/*.test.sh)
  alert_target: red required `test` check on the PR
  configured_in: scripts/test-all.sh discovery plus the floors at the bottom of changed-path-readers.test.sh
error_reporting:
  destination: stderr and exit status of each converted reader (exit 2 / refuse / run), surfaced in the CI step log or the hook deny message
  fail_loud: true - every converted reader maps a git or API failure to run, refuse or exit 2, never to "nothing changed"
failure_modes:
  - mode: a converted reader's git or API call fails
    detection: failing-git shim rows in each converted site's suite (RED-first)
    alert_route: red CI step, or a hook/lane abort naming the cause
  - mode: a new plain reader is added later
    detection: the code and prose census (an UNLISTED row names file:line)
    alert_route: red `test` check
  - mode: an exemption's stated reason goes stale or its anchor stops matching
    detection: STALE row in the census
    alert_route: red `test` check
  - mode: the census scans nothing (glob rot)
    detection: file and site floors
    alert_route: red `test` check
logs:
  where: CI step logs and the suite transcript (`census: N sites, M unlisted, K stale`)
  retention: GitHub Actions default run-log retention
discoverability_test:
  command: git grep -c -e 'ignore-submodules=none' -- scripts/pre-push-ratchet-lane.sh
  expected_output: scripts/pre-push-ratchet-lane.sh:
```

## Guard Contract

### Guard 1 - changed-path reader census (code)

**Property.** No tracked non-test script reads a PR's changed paths through a plain `--name-only`/`--name-status` listing (or an API file list without `previous_filename`) unless a reasoned exemption row names that exact site.

**Assembly.** The chokepoint is `section_sentinel` in `plugins/soleur/test/changed-path-readers.test.sh`. It quantifies over (a) every tracked `.github/workflows/*.yml` (existing), (b) every tracked non-test `*.sh *.py *.ts *.mjs` under the six code roots, (c) the closed prose file list of Guard 2, and (d) `PINNED_Z` for converted files. Members drift, so the file lists come from `git ls-files` at run time and are never enumerated; the exemption tables are per SITE (two identical sites need two rows) and stale rows fail. It runs from both the `sentinel` and the default `all` dispatch arms (one function, two entries).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | strip `-z` from the SECOND reader in a file whose first reader is compliant (second member after a compliant first) | RED, second site reported with file:line |
| 2 | add an `EXEMPT_CODE_TABLE` row whose anchor matches no site | RED (STALE) |
| 3 | point the census root at an empty directory / drop the code roots from the scan list | RED (the file floor fires; a scan of 0 files must not exit 0) |
| 4 | run `changed-path-readers.test.sh sentinel` and the default `all` against the same mutant | both RED (the new census is dispatched from both arms) |
| 5 | remove `previous_filename` from a `gh api .../files` or `.../compare` reader | RED |
| 6 | put `-z` only in a trailing `# comment` of an unconverted reader | RED (still unconverted) |
| 7 | add a plain reader in a NEW file under a code root that no row names | RED (UNLISTED) |
| 8 | revert one converted file to the plain form while leaving its PINNED_Z row | RED (the pinned row fails independently of the census) |

**Harness rows:** an edit to the suite itself - move the unlisted-site counter into a `| while` subshell (the arc's defect 4) - must make the control row go RED, proven through the existing `selftest_moved` positive controls. Must-PASS inputs that are NOT the canonical: a `-c core.quotePath=false diff -z` spelling, a `$GIT`-launcher spelling, a backslash-continued reader, and a `gh api` reader that carries `previous_filename` on a continuation line.

**Anchor.** The stored values (exemption tables, floors) live in the same file as the guard, so one diff can edit both. The outside movers are (1) the required `test` check executing the suite against the PR's own tree, (2) the reviewer reading the diff of the exemption reasons, and (3) exact-count floors paired with set identity (one row per site), so a substitution that keeps the count still reddens.

### Guard 2 - skill prose and agent call-form pins

**Property.** Every converted prose site (ship, one-shot, the converted references and agents) spells the helper call in the one canonical bare-token form and states the failure arm (unknown fires the gate, never exempts).

**Assembly.** The chokepoint is `skill_prose_pins` plus the new ref/agent pin: the SKILL.md files of preflight, ship, review and now one-shot (three pin loops: spelling, range, handler) and the converted refs/agents (spelling + failure arm). The handler pin's variable names are derived from the handler regex, with only the `LEDGER_TOUCHED`/`PLAN_REFS` rename added.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | garble one call (`changed-paths.shchanged-paths.sh`) in one-shot | RED |
| 2 | add a second helper call to a converted ref without the unknown arm | RED |
| 3 | reintroduce `${CLAUDE_PLUGIN_ROOT:-}` in a converted agent body | RED (and `plugin-root-anchoring.test.ts` RED independently) |
| 4 | reintroduce uppercase `LEDGER_TOUCHED=` at column 0 in ship | RED (handler pin count) |
| 5 | delete the one-shot fixture/DEFECTS row | RED (the suite refuses to run with inert pins) |

**Harness rows:** the good-tree control must exit green and a mutated-tree control must exit red before the pins count (existing pattern). A must-PASS non-canonical input: the same call inside an indented fenced block in a reference file.

**Anchor.** As Guard 1: the spelling constants live in the suite; the outside movers are the required `test` check and `plugin-root-anchoring.test.ts`, which independently rejects the `:-` spelling in tracked prose.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "classify and convert the remaining plain `--name-only` changed-path readers that fail open" | Phases 1-4, Site classification table | mapped |
| 2 | "classify each site first (does a match ALLOW, or only select? exact-line, prefix or unanchored?) and convert only the ones that fail open" | Site classification table + exemption tables | mapped |
| 3 | "Send the \"which are worth converting and does the sentinel extend to them\" fork to the CTO agent (never the operator)" | decision-challenges.md F1, F2 | mapped |
| 4 | "Reuse the helper for skill prose; stay inline in hooks and workflows." | Phase 3 (prose via helper); Phases 1-2 (inline) | mapped |
| 5 | "Close at least as many issues as you file; if you must file, file ONE consolidated tracker with --label meta/machinery and declare `Filed: #N`." | Overview net issue flow; F7 | mapped |
| 6 | "INFRA_RE and its twins stay unchanged ... test-all.sh and battery-refusal-wait.sh only append --ignore-submodules=none; the ship Phase 7 queue-wait gap is NOT fixed" | Non-Goals | mapped |
| 7 | "Plan must include running these meta-guards on any new suite BEFORE pushing" | Phase 5.2 | mapped |
| 8 | "Registry rows ... go in sorted position; accept rows need one of the six typed kinds and are re-derived LAST." | Phase 4.5 | mapped |
| 9 | "Do not touch apps/web-platform/test/claude-pin-lockstep.test.ts. Leave the stale-accept row for real-sdk-ask-probe-workflow.test.sh alone." | Non-Goals | mapped |
| 10 | "Cap fix rounds at two targeted rounds plus one verification pass." | Phase 5 preamble | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Wave 1 hook/script/lint conversions | ".claude/hooks/pre-merge-rebase.sh (532/818/854), scripts/pre-push-ratchet-lane.sh (358/360), plugins/soleur/scripts/affected-tests.sh (685-705, same selection as test-all.sh), scripts/lint-*.py readers, apps/web-platform/scripts/allowlist-diff.sh and sdk-bump-sandbox-gate.sh" | asked |
| `pr-overlap-preflight.sh`, `rename-guard.sh`, `lint-migration-fk-preconditions.sh`, `tier1-scan.ts`, `real-sdk-ask-probe.sh` | "classify each site first ... and convert only the ones that fail open" (found by the census, not named) | inferred - justification: the brief's list is "about 20" and says "Examples"; the same rule applies to every site the census finds and CTO F1 ruled them IN |
| Wave 2 compare-API, fix-constraints and `check-sweep-completeness.sh` | "the web-platform-release.yml / registry-host-replace-dispatch.yml compare-API readers ..., fix-constraints-stage-a.yml (-z without --no-renames)" and ".github/scripts/check-pr-body-vs-diff.sh and check-sweep-completeness.sh" | asked |
| ci.yml canary/propagation and `pr-quality-guards.yml` stray-marker step | (exemption-table rows of the existing sentinel, not named in the brief) | inferred - justification: their stated exemption reasons are false or stale and the "convert only the ones that fail open" rule covers them; CTO F1 ruled IN |
| Wave 3 prose and agents | "unconverted skill prose (review:391, preflight:132/304, ship, one-shot, postmerge, work, qa, four agents/*.md)" | asked (all classified; converted only where it fails open) |
| Wave 4 census extension | "does the sentinel extend to them" and "extend the sentinel only after a separate pass over them" | asked |

### Split Assessment

- Subsystems touched: 6 - `.claude/hooks`, `scripts/`, `plugins/soleur` (scripts, skills, agents, tests), `apps/web-platform/scripts`, `.github` (workflows, scripts), constraint-scaffold template.
- Planned files: ~50 | Estimated changed lines: ~1500-2000 (mostly suite rows).
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines - all three exceeded.
- Recommendation: single PR - CTO F6 ruled one PR in four ordered waves (two PRs double CI/merge-queue cost and the follow-up census would let the remainder regrow); shrink order if needed is 22, 15, 17, 19, the P10 refs, 21, and a size-driven drop is the only thing that justifies the single consolidated tracker.

## Acceptance Criteria

- [ ] Every site in the final convert set (25 groups) reads NUL-delimited, rename-free, submodule-honest names (or the files/compare API with `previous_filename`), and a git or API failure runs or refuses - evidenced by one RED-first suite row per site (`file:test-name` listed in the PR body).
- [ ] No ALLOW-class reader accepts a fragment of a newline-named path: `allowlist-diff.sh` (pathspec), `check-sweep-completeness.sh` (jq sentinel), ship `ledger_touched` (`unknown` never exempts), the PIR meta-case (`unknown` = not contained), the admin-merge classifier (helper rc 2 = not eligible).
- [ ] `pre-merge-rebase.sh`'s `git log --name-only` todos read is NOT converted and the suite still passes its todos fixtures; recorded as NC with the fragment-line reason.
- [ ] `changed-path-readers.test.sh` full run: 0 failures; code census reports `0 unlisted, 0 stale`; floors set to the exact new counts; Guard 1 (8 rows) and Guard 2 (5 rows) mutation rows demonstrated RED with a green unmutated control and a mutation-landed check each (transcript in the PR body).
- [ ] The header of `changed-path-readers.test.sh` no longer says "about twenty unconverted sites"; the remainder is a reasoned table whose every row is also an exemption-table row.
- [ ] `python3 scripts/lint-skill-body-budget.py --base origin/main` is green: ship and one-shot byte deltas <= 0 (or within headroom 18 B / 9 B) and no ceiling raised.
- [ ] All Phase 5.2 meta-guards pass on the final tree; registry rows (if any) are in sorted position and accept rows re-derived last.
- [ ] PR body: `Ref #12246`, `Ref #12332`, `Ref #6480` (no `Closes`), `Filed: none` (or `Filed: #N` for the single consolidated tracker if and only if a size-driven drop happened), a `## Changelog` section, label `semver:patch`.
- [ ] Required checks green (`test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required`); `infra-validation` and `sandbox-canary-capture-gate` read by hand; merged; `deploy-arm.sh find --wait <sha>`, `served <sha>` = CONTAINS, `/health` ok.

## Test Scenarios

(Layer in brackets; all `unit` or `integration` against scratch git repos built with `git_fixture_env`; no `e2e`.)

- Given a branch that renames `ci.yml` away, when `pre-push-ratchet-lane.sh` runs, then the conditional kb-consumers member fires [integration].
- Given a suite file named `tab<TAB>name.test.sh` on the branch, when the lane selects branch-touched suites, then it is selected [integration].
- Given `git mv src/x.ts docs/x.md`, when `affected-tests.sh` classifies, then the result is not `NO_TESTS_AFFECTED` [integration].
- Given a gitlink hidden by `ignore=all` and changed on both sides, when `pre-merge-rebase.sh` evaluates disjointness, then the sync runs [integration].
- Given a non-ASCII `.md` under `knowledge-base/`, when each Python lint runs with `--changed`, then the file is scanned; given a failing git, then exit 2 [unit].
- Given an unresolvable `BASE_SHA`, when `allowlist-diff.sh` runs, then exit 2 (not "unchanged; skipping"); given `.gitleaks.toml` renamed, then it is detected [integration].
- Given no `SDK_GATE_CHANGED_FILES` and an unresolvable `BASE_REF`, when `sdk-bump-sandbox-gate.sh` runs, then `capture_trigger=1` [integration].
- Given a rename whose destination holds `"` or a tab, when `rename-guard.sh` runs, then the laundering rename is reported; given a failing `git log`, then non-zero [integration].
- Given a compare payload with `status: renamed` and `previous_filename` on a gated path, when the live-verify trigger and the registry dispatch steps run, then each reads the old path [integration; steps executed].
- Given a files-API payload with a name containing a newline, when `check-sweep-completeness.sh` derives the changeset, then it fails closed [unit; stub `gh`].
- Given `git diff` failing inside the `ci.yml` canary and propagation steps, then `hit=1` [integration; steps executed].
- Given a PR touching `.claude/worktrees/é`, when the stray-marker step runs, then it blocks [integration; steps executed].
- Given a planted `x/knowledge-base/operations/expenses.md.bak`, when ship's vendor-cost gate evaluates, then `ledger_touched` is empty and the gate fires [prose pin + fixture].
- Property that must never break: a failing `git` or `gh` never yields rc 0 with an empty list in any converted reader (generated over the failing-shim set, not enumerated by hand).

## Risks and Sharp Edges

- **Conversion can open a closed arm.** `-z | tr` turns a newline name into fragment lines. Harmless for SELECT; fatal for an ALLOW reader that looks names up one by one (`pre-merge-rebase.sh`'s todos read stays plain for exactly that reason). Every converted ALLOW reader needs a newline-name row.
- **Skill body ceilings are almost exhausted** (ship 18 B, one-shot 9 B). A conversion without a same-file trim reddens `lint-skill-body-budget.py`; edit and trim in the same commit and measure with `wc -c` before and after. Do not raise a ceiling.
- **The pins are shape-specific.** Handler pin = column-0 lowercase variable plus an `origin/main...HEAD` range; a `HASH..HEAD` or uppercase site fails it (hence ship's `HASH..HEAD` readers stay NC with their backstops).
- **Mirror suites slice workflow steps by fragile markers** (the arc's `infra-validation-detect.test.sh` incident). After editing a `ci.yml` or `pr-quality-guards.yml` step, run the sibling suite that extracts it, individually.
- **ugrep on the host.** `grep -z` and `\b` behave differently from CI's GNU grep; any local smoke needs a known non-zero-count fixture, and no new regex may rely on `\b`.
- **Process hygiene:** no `git stash` (use a WIP commit); `git add` and `git commit` in separate calls; no bare pipe into `grep -q`; no `pgrep` with `-f`; no SSH; check a push's real exit code.
- **A plan whose `## User-Brand Impact` section is empty, TBD or omits the threshold fails deepen-plan Phase 4.6** - this one declares `aggregate pattern`.
- **Accept rows** (`scripts/ci-pr-affected-audit.accept.tsv`) key on content anchors in the edited suites; every suite edit invalidates some rows, so re-derive them once, last.
- **Sites dropped for size are real deferrals**; only then is the one consolidated tracker filed.
