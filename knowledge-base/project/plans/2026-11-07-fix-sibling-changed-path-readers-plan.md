---
title: "fix: sibling changed-path readers still C-quote paths, miss renames and hide gitlinks (#12332)"
date: 2026-11-07
slug: sibling-changed-path-readers
branch: feat-one-shot-12332-sibling-changed-path-readers
issue: 12332
closes: 12332
refs: 12246
type: fix
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

## Overview

Issue #12332 is the deferred sweep from PR #12326. That PR rebuilt the changed-path list in `plugins/soleur/skills/ship/scripts/battery-owed.sh`
so it reads NUL-delimited, rename-free, submodule-honest names rooted at the repository top. Other readers of changed-path lists were left on
the old unquoted form, with four distinct blind spots: a path holding a non-ASCII byte, tab, `"` or `\` is C-quoted by git and a `^`-anchored
regex then misses it; default rename detection lists only a rename's new path, so a rename away from a gated surface is invisible; a gitlink
hidden by configuration is not listed; and a bare `$(git diff ... | tr)` pipe turns a git failure into an empty list, which a skip-gate reads as
"nothing changed".

This PR converts the readers the brief names, plus the census siblings the CTO folded in, to the construction that fits each one. It does not
impose one shape everywhere: the CTO ruled that unanchored readers keep their shape and gain only the flag they are missing. One PR, closes
#12332, `Ref #12246` only (arc PR), net issue flow -1 (`Filed: none`).

Planning phase only: this document, `decision-challenges.md`, `session-state.md` and (at plan finalization) `tasks.md` are the only files written.
Implementation is the work phase.

## Research Reconciliation: Spec vs. Codebase

