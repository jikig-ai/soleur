# Tasks — Fix C1 itemized byte-identity verify (workspaces-luks cutover diagnosability)

Plan: `knowledge-base/project/plans/2026-07-19-fix-workspaces-luks-c1-verify-diagnosable-plan.md`
Branch: `feat-one-shot-luks-cutover-verify-diag` · ADR-119 · epic #6588 PR 2
Threshold: single-user incident (`requires_cpo_signoff: true`) — preserve fail-closed EXACTLY.

## Phase 0 — Preconditions (verify, do not assume)
- [ ] 0.1 Re-read `apps/web-platform/infra/workspaces-cutover.sh:396-442`; confirm anchors (verify 408-416; pass-2 :399; sync/drop_caches :406-407; die :36).
- [ ] 0.2 Confirm rsync `--out-format='%i %n'` itemize shape; lock count regex `^(\*deleting|[<>ch.*][fdLDS])` (counts ALL codes, excludes stderr/blank).
- [ ] 0.3 (Deepen-resolved: no `infra/*.sh` logger-tag extractor exists → no drift-guard concern; `luks-monitor` already in `vector.toml:184` → no vector.toml change.) Still adopt `luks-monitor.sh:34-38` shape: `LUKS_LOG_TAG="luks-monitor"` real assignment + own-line `logger -t "$LUKS_LOG_TAG" --`.
- [ ] 0.4 Confirm no open `code-review` issue references the edited files (`gh issue list --label code-review --state open` grep).

## Phase 1 — Counting fix (defect 1)
- [ ] 1.1 Add `verify_byte_identity <src> <dst>` after `emit_drift` (~:178): capture stdout→`$vout`, stderr→`$verr` SEPARATELY (`>"$vout" 2>"$verr"`), `rc=$?`.
- [ ] 1.2 Preserve fail-closed rc-check: `rc != 0` → capture stderr tail into a var, emit diagnostic, then `die` "verify rsync itself FAILED (rc=$rc) … stderr: …".
- [ ] 1.3 Count only itemize-shaped stdout lines: `diff_n="$(grep -cE '^(\*deleting|[<>ch.*][fdLDS])' "$vout" || true)"`. Threshold unchanged (fail iff ≠ 0); codes NOT narrowed.

## Phase 2 — Diagnostic (defect 2) — BEFORE die, BEFORE rm
- [ ] 2.1 Add `emit_verify_diff <count> <vout> <verr> <reason>` + `_vscrub` (strip CR/LF/non-printable) + `VERIFY_DIFF_CAP=40`.
- [ ] 2.2 Print capped (~40) itemized lines to stdout (run log) via `log`, with a `+N more` note.
- [ ] 2.3 Emit `SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF feature=workspaces-luks op=workspaces-luks-verify-diff count=… [idx= icode= path=…]` — summary + per-diff rows (capped 40), each via `logger -t "$LUKS_LOG_TAG"` (Better Stack) AND `echo` (run log). `path=` LAST; every value `_vscrub`-sanitized.
- [ ] 2.4 Page Sentry via existing `emit_drift "workspaces_luks_<reason>"` (existing `op=workspaces-luks-drift`; no Sentry filter change).
- [ ] 2.5 Ensure emit happens BEFORE any `rm` of temp files and BEFORE `die`.

## Phase 3 — Sourced-detection guard + call-site swap
- [ ] 3.1 Insert `if [ "${BASH_SOURCE[0]:-$0}" != "$0" ]; then return 0 2>/dev/null || true; fi` after the new functions, before the ROLLBACK block (~:234), before `trap cleanup EXIT`.
- [ ] 3.2 Replace inline verify block (408-416) with `verify_byte_identity "$MOUNT" "$STAGING"` — called DIRECTLY (no subshell/pipe, so `die` exit propagates to the EXIT trap).

## Phase 4 — Tests
- [ ] 4.1 Create `apps/web-platform/infra/workspaces-luks-verify.test.sh` (harness mirrors `git-data-luks.test.sh`): source the cutover script (guard → funcs only); stub `rsync`/`logger`/`die`/`log`/`emit_drift`; run each case in a subshell (`die`→`exit 1`); capture stdout+stderr+rc+marker log.
- [ ] 4.2 Case a — benign stderr (rc=0, empty stdout): no die, no marker. Mutation: `2>&1`+`grep -c .` → flips to failing.
- [ ] 4.3 Case b — real content diff (`>f… workspaces/ws1/secret.txt`): dies; path+code in marker+stdout. Mutation: drop `emit_verify_diff` → flips.
- [ ] 4.4 Case c — hard error (rc=23, stderr): dies "verify rsync itself FAILED" incl. stderr. Mutation: remove rc-check → flips.
- [ ] 4.5 Case d — codes not narrowed (`.f..t…`, `.d..t…`): dies count=2, both in diagnostic. Mutation: narrow regex to `^>f` → flips.
- [ ] 4.6 Case e — clean verify (rc=0, empty stdout): no die, no marker.
- [ ] 4.7 (Optional) add static stream-separation + emit-before-rm mutation assertions to `workspaces-luks-header.test.sh`.
- [ ] 4.8 Register `bash apps/web-platform/infra/workspaces-luks-verify.test.sh` in `.github/workflows/infra-validation.yml` (next to the `luks-monitor.test.sh` step, ~:379).

## Phase 5 — Docs
- [ ] 5.1 One-line ADR-119 observability-addendum: `op=workspaces-luks-verify-diff` (Better Stack, via the `luks-monitor` tag) is the itemized-diff channel.

## Verify (pre-ship)
- [ ] V1 `bash apps/web-platform/infra/workspaces-luks-verify.test.sh` green locally.
- [ ] V2 `bash apps/web-platform/infra/workspaces-luks-header.test.sh` green (if edited).
- [ ] V3 `bash apps/web-platform/infra/luks-monitor.test.sh` + `vector-pii-scrub.test.sh` green (no allowlist/emitter-extractor regression).
- [ ] V4 Confirm ACs: no `2>&1` in verify rsync; regex counts all codes; emit before rm/die; marker tag `luks-monitor`; :399/:406/:407 byte-unchanged.
