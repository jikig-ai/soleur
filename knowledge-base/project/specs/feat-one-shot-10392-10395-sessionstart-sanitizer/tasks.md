# Tasks — feat-one-shot-10392-10395-sessionstart-sanitizer

Plan: `knowledge-base/project/plans/2026-10-19-feat-plugin-bare-root-arm-context-sanitizer-plan.md`
Issues: closes #10392, #10395.

## Phase 0 — Tests first (RED)

- [ ] 0.1 Write `.claude/hooks/lib/context-sanitize.test.sh` — byte-contract fixtures (DEL, NEL, U+2028, U+2029, ESC stripped; `\t`/`\n` per-variant), copy-parity `cmp`, and the drift-sentinel enumeration with disposition list.
- [x] 0.2 Write `plugins/soleur/test/bare-root-cwd-plugin-guard.test.sh` — 8 fixture classes (bare fires; plain/masked/wtmask/sym/truebare/imposter/nonrepo silent), dedup fixture, no-jq arm, GIT_DIR env-injection arm, envelope-shape assertions.
- [ ] 0.3 Add separator-laden fixtures to `session-rules-loader.test.sh` (BARE_CWD_BLOCK + WS_WORKTREE carry no DEL/U+2028/U+2029) and `bare-root-cwd-guard.test.sh`.
- [x] 0.4 Add non-worktree/bare-root rows to `scripts/ensure-kb-index.test.sh`.
- [x] 0.5 Extend `plugins/soleur/test/git-repo-readiness-diag.test.sh` D5 parity loop 2-way → 3-way (repo guard + diag + plugin arm).

## Phase 1 — Shared lib + probe

- [ ] 1.1 Create `.claude/hooks/lib/context-sanitize.sh` — `soleur_ctx_sanitize`, `soleur_ctx_sanitize_lines`, `soleur_ctx_sanitize_nl`; `LC_ALL=C` tr + sed `\xc2\x85`/`e2 80 a8`/`e2 80 a9`; `# shellcheck shell=bash`, no `set`, BASH_SOURCE direct-exec guard.
- [ ] 1.2 Create `plugins/soleur/scripts/lib/context-sanitize.sh` — byte-equal copy (Guard 2 `cmp` target).
- [ ] 1.3 Extend `scripts/bare-root-cwd-guard-probe.sh` — also pipe a fixture envelope through the plugin hook and a separator fixture through the lib; `sanitizer-ok` as last line.

## Phase 2 — Adoption sweep (`.claude/hooks/` then `plugins/soleur/`)

Per site: source-if-readable block + `declare -F` fallback carrying the site's pre-change strip set + call-site swap.

- [x] 2.1 `.claude/hooks/session-rules-loader.sh` — lines 342 (lines variant), 383, 474 (strip-all); jq `gsub` at 371-373 gains `| gsub("[  ]";"")`.
- [x] 2.2 `.claude/hooks/bare-root-cwd-guard.sh:53` — strip-all.
- [x] 2.3 `.claude/hooks/agent-token-tee.sh:97` `sanitize_field`, `pre-merge-rebase.sh:833`, `prod-write-defer-gate.sh:404,432,433` — strip-all.
- [x] 2.4 `.claude/hooks/ship-kb-archive-gate.sh:778`, `cla-signed-author-gate.sh:109`, `ship-unpushed-commits-gate.sh:166` — lines variant.
- [x] 2.5 `.claude/hooks/monitor-arm-recorder.sh:72` — DESC upgrade to strip-all.
- [x] 2.6 `plugins/soleur/hooks/operator-stage-approval.sh:345`, `plugins/soleur/scripts/run-in-pid-namespace.sh:74`, `resolve-regenerable-conflicts.sh:168`, `skills/ship/scripts/battery-owed.sh:53`, `technical-ruling-gate.sh:278,279` — strip-all.
- [x] 2.7 `plugins/soleur/scripts/domain-model-drift.sh:321,322` — lines variant; `resolve-regenerable-conflicts.sh:50` — nl variant.
- [ ] 2.8 Run each touched file's existing suite; drift sentinel clean.

## Phase 3 — Plugin arm (#10392 item 1)

- [x] 3.1 Create `plugins/soleur/hooks/bare-root-cwd-guard.sh` — envelope `.cwd` (jq-gated), `GIT_*` scrub, toplevel check, three-term predicate, dedup, emit `SOLEUR_BARE_ROOT_CWD source=plugin-session-start` + generic `[bare-root-cwd]` block + gated soleur-hint; `exit 0` everywhere.
- [x] 3.2 Register `""`-matcher SessionStart entry in `plugins/soleur/hooks/hooks.json` (`timeout: 10`, `bash "${CLAUDE_PLUGIN_ROOT}/hooks/bare-root-cwd-guard.sh"`).
- [x] 3.3 Add `soleur-plugin` row to `.claude/hooks/devin-dispositions.tsv` (matcher sentinel `""`, disposition `already-fires`).
- [x] 3.4 Green: new test + `devin-matcher-parity.test.sh` + `repo-hook-launchers.test.ts` + `devin-plugin.test.ts` + `devin-cloud-mode.test.ts`.

## Phase 4 — Audit fixes (#10392 item 2)

- [x] 4.1 `scripts/ensure-kb-index.sh` — skip regen when `git -C "$KB_DIR" rev-parse --is-inside-work-tree` is not `true`; header comment records the overlay-materialization rationale.
- [x] 4.2 `plugins/soleur/hooks/devin-session-start.sh` — skip the sentinel write when `_sentinel_root` is empty or non-absolute.
- [x] 4.3 Audit dispositions verified: session-manifests keep (standing ruling), supabase-loopback clean, backstop ledger keep (decision-challenges row), codex-session-start clean.

## Phase 5 — Docs & model

- [ ] 5.1 `.claude/hooks/README.md` — plugin arm section, audit disposition table, shared-sanitizer note.
- [ ] 5.2 ADR-099 amendment — deferred→shipped bullet; capabilities bullet gains plugin arm.
- [ ] 5.3 `model.c4` SessionStart census fix (six→seven, name the hook, no-web-override rationale) + regenerate `model.likec4.json`; run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 5.4 Final suite pass: all AC10-named suites green; PR body carries `Closes #10392` and `Closes #10395`.
