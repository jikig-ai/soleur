# Tasks: convert the remaining changed-path readers (D7 remainder)

Plan: `knowledge-base/project/plans/2026-11-09-fix-convert-remaining-changed-path-readers-plan.md`. Every conversion is RED-first: commit the failing suite row, then convert. CI required checks are the gate; no local affected-battery run.

## Phase 1 - Wave 1: hooks, scripts, lints, app scripts

- [x] 1.1 `scripts/pre-push-ratchet-lane.sh`: `-z --no-renames --ignore-submodules=none | tr` for the two diff reads; `--ignore-submodules=none` on the quiet diff; `--no-renames` on the name-status checks; suite rows (rename-away from `ci.yml`, tab-named suite, gitlink-only branch); check the `KB_CONSUMERS_INPUTS` exact-line observation
- [x] 1.2 `.claude/hooks/pre-merge-rebase.sh`: append `--ignore-submodules=none` to the two disjointness reads only; keep the todos `git log` read and the `--diff-filter=U` listing; suite row for a gitlink changed on both sides
- [x] 1.3 `scripts/hooks/pre-push`: append `--ignore-submodules=none`; gitlink-only-push case or PINNED_Z pin
- [x] 1.4 `plugins/soleur/scripts/affected-tests.sh`: four legs `-M` to `--no-renames` plus `--ignore-submodules=none`; rename-into-docs row and gitlink row
- [x] 1.5 `plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh`: `OWN_FILES` via `-z | tr` with a gated status (script has no `-e`); leave `OWN_STATS` and `own_pid`; update `# mut:norenames` marker, mutation string and text pin
- [x] 1.6 Python lints (credential-path-literals, infra-no-human-steps, shell-trace-credential-refusal): `-z --no-renames --ignore-submodules=none`, `.split("\0")`, `git_out_z`; non-ASCII and failing-git rows
- [x] 1.7 `apps/web-platform/scripts/lint-migration-fk-preconditions.sh`: exit-status-gated capture, `--no-renames`; `--from-pr-diff` rows
- [x] 1.8 `apps/web-platform/scripts/allowlist-diff.sh`: `git -C "$REPO_ROOT"` pathspec read `':(top,literal).gitleaks.toml'` with `|| exit 2` and an `::error::` line (smoke case `allowlist-diff-fires`); create `scripts/allowlist-diff.test.sh` (NOT under apps/web-platform/scripts: ARM 5c) with its own floor
- [x] 1.9 `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh`: keep override precedence via `${VAR+x}`, pipefail git arm, separate `git_failed` flag OR-ed into `capture_trigger` after its `=0` line; scratch-repo rows; script runs under required `lockfile-sync`
- [x] 1.10 `apps/web-platform/scripts/real-sdk-ask-probe.sh` (drop-first)
- [x] 1.11 `apps/web-platform/scripts/rename-guard.sh`: fail-closed line form (CTO G1): capture to file, no `|| true`, `LC_ALL=C` on awk and every `grep -P`, exit 2 on a path starting with `"`; suite rows (a)-(f)
- [x] 1.12 `plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts` (drop-first)

## Phase 2 - Wave 2: workflows and .github/scripts

- [x] 2.1 `web-platform-release.yml` trigger step: `previous_filename`, `.files|length >= 300` reads as triggered, empty pattern set fails; ADD to `STEP_MANIFEST` (no suite runs it today)
- [x] 2.2 `registry-host-replace-dispatch.yml`: `previous_filename`, `(.files|type)=="array"` check; rename-capable `gcompare` builder and rename rows for three render inputs
- [x] 2.3 `fix-constraints-stage-a.yml` + template + `.emitted.sha256` (drop-first)
- [x] 2.4 `ci.yml` trigger-canary and trigger-propagation: pipefail `-z` capture, failure sets `hit=1`; steps ALREADY in `STEP_MANIFEST` - flip the existing `hit 0` git-failure expectation to `hit 1`; delete both exemption rows
- [x] 2.5 `pr-quality-guards.yml` stray-worktree-marker step: LOCAL inline git form (CTO G4), failure fails the step; `detect` emits `worktrees=true` at the 3000 cap; add both to `STEP_MANIFEST`; delete exemption row
- [x] 2.6 `.github/scripts/check-sweep-completeness.sh`: `[\r\n]` refusal on all three routes before the CR strip, 3000 cap exits 1, no `previous_filename`; PATH-shim `gh` derivation rows

## Phase 3 - Wave 3: prose, references, agents

- [x] 3.1 `ship/references/settle-then-admin-merge.md`: INLINE `-z | tr` classifier (CTO G2, runs before the `_top` guard); PINNED_Z row; allowlist breadth is a PR-body observation
- [x] 3.2 `counsel-review-clo-attestation.md` (`main...HEAD` -> `origin/main...HEAD`), `adr-ordinal-collision.md:33`, `review/references/risk-tier-and-fix-rounds.md:58` (`$PANEL_SHA..HEAD`); each gains the W4a plugin-root notice
- [x] 3.3 `ship/SKILL.md` (ledger exact-equality exemption with `--diff-filter=AMT`, anchored PIR meta-case regex, explicit `unknown` branch for plan refs) with same-commit trims of >= ~190 B; lowercase renames; keep PIR-section `rc=$?` count and path occurrences
- [x] 3.4 `one-shot/SKILL.md` scope check with trim
- [x] 3.5 `semgrep-sast.md`, `observability-coverage-reviewer.md`
- [x] 3.6 Pins: one-shot in the TWO per-skill loops (fixture dir + DEFECTS row) plus its own failure-arm regex; handler floor 3 -> 5 and closed variable list + fixture lines; ref/agent exact capture-shape pin; raise SELFTESTS/MIN_* literals

## Phase 4 - Wave 4: sentinel, census, header, registries (last)

- [x] 4.1 Code census: three-flag predicate, Python/ts/mjs call forms, per-physical-line comment strip, exempt rows keyed on repo-relative path, `census_report` extracted for `selftest_moved`, `CENSUS_ROWS` + `MIN_CENSUS_ROWS` floor (multi-line block, adjacent literal)
- [x] 4.2 Bounded prose census with `EXEMPT_PROSE`
- [x] 4.3 PINNED_Z additions; header remainder rewritten as a reasoned table; floors and SELFTESTS count updated
- [x] 4.4 Exemption maintenance (delete three rows, re-verify the rest)
- [x] 4.5 Registries: accept rows re-derived LAST; suite registry rows in sorted position

## Phase 5 - Verification

- [x] 5.1 Targeted single-suite local runs
- [x] 5.2 Meta-guards: guard-vacuity-floor, fixture-relative-assert, lint-trap-tempfile-ownership, lint-shell-capture-exit (baseline), test-affected-kb-consumers, grep-q-pipe-guard, battery-tag-authorship, vitest plugin-root-anchoring, lint-skill-body-budget, components.test.ts
- 5.3 Mutation battery in a git-repo scratch copy (green control, mutation-landed check, unique scratchpad names); two targeted fix rounds plus one verification pass
- 5.4 Push (real exit code), required checks, hand-read infra-validation / sandbox-canary-capture-gate, merge, deploy verification
