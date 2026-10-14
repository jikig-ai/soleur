# Tasks: fix — PIR no-item sentinel vs MD049, adr-ordinals is required (#7941), bun-test hook on merge commits

Plan: `knowledge-base/project/plans/2026-09-11-fix-pir-gate-md049-adr-ordinals-merge-hook-plan.md`
(deepened 2026-09-11 — the plan's Design "The script" / "The caller" / "The suite" subsections are
the contract for 1.1-1.7).

## Phase 1: Thread 1 — extract, prove parity, then widen (RED first)

- [x] 1.1 Create the twelve fixtures (23 after review: legacy marker forms committed, nine panel-found shapes added; `expect:` token sits after the frontmatter fence) under `plugins/soleur/test/fixtures/ship-pir-action-items/`
      (`pass-table-all-issued.md`, `pass-sentence.md`, `pass-subheading-inside-section.md`,
      `fail-table-missing-issue.md`, `fail-table-tbd-placeholder.md`, `fail-header-only-table.md`,
      `fail-bullet-list.md`, `fail-empty-section.md`, `fail-no-heading.md`, `fail-sentence-bold.md`,
      `fail-instructional-prose-only.md`, `fail-sentence-in-later-section.md`), each with a
      first-line `<!-- expect: pass -->` / `<!-- expect: fail/<reason> -->` token.