| Claim (issue #12332 / brief) | Reality (verified on this tree) | Plan response |
|---|---|---|
| `test-all.sh` `_diff_names` and `battery-refusal-wait.sh` `infra_state` lack `--ignore-submodules=none`; their unanchored `grep -F` makes C-quoting harmless | True for both. `_diff_edge_hit` also unwraps `"..."` for anchored edges and the `--name-status -M` reads already list rename sources. Exact-text pins and awk-range extractors depend on the read lines. | Fork 3 / 3b / 7a (CTO): append `--ignore-submodules=none` only; no NUL form, no `--no-relative`. Narrows the brief's `-z` wording for these two readers. |
| Brief: convert to `git diff -z --no-renames --ignore-submodules=none --name-only ... \| tr '\0' '\n'`, "rooted at the repo top" | Workflow steps run at the checkout root; `battery-refusal-wait.sh` already runs under `git -C "$top"`; `test-all.sh` has no `cd` but the issue lists only the gitlink gap for it. | Per-reader construction in the census table. |
| Six workflow files "regex-match an unquoted `git diff --name-only` with `^`-anchored patterns" | Not all are `^`-anchored: `pr-quality-guards.yml` surface patterns and the two `ci.yml` guards-advisory steps are unanchored (rename-away is the only live defect there). The census found more readers than the issue lists, and the push/schedule arm of `secret-scan.yml` is a separate step (`lint-fixture-files-nonpr`). | Census table; CTO Fork 2 and Fork 7. |
| This repo's gitlink exposure | `git ls-files -s \| grep -c '^160000'` is `0`, no `.gitmodules`, and a fresh CI checkout carries no `diff.ignoreSubmodules`. | `--ignore-submodules=none` is latent/defensive in CI; stated as such. The live CI defects are C-quoting and rename-away. |
| Skill prose in preflight/ship/review is "lower risk" | `skill-body-budget.json` leaves ship 98 bytes and review 111 bytes of headroom (preflight has no row); the helper call costs about +31 bytes per site over the bare `git diff`, the inline form about +59; a bare pipe loses git's exit status. | Fork 6 / 7g: one tested helper `plugins/soleur/scripts/changed-paths.sh` with a `--match` mode; the overshoot is trimmed from the same paragraph. |
| Probe `scripts/followthroughs/sibling-changed-path-readers-12326.sh` "must be updated/retired consistently" | A date-shape `exit 0` stub (`earliest=2026-12-07`); `git grep` of its stem finds no other live reference; `sweep-followthroughs.sh` reports a missing script on a labelled tracker as "script ... missing in repo HEAD - leaving issue open". | `git rm` the probe and remove the `follow-through` label from #12332 before merge. |
| Phase 7 queue-wait expiry counts only NAMED required contexts as pending | The block already counts an ABSENT required aggregate as pending while any check runs (`anypend`). An observed expiry therefore means the aggregate sat in a non-`pending` bucket or the shards reported under another bucket: not reproduced from data. | Fork 4 / 4b: no fix here; one line on the PR, on #12332, and as an observation in `queue-mode.md`. |
| `INFRA_RE` narrower than `infra-validation.yml`'s trigger set | The local infra shard (`apps/web-platform/infra/run-registered-suites.sh`) globs only `apps/web-platform/infra/`. | Fork 1: unchanged; one reason line in the `battery-owed.sh` header. |
| "Rename-away is invisible" applies to every reader | Not to a reader whose matcher is an exact line of a legal document (`pr-quality-guards` required-files check): there `--no-renames` would WEAKEN the gate (a rename away would list the old path and count as updated). | Fork 7d: separate surface-scan read; the required-files read stays destination-only. |

## Research Insights

**Premise validation (Phase 0.6).** #12332 OPEN (labels `follow-through`, `deferred-scope-out`, `meta/machinery`, `priority/p3-low`), not closed by any
PR. Arc PR #12246 MERGED (`Ref` only). #12326 MERGED (the reference fix). Draft PR #12357 is this branch. Collision pre-check hit only PR #12357;
the foreign `test-all.sh` processes belong to unrelated worktrees. Open PRs touching the same files, read with `gh pr diff --name-only` on 2026-11-07
(re-read at each sync): #12329 (`ci.yml`, `test-all.sh`, the three registry TSVs) and #12168 (`infra-validation.yml`), so every edit anchors on
content, not line numbers. Cited paths exist on `origin/main`. ADR corpus: no ADR rejects the NUL-delimited construction; it is the repo-native
shape (`.claude/hooks/brand-hex-commit-gate.sh`, `plugins/soleur/scripts/resolve-regenerable-conflicts.sh`, `scripts/ci-oracle-lane.sh`).

**Property list (Phase 0.6b).**

- P1: every converted reader sees exact path bytes for names holding a non-ASCII byte, tab, `"` or `\`.
- P2: a rename away from a gated surface lists the old path to the reader (except where that would weaken an exact-file check, Fork 7d).
- P3: a gitlink hidden by `diff.ignoreSubmodules` or a committed `ignore=all` is listed (latent in CI).
- P4: a git failure never collapses into an empty list; each site fails toward running or blocking (per-site table below).
- P5: each converted reader is exercised by an executed test with a control OUTSIDE the surface, so a row cannot pass vacuously.
- P6: the class does not regrow in the workflows, and the converted hooks and scripts keep `-z`.
- P7: the #12332 probe is retired consistently (file, label, no dangling reference).
- P8: the `INFRA_RE` fork is decided and the reason written where the next reader looks.
- P9: the Phase 7 expiry observation is recorded durably without a guessed fix.

**Cut List (Phase 0.6b).**

| Mechanism proposed in the ask or by a reviewer | Property | What covers it / ruling |
|---|---|---|
| Full NUL conversion of `test-all.sh` `_diff_names` | P1-P3 | Cut. Unanchored `grep -F` and `_diff_edge_hit` cover P1; `--name-status -M` covers P2; only P3 is missing (Fork 3). |
| `--no-relative` on `test-all.sh` | P1 (cwd) | Cut (Fork 7a): not listed in the issue for this reader, no `cd` in the script, adds a git 2.28 dependency. |
| NUL conversion of `battery-refusal-wait.sh` `infra_state` | P1-P3 | Cut to the one missing flag (Fork 3b). |
| Widening `INFRA_RE` and its twins | P8 | Cut (Fork 1). |
| A fix to ship Phase 7 expiry | P9 | Cut (Fork 4): no data, byte-ceilinged fence, spec drift. |
| Inline `-z` form in ship/review/preflight prose | P1-P4 | Replaced by one helper (Fork 6). |
| `skill-security-scan.sh` conversion plus its own suite | P1 | Cut (Fork 7b): advisory, ASCII slugs. EXEMPT in the census. |
| Separate `changed-paths.test.sh` suite | P5 | Cut (Fork 7f): folded into the one new suite. |
| Sentinel over hooks and top-level `scripts/` | P6 | Cut (Fork 7h): about twenty unconverted sites; replaced by a pinned must-keep-`-z` list. |
| Effective-shell resolver in the harness | P4 | Cut (Fork 7e): plain `bash -e {0}` is the weakest shell. |

**Learnings applied.** The #12326 learning (enumerate every consumer; `cmd | grep -c || true` collapses failure into `0`; capture the producer
first); `2026-10-14-c-quoted-names-evade-extension-anchored-list-filters` (`core.quotePath=false` covers only bytes at or above 0x80);
`2026-05-29-ugrep-as-grep-breaks-grep-z-null-delimited-pipelines` (some dev hosts alias `grep` to ugrep, where short `-z` means decompress: use
`tr '\0' '\n'` or `grep --null-data`, never short `-z`, no `\b`); `2026-07-27-my-assertion-pinned-the-text-not-the-shell-that-runs-it` (extract and
EXECUTE `run:` blocks); `2026-05-18-infra-validation-pathspec-silent-zero-match` (fixture top-level, single-ancestor and deep-nested shapes);
`2026-10-18-ratchet-guards-must-pin-the-scan-population-and-their-own-registrations` (totality of the scanned population);
`2026-11-03-one-malformed-accept-row-reason-drops-every-exemption` (validate accept-row shape before commit).

## Census of changed-path readers (content anchors, not line numbers)

Disposition: **IN** = converted; **EXEMPT** = kept with the reason the sentinel records; **OUT** = outside the sentinel and covered by its own pins.
"Fail arm" is what a git failure does at that site, always toward running or blocking, never toward skipping, except where noted.

| Reader (file : step id or content anchor) | Matcher | Live defects | Disposition, construction and fail arm |
|---|---|---|---|
| `battery-refusal-wait.sh` : `infra_state()` four `git diff` reads | unanchored `grep -qF` x2 | gitlink | IN (B'): append `--ignore-submodules=none`; keep the rest. Fail arm: unchanged (`unresolved`). |
| `scripts/test-all.sh` : `_diff_names` assembly, six `git diff` reads | unanchored substring + `_diff_edge_hit` | gitlink | IN (B): append `--ignore-submodules=none` inside the pinned text. Fail arm: unchanged. Sentinel-irrelevant (not a workflow). |
| `infra-validation.yml` : step `dirs`, push arm and PR arm | `^(apps/[^/]+/infra\|infra/[^/]+)/` then `sed` | C-quote, rename-away, gitlink | IN: capture `CHANGED` first in each arm, then run the existing `grep \| sed \| sort \| jq` chain over it. Fail arm: all infra roots (the step's own fail-safe). |
| `ci.yml` : job `detect-changes` step `filter` | `^(...)` | C-quote, rename-away | IN. Fail arm (new text): emit `docs=true`. |
| `ci.yml` : `guards-advisory` steps `trigger-canary`, `trigger-propagation` | unanchored `grep -cE` | rename-away | IN, shape-preserving: add `--no-renames` only; keep `2>/dev/null \|\| true` (advisory, `hit=0` on failure by design). |
| `apply-sentry-infra.yml` : `detect-changes` step `filter` | `^(...)` | C-quote, rename-away | IN. Fail arm: existing `::error::` + exit 1. |
| `tenant-integration.yml` : `detect-changes` step `filter` (`CHANGED`) ; later `git log --name-only` (`MIG_HIST`) | `^(...)` ; emptiness test | C-quote, rename-away | IN (`CHANGED`, existing `::error::` arm); `MIG_HIST` EXEMPT (emptiness only). |
| `vendor-pin-verify.yml` : `detect-changes` step `filter` | `^(...)` via here-string | C-quote, rename-away | IN. Fail arm: existing `::error::` + exit 1. |
| `pr-quality-guards.yml` : step `enforce-legal-lockstep` | unanchored `grep -Ec` (surface) ; `grep -Fxc` (required docs) | rename-away (surface only) | IN: new separate `surface_files` read with `--no-renames`; `changed_files` unchanged (Fork 7d). Fail arm: `set -e` as today. |
| `pr-quality-guards.yml` : step `constraint-gates-changed` (`git -c core.quotePath=false diff --name-only`) | `^apps/web-platform/` | C-quote (tab, `"`, `\`), rename-away | IN. Fail arm: `set -e` as today. |
| `secret-scan.yml` : steps `lint-fixture-files-pr` (two arms), `lint-fixture-files-nonpr`, `lint-fixture-content` | `^(...)` PATTERN | C-quote drops a fixture from the secret scan; `xargs -a` re-splits `"`/`\` | IN: git captured to a file first (no `\|\| true` on the git line), then `grep --null-data -E "$PATTERN" ... \|\| [ $? -eq 1 ]`, then `xargs -0 -a`. Fail arm: step fails. |
| `.claude/hooks/ship-cmo-content-gate.sh` : `CHANGED_MARKETING` | `^(...)` | C-quote, rename-away | IN (empty = deny, already fail-closed). |
| `.claude/hooks/ship-runbook-ssh-gate.sh` : `RUNBOOK_FILES` and the per-file re-diff | pathspec + word-split | C-quote makes the re-diff pathspec match nothing, so an ssh step in a runbook with a non-ASCII name passes | IN (Fork 7c): `-z` list into an array via `mapfile -d ''`, loop the array, `-- "$f"` with the raw name, `--literal-pathspecs`; keep the unknown-base fail-open. |
| `scripts/check-backstop-revision.sh` : `changed_files` | `grep -Fxq` against two fixed ASCII paths | rename-away | IN, shape-preserving: add `--no-renames` only. |
| `.claude/hooks/skill-security-scan.sh` : `override_present` | `grep -c '^knowledge-base/...'` | none live | EXEMPT (Fork 7b): "advisory breadcrumb only (always exit 0); override file names are ASCII slugs". |
| `preflight/SKILL.md` Step 0.1 and its two fallback `git diff` lines; `ship/SKILL.md` gdpr gate (two sites near the `CANONICAL_REGEX` blocks), DPF gate, and the `^\.github/(workflows\|actions)/` check; `review/SKILL.md` Change Classification block (name-only line) and the gdpr line | `^`-anchored / exact | C-quote, rename-away | IN via `changed-paths.sh` (Fork 6, 7g). |
| `ship/SKILL.md` : `LEDGER_TOUCHED`, `PLAN_REFS`, brand-guide check, the `--diff-filter` reads; `preflight` Check 3 (`--name-status`, status letters load-bearing); `review` `(^\|/)`-anchored domain-model check | count / unanchored / status letters | none live | OUT (skills are outside the sentinel; each carries its own pins). |
| `web-platform-release.yml`, `reusable-release.yml` (path-filtered `git diff --name-only`) | emptiness / pathspec-filtered | none live | EXEMPT, reason recorded in the sentinel table. |
| `skill-security-scan-postmerge.yml`, `pr-quality-guards.yml` `gh pr diff --name-only` readers, `ci.yml` `--raw` readers (`e2e`, `shard-totality-mutations` detect), hooks and top-level `scripts/` not listed above (about twenty sites: `pre-merge-rebase.sh`, `pre-push-ratchet-lane.sh`, `ci-battery-gate-replay.sh`, `weakness-miner.sh`, `lint-art30-reverification.sh`, ...) | various | not assessed | OUT, a known remainder: named in the sentinel header and the PR body, no filing (Fork 7h). The work phase re-runs the census with the regex in Phase 5 and adds any ^-anchored workflow site it finds. |

## Implementation Phases

Write the failing test first in every phase (`cq-write-failing-tests-before`), then the conversion. Run only the targeted suites by path; CI is the gate for
the battery (`ci-is-the-gate`, `session-state.md`). Commits are ordered so each is green on its own and the accept rows come last:

1. helper + its suite section; 2. workflow conversions + the step-exec section; 3. hooks, `scripts/` and `battery-refusal-wait.sh` flag appends + pin updates;
4. skill prose; 5. sentinel; 6. probe retirement, `queue-mode.md` observation, registries (accept rows in the final commit).

### Phase 1: the helper `plugins/soleur/scripts/changed-paths.sh`

Contract: `bash changed-paths.sh [--match ERE] <git diff args...>`.

- Plain mode: `set -o pipefail; git -C "$top" diff -z --no-renames --ignore-submodules=none --name-only "$@" | tr '\0' '\n'`, `$top` = `git rev-parse --show-toplevel`.
  Prints repo-root-relative paths, newline-separated; exit non-zero on any git failure (callers check the status; stdout is not trusted on failure).
  An empty diff exits 0 with empty stdout.
- `--match ERE` mode (grep exit semantics): runs git first and checks its status, then greps; prints the matching paths; exit 0 = at least one match,
  1 = none, 2 or more = git or usage failure. One construct, never `grep -q` on a pipe under pipefail (SIGPIPE 141 would read as failure).
- An empty argument list or an unknown flag exits 2 with a usage line on stderr; the helper never defaults to a diff target.
- Header comment: when to use this versus the inline `-z` form (skill prose uses the helper; workflow steps stay inline so `on.paths`-filtered gates do not depend on a plugin script).

Tests live in the single new suite `plugins/soleur/test/changed-path-readers.test.sh` (Fork 7f), section `helper`, scratch repos via
`plugins/soleur/test/lib/git-fixture-env.sh`: `é.tf`, tab, `"` and `\` names (precondition row: the PLAIN `git diff --name-only` really C-quotes each,
captured with its status so a failing git prints nothing, never `0`); rename-away; gitlink under a committed `ignore=all` and under a local
`diff.ignoreSubmodules=all`; `diff.relative=true` run from a subdirectory; `--cached` and `main...HEAD` argument forms; a failing-git shim (non-zero);
`--match` exits 0/1/2; empty args exit 2; control path outside any surface.

