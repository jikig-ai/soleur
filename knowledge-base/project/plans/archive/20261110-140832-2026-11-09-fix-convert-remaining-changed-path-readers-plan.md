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

## Enhancement Summary

**Deepened on:** 2026-11-09
**Sections enhanced:** Phases 1-5, Guard Contract (both guards), Acceptance Criteria, Test Scenarios, Risks, plus a new Observations section.
**Agents used:** two read-only claim verifiers (prose/pins, code/workflows), `soleur:engineering:review:code-simplicity-reviewer`, `soleur:engineering:review:test-design-reviewer`, `soleur:engineering:review:security-sentinel`, and a second CTO round (G1-G5) for the forks they surfaced. Halt gates 4.6-4.13 were run mechanically: User-Brand Impact present (`aggregate pattern`), Observability schema complete, no PAT-shaped variable, no UI surface, `lint-guard-contract.py` green (2 entries), one unfenced `## Scope Check`, no encryption/IaC/task-design trigger, no downtime trigger.

### Key improvements

1. **Corrected seven factual errors in the plan** (all verified against code): the SKILL.md pin has two per-skill loops plus a ship-only handler pin (not three loops); `sdk-bump-sandbox-gate.sh` does not trigger `sandbox-canary-capture-gate`; the two `ci.yml` canary steps are already in `STEP_MANIFEST` (an existing `hit 0` expectation flips instead of a new scenario); a new suite in `apps/web-platform/scripts/` reddens guard-vacuity ARM 5c (moved to `scripts/`); suite-registry rows are optional, not required; `counsel-review`, `adr-ordinal-collision` and `risk-tier` use `main...HEAD` / `ls-tree` / `$PANEL_SHA..HEAD`, not the assumed range; any reference file that gains the plugin-root token must carry the W4a notice.
2. **Closed four fail-open holes the plan itself would have shipped:** `plan_refs=unknown` would have grepped a file named `unknown` (now an explicit test); `ledger_touched=unknown` would have exempted the vendor-cost gate under a `-n` test (now an exact-equality exemption); `rename-guard.sh` under a UTF-8 locale passes a `\xff` laundering rename (now `LC_ALL=C`); the `-z` NUL-triple parser would have misaligned after the first commit (now the fail-closed line form, CTO G1).
3. **Census design hardened:** the converted-reader predicate is the three-flag form, not a bare `-z`; the census sees Python call forms; exempt rows key on repo-relative path; `census_report` is extracted so `selftest_moved` can drive it; counts are floored through a `CENSUS_ROWS` counter the vacuity guard can see.
4. **Scope trimmed to the property:** `pr-overlap-preflight.sh` uses the plain `-z | tr` form (no NUL-in-jq); the admin-merge classifier stays inline (CTO G2); `pr-quality-guards.yml` uses the local git form (CTO G4).

### New considerations discovered

- Several `*-test` pins hold exact text near the edited prose (`ship-pir-action-items-gate.test.sh` counts `rc=$?` lines and backticked paths in the PIR meta-case section; `admin-merge-ready-wiring.test.sh`; `review-tier-parity.test.ts`; `deploy-arm.test.sh` pins postmerge line text, which is why postmerge is untouched).
- ship's body-budget cost is about +190 B against 18 B of headroom, so trims are a hard prerequisite of the prose wave.

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

### Deepen-plan amendments to the classification table (2026-11-09; supersede the table cells where they differ)

Row 5 (`pr-overlap-preflight.sh`): plain `-z ... | tr` for `OWN_FILES` with a gated status, not NUL-in-jq. Row 13 (`allowlist-diff.sh`): `git -C "$REPO_ROOT" ... -- ':(top,literal).gitleaks.toml'`, `::error::` on the exit-2 arm, new suite at `scripts/allowlist-diff.test.sh`. Row 14 (`sdk-bump-sandbox-gate.sh`): separate `git_failed` flag OR-ed into `capture_trigger`. Row 16 (`rename-guard.sh`): CTO G1 fail-closed line form (capture to file with no `|| true`, `LC_ALL=C` on awk and every `grep -P`, exit 2 on a path beginning with `"`); the table's "H1" label is only for tab/quote/backslash/control names since `core.quotePath=false` already keeps non-ASCII raw. Row 19 (`check-sweep-completeness.sh`): the `[\r\n]` refusal covers all three routes and runs before the `tr -d '\r'`, a 3000-entry listing exits 1, no `previous_filename`. Rows 20/21: rename-capable `gcompare`, `(.files|type)=="array"`, empty pattern set fails, `.files|length >= 300`. Row 24: the steps are already in `STEP_MANIFEST`. Row 25: CTO G4 local inline git form plus the `detect` cap fix. P1: CTO G2 inline classifier. P2: exact-equality exemption and `--diff-filter=AMT`. P4: explicit `unknown` branch. P10: W4a notice in three reference files.

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

