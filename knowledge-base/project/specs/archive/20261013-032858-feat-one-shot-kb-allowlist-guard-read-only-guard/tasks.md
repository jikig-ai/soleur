# Tasks — fix: kb-domain-allowlist-guard read-only Bash false-positive

Plan: `knowledge-base/project/plans/2026-06-11-fix-kb-allowlist-guard-read-only-bash-false-positive-plan.md`
Lane: procedural

## Phase 1 — RED (write failing tests first)

- [x] 1.1 Add helper `invoke_bash_named()` to `kb-domain-allowlist-guard.test.sh`
      (`jq -nc --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'`).
- [x] 1.2 Add optional helper `invoke_write_named()` (`{tool_name:"Write", tool_input:{file_path:...}}`).
- [x] 1.3 Add T13: exact repro command via `invoke_bash` → expect pass-through (currently FAILS — captures bug).
- [x] 1.4 Add T14: `git show main:knowledge-base/.gitkeep` via `invoke_bash` → pass-through (currently FAILS).
- [x] 1.5 Add T15: `grep -r knowledge-base/foo .` via `invoke_bash` → pass-through (currently FAILS).
- [x] 1.6 Add T15b: repro command via `invoke_bash_named` → pass-through (exercises explicit tool_name).
- [x] 1.7 Add T16: `mkdir knowledge-base/newdomain` → `ask` (regression guard).
- [x] 1.8 Add T17: `echo x > knowledge-base/newdomain/file.md` → `ask` (regression guard).
- [x] 1.9 Add T18: `git add knowledge-base/newdomain/file.md` → `ask` (regression guard).
- [x] 1.10 Add T19: `mkdir knowledge-base/engineering/x` → pass-through (sanctioned domain).
- [x] 1.11 Add T20: file-tool Write to `knowledge-base/newdomain/x.md` → `ask` (unaffected); T20b via `invoke_write_named`.
- [x] 1.12 Add T21: `echo "cp x > knowledge-base/y is the move cmd" > /tmp/notes.txt` → `ask` (documented-acceptable string-literal false positive; locks Sharp-Edge Finding 1).
- [x] 1.13 Add T22: `sed "s/a/b/" knowledge-base/engineering/x.md` (read-only sed, no `-i`) → pass-through (locks the `-i`-anchored verb boundary).
- [x] 1.14 Add T23: `mv knowledge-base/project/foo.md /tmp/` (kb-as-source, sanctioned segment) → pass-through (locks kb-as-source against a future verb-regex narrowing).
- [x] 1.15 Run `bash .claude/hooks/kb-domain-allowlist-guard.test.sh`; confirm T13/T14/T15/T15b FAIL, others pass.

## Phase 2 — GREEN (implement the gate)

- [x] 2.1 Extract `TOOL_NAME` via `jq -r '.tool_name // empty'` (fail-open, mirror `background-poll-prefer-monitor.sh:81`).
- [x] 2.2 After `SEGMENT=...`, compute `IS_BASH` = (`TOOL_NAME == "Bash"`) OR (`TOOL_NAME` empty AND `.tool_input.command` present AND `.tool_input.file_path` absent).
- [x] 2.3 Define `KB_WRITE_VERB_RE` and `KB_WRITE_REDIR_RE` as shell variables (NOT inline — avoids `;`/`&` parse error).
- [x] 2.4 If `IS_BASH` and neither regex matches `$TARGET` → `exit 0` (read-only reference pass-through).
- [x] 2.5 Update header comment block (lines 22-27): Bash now gates on write-target detection.
- [x] 2.6 Add inline read-vs-write comment in the glob-guard comment style. Per code-reviewer Finding 2: phrase as "Bash reads that pass this gate `exit 0` here; they do not need the downstream checks (all pass-throughs). Only Bash *writes* fall through." Do NOT say "runs after the glob-guard" — placement is BEFORE it.
- [x] 2.7 Re-run the suite; all cases (T1-T20b) pass.

## Phase 3 — Verify

- [x] 3.1 `bash -n .claude/hooks/kb-domain-allowlist-guard.sh` (syntax) + `shellcheck` if available.
- [x] 3.2 Confirm `.claude/settings.json` routing unchanged (file tools + Bash → same hook).
- [x] 3.3 Confirm `set -euo pipefail` preserved and gate uses pure `[[ =~ ]]` (no new subprocess).
- [x] 3.4 Verify the exact repro command returns no `permissionDecision` against the patched hook.