### Phase 2: workflow conversions (RED first), plus the step-exec section of the suite

Suite section `steps`, modelled on `ci-classify-step-exec.test.sh`: ONE `python3` call (PyYAML) extracts every target step's `run:` body by job id + step id;
each body runs under plain `bash -e {0}` (the weakest shell; Fork 7e) in a scratch repo cloned from ONE template repo (`cp -a` per row), with a shared
`DEFAULT_ENV` map (`BASE_REF`, `EVENT_NAME`, `BEFORE_SHA`, `MERGE_SHA`, `GH_TOKEN`, `MERGE_GROUP_BASE_SHA`, `BASE_SHA`, `HEAD_SHA`, named scenarios push / PR /
merge_group, per-step deltas only) and `GITHUB_OUTPUT` pointed at a file; the suite asserts each step's `env:` keys are a subset of `DEFAULT_ENV` and prints
"add KEY to DEFAULT_ENV" when not. Observable per step: the emitted flag (`directories=`, `docs=`, `sentry=`, `tenant=`, `vendor=`, `hit=`, `changed=`), the exit
code (`pr-quality-guards`: 1 vs "trivially passes"), or the selected file list and the linter argv (`secret-scan`).

Rows apply only where the defect is live; a not-live defect gets a control row that must stay green, never a skipped row:

- `^`-anchored steps (`infra-validation` both arms, `ci.yml` `filter`, `apply-sentry-infra`, `tenant-integration`, `vendor-pin-verify`, `constraint-gates-changed`, `secret-scan`
  selection steps): C-quoted name; rename-away; gitlink; failing-git shim with the per-site fail arm from the census; control outside the surface; surface-shape rows
  (top-level, single-ancestor, deep-nested) for pathspec-derived regexes.
- Shape-preserving steps (`trigger-canary`, `trigger-propagation`, `enforce-legal-lockstep` surface scan, `check-backstop-revision.sh`): one rename-away row and one
  control row; the `|| true` advisory behaviour is asserted UNCHANGED.
- `enforce-legal-lockstep`: a row where a required legal document is renamed away must still be reported missing (Fork 7d).
- `secret-scan`: `lint-fixture-files-pr` (two arms), `lint-fixture-files-nonpr` and the linter argv, with a name holding an accented byte and a quote reaching the linter intact
  through `xargs -0`; a failing-git shim must fail the step (not print "No fixture/golden/snapshot files in scope").

Conversion form at each `^`-anchored site: `if ! CHANGED=$(set -o pipefail; git diff -z --no-renames --ignore-submodules=none --name-only <range> | tr '\0' '\n'); then <fail arm>; fi`
(pipefail scoped to the substitution, so no later pipe in the step changes behaviour; steps that already carry step-level pipefail need no extra line).
`infra-validation.yml` `dirs` has no `CHANGED` variable today: both arms capture the diff first, then the existing chain reads `printf '%s\n' "$CHANGED"`. Existing pin
suites that extract these steps are updated in the same commit: `plugins/soleur/test/infra-validation-detect.test.sh` (TS15/TS18 extract the `dirs` step by its
`name:`), plus the result of `git grep -lE 'workflows/(infra-validation|apply-sentry-infra|tenant-integration|vendor-pin-verify|pr-quality-guards|secret-scan|ci)\.yml' -- '*.test.sh' tests`.

### Phase 3: the non-workflow readers