- [x] 1.2 Write `plugins/soleur/test/ship-pir-action-items-gate.test.sh` — sources
      `test-helpers.sh`, `export LC_ALL=C`, `set +e; …; rc=$?; set -e` captures, all writes under
      `mktemp -d`; five arms: fixture (name-derived rc + `expect:` token agreement + reason on
      stderr + hard floors (`pass_n >= 6` / `fail_n >= 17` after review) + unknown prefix aborts + committed
      legacy `_…_`/`*…*` fixtures + exit 2 on a missing path + symlink/usage arms), template parity
      (`grep -oE 'write exactly `[^`]+`' pir.md | sed …`, cardinality 1, plain-form assertion,
      synthesised PIR passes, fixed-string greps on `incident/SKILL.md` and `dry-run.sh`), corpus
      (`--corpus`; anchored summary regex; `failed=0`; `selected == examined + skipped`;
      `selected >= 50`; SKIP only when `scripts/test-all.sh` is absent), branch (fixture repo via
      `git_fixture_env` before `git init`; `refs/remotes/origin/main`; A modified / B unbacked /
      C renamed / D deleted → exit 1 with verdicts for A, B, C-new; no-PIR branch → exit 3;
      no-`origin/main` repo → exit 2), wiring (invocation form, `rc=$?`, `3)` arm,
      `SOLEUR_SHIP_PIR_GATE_HALT`, ERE absent from the Incident-PIR section, three conjunct-1
      paths). Run it: RED.
- [x] 1.3 Step A — write `plugins/soleur/skills/ship/scripts/ship-pir-action-items-gate.sh`
      (`set -uo pipefail`; `--branch` with `git diff --name-only --no-renames --diff-filter=d
      origin/main...HEAD` run on its own and exit 2 on git failure; `--corpus`; `<path>`; exit
      0/1/2/3; `[PASS]`/`[FAIL] <path>: <reason>` per file; executable bit; no literal `/tmp`; no
      emphasised sentence in comments; fence-unaware limitation stated) with the block's ORIGINAL
      anchor. `--corpus` must report `selected=119 examined=103 skipped=16 failed=9`, the nine
      failures being exactly `grep -l '^\*No action items' <PIR dir>/*.md`. Record the line.
- [x] 1.4 Step B — widen the anchor to `^[_*]?…` with the frozen-class comment. `--corpus` →
      `failed=0`. Fixture, corpus and branch arms GREEN; template-parity still RED.
- [x] 1.5 Change the three authoring sites to the plain sentence: `pir.md:135`,
      `incident/SKILL.md:224`, `dry-run.sh:385`. Template-parity arm GREEN.
- [x] 1.6 One-time RED check: Guard 1 mutation rows #2, #3, #6, #10, #12 applied and observed RED,
      reverted; five one-line observations for the PR body.
- [x] 1.7 Rewire `ship/SKILL.md` Phase 5.5 per "The caller": remove the `:1122` selector line and
      the inline block; insert the `--branch` invocation + `rc=$?` + four-arm `case` (0 pass /
      1 fix-and-rerun / 3 No-match arm / * `SOLEUR_SHIP_PIR_GATE_HALT`), stderr never redirected;
      replace the `bad`-variable sentence at `:1154`; check 1 reads paths from `[PASS]` lines;
      legacy forms described as "an optional leading `_` or `*` marker" (never spelled); no
      backtick-wrapped `scripts/…`-relative path in new prose; "do NOT re-inline" comment;
      meta-case conjunct 1 gains the three new paths. Wiring arm GREEN.

## Phase 2: Thread 2 — five prose sites

- [x] 2.1 `ship/SKILL.md:2083` — the explaining paragraph: `adr-ordinals` is required
      (`scripts/required-checks.txt`, `infra/github/ruleset-ci-required.tf`, `gh api` probe);
      strict up-to-date policy; BEHIND sync → red `adr-ordinals` on the PR → required-check-failure
      exit; recovery steps unchanged.
- [x] 2.2 `ship/SKILL.md:1435`, `:1481` — defense-in-depth rationale + Why written in the positive
      (#6049/#6050 landed it), pointing at Phase 7. No "not" adjacent to "required" in any tense.
- [x] 2.3 `ship/SKILL.md:359` — "tracked as #6480". `:2120` — drop the literal context count AND
      add "present and green on the current SHA" to the settle-then-admin-merge hatch's step 2.
- [x] 2.4 `plan/SKILL.md:698` — corrected parenthetical.
- [x] 2.5 ADR-156 ordinal note — one bracketed correction citing #7941.
- [x] 2.6 AC7 grep returns no `not a required` / `non-required` / `not required` /
      `not yet required` / `until/unless that lands` line.

## Phase 3: Thread 3 — the skip

- [x] 3.1 `lefthook.yml` `bun-test`: add `skip: [merge]` with the comment (no pre-push net; CI is
      the gate; clean merges never reached the hook; `run:` unchanged).
- [x] 3.2 `ship/SKILL.md:1875` — one clause: the hook skips merge commits, no `--no-verify`.
- [x] 3.3 Scratchpad probe, five cases (plain-repo merge, linked-worktree merge, merge with
      `.md`-only resolution, `.ts` commit, `.md`-only commit) asserting the exact marker per case
      (`(skip) by condition` / `PROBE-RAN` / `(skip) no matching staged files`); five lines for
      the PR body.
- [x] 3.4 `fanout-suite-scope.test.sh` and `hook-git-env-coverage.test.sh` green; AC11 PyYAML
      assertion (skip == [merge], glob unchanged, no other skip) prints `ok`.

## Phase 4: Gates and verification

- [x] 4.1 `bash scripts/markdown-lint.sh --repo-sweep` exits 0; `bash scripts/lint-orphan-test-suites.sh` exits 0.
- [ ] 4.2 Touched shards: `TEST_GROUP=scripts` (the new suite is auto-globbed there) green; — REFUSED at /work exit (rc=4: five sibling full-gate runs in flight; runner prescribed targeted suites, which ran green: new suite 80/0, fanout-suite-scope 36/0, hook-git-env-coverage, c4-count-parity, components+scratch-path 1300/0, adr-frontmatter/gdpr-gate/ship-incident-pir-gate 91/0, plus every other suite reading a touched file). Full battery runs at ship Phase 4 (ADR-183).
      `c4-count-parity` in that shard green.
- [x] 4.3 PR body: `Closes #7941`; "#6480 exists"; Thread 3 decision paragraph; `head -n1` fix as
      its own line; signal-scan shipped-location gap noted; `:2120` note; parity + mutation +
      probe lines; the `[PASS]`-line convention note; no `Filed:` line. `OUTAGE_RE` terms only
      inside fenced blocks/backticks; `PROD_RE` terms (`prod`, `production`, `deployed`, `live`,
      `customer`) absent from prose.
- [x] 4.4 `bash scripts/ship-incident-pir-gate.sh --pr <N>` → exit 1, no `INCIDENT-SIGNAL` line —
      the only legal exit for this PR; reword until it holds.
- [x] 4.5 `net-issue-flow.sh <PR>` → NET −1 (or 0), exit 0.
- [x] 4.6 AC17: no file under `knowledge-base/engineering/operations/` in the diff.
- [x] 4.7 Walk every AC in the plan and check it off.
