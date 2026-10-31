# Tasks — feat-one-shot-11578-ruling-gate-midnight-flake

Plan: `knowledge-base/project/plans/2026-10-31-fix-technical-ruling-gate-midnight-flake-plan.md`
Issue: #11578 (closes)

## Phase 1 — Clock stub and pin (test file only)

- 1.1 In `plugins/soleur/test/technical-ruling-gate.test.sh`, after the `gh` stub block (~line 496), add an argv-strict `$DBIN/date` stub:
  - serves `-u +%Y-%m-%dT%H:%M:%SZ` → `cat "$DBIN/clock"`
  - serves `-u +%s` → `cat "$DBIN/clock.epoch"`
  - serves `-u +%Y-%m-%d` → `${PIN%%T*}` of `clock`
  - appends each argv to `$DBIN/dcalls.log`
  - exits 64 with a stderr line on any other argv (no passthrough — a passthrough is a bypass)
  - `chmod +x`
- 1.2 Add `DNOON="${DTODAY}T12:00:00Z"` and `dclock_at <iso>` (writes `clock` + `clock.epoch` via `jq -rn --arg p '$p|fromdateiso8601'`; fails loudly on an unparseable instant) immediately after `DEXP` is set (~line 505); call `dclock_at "$DNOON"` once before the first `run_d` call (line 537).
- 1.3 Add a suite comment naming the mechanism and the `DPATH`/`run` carve-outs (the pin reaches only `run_d`'s `$DBIN` PATH; `run`-arm fixtures carry no delegation rows and never fire a `date` call; `mkbin_t` reduced-PATH cases carry the same stub via symlinks (post-review); ambient `run`/subshell arms are swept by the AMBF floor).

## Phase 2 — Controls

- 2.1 After the Arm 6g2 receipt block (~line 689), add the CLK bypass-detection case: `dclock_at "$(dts -1)"`; `dscn`; `mkdr clk "$AT"`; `run_d "$GATE" "$DF"`; assert rc 1 + `assert_reason delegation-invalid` ("ran reads as future under a yesterday pin — only a live stub produces this verdict; a bypassed stub reads rc 2 receipt-missing"); restore `dclock_at "$DNOON"` immediately after.
- 2.2 Add a `clock`/`clock.epoch` consistency assertion (`jq` epoch of `clock` equals `clock.epoch` content).
- 2.3 Beside the existing SUT-marker floor (~line 989), add the dispatch floor: `wc -l < "$DBIN/dcalls.log"` ≥ the committed count measured on a green run, and `grep -vc` of the three sanctioned argv over the log equals 0.
- 2.4 Confirm `print_results` floor (currently `493`) still holds — it is a `>=` floor, so added assertions do not require bumping it; re-measure and record the new count in a comment.

## Phase 3 — Verify

- 3.1 `bash plugins/soleur/test/technical-ruling-gate.test.sh` — exits 0, all arms green including the new CLK controls.
- 3.2 `git diff --name-only origin/main...HEAD -- plugins/` — only `plugins/soleur/test/technical-ruling-gate.test.sh` (AC1/AC6: no production file modified).
- 3.3 Confirm every `# mut:` line in `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh` is byte-identical to `origin/main` (the SUT is untouched).
- 3.4 AC sweep per plan `## Acceptance Criteria` (AC1–AC6); PR body: `Closes #11578`.