- `battery-refusal-wait.sh`: append `--ignore-submodules=none` to the four reads; update the header sentence to say the flag was added and the NUL form deliberately was not (Fork 3b).
  Tests in `ship-battery-refusal-wait.test.sh`: add an argv-recording git shim scenario per read that fails any `diff` invocation lacking `--ignore-submodules=none`
  (a fixture alone cannot kill one read, because a sibling read still shows the gitlink: committed gitlinks are seen by reads 1 and 4, worktree ones by 2 and 3), plus one defensive fixture
  (local `diff.ignoreSubmodules=all`, gitlink under `apps/web-platform/infra/`, expect `infra`), reusing the existing `scn_gitfail` shim pattern.
- `scripts/test-all.sh`: append `--ignore-submodules=none` to the six reads, inside the pinned text. Re-derive the pins by grep and run the four named suites FIRST; edit only the ones that go red.
  Known pins: `staged_anchor` in `test-all-affected.test.sh` (pins through `-M 2>/dev/null || true)"`); the `rename-sources-dropped` mutant strings in `test-all-pr-battery-gate.test.sh`;
  the `*"diff --name-only HEAD") exit 128` shim glob in `test-all-pr-battery-gate.test.sh` (end-anchored: appended flags make it never fire, so the `headfail` row would go vacuous; widen the glob);
  the `^\$\(git -c core\.quotePath=false diff --name-status -M ` regex in `test-all-infra-coverage-notice.test.sh`; `scripts/ci-battery-gate-replay.sh`; `tests/scripts/test-trio-baseline-census.sh`.
  Add argv-shim scenarios (a git shim failing any of the six reads that lacks the flag) to the infra-notice suite.
- `.claude/hooks/ship-cmo-content-gate.sh`: swap to the `-z` form; add rows to `ship-cmo-content-gate.test.sh` (non-ASCII marketing path).
- `.claude/hooks/ship-runbook-ssh-gate.sh` (Fork 7c): array read via `mapfile -d ''`, raw-name re-diff with `--literal-pathspecs`; add to `ship-runbook-ssh-gate.test.sh` an `é`-named runbook with an added
  `ssh prod-host` line that must block, a name with `*` or `[` that must not glob, and a control runbook that must pass.
- `scripts/check-backstop-revision.sh`: add `--no-renames`; add a rename-away row to `check-backstop-revision.test.sh`.
- `INFRA_RE` (Fork 1): one reason line in the `battery-owed.sh` header; no regex change.
- T19h pins the set of files that may name `gate-or-skip` or `--token-only` across `plugins/soleur/skills`, `plugins/soleur/scripts` and `.github/workflows`: no new or edited file in those trees
  (`changed-paths.sh`, the new suite, `queue-mode.md`, every edited SKILL.md) may add either string.

### Phase 4: skill prose through the helper

Record the byte delta BEFORE editing: ship has at least four in-scope sites at about +31 bytes each against 98 bytes of headroom; review two sites against 111; preflight has no ceiling.
Use `--match` at the gate sites so there is no pipe to lose the status: for example `bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" --match "$DPF_REGEX" origin/main...HEAD`,
branching on its exit status (0 = gate fires, 1 = not, 2 = treat as "gate applies" and say so). The two gdpr sites in ship share one invocation. preflight Step 0.1 redirects the
helper's output into `"$PREFLIGHT_TMP/preflight-diff-files.txt"` (non-zero exit keeps the stated "every check falls back" contract); its two fallback `git diff` lines are routed through the
helper too. review's Change Classification block converts the name-only line only (`--name-status` and `--numstat` stay). `python3 scripts/lint-skill-body-budget.py --base origin/main`
must exit 0 with no ceiling changed; an overshoot is paid by trimming prose in the same paragraph, never by raising a ceiling. No prose-text pin is added (it certifies spelling, not behaviour,
and every byte trim would risk reddening it).

### Phase 5: the sentinel (a section of the same suite)

Scan `git ls-files '.github/workflows/*.yml'`; strip comment lines; join `\` continuations; every `git [-c k=v ...] diff|log|show ... --name-only|--name-status|--raw` or `gh pr diff ... --name-only` site must carry a standalone
`-z` or appear in the exemption table (a data block at the top of the suite: `file<TAB>content-anchor<TAB>reason`, about three or four rows). Unlisted sites fail closed with `file:line`, the canonical string
`-z --no-renames --ignore-submodules=none --name-only` and "add `-z` or add a table row"; a table entry that no longer matches a site fails (stale); the scanned-file count has a floor. A pinned must-keep-`-z`
list names the converted hooks and scripts by content anchor (`ship-cmo-content-gate.sh`, `ship-runbook-ssh-gate.sh`, `changed-paths.sh`) and fails if any loses it. The header names what is NOT covered
(skill prose has its own pins; the hooks and top-level `scripts/` remainder; `--raw` readers) without citing an issue.

### Phase 6: retirement, records, registries

- `git rm scripts/followthroughs/sibling-changed-path-readers-12326.sh`; remove the `follow-through` label from #12332 BEFORE the merge is armed.
- `plugins/soleur/skills/ship/references/queue-mode.md`: one line, "Unreproduced (#12332): an expiry was observed while the required aggregate was not in the `pending` bucket; capture
  `gh pr checks <PR> --json name,bucket` at the expiry tick before changing the block."
- Registries for the one new suite: `scripts/suite-durations.tsv` (a MEASURED floor, not the 1222 default: run the suite once, set the floor from the measurement), `scripts/suite-shard-legs.tsv` (a leg),
  `scripts/lib/test-affected-paths.sh` (an `AFFECTED_PLUGINS_SOLEUR_TEST_CHANGED_PATH_READERS_TEST_SH_PATHS=(...)` declaration beside `..._CI_CLASSIFY_STEP_EXEC_TEST_SH_PATHS`, listing the workflow files,
  the converted hooks and scripts, the three SKILL.md files and `scripts/lib/test-affected-paths.sh` itself), then LAST `scripts/ci-pr-affected-audit.accept.tsv` rows keyed by 12-hex anchor citing `file:line`
  (sorted position; validate row shape first; re-derive after ANY later edit to the suite). `bash scripts/lint-orphan-test-suites.sh` must exit 0 with the new file tracked. Do not touch the stale-accept row for
  `real-sdk-ask-probe-workflow.test.sh`, `apps/web-platform/test/claude-pin-lockstep.test.ts`, `plugins/soleur/skills/cve-exposure/` or its `go.md` routing. Every new file that calls `mktemp` registers its
  EXIT trap before `source test-helpers.sh` in suites (`lint-trap-tempfile-ownership`).

### Phase 7: mutation battery (agent-run, results in the PR body)

For every guard in `## Guard Contract`: an unmutated green control, a mutation-landed check (the edit changed the file and landed the expected count), a lead-unique scratchpad file name per mutant. The
mutants run against COPIES by the agent; the suite itself holds only the unmutated rows, the harness rows and the floor assertions (so CI minutes are not multiplied). Two targeted fix rounds plus one
verification pass, then stop.

### Phase 8: ship-time and post-merge (agent-run)