1.1 `scripts/pre-push-ratchet-lane.sh` - the two `git diff --name-only` reads into `$BRANCH_ALL` (`$BASE HEAD`) and `$MAIN_CHANGES` (`$BASE origin/main`) become `git ... diff -z --no-renames --ignore-submodules=none --name-only ... | tr '\0' '\n' > "$BRANCH_ALL" || abort - "branch-diff-failed"` (global `set -euo pipefail`, so the pipeline status reaches the existing `|| abort`; identical for ASCII names); the early-PASS `git diff --quiet "$BASE" HEAD` gains `--ignore-submodules=none` (an error already falls through to running); the `--name-status` baseline checks gain `--no-renames`. Suite `scripts/pre-push-ratchet-lane.test.sh`: rename-away from a `KB_CONSUMERS_INPUTS` file (e.g. `ci.yml`) fires the conditional member; a suite file with a tab/non-ASCII name is still selected; a gitlink-only branch does not early-PASS. The `KB_CONSUMERS_INPUTS` entries (`knowledge-base/`, seven `glob:...`) that an exact-line `grep -qxF` can never match are an existing defect already tracked by #11166 (the array is parity-pinned at `pre-push-ratchet-lane.test.sh` ~L1016, so the fix is a matcher change): `Ref #11166`, not folded in (CTO G3).
1.2 `.claude/hooks/pre-merge-rebase.sh` disjoint-delta reads (`$MERGE_BASE HEAD` and `$MERGE_BASE "$REMOTE_MAIN"`): append `--ignore-submodules=none` only; keep `--name-only --no-renames` as separate arguments and add no `--diff-filter` (T-DJ3's git stub matches the literal ` --name-only `). The `git log ... -G'code-review' --name-only -- todos/` read stays (NC: a `-z` form creates fragment lines that can point at a real tagged todo) and the `--diff-filter=U` listing stays (advisory). Suite `.claude/hooks/pre-merge-rebase.test.sh`: the gitlink row must use REAL git (the T-DJ stubs match text only): both sides change the same gitlink under `ignore=all` -> overlap, so the sync runs; mutation: delete `--ignore-submodules=none` -> that row RED.
1.3 `scripts/hooks/pre-push` - append `--ignore-submodules=none` to the emptiness diff. Add a gitlink-only-push case in a suite that can run the hook against a scratch repo; if the hook cannot be driven there, pin the flag via PINNED_Z (flag-only site: `--no-renames.*--ignore-submodules=none`) and execute the extracted line in the `steps`-style harness.
1.4 `plugins/soleur/scripts/affected-tests.sh` (four `-c core.quotePath=false diff --name-only -M ...` legs): `-M` -> `--no-renames`, append `--ignore-submodules=none`. No `-z` (CTO F3: residual C-quote fails closed because a quoted path ends in `"` and cannot match an inert glob). Suite `plugins/soleur/scripts/affected-tests.test.sh`: `git mv src/x.ts docs/x.md` must not exit `NO_TESTS_AFFECTED`; a gitlink row; the existing rename rows (around lines 1918-1930, 2186, 2290) stay green.
1.5 `plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh`: the `OWN_FILES` read (the line carrying `# mut:norenames`) becomes `OWN_FILES="$(set -o pipefail; git diff -z --no-renames --ignore-submodules=none --name-only origin/main...HEAD | tr '\0' '\n')"` with its status gated (`|| cannot_check`; the script is `set -uo pipefail` WITHOUT `-e`, so an ungated status is dropped). Fragments of a newline name can only add a false overlap, which is harmless for a BLOCK reader (simplicity review: no NUL-in-jq, which also avoids an unverified jq 1.7.1 `split("\u0000")` on the runner). `OWN_STATS` (`--numstat`, fail-soft to `{}`, advisory) and the `own_pid` pathspec read stay. Update the `# mut:norenames` marker, the suite's mutation string and its text pin in the same commit. Suite `plugins/soleur/test/pr-overlap-preflight.test.sh`: an own file with a non-ASCII/tab name that another PR also touches reports the overlap.
1.6 `scripts/lint-credential-path-literals.py`, `scripts/lint-infra-no-human-steps.py`, `scripts/lint-shell-trace-credential-refusal.py`: the diff and `ls-files --others` argv gain the Python recipe; decode the bytes with `errors="surrogateescape"` (or split bytes) so a non-UTF-8 name cannot raise; the shell-trace lint gets a `git_out_z` helper (it shares `git_out` with `merge-base`) and its non-`--changed` `ls-files "*.sh"` path uses it too. Each lint's `.test.sh` gains a non-ASCII-named `.md`/`.sh` row driven through `--changed` (must be scanned) and a failing-git row (exit 2). The census regex must be extended to see these call forms (Phase 4.1).
1.7 `apps/web-platform/scripts/lint-migration-fk-preconditions.sh`: capture the diff into a variable with `|| rc` -> exit 2, `--no-renames` with `--diff-filter=AM` (a rename becomes D+A and the new file is linted), `-z ... | tr` inside a pipefail scope; the suite gains the missing `--from-pr-diff` rows (failing diff -> 2; rename -> linted).
1.8 `apps/web-platform/scripts/allowlist-diff.sh`: replace `grep -Fxq '.gitleaks.toml' < <(git diff --name-only ...)` with a pathspec read `cfg="$(git -C "$REPO_ROOT" diff --no-renames --ignore-submodules=none --name-only "${BASE_SHA}..${HEAD_SHA}" -- ':(top,literal).gitleaks.toml')" || { echo "::error::allowlist-diff: git diff failed"; exit 2; }` and an emptiness test (the 0/1/2 exit contract is preserved; `:(top,literal)` makes the pathspec independent of cwd and `diff.relative`). The `::error::` line is REQUIRED: the smoke case `allowlist-diff-fires` in `secret-scan.yml` expects a non-zero exit with an `::error::` line, and editing this script (`SUBJECT_RE ^apps/web-platform/scripts/`) runs the smoke matrix. The workflow member step treats any non-zero as a failed job and no sticky comment is posted before the skip check. New suite `scripts/allowlist-diff.test.sh` (CTO G5: `apps/web-platform/scripts/` is in guard-vacuity-floor `DEFERRED_DIRS` with a shrink-only `MAX_DEFERRED`, so a suite born there reddens ARM 5c; precedent `scripts/rename-guard.test.sh`; auto-discovered by the `scripts/*.test.sh` glob of `test-all.sh`): bad SHA -> 2 with `::error::`, rename of `.gitleaks.toml` -> detected, unchanged -> 0 with "skipping"; it carries its own floor as a multi-line `if [ "$X" -lt "$MIN_X" ]` block. Registry rows (`suite-durations.tsv`, `suite-shard-legs.tsv`) are OPTIONAL (untabled labels hash-fall back; `scripts-shard-manifest.test.sh` fails only on phantom rows or key mismatch) - add via `python3 scripts/regenerate-shard-manifest.py --incremental --write` only if a guard fails without them. The file is on the secret-scanning floor (CODEOWNERS here is routing text only - no `require_code_owner_review`).
1.9 `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh`: `CHANGED="${SDK_GATE_CHANGED_FILES-$(git diff ...)}"` is restructured to `if [[ -n "${SDK_GATE_CHANGED_FILES+x}" ]]; then CHANGED=$SDK_GATE_CHANGED_FILES; elif ! CHANGED="$(set -o pipefail; git diff -z --no-renames --ignore-submodules=none --name-only "${BASE_REF}...HEAD" | tr '\0' '\n')"; then CHANGED=""; git_failed=1; fi` (a subshell inside `${VAR-...}` cannot set a flag, and the existing `capture_trigger=0` on the next line would clobber an earlier assignment, so use a separate `git_failed` flag and OR it into `capture_trigger` after that line). The unset-vs-empty override precedence is preserved. Suite `sdk-bump-sandbox-gate.test.sh` always injects the override today, so the git arm is unexercised: add scratch-repo rows (unresolvable `BASE_REF` -> trigger; rename away from a gated file -> trigger). This script runs live under the required `lockfile-sync` check (`ci.yml` step `lockfile-sync-sdk-bump`); it is NOT in the `trigger-canary` path regex, so editing it alone does not fire `sandbox-canary-capture-gate`, but read that check by hand if it appears.
1.10 `apps/web-platform/scripts/real-sdk-ask-probe.sh` (drop-first, F6): one-line `-z ... | tr` in the existing `if !` capture; suite row: a non-ASCII `plugins/soleur/hooks/...` file with a lockfile-only change runs the probe.
1.11 `apps/web-platform/scripts/rename-guard.sh` (CTO G1: fail-closed line form, NOT a NUL parser - `git log -z --pretty=format:` emits an empty NUL token between commits, which misaligns a fixed 3-token loop from the second commit on): capture `git log ... --name-status` to a temp file with NO `|| true` (a git failure exits 2, not "no renames"), run awk on the file, set `LC_ALL=C` on the awk and on EVERY `grep -P` including `matched_allow_res` (under a UTF-8 locale `grep -qP '^knowledge-base/plans/.*\.md$'` returns 1 for a `\xff` name, so a laundering rename passes), and exit 2 naming the cause if a source or target path begins with `"` (git C-quotes tab, quote, backslash, control and newline names; `core.quotePath=false` already keeps non-ASCII raw). Keep the 5% thresholds and `--diff-merges=first-parent`. Suite `scripts/rename-guard.test.sh` (real scratch repos): (a) bad `BASE_SHA` -> 2; (b) a tab/quote name in the source and in the target, separately -> 2; (c) a `\xff` laundering rename into `knowledge-base/plans/` flagged, fixture run under an exported UTF-8 locale so removing `LC_ALL=C` reddens it; (d) a rename in the SECOND commit of a multi-commit range still seen; (e) a copy (`C`) row still seen; (f) mutation: drop the `"` check -> (b) RED.
1.12 `plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts` (drop-first): `-z`, split on `"\0"`, non-zero exit -> exit 2 instead of `[]`; the frontend-anti-slop suite gains a quoted-name row.

### Phase 2 - Wave 2: workflows and `.github/scripts`

2.1 `.github/workflows/web-platform-release.yml` live-verify trigger step (`id: gate`): the compare jq becomes `.files[] | .filename, (.previous_filename // empty)`; `(.files|length) >= 300` sets `triggered=1` (SELECT reader: the cap reads as run; a `triggered=1` costs CI minutes - Doppler, bun, `playwright install` ~10 min - and never blocks a release, `BLOCK=1` only on a genuine FAIL); an EMPTY pattern set from `trigger-paths.txt` fails the step instead of matching nothing. No suite executes this step today (`trigger.test.ts` only reads `trigger-paths.txt`), so it is ADDED to `STEP_MANIFEST` in `changed-path-readers.test.sh` with named scenarios (rename-away from a gated path -> triggered; cap -> triggered; API failure -> CANT-RUN unchanged).
2.2 `.github/workflows/registry-host-replace-dispatch.yml` render-input read: `.files[]? | .filename, (.previous_filename // empty)`, and require `(.files|type)=="array"` (a 200 with `files` null/absent currently reads as "0 files" -> `deliver=false`; exit 1 instead). The verdict suite executes the real run bodies (PyYAML extraction) so only its fixtures change: `gcompare` (L203-210) builds `map({filename: .})` and cannot carry `previous_filename`, so add a rename-capable builder or argument (its precondition scans only `.filename`, so a rename row naming a render input only as `previous_filename` will not trip it): a rename row for each of `zot-registry.tf`, `variables.tf`, `cloud-init-registry.yml` (rename away -> the render-input flag is set, never `deliver=false`).
2.3 `.github/workflows/fix-constraints-stage-a.yml` and `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.template` (plus the `.emitted.sha256` pin, refreshed in the same commit): `git diff --cached --name-only -z` gains `--no-renames --ignore-submodules=none`. Drop-first candidate. Suites: `emit-fix-constraints.test.sh`, `refresh-stage-a.test.sh`.
2.4 `.github/workflows/ci.yml` trigger-canary and trigger-propagation steps (`CHANGED="$(git diff --no-renames --name-only origin/main...HEAD 2>/dev/null || true)"`, checkout `fetch-depth: 0`): pipefail-scoped `-z ... | tr` capture; a git failure sets `hit=1` (run), never `hit=0`; `hit` gates the advisory `sandbox-canary-capture-gate` and `plugin-root-propagation-gate` (a paid turn / a docker run, bounded and advisory, only in the near-impossible event of a git failure after a full-depth checkout). Both steps are ALREADY in `STEP_MANIFEST` (`ci-canary`, `ci-propagation`) with `advisory_rows` scenarios: FLIP the existing git-failure expectation (`hit 0`, labelled "UNCHANGED by this PR", ~L830) to `hit 1` and drop the label; delete both `EXEMPT_TABLE` rows. ci.yml is high-traffic: no other suite mirrors these steps (checked), but re-run `ci-classify-step-exec.test.sh` and `ci-path-gating.test.sh` individually after the edit.
2.5 `.github/workflows/pr-quality-guards.yml` (CTO G4 supersedes F5 for this row): the stray-worktree-marker step (`id: stray-worktree-marker-block`, job `quality-advisory`, `fetch-depth: 0`) switches to the LOCAL inline form `git diff -z --no-renames --ignore-submodules=none --name-only "<base>"...HEAD | tr '\0' '\n'` (base from the event or the step's existing `diff_base`), captured under pipefail; a git failure fails the step (`::error::`, exit 1), never reads as empty; fragment lines from a newline name only add false positives to a BLOCK match. No new permission and no 3000-file ceiling. Its exemption row is deleted. In the SAME file the `detect` job (`gh api --paginate .../pulls/N/files --jq '.[].filename, .[].previous_filename'`) must emit `worktrees=true` when the listing count reaches the 3000 cap (a truncated list would skip the BLOCK step through its `needs.detect.outputs.worktrees == 'true'` condition); keep its exit-status gating. Neither is executed by any suite today (`ci-path-gating.test.sh` pins structure only): add the step and the detect cap to `STEP_MANIFEST` (key, job `quality-advisory`, id `stray-worktree-marker-block`; raise the manifest `STEP_FLOOR`/row counts). The `.claude/worktrees/é` scenario is driven with a real scratch repo (local git form), not a `gh` stub.
2.6 `.github/scripts/check-sweep-completeness.sh` (ALLOW reader; `grep -Fxq` on the changeset): apply a `[\r\n]` refusal to the RAW names on EVERY route, BEFORE the `tr -d '\r'` normalisation at the end of the derivation (a name ending in `\r` would otherwise equal a dependent): the files-API route (jq `if test("[\r\n]") then "::NL-IN-PATH::" else . end`, then `grep -q '^::NL-IN-PATH::'` -> exit 1 fail closed), the `CHANGESET_SRC`/stdin route (refuse any CR) and the `gh pr diff --name-only` fallback. A files-API listing at the 3000 cap exits 1 (a missed trigger would let dependents pass). Do NOT add `previous_filename` here: pass 1's `[[ -f ]]` already catches a rename-away of a registered path, and an old name would let a dependent's old path satisfy the check. New derivation rows in `.github/scripts/test/test-check-sweep-completeness.sh` using a PATH-shim `gh` (it is called by bare name) that accepts exactly the modeled argv (exit 64 otherwise): newline-name row, CR row, forged-dependent row, drop-`--paginate` mutation.

### Phase 3 - Wave 3: skill prose, references, agents

3.1 `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` hatch-eligible classifier (highest value; CTO G2): keep the classifier INLINE, not the helper - it runs BEFORE steps 2 and 4 (where the `_top` realpath guard lives), and executing a script from a `CLAUDE_PLUGIN_ROOT` not yet proven to be outside the PR checkout on the path that gates `--admin` is worse than the bug. `files="$(set -o pipefail; git diff -z --no-renames --ignore-submodules=none --name-only origin/main...HEAD | tr '\0' '\n')"` inside the existing `&&` chain, so a failed or empty diff still prints `NOT eligible`; a newline name yields fragment lines that must not match the allowlist (they cannot satisfy `every path matches`); add a PINNED_Z row for this file. The file already carries the W4a notice (token count 9), so no notice work. Pinned by `admin-merge-ready-wiring.test.sh:28` (reads the file) - re-run it. OBSERVATION for the PR body only (CTO G2b: authorization policy is the operator's call): the allowlist admits executable `plugins/soleur/skills/**` scripts and `.*\.md$` including AGENTS.md, CLAUDE.md and `.claude/agents/*.md`.
3.2 `plugins/soleur/skills/ship/references/counsel-review-clo-attestation.md:10` (currently `legal_touch=$(git diff main...HEAD --name-only | grep -E '^(...)' | head -n 1)` - note `main`, not `origin/main`): `legal_touch=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" --match '^(docs/legal/|plugins/soleur/docs/pages/legal/|knowledge-base/legal/)' origin/main...HEAD) || { [ $? -eq 1 ] || legal_touch=unknown; }`. `ship/references/adr-ordinal-collision.md:33` (the `for f in $(git diff --name-only origin/main...HEAD)` sweep; `:17` is a `git ls-tree` reader and stays) reads the helper list through a `while IFS= read -r f` loop; `review/references/risk-tier-and-fix-rounds.md:58` passes the PANEL range through unchanged: `files=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" "$PANEL_SHA"..HEAD) || files=unknown   # unknown: spawn the full class panel` (the helper accepts any rev range; keep it off the SKILL.md range pin, which does not read references). W4a TRAP (`plugin-root-anchoring.test.ts` `isReadSurfaceDoc`): any non-SKILL.md under `skills/` that gains a `${CLAUDE_PLUGIN_ROOT}/` token becomes a Read-surface doc and must carry BOTH `**Plugin root in this file:**` and the sentence `The root is ONLY the prefix of the path you read this file from` - counsel-review, adr-ordinal-collision and risk-tier have zero tokens today, so each needs the notice (copy `settle-then-admin-merge.md:3`); these files have no body ceiling. Pinned files to re-run: `review-tier-parity.test.ts` (reads risk-tier).
3.3 `plugins/soleur/skills/ship/SKILL.md` (three sites; headroom 18 B; MEASURED cost: the new ledger line is 188 B vs 116 B today, the `plan_refs` line 176 B vs 111 B, the meta-case edit ~+60 B, i.e. about +190 B, so at least ~190 B (aim for 300 B) must be trimmed in the SAME commit; measure with `wc -c` before and after; never raise a ceiling): (1) vendor-cost ledger: `ledger_touched=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" --diff-filter=AMT --match '^knowledge-base/operations/expenses\.md$' origin/main...HEAD) || { [ $? -eq 1 ] || ledger_touched=unknown; }`; the Rule/comment text exempts ONLY when `[ "$ledger_touched" = "knowledge-base/operations/expenses.md" ]` (any `-n`/`!= 0` test would treat `unknown` as touched and exempt the gate; `--diff-filter=AMT` so a deletion does not count as touching); (2) PIR meta-case conjuncts 1-2: the list comes through the helper with a fully anchored allowlist regex (`^(scripts/ship-incident-pir-gate\.sh|...|plugins/soleur/test/fixtures/ship-incident-pir-gate/.*)$`, `\.` escaped) and containment means plain-mode output piped through `grep -vE` leaves nothing; "exit 2/127 = unknown = NOT contained: run the PIR gate"; keep each helper call on ONE physical line with `origin/main...HEAD` (range pin) and keep the three backticked paths between `ALL THREE hold` and the `2. **Every**` line exactly once, exactly two `rc=$?` lines and no `head -n1` in that section (`ship-pir-action-items-gate.test.sh:194-199`); (3) Closes-after-verification gate: `plan_refs=$(... --match '^knowledge-base/project/(plans|specs)/' origin/main...HEAD) || { [ $? -eq 1 ] || plan_refs=unknown; }` and the following line must test `unknown` EXPLICITLY (`[[ $plan_refs == unknown ]] && echo 'unverifiable: use Ref #N'`) - otherwise `grep -inE "$CLOSE_DEFER_RE" $plan_refs` greps a file named `unknown`, prints nothing and lets `Closes` through; replace the unquoted word-split `$plan_refs` with `xargs -d '\n' grep -inE -e "$CLOSE_DEFER_RE" --`. Trim candidates (content anchors): the "Why conjuncts 2 and 3 exist" verification paragraph, the "Why this lives here and not only in `work`" paragraph, redundant comment lines in the ledger block. Grep done: `LEDGER_TOUCHED` appears only at ship/SKILL.md (assignment, comment, Rule), `PLAN_REFS` only at the Closes gate; no test pins either.
3.4 `plugins/soleur/skills/one-shot/SKILL.md` scope check (headroom 9 B; the paragraph is ONE physical line carrying both `origin/main...HEAD` and the `<base-sha>..HEAD` fallback, so the existing range pin passes): both `git diff ... --name-only` forms become the helper; "exit 2/127 = scope unverified: treat as a breach and re-diff, never as in scope". Pay with a trim of the `#4587` Why sentence. No test pins the paragraph's text. OBSERVATION (not adopted, byte budget and a different threat): `--name-only` cannot see mode 120000/160000 changes, so a symlink under `plans/` would pass as in scope; an anchored `^knowledge-base/project/(plans|specs)/` regex is used for the containment test.
3.5 Agents: `plugins/soleur/agents/engineering/review/semgrep-sast.md` (`--diff-filter=ACMR origin/main...HEAD` via the helper; exit 2/127 aborts, consistent with its hard-gate rule) and `observability-coverage-reviewer.md` (exit 2/127 = "inventory unknown", all categories in scope). `${CLAUDE_PLUGIN_ROOT}` in an agent body has precedent in `agents/engineering/cto.md`.
3.6 Pins in `changed-path-readers.test.sh` (verified against `skill_prose_pins`, ~L1387-1394): `one-shot` joins the TWO per-skill loops `skill_spelling_pin` and `skill_range_pin` (preflight/ship/review today); the handler pin is the ship-only function `skill_ship_handler_pin` and cannot take one-shot, so one-shot gets its own exact failure-arm regex (the `--match`-less list read: `exit 2/127` -> breach). `skill_fixture` gains `mkdir -p "$r/one-shot"` plus a fixture file (else the good-tree control FAILs), at least one DEFECTS row per new pin (its `old` string must occur exactly once in the fixture), and the literals `SELFTESTS` (45 -> +1 per DEFECTS row), `MIN_TOTAL`, `MIN_HELPER_ROWS`, `MIN_STEP_ROWS` rise to the exact new counts. The handler pin passes `calls -ge 3` as a FLOOR plus `calls == good`: raise the floor to 5, extend the closed variable list (`gdpr_gate_touch diff_match dpf_match`) with `ledger_touched plan_refs`, and give the fixture's ship file matching `ledger_touched`/`plan_refs` handler lines (else the compliant-tree control hits the `FATAL` at ~L1438). Add a ref/agent pin with the EXACT capture shape per file (`files=$(...) || files=unknown`, or `|| { [ $? -eq 1 ] || v=unknown; }`), trailing inline comments stripped before matching, with a good tree plus DEFECTS rows (generalise `skill_body`, which hardcodes `skills/$1/SKILL.md`).

### Phase 4 - Wave 4: sentinel, census, header, registries

4.1 Code census in `changed-path-readers.test.sh` `section_sentinel` (CTO F2): scan tracked non-test `*.sh *.py *.ts *.mjs` under `.claude/hooks`, `scripts`, `plugins/soleur/scripts`, `plugins/soleur/skills/*/scripts`, `apps/web-platform/scripts`, `.github/scripts`. The converted-reader PREDICATE is `--ignore-submodules=none` AND (`-z` OR `--no-renames`) AND no trailing `|| true`/`2>/dev/null || true` swallow - not a bare `-z` (the deliberate flag-only conversions in 1.2/1.3/1.4 and a `-z` without `--no-renames` such as the old fix-constraints defect must be classified correctly). Detection must see the call forms the shell regex misses (test-design review): Python `_git(["diff","--name-only"...])` / `git_out([...])` / `["git","diff",...]` (the existing `\bgit\b` never matches `_git(`, and its `Z` regex needs whitespace before `-z`, so a compliant `"-z"` argv token would false-RED), `.ts`/`.mjs` `//` and `/* */` comments, and comments stripped per PHYSICAL line before continuation-joining (a mid-continuation `` `# MUT:x` `` marker in `rename-guard.sh` currently eats `--name-status`). API readers (`gh api .../files|.../compare`) must carry the emitting form `.filename, (.previous_filename // empty)` (a bare `previous_filename` token is stub-satisfiable) or an exempt row. `EXEMPT_CODE_TABLE` rows (`path<TAB>content anchor<TAB>reason`) are keyed on the REPO-RELATIVE PATH, not the basename (the existing table matches `r[0]==base`, so a same-named file elsewhere could consume a row); one row per site; stale rows fail through process substitution, never a `| while` subshell. Floors: the Python census counts are not in-file counters, so add `CENSUS_ROWS` plus a bottom-of-file literal `MIN_CENSUS_ROWS=N` directly above `if [ "$CENSUS_ROWS" -lt "$MIN_CENSUS_ROWS" ]; then printf ...; exit 1; fi` (guard-vacuity-floor shape), AND keep in-function `fail` floors for the `sentinel`-only dispatch. Extract the UNLISTED/STALE reporting into a function `census_report <SENT_OUT>` so `selftest_moved` can drive it (`selftest_moved ... fail census_report "$one_unlisted"` and `... "$one_stale"`, one violation each because it demands `df==1`), and add `CENSUS_ROWS=$c0` to `selftest_moved`'s unwind line (~L94) or the self-tests inflate the exact floor.
4.2 Bounded prose census: the SKILL.md files of ship, one-shot, work, qa, review, preflight, postmerge plus the converted refs and agents; each plain `git diff|log ... --name-only|--name-status` / `gh pr diff --name-only` mention is converted or has an `EXEMPT_PROSE` row (anchor + reason). Lesson/example text elsewhere is out of the census by construction (the closed file list).
4.3 `PINNED_Z` keeps ONLY what the census cannot see (CTO F2 + simplicity review): the prose files, the `previous_filename` emitting-form jq in the workflows/scripts, the Python flag trio (`"-z", "--no-renames", "--ignore-submodules=none"` argv - not just `"-z"`), the flag-only sites (`--no-renames.*--ignore-submodules=none` for pre-merge-rebase, pre-push, affected-tests, allowlist-diff) and `settle-then-admin-merge.md`. Rewrite the header's NOT COVERED / KNOWN REMAINDER block as a reasoned table (no "about twenty unconverted sites" prose left) and update `MIN_HELPER_ROWS`, `MIN_STEP_ROWS`, `MIN_TOTAL`, `MIN_CENSUS_ROWS` and the `SELFTESTS` count to the exact new values.
4.4 Exemption maintenance: delete the two `ci.yml` rows and the `pr-quality-guards.yml` `gh pr diff` row; re-verify the remaining rows (`reusable-release`, `web-platform-release:595`, `tenant-integration`, the two AMRT rows); record "advisory by design" for `check-pr-body-vs-diff.sh`.
4.5 Registries LAST: re-derive `scripts/ci-pr-affected-audit.accept.tsv` rows for the edited suites (the existing rows for `changed-path-readers.test.sh` key on content anchors that move with every edit; re-derive from a grep of the suite's real-tree read arms, never by copying a sibling row's reason), then add the new `allowlist-diff.test.sh` to the suite registries in sorted position (`scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, and the `apps/web-platform/infra/` pair if that suite is registered there - decided by how `apps/web-platform/scripts/*.test.sh` is discovered); each accept row is one of the six typed kinds.

### Phase 5 - verification (CI is the gate; no local affected-battery run)

5.1 Targeted local runs only, one suite at a time (the arc learning: never run pin suites in parallel): the edited suites named above plus `changed-path-readers.test.sh` sections individually.
5.2 Pre-push meta-guards, on the new and edited suites: `bash scripts/guard-vacuity-floor.test.sh` (note ARM 5c / `DEFERRED_DIRS`: the new suite lives in `scripts/`); `bash plugins/soleur/test/fixture-relative-assert.test.sh` and `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh` (scratch roots via `mktemp -d -t <prefix>.XXXXXXXX` - GNU mktemp needs the X template; check the `fixture-relative-assert.baseline.txt` equality pin; every new `rm -rf`/`git -C "$d"` operand goes through `assert_fixture_dir`); `python3 scripts/lint-trap-tempfile-ownership.py`; `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` (the converted scripts add no findings; the baseline is not edited); `bash scripts/test-affected-kb-consumers.test.sh`; `bash .claude/hooks/grep-q-pipe-guard.test.sh`; `bash scripts/battery-tag-authorship.test.sh`; `cd apps/web-platform && npx vitest run test/plugin-root-anchoring.test.ts` (W1 rejects the `:-` arm, W3 an unquoted token operand, W4a demands the notice in every Read-surface reference). Also `python3 scripts/lint-skill-body-budget.py --base origin/main`, `bun test plugins/soleur/test/components.test.ts` (description budget untouched) and the pinned-text suites `ship-pir-action-items-gate.test.sh`, `admin-merge-ready-wiring.test.sh`, `review-tier-parity.test.ts`, `deploy-arm.test.sh` (postmerge text untouched), run one at a time.
5.3 Mutation battery for the extended guard (Guard Contract rows) in a scratch copy that IS a git repo (`git init && git add -A`), lead-unique file names under the session scratchpad, a green unmutated control first, and a mutation-landed check per row.
5.4 Push (check the real exit code), mark ready, wait for the required checks (`test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required`); read `infra-validation` and `sandbox-canary-capture-gate` by hand when they appear. Never push to a PR in the merge queue; never `--admin`; ruleset untouched. After merge: `deploy-arm.sh find --wait <sha>`, `served <sha>` = CONTAINS, `/health` ok.

## Files to Edit

- Wave 1: `scripts/pre-push-ratchet-lane.sh`, `scripts/pre-push-ratchet-lane.test.sh`, `scripts/hooks/pre-push`, `.claude/hooks/pre-merge-rebase.sh`, `.claude/hooks/pre-merge-rebase.test.sh`, `plugins/soleur/scripts/affected-tests.sh`, `plugins/soleur/scripts/affected-tests.test.sh`, `plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh`, `plugins/soleur/test/pr-overlap-preflight.test.sh`, `scripts/lint-credential-path-literals.py`, `scripts/lint-credential-path-literals.test.sh`, `scripts/lint-infra-no-human-steps.py`, `scripts/lint-infra-no-human-steps.test.sh`, `scripts/lint-shell-trace-credential-refusal.py`, `scripts/lint-shell-trace-credential-refusal.test.sh`, `apps/web-platform/scripts/lint-migration-fk-preconditions.sh`, `apps/web-platform/scripts/lint-migration-fk-preconditions.test.sh`, `apps/web-platform/scripts/allowlist-diff.sh`, `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh`, `apps/web-platform/scripts/sdk-bump-sandbox-gate.test.sh`, `apps/web-platform/scripts/real-sdk-ask-probe.sh`, `apps/web-platform/scripts/real-sdk-ask-probe.test.sh`, `apps/web-platform/scripts/rename-guard.sh`, `scripts/rename-guard.test.sh`, `plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts`, `plugins/soleur/test/frontend-anti-slop/tier1-scan.test.ts`.
- Wave 2: `.github/workflows/web-platform-release.yml`, `.github/workflows/registry-host-replace-dispatch.yml`, `plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh`, `.github/workflows/fix-constraints-stage-a.yml`, `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.template` and the ledger `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.emitted.sha256` (refreshed through `refresh-stage-a.test.sh`'s mechanism in the same commit, never hand-edited), `.github/workflows/ci.yml`, `.github/workflows/pr-quality-guards.yml`, `.github/scripts/check-sweep-completeness.sh`, `.github/scripts/test/test-check-sweep-completeness.sh`.
- Wave 3: `plugins/soleur/skills/ship/SKILL.md`, `plugins/soleur/skills/one-shot/SKILL.md`, `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`, `plugins/soleur/skills/ship/references/counsel-review-clo-attestation.md`, `plugins/soleur/skills/ship/references/adr-ordinal-collision.md`, `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md`, `plugins/soleur/agents/engineering/review/semgrep-sast.md`, `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`.
- Wave 4: `plugins/soleur/test/changed-path-readers.test.sh`, `scripts/ci-pr-affected-audit.accept.tsv`, and (OPTIONAL, only if a guard fails without them) `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, all in sorted position.

## Files to Create

- `scripts/allowlist-diff.test.sh` - new suite (in `scripts/`, not `apps/web-platform/scripts/`, per CTO G5 and guard-vacuity-floor ARM 5c); the only unit that exercises the allowlist-diff gate's git arm.
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

**Assembly.** The chokepoint is `section_sentinel` in `plugins/soleur/test/changed-path-readers.test.sh`. It quantifies over (a) every tracked `.github/workflows/*.yml` (existing), (b) every tracked non-test `*.sh *.py *.ts *.mjs` under the six code roots, (c) the closed prose file list of Guard 2, and (d) `PINNED_Z` for converted files. The converted-reader predicate is `--ignore-submodules=none` AND (`-z` OR `--no-renames`) AND no swallowed failure (`|| true`), detected over shell, Python (`_git([...])`, `git_out([...])`, `["git","diff",...]`) and `.ts`/`.mjs` call forms with comments stripped per physical line. Members drift, so the file lists come from `git ls-files` at run time and are never enumerated; the exemption tables are per SITE (two identical sites need two rows) and stale rows fail. It runs from both the `sentinel` and the default `all` dispatch arms (one function, two entries).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | strip `-z` from the SECOND reader in a file whose first reader is compliant (second member after a compliant first) | RED, second site reported with file:line |
| 2 | add an `EXEMPT_CODE_TABLE` row whose anchor matches no site | RED (STALE) |
| 3 | point the census root at an empty directory / drop the code roots from the scan list | RED (the file floor fires; a scan of 0 files must not exit 0) |
| 4 | run `changed-path-readers.test.sh sentinel` and the default `all` against the same mutant; separately delete `section_sentinel` from the `all)` arm only, then from the `sentinel)` arm only | both RED; each arm-deletion mutant reddens the floor |
| 5 | remove `previous_filename` from a `gh api .../files` or `.../compare` reader | RED |
| 6 | put `-z` only in a trailing `# comment` of an unconverted reader | RED (still unconverted) |
| 7 | add a plain reader in a NEW file under a code root that no row names | RED (UNLISTED) |
| 8 | revert one flag-only or prose file (which the census cannot see) to the plain form while leaving its PINNED_Z row | RED (the pinned row fails independently of the census) |
| 9 | drop `--no-renames` from a converted `-z` site (the old `fix-constraints` defect) | RED (three-flag predicate) |
| 10 | drop `--ignore-submodules=none` from a converted site | RED |
| 11 | append `\|\| true` or `2>/dev/null \|\| true` to a converted reader | RED (swallowed failure) |
| 12 | change a `gh api .../files` selector to `.filename` only or `select(.previous_filename==null)`, or drop `--paginate` | RED (emitting-form pin; the PATH-shim `gh` accepts exactly the modeled argv and exits 64 otherwise) |
| 13 | replace a Python `git_out(["diff","-z",...])` with plain `_git(["diff","--name-only"])` | RED (census sees Python forms) |

**Harness rows:** an edit to the suite itself - move the unlisted-site counter into a `| while` subshell (the arc's defect 4) - must make the control row go RED, proven through the existing `selftest_moved` positive controls. Must-PASS inputs that are NOT the canonical: a `-c core.quotePath=false diff -z` spelling, a `$GIT`-launcher spelling, a backslash-continued reader, a `gh api` reader that carries `previous_filename` on a continuation line, Python `git_out(["diff","-z","--no-renames","--ignore-submodules=none","--name-only"])`, `git log -z ... | tr`, a pathspec emptiness reader (`allowlist-diff`) classed explicitly, and a `.ts` `// -z` comment on an unconverted reader (RED). The unlisted/stale reporting is extracted as `census_report` so `selftest_moved` drives one-violation inputs for each.

**Anchor.** The stored values (exemption tables, floors) live in the same file as the guard, so one diff can edit both. The outside movers are (1) the required `test` check executing the suite against the PR's own tree, (2) the reviewer reading the diff of the exemption reasons, and (3) exact-count floors paired with set identity (one row per site), so a substitution that keeps the count still reddens.

### Guard 2 - skill prose and agent call-form pins

**Property.** Every converted prose site (ship, one-shot, the converted references and agents) spells the helper call in the one canonical bare-token form and states the failure arm (unknown fires the gate, never exempts).

**Assembly.** The chokepoint is `skill_prose_pins` plus the new ref/agent pin: the SKILL.md files of preflight, ship, review and now one-shot (two per-skill loops - spelling and range - plus the ship-only handler pin and the one-shot failure-arm pin; verified against `skill_prose_pins`) and the converted refs/agents (spelling + failure arm). The handler pin's variable names are derived from the handler regex, with only the `LEDGER_TOUCHED`/`PLAN_REFS` rename added.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | garble one call (`changed-paths.shchanged-paths.sh`) in one-shot | RED |
| 2 | add a second helper call to a converted ref without the unknown arm | RED |
| 3 | reintroduce `${CLAUDE_PLUGIN_ROOT:-}` in a converted agent body | RED (and `plugin-root-anchoring.test.ts` RED independently) |
| 4 | reintroduce uppercase `LEDGER_TOUCHED=` at column 0 in ship | RED (handler pin count) |
| 5 | delete the one-shot fixture/DEFECTS row | RED (the suite refuses to run with inert pins) |
| 6 | flip the ship ledger prose from "`unknown` never exempts" to "exempts", or change the exemption test to `-n "$ledger_touched"` | RED (property 1: unknown never exempts) |
| 7 | remove the `\.` escape or the `^...$` anchors from the ledger `--match` regex (the planted `expenses.md.bak` case) | RED |
| 8 | add `\|\| true # unknown` after a converted ref/agent capture | RED (exact capture shape pinned, trailing comment stripped) |
| 9 | give one-shot a `HEAD~1` range on a helper line | RED, while the `<base-sha>..HEAD` fallback on the same physical line as `origin/main...HEAD` stays GREEN |

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
- [x] No ALLOW-class reader accepts a fragment of a newline-named path: `allowlist-diff.sh` (pathspec), `check-sweep-completeness.sh` (jq sentinel), ship `ledger_touched` (`unknown` never exempts), the PIR meta-case (`unknown` = not contained), the admin-merge classifier (helper rc 2 = not eligible).
- [x] `rename-guard.sh` proves (a)-(f) of task 1.11 (bad SHA -> 2; tab/quote source and target -> 2; `\xff` laundering rename flagged under an exported UTF-8 locale; second-commit rename seen; copy row seen; dropping the `"` check reddens (b)).
- [x] `allowlist-diff.sh`'s exit-2 arm prints an `::error::` line (secret-scan smoke case `allowlist-diff-fires`) and the new suite lives at `scripts/allowlist-diff.test.sh` with its own floor.
- [x] ship `ledger_touched` exempts only on exact equality with the ledger path; `plan_refs=unknown` yields an explicit "use `Ref #N`" line; the PIR meta-case treats `unknown` as not contained; ship net bytes <= 0 after trims.
- [x] `pre-merge-rebase.sh`'s `git log --name-only` todos read is NOT converted and the suite still passes its todos fixtures; recorded as NC with the fragment-line reason.
- [x] `changed-path-readers.test.sh` full run: 0 failures; code census reports `0 unlisted, 0 stale`; floors set to the exact new counts; Guard 1 (13 rows) and Guard 2 (9 rows) mutation rows demonstrated RED with a green unmutated control and a mutation-landed check each (transcript in the PR body).
- [x] The header of `changed-path-readers.test.sh` no longer says "about twenty unconverted sites"; the remainder is a reasoned table whose every row is also an exemption-table row.
- [x] `python3 scripts/lint-skill-body-budget.py --base origin/main` is green: ship and one-shot byte deltas <= 0 (or within headroom 18 B / 9 B) and no ceiling raised.
- [x] All Phase 5.2 meta-guards pass on the final tree; registry rows (if any) are in sorted position and accept rows re-derived last.
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
- Given a three-commit range whose SECOND commit renames into `knowledge-base/plans/`, when `rename-guard.sh` runs, then that rename is seen (the NUL-triple trap) [integration].
- Given a rename into `knowledge-base/plans/\xff.md` under an exported UTF-8 locale, when `rename-guard.sh` runs, then it is flagged [integration].
- Given `plan_refs=unknown`, when ship's Closes gate runs, then it prints the "use `Ref #N`" line rather than grepping a file named `unknown` [prose pin + fixture].
- Given `SDK_GATE_CHANGED_FILES=""` (explicitly empty), when `sdk-bump-sandbox-gate.sh` runs, then it means "no relevant changes" and `git_failed` stays 0 [integration].
- Given a files-API listing of exactly 3000 entries, when the `pr-quality-guards.yml` `detect` step runs, then `worktrees=true` [integration; steps executed].
- Property that must never break: a failing `git` or `gh` never yields rc 0 with an empty list in any converted reader (generated over the failing-shim set, not enumerated by hand).

## Observations for the PR body (not deferrals of in-scope work; no issues filed)

- `settle-then-admin-merge.md` hatch allowlist (CTO G2b): it admits executable `plugins/soleur/skills/**` scripts and `.*\.md$` including AGENTS.md, CLAUDE.md and `.claude/agents/*.md`. Tightening it is an authorization-policy decision for the operator; state it plainly in the PR body.
- `KB_CONSUMERS_INPUTS` never-matching entries in `scripts/pre-push-ratchet-lane.sh`: already tracked by #11166 (`Ref #11166`, left open; CTO G3).
- `--name-only` cannot see mode 120000/160000 changes: the one-shot scope check would pass a symlink under `plans/`. Not addressed (byte budget, different threat).
- `check-pr-body-vs-diff.sh` is advisory by design (warns and exits 0 on a gh failure), `parse-override.sh:42` fails closed, `ci.yml` `--raw` classifiers fail closed: all recorded as exemption rows with those reasons.

## Risks and Sharp Edges

- **Conversion can open a closed arm.** `-z | tr` turns a newline name into fragment lines. Harmless for SELECT; fatal for an ALLOW reader that looks names up one by one (`pre-merge-rebase.sh`'s todos read stays plain for exactly that reason). Every converted ALLOW reader needs a newline-name row.
- **Skill body ceilings are almost exhausted** (ship 18 B, one-shot 9 B). A conversion without a same-file trim reddens `lint-skill-body-budget.py`; edit and trim in the same commit and measure with `wc -c` before and after. Do not raise a ceiling.
- **The pins are shape-specific.** Handler pin = column-0 lowercase variable plus an `origin/main...HEAD` range; a `HASH..HEAD` or uppercase site fails it (hence ship's `HASH..HEAD` readers stay NC with their backstops).
- **Mirror suites slice workflow steps by fragile markers** (the arc's `infra-validation-detect.test.sh` incident). After editing a `ci.yml` or `pr-quality-guards.yml` step, run the sibling suite that extracts it, individually.
- **ugrep on the host.** `grep -z` and `\b` behave differently from CI's GNU grep; any local smoke needs a known non-zero-count fixture, and no new regex may rely on `\b`.
- **Process hygiene:** no `git stash` (use a WIP commit); `git add` and `git commit` in separate calls; no bare pipe into `grep -q`; no `pgrep` with `-f`; no SSH; check a push's real exit code.
- **A plan whose `## User-Brand Impact` section is empty, TBD or omits the threshold fails deepen-plan Phase 4.6** - this one declares `aggregate pattern`.
- **Accept rows** (`scripts/ci-pr-affected-audit.accept.tsv`) key on content anchors in the edited suites; every suite edit invalidates some rows, so re-derive them once, last.
- **ship body bytes:** about +190 B needed against 18 B headroom (measured line sizes: ledger 188 vs 116 B, plan_refs 176 vs 111 B); review has 20 B, qa 11 B, postmerge 1 B if the prose census ever pulls them in.
- **W4a:** any reference under `skills/` that gains the plugin-root token must carry `**Plugin root in this file:**` and `The root is ONLY the prefix of the path you read this file from`, or `plugin-root-anchoring.test.ts` reddens.
- **The `git log -z` stream has an empty token between commits** and `grep -qP` is locale-sensitive: the reason `rename-guard.sh` takes the fail-closed line form with `LC_ALL=C`.
- **Existing `advisory_rows` expectation** (`hit 0` on git failure, "UNCHANGED by this PR") flips to `hit 1`; leaving it red-then-green by accident would hide the intent.
- **Sites dropped for size are real deferrals**; only then is the one consolidated tracker filed.
