# Tasks: convert the remaining changed-path readers (D7 remainder)

Plan: `knowledge-base/project/plans/2026-11-09-fix-convert-remaining-changed-path-readers-plan.md`. Every conversion is RED-first: commit the failing suite row, then convert. CI required checks are the gate; no local affected-battery run.

## Phase 1 - Wave 1: hooks, scripts, lints, app scripts

- 1.1 `scripts/pre-push-ratchet-lane.sh`: `-z --no-renames --ignore-submodules=none | tr` for the two diff reads; `--ignore-submodules=none` on the quiet diff; `--no-renames` on the name-status checks; suite rows (rename-away from `ci.yml`, tab-named suite, gitlink-only branch); check the `KB_CONSUMERS_INPUTS` exact-line observation
- 1.2 `.claude/hooks/pre-merge-rebase.sh`: append `--ignore-submodules=none` to the two disjointness reads only; keep the todos `git log` read and the `--diff-filter=U` listing; suite row for a gitlink changed on both sides
- 1.3 `scripts/hooks/pre-push`: append `--ignore-submodules=none`; gitlink-only-push case or PINNED_Z pin
- 1.4 `plugins/soleur/scripts/affected-tests.sh`: four legs `-M` to `--no-renames` plus `--ignore-submodules=none`; rename-into-docs row and gitlink row
- 1.5 `plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh`: NUL stream into jq, `--numstat -z`; update `# mut:norenames` marker, mutation string and text pin
- 1.6 Python lints (credential-path-literals, infra-no-human-steps, shell-trace-credential-refusal): `-z --no-renames --ignore-submodules=none`, `.split("\0")`, `git_out_z`; non-ASCII and failing-git rows
- 1.7 `apps/web-platform/scripts/lint-migration-fk-preconditions.sh`: exit-status-gated capture, `--no-renames`; `--from-pr-diff` rows
- 1.8 `apps/web-platform/scripts/allowlist-diff.sh`: pathspec read with `|| exit 2`; create `apps/web-platform/scripts/allowlist-diff.test.sh`
- 1.9 `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh`: keep override precedence, pipefail git arm, failure sets `capture_trigger=1`; scratch-repo rows; read `sandbox-canary-capture-gate` by hand
- 1.10 `apps/web-platform/scripts/real-sdk-ask-probe.sh` (drop-first)
- 1.11 `apps/web-platform/scripts/rename-guard.sh`: `git log -z --name-status` triples, no `|| true`, newline-name refusal
- 1.12 `plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts` (drop-first)

## Phase 2 - Wave 2: workflows and .github/scripts

- 2.1 `web-platform-release.yml` trigger step: `previous_filename`, cap at 300 reads as triggered, join `steps`
- 2.2 `registry-host-replace-dispatch.yml`: `previous_filename`; `gcompare` rename rows for three render inputs
- 2.3 `fix-constraints-stage-a.yml` + template + `.emitted.sha256` (drop-first)
- 2.4 `ci.yml` trigger-canary and trigger-propagation: pipefail `-z` capture, failure sets `hit=1`; join `steps`; delete both exemption rows
- 2.5 `pr-quality-guards.yml` stray-worktree-marker step: files API, exit-status gated; join `steps`; delete exemption row
- 2.6 `.github/scripts/check-sweep-completeness.sh`: `[\r\n]` jq sentinel; stub-`gh` derivation rows

## Phase 3 - Wave 3: prose, references, agents

- 3.1 `ship/references/settle-then-admin-merge.md` helper capture
- 3.2 `counsel-review-clo-attestation.md`, `adr-ordinal-collision.md`, `review/references/risk-tier-and-fix-rounds.md`
- 3.3 `ship/SKILL.md` (ledger, PIR meta-case, plan refs) with same-commit byte trims; lowercase renames
- 3.4 `one-shot/SKILL.md` scope check with trim
- 3.5 `semgrep-sast.md`, `observability-coverage-reviewer.md`
- 3.6 Pins: one-shot in the three loops (fixture + DEFECTS row), handler variable list, ref/agent spelling-plus-failure-arm pin

## Phase 4 - Wave 4: sentinel, census, header, registries (last)

- 4.1 Code census with `EXEMPT_CODE_TABLE`, floors as multi-line blocks with adjacent literal bounds
- 4.2 Bounded prose census with `EXEMPT_PROSE`
- 4.3 PINNED_Z additions; header remainder rewritten as a reasoned table; floors and SELFTESTS count updated
- 4.4 Exemption maintenance (delete three rows, re-verify the rest)
- 4.5 Registries: accept rows re-derived LAST; suite registry rows in sorted position

## Phase 5 - Verification

- 5.1 Targeted single-suite local runs
- 5.2 Meta-guards: guard-vacuity-floor, fixture-relative-assert, lint-trap-tempfile-ownership, lint-shell-capture-exit (baseline), test-affected-kb-consumers, grep-q-pipe-guard, battery-tag-authorship, vitest plugin-root-anchoring, lint-skill-body-budget, components.test.ts
- 5.3 Mutation battery in a git-repo scratch copy (green control, mutation-landed check, unique scratchpad names); two targeted fix rounds plus one verification pass
- 5.4 Push (real exit code), required checks, hand-read infra-validation / sandbox-canary-capture-gate, merge, deploy verification