PR body: `Closes #12332`, `Ref #12246`, `Filed: none` (net issue flow -1, confirmed by `net-issue-flow.sh`), the one Phase 7 line, the Fork 1 reason, a `## Changelog` section, a review-map table (mechanical flag
appends versus judgment hunks: the `secret-scan` NUL chain, the sentinel, the helper contract), and the known remainder from Fork 7h. Comment the same Phase 7 line on #12332. Before any push check
`bash plugins/soleur/scripts/sync-pr-behind.sh <PR> --queue-state`; never push to a queued PR; never `--admin`; never touch the ruleset; a second dequeue means stop and report. Check `git merge-tree` against
#12329 and #12168 before the first push; if the `ci.yml` detect-step hunks conflict, drop only the two guards-advisory steps and say so in the PR body. Required checks: `test`, `lockfile-sync`,
`markdown-lint`, `tenant-integration-required`; read `infra-validation` and `sandbox-canary-capture-gate` by hand when they appear. After merge: `deploy-arm.sh find --wait <full-sha>`,
`deploy-arm.sh served <full-sha>` = CONTAINS, and `/health` on app.soleur.ai with supabase connected.

## Files to Edit

- `.github/workflows/infra-validation.yml` (step `dirs`, both arms)
- `.github/workflows/ci.yml` (`detect-changes` step `filter`; `guards-advisory` steps `trigger-canary`, `trigger-propagation`)
- `.github/workflows/apply-sentry-infra.yml`, `tenant-integration.yml`, `vendor-pin-verify.yml` (the `filter` steps)
- `.github/workflows/pr-quality-guards.yml` (steps `enforce-legal-lockstep`, `constraint-gates-changed`)
- `.github/workflows/secret-scan.yml` (steps `lint-fixture-files-pr`, `lint-fixture-files-nonpr`, `lint-fixture-content`)
- `.claude/hooks/ship-cmo-content-gate.sh`, `.claude/hooks/ship-runbook-ssh-gate.sh`, `scripts/check-backstop-revision.sh`
- `plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh`, `plugins/soleur/skills/ship/scripts/battery-owed.sh` (header reason line only)
- `scripts/test-all.sh` (six reads in the `_diff_names` assembly)
- Pin and fixture updates (only where the targeted suites go red or a row is added): `scripts/test-all-affected.test.sh`, `scripts/test-all-infra-coverage-notice.test.sh`, `scripts/test-all-pr-battery-gate.test.sh`,
  `scripts/ci-battery-gate-replay.sh`, `tests/scripts/test-trio-baseline-census.sh`, `plugins/soleur/test/ship-battery-refusal-wait.test.sh`, `plugins/soleur/test/infra-validation-detect.test.sh`,
  `.claude/hooks/ship-cmo-content-gate.test.sh`, `.claude/hooks/ship-runbook-ssh-gate.test.sh`, `scripts/check-backstop-revision.test.sh`
- `plugins/soleur/skills/preflight/SKILL.md`, `plugins/soleur/skills/ship/SKILL.md`, `plugins/soleur/skills/review/SKILL.md`, `plugins/soleur/skills/ship/references/queue-mode.md`
- `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, `scripts/ci-pr-affected-audit.accept.tsv` (sorted-position rows only), `scripts/lib/test-affected-paths.sh` (one declaration)

## Files to Create

- `plugins/soleur/scripts/changed-paths.sh`
- `plugins/soleur/test/changed-path-readers.test.sh` (helper rows, step-exec rows, sentinel)
- `knowledge-base/project/specs/feat-one-shot-12332-sibling-changed-path-readers/tasks.md` (written at plan finalization; `decision-challenges.md` and `session-state.md` already exist)

## Files to Delete

- `scripts/followthroughs/sibling-changed-path-readers-12326.sh`

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` (limit 200) and searched each planned path in the bodies. The only issue naming these files is #12332 itself (label `deferred-scope-out`), which this PR
closes. No other open scope-out names a planned file: **None** to fold in, acknowledge or defer.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement issue #12332 as its own PR. Arc tracker: Ref #12246 only (never Closes). PR closes #12332" [brief] | Phase 8 PR body; frontmatter `closes: 12332` | mapped |
| 2 | "probe scripts/followthroughs/sibling-changed-path-readers-12326.sh must be updated/retired consistently" [brief] | Phase 6 `git rm` + label removal | mapped |
| 3 | "Files no new issue unless net flow nets out; declare net issue flow (`Filed: #N`)" [brief] | Phase 8 `Filed: none`, net -1 | mapped |
| 4 | "plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh (infra_state, ~273-282)" [brief] | Phase 3 first bullet (B', flag only) | mapped (form narrowed by Fork 3b) |
| 5 | "scripts/test-all.sh `_diff_names` (~2701-2741)" [brief] | Phase 3 second bullet (B, flag only) | mapped (form narrowed by Fork 3 and 7a) |
| 6 | "^-anchored regex readers in .github/workflows: infra-validation.yml ~411/423, ci.yml ~126, apply-sentry-infra.yml ~205, tenant-integration.yml ~117, vendor-pin-verify.yml ~100, pr-quality-guards.yml ~189" [brief] | Phase 2 | mapped |
| 7 | "skill prose in preflight/ship/review SKILL.md" [brief] | Phase 4 | mapped |
| 8 | "Reference implementation: plugins/soleur/skills/ship/scripts/battery-owed.sh" [brief] | Phase 1 helper uses its construction | mapped |
| 9 | "ship Phase 7 queue-wait expiry counts only NAMED required contexts as pending ... (add to #12332 if not fixed in this PR)" [brief] | Phase 6 line; Phase 8 PR + #12332 comment | mapped |
| 10 | "decide whether INFRA_RE should match infra-validation.yml's trigger set ... Send this fork to the soleur:engineering:cto agent" [brief] | Fork 1 ruling; Phase 3 reason line | mapped |
| 11 | "Mutation-battery discipline for any new guard: green unmutated control, mutation-landed check, lead-unique scratchpad file name; cap fix rounds at two targeted rounds plus one verification pass" [brief] | Phase 7, `## Guard Contract` | mapped |
| 12 | "Registry rows (scripts/ci-pr-affected-audit.accept.tsv, suite-durations.tsv, suite-shard-legs.tsv) go in sorted position" [brief] | Phase 6 registries | mapped |
| 13 | "Done = PR merged with required checks green, then `deploy-arm.sh find --wait <full-sha>` ..." [brief] | Phase 8 | mapped |
| 14 | "Write the ci-is-the-gate token into the session's session-state.md under ## Operator Constraints" [brief] | `session-state.md` written in this planning phase | mapped |
| 15 | "each reader needs its own test" [issue #12332] | Phases 1-3 rows | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Step-exec rows and per-reader hook rows | "each reader needs its own test" (ask 15) | asked |
| `changed-paths.sh` helper | — | inferred — justification: ship has 98 bytes and review 111 bytes of body-ceiling headroom, the inline form is +59 bytes per site, and a bare pipe loses git's exit status (CTO Fork 6, 7g) |
| Census sentinel (a section of the one suite) | — | inferred — justification: the #12326 learning says a fix to how a list is built is not closed until every consumer is enumerated; without a closed-set check the next workflow reader regrows the class (CTO Fork 5b, 7h) |
| `secret-scan.yml`, `ship-cmo-content-gate.sh`, `ship-runbook-ssh-gate.sh`, `check-backstop-revision.sh`, `ci.yml` guards-advisory steps, `pr-quality-guards.yml` `constraint-gates-changed` | — | inferred — justification: same defect class and the same swap found by the census; `secret-scan.yml` and `ship-runbook-ssh-gate.sh` are fail-open security selectors (CTO Fork 2, 7c) |
| `battery-owed.sh` header reason line | "decide whether INFRA_RE should match infra-validation.yml's trigger set" (ask 10) | asked |
| `queue-mode.md` observation | — | inferred — justification: #12332 closes with this PR so a comment on it becomes invisible, and the ship skill already routes a reader there on `queue_wait_expired` (CTO Fork 4b); the brief's "one line on the PR or on #12332" is satisfied separately |
| Registry rows and the `test-affected-paths.sh` declaration | "Registry rows ... go in sorted position" (ask 12) | asked |
| Pin updates in the `test-all` suites | — | inferred — justification: the Fork 3 flag append changes lines those suites pin by exact text; leaving them stale reddens required checks |
| Probe `git rm` and label removal | "must be updated/retired consistently" (ask 2) | asked |

### Split Assessment

- Subsystems touched: 5 — `.github`, `.claude`, `scripts`, `plugins/soleur`, `tests`
- Planned files: 31 | Estimated changed lines: about 900 (tests dominate)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — over every threshold by count, but the brief fixes the unit ("as its own PR", closing #12332) and every file carries the same defect class. The considered seams (workflows plus hooks vs. test-all plus skills) would each leave #12332 half-closed; the commit order in Implementation Phases makes each part revertable on its own, and the helper plus its rows land first.

## Guard Contract

### Guard 1 — workflow step-exec rows

**Property.** Each converted workflow step, executed under plain `bash -e {0}`, classifies a PR whose only qualifying change is a C-quoted name, a rename away from the surface (where the matcher is not an exact-file check), or a config-hidden gitlink as touching the surface, and fails toward running or blocking when git fails.

**Assembly.** The chokepoint is the one diff construction inside each step's `run:` body, reached by `job id + step id` extraction in one PyYAML call. Members: `infra-validation.yml` `dirs` (TWO arms in one step), `ci.yml` `filter` / `trigger-canary` / `trigger-propagation`, `apply-sentry-infra.yml` `filter`, `tenant-integration.yml` `filter`, `vendor-pin-verify.yml` `filter`, `pr-quality-guards.yml` `enforce-legal-lockstep` / `constraint-gates-changed`, `secret-scan.yml` `lint-fixture-files-pr` (two arms) / `lint-fixture-files-nonpr` / `lint-fixture-content`. The list is a snapshot; the population is derived by the sentinel (Guard 2) and the extracted-step count has a floor.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `-z` from one `^`-anchored step (copy of the YAML) | RED: that step's C-quoted-name row |
| 2 | Drop `--no-renames` from one step (any converted step, including the shape-preserving ones) | RED: that step's rename-away row |
| 3 | Delete the scoped `set -o pipefail;` from `infra-validation.yml` `dirs` or `ci.yml` `filter` (the two steps with no step-level pipefail) | RED: failing-git shim row under `bash -e {0}` |
| 4 | Own dispatch: rename a step id so extraction finds zero steps | RED: extracted-step count below the floor, never "0 checked, exit 0" |
| 5 | Second member: revert ONLY the PR arm of `infra-validation.yml` after the push arm is compliant | RED: the PR-arm row (a check that stops at the first member is the defect) |
| 6 | Drop `--ignore-submodules=none` from one `^`-anchored step | RED: its gitlink row |
| 7 | Keep `-z` on `secret-scan.yml`'s diff but drop `-0` from the `xargs` (or restore `|| true` on the git line) | RED: the quote/backslash name must reach the linter argv intact / the failing-git row must fail the step |
| 8 | Drop `-z` from `lint-fixture-files-nonpr` only (the separate push/schedule step) | RED: its push-event row |
| 9 | Make `enforce-legal-lockstep` read the required-files list through `--no-renames` | RED: the legal-doc rename-away row (must still report the document missing) |

Harness rows: (H1) edit the SUITE so a C-quoted fixture name is plain ASCII: RED via the precondition assertion that the plain diff really C-quotes it. (H2) must-PASS inputs that are not the canonical: an `é.tf` under a directory OUTSIDE every surface expects the skip flag, and a deeper-nested surface path than the canonical expects the surface flag. (H3) the suite fails if it reaches its pass line with zero rows executed.

**Anchor.** The stored values are the `DEFAULT_ENV` map and the expected-flag map in the suite. A diff that edits a workflow and the suite together proves consistency, not integrity; the outside mover is the required `test` check executing the suite against the PR's own YAML, plus the reviewer reading the diff of the maps. Said plainly rather than claimed as integrity.

### Guard 2 — workflow census sentinel

**Property.** Every `git diff|log|show` (including the `-c k=v` spelling) or `gh pr diff` site that lists names in `.github/workflows/*.yml` is NUL-delimited (`-z`) or listed in the exemption table with a reason, and the converted hooks and scripts keep `-z`.

**Assembly.** One chokepoint: the scan over `git ls-files '.github/workflows/*.yml'` (tracked files, not the working directory) after stripping comment lines and joining `\` continuations, plus a pinned list of the converted hook and script files by content anchor. The exemption table is keyed by file plus content anchor (never a line number); stale entries fail. Hooks and top-level `scripts/` are outside the scan by CTO ruling and the header says so.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add an unlisted `git diff --name-only \| grep -E '^x'` site to a workflow copy | RED: unlisted site, with `file:line` |
| 2 | Remove `-z` from a converted workflow site | RED |
| 3 | Own dispatch: point the scan glob at a nonexistent path | RED: scanned-file count below the floor |
| 4 | Second member: two sites in one file, exempt only the first | RED for the second (entries are per site, not per file) |
| 5 | Delete a reader but keep its exemption entry | RED: stale entry |
| 6 | Remove `-z` from `ship-runbook-ssh-gate.sh` (a pinned must-keep file) | RED: pinned list |
| 7 | After the change lands: the new explanatory comments added by this PR contain the scanned phrase | stays GREEN (comments are stripped; the remediation's own text must not match the classifier) |

Harness rows: (H1) a comment line that mentions `git diff --name-only` stays GREEN while the same text inside a `run:` string literal stays RED (control for the comment-stripping step). (H2) must-PASS: a site written with `-c core.quotePath=false diff -z ...` passes.

**Anchor.** The exemption table can be edited in the same diff that adds a reader, so this guard proves consistency. The independently checkable bound is the reviewer reading each reason line; the table is expected to stay at about three or four rows.

### Guard 3 — `changed-paths.sh` contract

**Property.** The helper prints exact repo-root-relative paths, exits non-zero whenever git fails, and in `--match` mode keeps a git failure (2) distinct from "no match" (1).

**Assembly.** One construction in one script, reached by every skill-prose caller. A second entry path (`--match`, argument parsing) is covered by its own rows.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `-z` | RED: C-quoted-name rows |
| 2 | Drop `set -o pipefail` (bare pipe) | RED: failing-git shim row (exit 0 on a git failure is the defect) |
| 3 | Own dispatch: empty argument list | RED if it does anything but exit 2 with usage |
| 4 | Drop `git -C "$top"` | RED: the `diff.relative` run-from-subdirectory row |
| 5 | Drop `--no-renames`, or drop `--ignore-submodules=none` | RED: rename-away row / gitlink row |
| 6 | `--match`: let a git failure fall through as "no match" (exit 1) | RED: the failing-git `--match` row must be exit 2 |
| 7 | Second member: a name containing a newline | the list splits into extra lines but never hides the prefix line (asserted GREEN, documented) |

Harness rows: (H1) must-PASS: a clean repo with an empty diff exits 0 with empty stdout. (H2) `--match` with a pattern matching nothing exits 1, not 0.

**Anchor.** Not a stored-value comparison: the guard compares behaviour with git, so no outside mover is needed.

### Guard 4 — argv-shim rows for the non-workflow readers

**Property.** Every `git diff` read in `battery-refusal-wait.sh` `infra_state` and in the `test-all.sh` `_diff_names` assembly carries `--ignore-submodules=none`.

**Assembly.** `infra_state` has FOUR reads (committed range, worktree, and two `--name-status -M`); `test-all.sh` has SIX. A gitlink fixture alone cannot kill one read, because a sibling read still shows the gitlink, so the per-read kill uses an argv-recording shim that fails any `diff` invocation lacking the flag.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the flag from the committed-range read of `infra_state` | RED: that read's shim scenario |
| 2 | Drop it from the worktree `--name-status -M` read (second member) | RED: that read's shim scenario |
| 3 | Own dispatch: make `infra_state` print `clean` unconditionally | RED: the existing infra fixtures (`IW_PREFIX`) |
| 4 | Drop the flag from any one of the six `test-all.sh` reads | RED: that read's shim scenario in the infra-notice suite |
| 5 | Drop `-z` from `ship-cmo-content-gate.sh` or `ship-runbook-ssh-gate.sh` | RED: each suite's non-ASCII-name row (the runbook row must BLOCK) |
| 6 | Drop `--literal-pathspecs` from `ship-runbook-ssh-gate.sh` | RED: the `*` / `[` name row |

Harness rows: (H1) a gitlink OUTSIDE `apps/web-platform/infra/` stays `clean`. (H2) must-PASS: the near-miss directory fixture (`IW_NEAR`) stays `clean`.

**Anchor.** The trigger-literal pair is pinned against the live runner by the existing F13 parity row, left intact; a change to either literal reddens F13 without the same diff being able to edit a stored value to pass it.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash plugins/soleur/test/changed-path-readers.test.sh` exits 0 and prints the executed-step count, `census: N sites, 0 unlisted, 0 stale`, and the helper-row count; each is asserted against a floor inside the suite.
- [ ] Phase 7 results are in the PR body as "N killed + M controls green" per guard, with the real counts (Guard 1: 9 mutations, all killed; Guard 2: 6 killed + 1 control; Guard 3: 6 killed + 1 documented control; Guard 4: 6 killed), each preceded by a green unmutated control and a mutation-landed check.
- [ ] `grep -cE 'git -C "\$top" -c core\.quotePath=false diff .*--ignore-submodules=none' plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh` prints 4, and the same flag appears on all six reads in `scripts/test-all.sh` (`grep -cE '\$\(git -c core\.quotePath=false diff [^)]*--ignore-submodules=none' scripts/test-all.sh` prints 6); the pin suites `test-all-affected`, `test-all-infra-coverage-notice`, `test-all-pr-battery-gate`, `ship-battery-refusal-wait` and `infra-validation-detect` pass when run by path.
- [ ] `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0; no ceiling in `plugins/soleur/test/skill-body-budget.json` changed.
- [ ] `git ls-files scripts/followthroughs/sibling-changed-path-readers-12326.sh` is empty; `git grep -ln sibling-changed-path-readers -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'` prints nothing; `gh issue view 12332 --json labels` shows no `follow-through` label before the merge is armed.
- [ ] `bash plugins/soleur/skills/ship/scripts/net-issue-flow.sh <PR>` prints NET <= 0; the PR body carries `Closes #12332`, `Ref #12246`, `Filed: none`.
- [ ] `bash scripts/lint-orphan-test-suites.sh` exits 0; registry rows for the one new suite are in sorted position in all three TSVs; accept-row anchors re-derived after the last edit to the suite; `[ "$(git diff -U0 origin/main...HEAD -- scripts/ci-pr-affected-audit.accept.tsv | grep -c '^[-+].*real-sdk-ask-probe-workflow')" = 0 ]` and `git diff --quiet origin/main...HEAD -- apps/web-platform/test/claude-pin-lockstep.test.ts`.
- [ ] `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0.
- [ ] Tripwire, not proof: `[ "$(git diff --name-only origin/main...HEAD | grep -c -e cve-exposure)" = 0 ]` (the directory does not exist on this tree, so this guards a future creation only).
- [ ] CI required checks green: `test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required`; `infra-validation` and `sandbox-canary-capture-gate` read by hand when they appear.

### Post-merge (agent-run)

- [ ] `bash plugins/soleur/scripts/deploy-arm.sh find --wait <full-sha>` resolves; `bash plugins/soleur/scripts/deploy-arm.sh served <full-sha>` prints CONTAINS; `curl -s https://app.soleur.ai/health` reports supabase connected.

## Test Scenarios

- Given a PR whose only infra change is `apps/web-platform/infra/é.tf`, when the converted `infra-validation.yml` step runs (unit, executed step), then `directories` lists `apps/web-platform/infra`; the same for tab, `"` and `\` names.
- Given a PR that renames `apps/web-platform/infra/a.tf` to `docs/a.tf`, when each `^`-anchored detect step runs, then the flag is true (the old path is listed).
- Given a PR that renames `docs/legal/privacy-policy.md` away, when `enforce-legal-lockstep` runs with a DSAR surface file touched, then the document is still reported missing.
- Given `git` exits 128 inside a `bash -e {0}` step, when each `^`-anchored step runs, then it takes its per-site fail arm (all infra roots / `docs=true` / `::error::` exit 1) and never emits a skip flag.
- Given `diff.ignoreSubmodules=all` in the fixture's local config and a gitlink under the surface, when `infra_state` runs, then it echoes `infra` (defensive; this repo has no gitlinks).
- Given an `é`-and-quote-named file in `apps/web-platform/test/fixtures/`, when the secret-scan selection steps run on a PR and on a push, then the name reaches the linter argv intact through `xargs -0`.
- Given a runbook `knowledge-base/engineering/operations/runbooks/é.md` with an added `ssh prod-host` line, when `ship-runbook-ssh-gate.sh` runs, then it blocks.
- Given an unlisted `git diff --name-only | grep -E '^x'` site is added to a workflow, when the census runs, then it fails naming `file:line`.
- Given the plain `git diff --name-only` of each fixture, then it C-quotes the name (precondition; captured with status so a failing git prints nothing).
- Regression: `battery-owed.sh` T20 rows and `ship-battery-owed` T19h closed set stay green (no new file names the token).

## User-Brand Impact

- **If this lands broken, the user experiences:** a CI gate that silently skips on a PR touching the infra, tenant-isolation, vendor-pin, secret-scan or runbook-ssh surface and reports green (the silent-skip class #4012 hit), or a detect step that fails closed and blocks every merge.
- **If this leaks, the user's workflow is exposed via:** a fixture or golden file whose C-quoted name drops out of the secret-scan selection and merges unscanned, or a runbook with a non-ASCII name that adds an ssh fallback past the runbook gate.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the exposure needs a specially named file AND a secret or ssh step in it AND a reviewer missing both; it is a class of silent skips across many PRs, not one user's breach, so `aggregate pattern` rather than `single-user incident`.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Seventeen technical rulings (`decision-challenges.md`): `INFRA_RE` unchanged; census extras folded in; `test-all.sh` and `battery-refusal-wait.sh` keep their shape and gain `--ignore-submodules=none` only; Phase 7 expiry not fixed without data; one step-exec suite under the weakest shell plus a workflows-only sentinel; one tested helper with a `--match` mode for skill prose; `ship-runbook-ssh-gate.sh` in, `skill-security-scan.sh` out. Product, marketing, legal, finance, operations, sales and support: no implications (no user-facing page, copy, data schema, contract or spend). No UI-surface file in Files to Edit or Create, so the Product/UX gate does not apply.

Other gates considered and skipped: GDPR gate (no regulated-data surface; `secret-scan.yml` changes a selector, not a data flow); IaC routing (no server, secret or vendor); Encryption Posture (no store or connection); Task Design (no new autonomous surface; the new suite is a test, not a task); Architecture Decision (no ownership, substrate or trust-boundary change and no ADR reversed: the construction is the repo-native shape, so no ADR/C4 deliverable).

## Plan Review Disposition

Panel: DHH, Kieran, code-simplicity (with Property List, Cut List and Scope Check fed in) and the CTO devex lens; plus a sharp-edges verification pass. Applied (mechanical): secret-scan push step and capture-first form; pipefail scoped to the substitution and a per-site fail-arm table; `infra-validation` capture-first and its pin suite; argv-shim rows per read; the two extra pins in the `test-all` suites; sentinel scope flip; one suite instead of three; `queue-mode.md` wording; helper `--match` mode and no-args exit 2; AC rewritten with real counts and discriminating commands; ruling-row shapes; affected-index declaration; byte-delta pricing; commit order and review map. Applied (CTO Fork 7): `--no-relative` dropped; `skill-security-scan.sh` exempt; `ship-runbook-ssh-gate.sh` in; legal-docs read stays destination-only; weakest-shell harness. Declined with reason: DHH's "leave `test-all.sh` untouched" (the brief names it; latent value stated honestly) and DHH/CTO's "spend the one filing on Phase 7" (the brief says do not file separately; the `queue-mode.md` line cures the invisibility). Left to the work phase: confirm each EXEMPT site by reading it; re-run the census regex and add any other `^`-anchored workflow site.

## Observability

`plugins/soleur/scripts/changed-paths.sh` is a new script under `plugins/soleur/scripts/`, so the gate applies. It runs synchronously inside agent steps; its signal is its exit status and stderr.

```yaml
liveness_signal:
  what: per-invocation exit status and stderr of changed-paths.sh, visible in the calling skill step's own output
  cadence: per invocation (each preflight, review and ship run)
  alert_target: the calling skill step takes its documented failure path; CI runs the helper rows on every PR via the required test check
  configured_in: plugins/soleur/scripts/changed-paths.sh and plugins/soleur/test/changed-path-readers.test.sh

error_reporting:
  destination: stderr plus a non-zero exit code; the workflow readers surface failures as ::error:: annotations or their documented fail-safe output on the PR run
  fail_loud: a git failure exits non-zero (2 in --match mode) with a one-line "changed-paths: git diff failed" message, never an empty list read as no change

failure_modes:
  - mode: git cannot resolve the range (shallow clone, missing origin/main)
    detection: non-zero exit; callers take the documented fallback (preflight: every check falls back; ship and review gates: gate applies)
    alert_route: the calling step's own output and the required test check on this PR
  - mode: a converted workflow step loses its scoped pipefail in a later edit
    detection: the failing-git shim row in changed-path-readers.test.sh
    alert_route: required test check goes red on the PR that regresses it
  - mode: a new unconverted reader is added to a workflow
    detection: the census sentinel
    alert_route: required test check goes red on that PR

logs:
  where: GitHub Actions step logs for the workflow readers; the agent transcript for the skill readers
  retention: GitHub Actions default run-log retention

discoverability_test:
  command: bash plugins/soleur/scripts/changed-paths.sh origin/main...HEAD
  expected_output: plugins/soleur/scripts/changed-paths.sh
```

## Sharp Edges

- A workflow step with no `shell:` key runs `bash -e {0}` with NO pipefail: `if ! X=$(git diff -z ... | tr '\0' '\n')` is then fail-open (tr's status wins). Scope `set -o pipefail;` inside the substitution; the suite runs every body under plain `bash -e {0}`.
- Some dev hosts alias `grep` to ugrep, where short `-z` means decompress (silently matches nothing) and `\b` is not a word boundary; CI uses GNU grep. Use `tr '\0' '\n'` or `grep --null-data`; no `\b` in new regexes or tests. Never `producer | grep -q` under pipefail (SIGPIPE 141 reads as failure).
- `xargs -a file` treats `"` and `\` as quoting characters: the secret-scan chain must end in `xargs -0 -a`; and a `|| true` on the git line of a selection arm turns a git failure into the "No fixture/golden/snapshot files in scope" success.
- `--no-renames` is not always the stricter choice: an exact-file "was this document updated" check (the legal-docs read) gets weaker with it. Decide per matcher, not per file.
- Exact-text pins: re-derive by grep (`diff --name-status -M`, `diff --name-only`, `staged_anchor`, the end-anchored `*"diff --name-only HEAD") exit 128` shim glob) before editing a `test-all.sh` read; the flag lands INSIDE pinned text. The infra suite extracts the assembly by awk range ending at the first `git ls-files --others` line, so never wrap or reorder those lines. Run the pin suites first and edit only the red ones.
- Skill body ceilings only ratchet down and are read from the merge base: pay an overshoot by trimming prose in the same paragraph. `battery-owed.sh` T19h pins the set of files naming the wrapper token across `plugins/soleur/skills`, `plugins/soleur/scripts` and `.github/workflows`: no new or edited file there may add `gate-or-skip` or `--token-only`.
- Accept rows cite `file:line` under a 12-hex anchor: any insertion in a registered suite shifts them. Write them last; re-derive after every later edit; one malformed row drops every exemption. A new suite also needs an `AFFECTED_..._PATHS` declaration or the orphan lint reds.
- A gitlink fixture cannot kill one `git diff` read when a sibling read also shows it (committed: reads 1 and 4; worktree: reads 2 and 3). Kill each read with an argv-recording shim.
- A name containing a newline splits into extra lines that can only add a false positive, never hide the prefix line.
- Names reach `git diff -- "$f"` as pathspecs: pass `--literal-pathspecs`, or a name with `*` or `[` globs.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.
- Rebase risk: PR #12329 edits `ci.yml`, `test-all.sh` and the three TSVs; PR #12168 edits `infra-validation.yml`. Check `git merge-tree` before the first push; if the `ci.yml` detect-step hunks conflict, drop only the two guards-advisory steps (CTO Fork 2 flip) and say so in the PR body.

## References

- Issue #12332; PRs #12326 (reference fix), #12357 (this branch); arc PR #12246 (`Ref` only); #6480 (no required check on `apps/web-platform/infra`).
- `plugins/soleur/skills/ship/scripts/battery-owed.sh` (reference construction, `INFRA_RE`), `plugins/soleur/test/ci-classify-step-exec.test.sh` (step-exec precedent).
- `knowledge-base/project/learnings/2026-11-07-fixing-the-source-of-a-path-list-left-its-classifier-and-my-own-preconditions-failing-open.md`.
- `knowledge-base/project/specs/feat-one-shot-12332-sibling-changed-path-readers/decision-challenges.md` (all rulings), `session-state.md` (Operator Constraints).
