---
title: "chore(quality): audit silent and catch-all exception handlers in shipped plugin scripts (slice 1 of #10331)"
date: 2026-10-18
slug: plugin-script-except-audit
branch: feat-one-shot-10331-except-audit
issue: 10331
pr: 10503
lane: cross-domain
type: chore
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore(quality): audit silent and catch-all exception handlers in shipped plugin scripts (slice 1 of #10331)

## Enhancement Summary

**Deepened on:** 2026-10-18. **Sections enhanced:** Research Insights, Work list, Implementation Phases, Observability, Guard Contract, Sharp Edges. **Inputs:** the CTO rulings (five forks plus two plan-review rows), the five-seat plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow), the learnings sweep and the gdpr-gate run. The mechanical halts of this skill ran (4.6 user-brand, 4.7 observability, 4.8 PAT-shaped variables, 4.11 guard contract, 4.12 scope check); 4.5, 4.55, 4.9 and 4.10 do not fire (no network symptom, no downtime-inducing change, no UI surface, no store or `.tf`/migration file). No further agent fan-out was run: the slice is one subsystem with mechanical edits, the review panel already covered the correctness, simplicity, blast-radius and flow lenses, and every load-bearing claim was re-verified live below.

### Key improvements

1. Kieran's code reads closed three execution gaps that would have failed at work time: the proxy suite's stdlib import allowlist (`contextlib` must be added), `mk_variant` instead of `beside()` for characterization cases, and the proxy suite's pinned `EXPECTED_MUTANTS` / `EXPECTED_RED_ROWS` / `MIN_ASSERTIONS`.
2. The discoverability probe now exits 0 on success (Check 10 requires rc 0): the "count is zero" and `grep -L` forms exit non-zero when the slice succeeds, so the probe counts the new tuples instead.
3. B2 lost its helper: `decoded = None` in the handler plus `if decoded is not None: return decoded` is F841-clean and mirrors B3.

### Live verification (commands run 2026-10-18)

```text
PAT-shaped variable sweep (4.8)                  -> none
unfenced '## Scope Check' count (4.12)           -> 1 ; no 'unmapped' cell, no 'status: BLOCKED', one 'Recommendation:' line
'## User-Brand Impact' count (4.6)               -> 1 ; threshold: single-user incident
python3 scripts/lint-guard-contract.py <plan>    -> 1 guard entry ; lint-infra-no-human-steps.py -> OK
cited AGENTS rule ids resolved against AGENTS.rules.md / migrated-rule-ids.txt -> none missing
scripts/ruff-requirements.txt                    -> ruff==0.16.10 (the pin the plan cites)
cited paths exist: work-scratch-sandboxes.md, check10-test-manifest.txt, preflight-check10-suite-integrity.test.sh; proxy suite has fake_killpg (in-process teardown probe) and mk_variant; run_suite 'scripts/lint-ratchet-ruff-live' is wired in scripts/test-all.sh and test-affected-paths.sh
labels type/chore, deferred-scope-out, priority/p3-low exist; milestone 'Post-MVP / Later' exists
#10331 #10433 #10381 #8659 OPEN ; #10375 #10426 MERGED
grep -vc '^#' baseline -> 62 ; plugins S110/S112 entries -> 18 (S110 14, S112 4) ; post-slice S110 7, S112 6, total 44 / 52 lines
grep -c "SystemExit, KeyboardInterrupt" <proxy>  -> 0 today (rc 1), 3 after C1-C3
```

Spec lacks a valid `lane:` (no `spec.md` for this branch): defaulted to `cross-domain` (fail-closed).

## Overview

Slice 1 of the code-quality arc under #10331 (kept open; the PR body uses `Ref #10331`, never a closing
keyword). Audit the Python under `plugins/soleur/` (the whole tree ships: `.claude-plugin/marketplace.json`
sources `./plugins/soleur`) for silent handlers (`except ...: pass` / `: continue`) and for handlers of
`BaseException`, fix every one that can be fixed without changing behaviour, and shrink
`scripts/lint-ratchet-ruff.baseline.txt` in the same PR so the shrink-only ratchet (ADR-290) stays equal
to the live census. The baseline never grows.

Work in three parts, all decided by the CTO agent on 2026-10-18 (rows in
`knowledge-base/project/specs/feat-one-shot-10331-except-audit/decision-challenges.md`):

1. **12 ruff S110/S112 entries in five shipped scripts** (the ones PR2 #10375 already annotated): replace
   the empty handler with a behavior-identical form (`contextlib.suppress`, or an assigned sentinel for
   `continue` handlers). PR2's rulings stand: expected-negative probes stay silent, no `# noqa`, no new
   stderr notes.
2. **4 `except BaseException` handlers** (the `py/catch-base-exception` S-class): narrow to explicit
   tuples that keep the exit-code contracts.
3. **6 S110/S112 entries in `agent-browser/test/fixtures/*.py`**: same forms, in this PR.

Expected result: baseline 62 entries -> 44 entries (S110 21 -> 7, S112 10 -> 6), file 70 lines -> 52 lines.

## Research Insights

### Premise Validation (Phase 0.6)

Checked, all held: #10331 OPEN (umbrella; tracker body lists "~20 empty-except + 3 catch-base-exception");
#10433 OPEN (drawdown); #10381 OPEN (post-merge CodeQL confirmation for PR2); PR2 #10375 and PR3a #10426
on `origin/main` (`git log`: `b6951913f9`, `5a70e0207e`); ADR-290 and ADR-095 exist; every cited script
exists. Two premises corrected:

- **"~20 empty-except"** is CodeQL's count on `main` at `30407a8597`, which PREDATES PR2. PR2 added a
  comment to or replaced the body of every shipped-script handler, and the CodeQL query
  (`EmptyExcept.ql`) exempts a commented handler, so the S-class `py/empty-except` alerts are probably
  already cleared; the Code Quality alerts are not readable through `gh api .../code-scanning/alerts`
  (only security-suite alerts appear), so this stays unconfirmed until #10381's scan. What remains in
  the deterministic census is ruff's stricter reading (`--ignore-noqa`, `check-typed-exception`): 12
  shipped-script entries + 6 fixture entries (all S110/S112 under `plugins/soleur`: 18).
- **"3 catch-base-exception"** is 4 shipped sites in the census (proxy x3, scan-ancestor x1); the fifth
  CodeQL finding is archived spec scratch under `knowledge-base/` (excluded by `ruff.toml`, out of scope).
  PR2's plan left these four untouched ("fail-closed arms"); this slice revisits them under the CTO ruling.
- `.claude/hooks/security_reminder_hook.py` (2 S110 entries) does not ship to users (brainstorm premise
  correction); it stays in #10433.

Mechanism check against the ADR corpus: ADR-290 rejects count highwaters, advisory jobs and header
hashes, not a handler restructure; ADR-095 mandates that per-candidate decode errors are swallowed and
never bubble to exit 2 (the restructure keeps that); no ADR rejects `contextlib.suppress`.

### Property List and Cut List (Phase 0.6b)

Properties:

- P1. No shipped plugin script contains an empty handler (`pass`/`continue` body) that ruff's census sees.
- P2. No shipped script catches `BaseException` or a bare `except`, and each former catch-all keeps its
  exit-code contract (proxy refuses with rc 2; scan-ancestor reads an uncaught exception as rc 3).
- P3. Runtime behaviour of every restructured silent handler is unchanged (same exceptions swallowed, same
  silence, no new handler output). Accepted delta, recorded in the decision row: the four BaseException
  narrowings let `GeneratorExit`, `asyncio.CancelledError` and custom `BaseException` subclasses escape as an
  uncaught traceback (rc 1, not rc 2); unreachable in this synchronous startup code, and still fail-closed
  because the proxy dies before it relays anything.
- P4. The ratchet baseline equals the live census and is smaller than at the merge base.

Cut List (mechanism -> property -> what already covers it):

- Sentry mirror for swallowed handlers (the brief's `cq-silent-fallback-must-mirror-to-sentry`) -> would
  serve "diagnosable" -> NOT LEGITIMATE here: observability layer 7 (`observability-coverage-reviewer.md`)
  says a customer-run plugin script has no Soleur-side sink and must not have one (shipping
  repository-derived data to a Soleur vendor is a data-controller event). The class-name-only stderr
  `_note` PR2 shipped is the layer-7 form. Cut; recorded as a decision row.
- New `_note` calls on the expected-negative probes -> "diagnosable" -> PR2 ruling (thousands of lines on
  a large snapshot). Cut.
- Re-raising after the refusal in the BaseException arms -> rc contract -> changes the rc. Cut.
- Ruff-cache recovery hint (ADR-290 residual 7) -> "operator can recover" -> belongs to slice 2, which
  re-points the same script; today's failure is loud (exit 2). Cut, with a tracked deferral (Phase 4).
- F401/F841 in `quick_validate.py` / `founder-check.py` -> unrelated to handlers -> #10433. Cut.

### Institutional learnings applied

- `2026-10-15-a-never-raises-helper-must-survive-a-missing-stderr-and-a-locator-must-name-your-own-frame.md`:
  `sys.stderr` is `None` when fd 2 is closed, so a guard needs `AttributeError`; the `suppress` tuples
  keep exactly the PR2 tuples (`OSError, ValueError, AttributeError`; proxy adds `RuntimeError`).
- `2026-10-18-ratchet-guards-must-pin-the-scan-population-and-their-own-registrations.md`: edit the code,
  then `--update`; never hand-edit baseline entries; pin tests/registrations stay untouched.
- `2026-10-10-a-negative-row-passed-for-the-wrong-reason-four-times-...md` and
  `2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-...md`: each probe row asserts its reason
  (the `cannot load ...: <ClassName>` line, the rc), and a mutant counts as killed only on an assertion
  failure, never a crash.
- `2026-10-05-a-guard-built-from-spellings-...md`: run the affected gate (`scripts/test-all.sh
  --affected`), not only the targeted suites.
- Typed-handler blind spot: ruff S110/S112 only see typed handlers because `ruff.toml` sets
  `check-typed-exception = true`; do not weaken it.

### Live verification (commands run 2026-10-18)

```text
python3 scripts/lint-ratchet.py ruff --list      -> 62 findings; plugins/soleur S110/S112 = 18 (12 shipped scripts, 6 fixtures)
grep -v '^#' scripts/lint-ratchet-ruff.baseline.txt | wc -l -> 62 ; wc -l -> 70
grep -rnE "except\s+BaseException|except\s*:" plugins --include=*.py -> proxy 274/289/296, scan-ancestor 543 (the .test.sh hits are heredoc test code, not scanned)
gh api repos/github/codeql/contents/python/ql/src/Exceptions/CatchingBaseException.ql -> flags BaseException or bare except whose handler can reach exit; no comment exemption
gh issue view 10331 / 10433 / 10381 -> OPEN
gh issue list --label code-review --state open (jq contains(path) over the 8 target paths) -> none
bash plugins/soleur/test/resolve-debt.test.sh -> 2.9 s, ALL TESTS PASSED
```

### GDPR gate addendum (Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

`soleur:gdpr-gate` ran against this plan 2026-10-18 (fired by the `single-user incident` threshold, not by the
path regex): path scan 9 examined, 0 matched the canonical regex; no finding on Art. 6, 5(1)(e), 17, Chapter V
or Art. 9. No processing activity is added and no stderr output is added; the one Art. 32 observation (the
proxy's stderr is persisted in Claude Code's MCP logs) is unchanged because no handler gains or loses output.
No Critical finding; nothing written to `compliance-posture.md`.

## Research Reconciliation — Spec vs. Codebase

| Brief / tracker claim | Reality | Plan response |
|---|---|---|
| "~20 empty-except in shipped plugin scripts" | Pre-PR2 CodeQL count; PR2 already commented/noted every shipped-script handler. Ruff census: 12 shipped + 6 fixture handlers | Work list is the ruff census, not the CodeQL count |
| "3 catch-base-exception" | 4 shipped sites (proxy 3, scan-ancestor 1) | All four in scope |
| "start with ... resolve-debt.py, founder-check.py, playwright-mcp-redact-proxy.py; the earlier PR covered only five scripts" | The five are proxy, founder-check, resolve-debt, scan-ancestor and redact-engine; their remaining ruff hits are the `_note` guards and the adjudicated expected-negative probes | Restructure, do not re-note (CTO fork 1) |
| "mirror to Sentry per cq-silent-fallback-must-mirror-to-sentry" | That rule is the server-TS `reportSilentFallback`; a customer-machine plugin script has no legitimate Sentry sink (layer 7) | stderr class-name note stays the mirror; no Sentry (decision row 6) |
| "ruff baseline currently 70 lines incl. comments" | 70 lines = 8 header + 62 entries | Target 52 lines / 44 entries |
| "include the ruff-cache recovery hint only if trivially small" | Needs a `lint-ratchet.py` change, a test and an ADR sentence in the file slice 2 rewrites | Deferred to slice 2 (CTO fork 4) |

## Open Code-Review Overlap

None for the Files lists (checked 2026-10-18). #8659 names `plugins/soleur/test/resolve-debt.test.sh`, which this plan does not edit: acknowledged, stays open.

## Work list and site classification

Line numbers are plan-time locators only; the work phase finds each site by the handler's content.

### A. Shipped scripts, pass-bodied handlers -> `with contextlib.suppress(<same tuple>):`

| # | File and function | Handler today | Form after |
|---|---|---|---|
| A1 | `resolve-debt/scripts/resolve-debt.py` `_note` guard | `except (OSError, ValueError, AttributeError): pass` | `suppress(OSError, ValueError, AttributeError)` around the write+flush |
| A2 | `preflight/scripts/founder-check.py` `_note` guard | same tuple | same (Guard 4 of the founder suite bars subprocess/exec spellings, not `contextlib`) |
| A3 | `scripts/scan-ancestor-signal-helpers.py` `_note` guard | same tuple | same |
| A4 | `scripts/scan-ancestor-signal-helpers.py` `main` `reconfigure` probe | `except AttributeError: pass` around two `reconfigure` calls | one `suppress(AttributeError)` holding BOTH calls (first failure skips the second, as today) |
| A5 | `agent-browser/scripts/playwright-mcp-redact-proxy.py` `_log_quiet` | `(OSError, ValueError, RuntimeError, AttributeError)` | `suppress` with the same four |
| A6 | proxy `wait_group_empty` | `except subprocess.TimeoutExpired: pass` around `child.wait(timeout=0.05)` | `suppress(subprocess.TimeoutExpired)` |
| A7 | proxy `teardown`, stdin-wait | `except subprocess.TimeoutExpired: pass` around `child.wait(timeout=STDIN_CLOSE_WAIT_S)` | `suppress(subprocess.TimeoutExpired)` |
| A8 | proxy `teardown`, SIGTERM | `except ProcessLookupError: pass` around `os.killpg(self.pgid, SIGTERM)` | `suppress(ProcessLookupError)`; the `os.killpg` call and its place before any stderr write do not move |
| A9 | `incident/scripts/redact-engine.py` `main` internal-error write | `except (OSError, ValueError, AttributeError): pass` | `suppress` (same tuple) around the guarded stderr write; the `return 2` stays after it |

Keep each existing justification comment on the new `with` line or inside its body.

### B. Shipped scripts, `continue`-bodied handlers -> assigned sentinel, then `continue` (not `suppress`)

`suppress` around a loop body would widen what is swallowed (the proxy's `looks_like_a11y_tree` could then
hide a `ValueError`) and JSON `null` parses to `None`, so a sentinel is required.

| # | Site | Form after |
|---|---|---|
| B1 | proxy `escaped_tree_in` candidate loop (`json.loads(cand)`, `except (ValueError, RecursionError): continue`) | module-level `_NOT_JSON = object()`; handler assigns `parsed = _NOT_JSON  # comment kept`; `if parsed is _NOT_JSON: continue` |
| B2 | `redact-engine.py` `_b64_decode` (`except (binascii.Error, ValueError): continue`) | `decoded = base64.b64decode(...)` in the try, `decoded = None  # comment` in the handler, then `if decoded is not None: return decoded` (b64decode never returns `None`; no helper; the `decoded` local is read, so no F841) |
| B3 | `redact-engine.py` `_scan_encoded` hex probe (`bytes.fromhex(blob)`, `except ValueError: continue`) | `raw = None  # comment` in the handler, `if raw is None: continue` (`None` cannot be a valid `bytes.fromhex` result); same form as B2 |

Keep the ADR-095 citation in the B2/B3 comments.

### C. `except BaseException` -> explicit tuples (CTO fork 2)

| # | Site | Tuple | Contract kept |
|---|---|---|---|
| C1 | proxy `load_redactor` | `(Exception, SystemExit, KeyboardInterrupt)` | `refuse_start(... cannot load ...: <ClassName>)` -> rc 2 (a Ctrl-C during load happens before the SIGINT handler exists, so it is a real `KeyboardInterrupt`) |
| C2 | proxy `self_test`, `redact_text` call | same | `refuse_start("redactor self-test raised <ClassName>")` -> rc 2 |
| C3 | proxy `self_test`, `looks_like_a11y_tree` call | same | `refuse_start("looks_like_a11y_tree raised <ClassName>")` -> rc 2 |
| C4 | `scan-ancestor-signal-helpers.py` `main`, last handler (after `except SystemExit: raise` and `except Unresolved`) | `(Exception, KeyboardInterrupt)` | `os._exit(3)` in the `finally` (uncaught exception reads as rc 3, never rc 1 "findings") |

Delete the dead `# noqa: BLE001` on C1-C3 (BLE001 is not selected). Mutant 05 in the proxy suite matches the
`refuse_start(f"cannot load {REDACTOR_BASENAME}: {type(exc).__name__}")` line, so only the `except` line changes.

### D. Fixtures under `plugins/soleur/skills/agent-browser/test/fixtures` (CTO fork 3)

| # | File | Site | Form after |
|---|---|---|---|
| D1 | `capture-playwright-mcp-fixtures.py` `finish` | `except OSError: pass` around `self.child.stdin.close()` | `suppress(OSError)` |
| D2 | `proxy-session-driver.py` `main` | `json.loads` + id bookkeeping `except ValueError: pass` | `suppress(ValueError)` around both statements |
| D3 | same | `p.stdin.write(...); p.stdin.flush()` `except OSError: pass` (server-request answer) | `suppress(OSError)` around BOTH statements |
| D4 | same | `p.stdin.close()` `except OSError: pass` (end `eof`) | `suppress(OSError)` |
| D5 | same | drain loop `except Exception: pass` | `suppress(Exception)` (BLE001 is not selected) |
| D6 | `session-facts.py` `main` | `json.loads(...)` `except ValueError: continue` | sentinel form as B1 |

Flip condition (CTO), with a criterion: if a fixture handler swallows anything beyond the single failing call it
guards (D5 `suppress(Exception)` wraps the drain loop), narrow it to the exception the call can raise
(`OSError`/`ValueError`) rather than keep `Exception`. Verification: D2-D6 run under `playwright-mcp-redact-proxy.test.sh`
(the only suite that calls `proxy-session-driver.py` and `session-facts.py`); D1 (`capture-playwright-mcp-fixtures.py`)
needs a live Playwright MCP and has no suite, so it is checked by `python3 -I -m py_compile` plus the ruff census.

### E. Left on purpose

All SIM115 (24), F841 (4), F401 (3), the `.claude/hooks` and `scripts/` and `tests/` handlers, and
`apps/` stay baselined for #10433 / slice 3. The `.test.sh` heredoc `except BaseException` blocks are test
code in shell, not scanned by ruff or CodeQL, and stay.

## Implementation Phases

### Phase 0 - Baseline (no edits)

1. `python3 scripts/lint-ratchet.py ruff --check` is green; `--list` shows the 18 target entries. The script
   provisions its own pinned ruff (`scripts/ruff-requirements.txt`, hash-checked pip install into a private
   cache; first run needs network, a local run without it prints a loud SKIP and CI is the backstop).
2. Run, on the unchanged tree, and keep the captured outputs: `playwright-mcp-redact-proxy.test.sh`,
   `playwright-mcp-lifetime.test.sh`, `redact-a11y-snapshot.test.sh` (agent-browser), `redact-sentinel.test.sh`
   (incident), `preflight-founder-check.test.ts`, `resolve-debt.test.sh`, `scan-ancestor-signal-helpers.test.sh`
   (seven suites in all).
3. Enumerate every mutant in the proxy suite (`mutant NN-...` rows) and confirm none names an edited
   handler line (verified at plan time: they target other lines). Re-verify after Phase 2.
4. Import-surface pins: `preflight-founder-check.test.ts` Guard 4 `BAD_MODULES` omits `contextlib` (fine), but
   the proxy suite's case `NFR1/NFR3: stdlib-only imports, no threading` pins `allowed = {"__future__",
   "importlib", "json", "os", "selectors", "signal", "subprocess", "sys", "time", "typing"}` and goes red on
   `import contextlib`. Add `contextlib` to that set in Phase 1 (an allowlist widening to a stdlib module with
   no threading or process-spawning surface). The scan-ancestor, resolve-debt and incident suites have no
   import pin (grep-verified).

### Phase 1 - Cases first

Write the cases; those that pin existing behaviour must be GREEN on the unchanged tree (characterization),
then stay green through Phase 2.

1. Proxy suite. Use `mk_variant "$dir" "$PROXY" <old> <new>` (defined before the characterization rows) to build
   a proxy whose sibling redactor raises `SystemExit` or `KeyboardInterrupt` at import, and whose `redact_text`
   / `looks_like_a11y_tree` raise each; `beside()` needs `$MUTANT_PATH` and is for mutation rows only. Each case
   asserts rc 2 and the exact `cannot load ...: <ClassName>` / `self-test raised <ClassName>` line (reason
   asserted, not only the rc). Add `contextlib` to the `allowed` import set (Phase 0 step 4). If a case is added
   as a `mutant`/`red` row, bump `EXPECTED_MUTANTS`, `EXPECTED_RED_ROWS` and `MIN_ASSERTIONS` (currently 86 / 86 /
   491) to the measured values.
2. Scan-ancestor suite: the existing `python3 -I - "$SCAN" <<'PY'` pattern (section F) loads the script with
   `spec_from_file_location`, sets `mod.run` to a function that raises `KeyboardInterrupt`, and calls `mod.main()`
   in its own subprocess (`main` ends in `os._exit(3)`); assert rc 3 and the `UNRESOLVED: uncaught
   KeyboardInterrupt` line. A `kill -INT` is not used (non-interactive background jobs ignore SIGINT). The
   plain-`Exception` arm is already pinned by D7 (`/dev/full`), so no new Exception case. Bump `PLANNED_TOTAL`.
3. Equivalence case, one: `redact-engine._b64_decode` on a non-base64 string returns `None` (a hard requirement,
   it guards B2). The hex handler (B3) is documented in its comment as unreachable today (ADR-095); no case.
   The proxy non-JSON-candidate canary case and the clean-session no-marker case already exist from PR2: keep
   them and confirm they reach the sentinel branch.
4. Ratchet cases: none new. The live arm (`scripts/lint-ratchet-ruff-live`) and the baseline-equals-census
   rule are the guard for P1/P4.

### Phase 2 - Implement

Sections A to D above, one script at a time, in the order: resolve-debt, founder-check, scan-ancestor,
redact-engine, proxy, then the three fixtures. After each script run its suite. Add `import contextlib`
where used (stdlib only; `scan-ancestor` runs under `python3 -I`, which is fine for stdlib).

### Phase 3 - Verify and shrink

1. `python3 scripts/lint-ratchet.py ruff --list`: none of the 18 target entries remains and no new
   finding appeared (a dead assignment would be an F841, a missing import an F821 only at runtime: run
   the suites).
2. `python3 scripts/lint-ratchet.py ruff --update` (refuses to add), then `--check`: baseline 44 entries,
   52 lines; per `(path, rule)` counts only dropped. Never hand-edit the file.
3. All Phase 0 suites green (several capture `2>&1` and assert on stderr, so a new stderr line from a
   restructured handler turns them red); floors adjusted only where cases were added (`PLANNED_TOTAL`, the
   proxy suite's `EXPECTED_MUTANTS`/`EXPECTED_RED_ROWS`/`MIN_ASSERTIONS`,
   `plugins/soleur/test/fixtures/check10-test-manifest.txt`, `preflight-check10-suite-integrity.test.sh`).
   Confirm the surviving SIM115 and F841 baseline entries in touched files are byte-identical before and after
   `--update` (their anchors are whitespace-normalised, so re-indenting does not change them).
4. `scripts/test-all.sh --affected` and the `lint-shell-capture-exit` baseline check are green;
   `python3 -m pytest tests/scripts/test_lint_ratchet.py` is green (pin tests untouched).
5. Guard 1 rows 1-4 run on scratch copies (never in place), following
   `plugins/soleur/skills/work/references/work-scratch-sandboxes.md`, and the result is pasted in the PR body.
   Recorded evidence, not a CI gate.
6. Re-run the discoverability command (Observability) and record that it lists the baseline path.
7. Immediately before merge: rebase on `origin/main`; if the baseline file conflicts (#10433 or another PR drew
   it down), take main's copy and re-run `--update`, then re-verify the counts quoted in the PR body.

### Phase 4 - Issues and PR body

1. File one deferral issue for slice 2 (PR3b carry-ins): the ruff-cache recovery hint and the CI-less eslint
   per-extension test (ADR-290 residual 7). Labels `type/chore`, `deferred-scope-out`, `priority/p3-low`;
   milestone `Post-MVP / Later` (confirm it exists with `gh api repos/:owner/:repo/milestones`); a `Re-eval by:` date;
   flip condition from the CTO row: pull the hint in if PR3b is not scheduled.
2. One comment on #10433 with the new counts (62 -> 44; S110 21 -> 7, S112 10 -> 6) and what remains (SIM115, F841,
   F401, non-plugin handlers), posted after the final pre-merge count in Phase 3 step 7.
3. PR body: `Ref #10331` (no `Closes`/`Fixes`/`Resolves`; grep after `ship` rewrites it), the decision-challenges
   table, the Phase 3 census before/after and Guard 1 evidence, the deferral issue link, one line that CodeQL is not
   confirmed clean until #10381's scan (and that this PR converts the commented handlers to non-`try` forms, so
   #10381's alert-count comparison should read the post-slice-1 scan), and the umbrella checklist state (PR1, PR2,
   PR3a done; this slice; slice 2 PR3b, slice 3 #10433, slice 4 Code Quality keep/drop + `expenses.md` open).

## Files to Edit

- `plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py`
- `plugins/soleur/skills/preflight/scripts/founder-check.py`
- `plugins/soleur/scripts/scan-ancestor-signal-helpers.py`
- `plugins/soleur/skills/incident/scripts/redact-engine.py`
- `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py`
- `plugins/soleur/skills/agent-browser/test/fixtures/capture-playwright-mcp-fixtures.py`
- `plugins/soleur/skills/agent-browser/test/fixtures/proxy-session-driver.py`
- `plugins/soleur/skills/agent-browser/test/fixtures/session-facts.py`
- `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` (BaseException cases via `mk_variant`, the `allowed` import set, the pinned floors, mutant re-check)
- `plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh` (KeyboardInterrupt/Exception cases, `PLANNED_TOTAL`)
- `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` (one `_b64_decode` equivalence case)
- `plugins/soleur/test/fixtures/check10-test-manifest.txt` and `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` (only if case counts change)
- `scripts/lint-ratchet-ruff.baseline.txt` (via `--update` only)

Not touched: `scripts/lint-ratchet.py`, `ruff.toml`, the eslint baseline, `tests/scripts/test_lint_ratchet.py`
(pin tests), ADR-290 (its "62 ... findings that exist today" is the historical statement at introduction).
`preflight-founder-check.test.ts` and `resolve-debt.test.sh` need no new cases (their handlers are the
`_note` guards PR2 already probes); touch them only if Phase 0 shows an assertion on the guard's source text.

## Files to Create

None (`decision-challenges.md` and `tasks.md` live under `knowledge-base/project/specs/feat-one-shot-10331-except-audit/`).

## Architecture Decision (ADR/C4)

No architectural decision: a behavior-identical handler restructure on existing surfaces, inside ADR-290's
and ADR-095's existing contracts. C4 completeness check (all three `.c4` files read for external actors,
systems, stores and access relationships): the touched scripts are plugin-internal tools; no actor,
vendor, store or relationship changes, and no derived cardinality moves. `bash plugins/soleur/test/c4-count-parity.test.sh`
is part of the affected gate in Phase 3.

## User-Brand Impact

**If this lands broken, the user experiences:** a redaction proxy that refuses to start (rc 2) or that fails
to reap Chrome on teardown, so a browser-driven session stops working or leaves a browser running; or a
`scan-ancestor`/`founder-check`/`resolve-debt` run that reports the wrong verdict (rc 1 "findings" instead
of rc 3 "unresolved").

**If this leaks, the user's data is exposed via:** a handler that begins writing exception text or
input-derived content to stderr (the proxy's stderr is persisted in Claude Code's MCP logs), or a startup
handler change that lets the proxy relay without its redactor. This slice adds no output and no
processing: every restructure is behavior-identical and the BaseException tuples keep the refusal.

**Brand-survival threshold:** single-user incident

The CPO sign-off from the brainstorm and PR2 (verdict proceed) carries forward: this slice is detect-free,
adds no execution surface and no stderr line. `soleur:engineering:review:user-impact-reviewer` runs at
review time on this PR.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled five forks on 2026-10-18 (see `decision-challenges.md`): restructure not note,
explicit BaseException tuples, fixtures in, ratchet-tool residuals deferred to slice 2, F401/F841 to #10433.
One subsystem root (`plugins/soleur`) plus the baseline file, about 13 files and roughly 250 changed lines.

### Legal

**Status:** reviewed
**Assessment:** `soleur:gdpr-gate` run on this plan (fired by the `single-user incident` threshold, not by
the path regex): 0 of 9 paths matched, no finding (see the Research Insights addendum). No processing activity is added.

### Product/UX Gate

**Tier:** none
**Decision:** no user-facing UI surface; no file in the Files lists matches the UI-surface term list.
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Observability

```yaml
liveness_signal:
  what: the shrink-only ruff ratchet (baseline == live census) and the per-script suites; at runtime a customer sees only the unchanged exit codes and the existing `swallowed <ClassName> at <site>` stderr notes (observability layer 7, cli-stdout-artifact), no Soleur-side sink by design
  cadence: per PR and push in the required `test` context; per occurrence at runtime
  alert_target: required `test` check status on the PR (workflow run log); none at runtime by design (customer-hosted CLI, no Sentry for privacy)
  configured_in: scripts/lint-ratchet.py (live arm `scripts/lint-ratchet-ruff-live`), lefthook pre-commit ratchet entry, the seven script suites
error_reporting:
  destination: stderr of the script (the proxy's stderr is persisted in Claude Code's MCP logs); workflow run log for the tests
  fail_loud: true
failure_modes:
  - mode: a restructured handler swallows a wider or narrower exception set than before
    detection: characterization cases per handler class in the existing suites (non-JSON candidates, closed/None/raising stderr, clean teardown no-marker) plus the Guard 1 scratch-copy evidence; layer cited - workflow run log (`::error::` from the required test)
    alert_route: required test red
  - mode: a BaseException arm no longer refuses (proxy rc 2) or no longer maps to rc 3 (scan-ancestor), e.g. KeyboardInterrupt/SystemExit escapes
    detection: new SystemExit/KeyboardInterrupt probe cases asserting rc and the exact reason line; layer cited - workflow run log
    alert_route: required test red
  - mode: a new empty handler lands in a plugin script later
    detection: the ruff ratchet fails on any finding not in the baseline; layer cited - workflow run log / lefthook
    alert_route: required test red; pre-commit
  - mode: hosted path (plugin tree vendored into the production image) behaves differently
    detection: unchanged by this PR; no handler gains or loses a signal, so layers 1-6 see no delta
    alert_route: none needed (statement, verified by the byte-identical stderr diff in Phase 3)
logs:
  where: the user's terminal stderr; Claude Code MCP logs for the proxy; GitHub Actions run logs for CI
  retention: GitHub default (90 days) for CI; local for the customer
discoverability_test:
  command: grep -c "SystemExit, KeyboardInterrupt" plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py
  expected_output: "3"
```

On the unchanged tree the command prints `0` and exits 1 (so Check 10 FAILs it, which is what lets it fail on the
feature); after the slice it prints `3` and exits 0. Check 10 needs rc 0 for PASS, which rules out the
"count is zero" greps that exit 1 on success. It is a one-line `grep` (no ruff install, no network), far inside
the 15 s cap, and is not suite-shaped (the proxy source carries no other `SystemExit, KeyboardInterrupt` text today: `grep -c` prints 0). The ratchet itself (`python3 scripts/lint-ratchet.py ruff --check`) is the real gate but needs a pip-installed
ruff, which Check 10's sandbox (no network, tmpfs `HOME`) cannot provision.

## Guard Contract

### Guard 1 - catch-all exit-code contract

**Property.** A startup or contract handler that formerly caught `BaseException` still converts every
exception class it can meet (an `Exception`, a `SystemExit` raised by module-level code, and a
`KeyboardInterrupt`) into the script's documented exit code (proxy rc 2 with the unchanged reason line;
scan-ancestor rc 3), and no restructured silent handler swallows an exception it did not swallow before.

**Assembly.** The four narrowed handlers (proxy `load_redactor`, `self_test` x2, scan-ancestor `main`) and
the 14 restructured silent handlers in sections A, B and D; the chokepoints are the proxy's `refuse_start` and
scan-ancestor's `finally: os._exit(3)`. The probe cases quantify over every handler in `load_redactor` and
`self_test` (the two `self_test` calls are separate members; a case for one does not cover the other).

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Narrow proxy `load_redactor` to `(Exception, SystemExit)` | the KeyboardInterrupt-at-import case sees rc 130/traceback instead of rc 2 |
| 2 | Narrow scan-ancestor to `(Exception,)` | the injected-KeyboardInterrupt case sees a non-3 exit |
| 3 | In `self_test`, narrow only the second handler (`looks_like_a11y_tree`) after a compliant first | the `looks_like_a11y_tree` SystemExit case fails (a check that stops at the first member is itself the defect class) |
| 4 | Make the case loader skip silently when the variant file is missing (own dispatch) | the case fails on a missing fixture, and a floor of at least 1 executed BaseException case holds, so zero cases cannot pass |
| 5 | Widen the proxy `teardown` SIGTERM `suppress(ProcessLookupError)` to `suppress(Exception)` | the in-process `teardown` probe (PR2's `fake_killpg` seam) raises `PermissionError` from `os.killpg` and the case requires it to surface |

**Harness rows.** RED: delete the `SystemExit` variant and confirm the case fails rather than vanishing. PASS (not
the canonical): a user-defined `SystemExit` subclass maps to the same rc and prints its own class name.

**Anchor.** The independent anchors are the committed ruff baseline (can only shrink, checked against the merge
base) and the ruff output in the PR body (re-runnable with the pinned `ruff==0.16.10`); the case floor is a count,
so it is paired with named case labels, not only a total.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "audit the shipped plugin scripts (under plugins/soleur/ - what ships to users) for silent `except: pass` / empty-except and `except BaseException`" | Research Insights, sections A-E | mapped |
| 2 | "start with playwright-mcp-redact-proxy.py, founder-check.py, resolve-debt.py" | sections A (A1, A2, A5-A8), B1, C1-C3; Phase 2 order | mapped |
| 3 | "replace silent handlers with logged or re-raised handling" | sections A, B, D | narrowed - justification: PR2 (#10375) already added `_note` logging where a swallow is a real failure and CTO-ruled the expected-negative probes silent; what remains is a behavior-identical restructure whose purpose is the ruff census (P1/P4), stated plainly here rather than as new logging. Only section C changes what a handler does |
| 4 | "mirror to Sentry per cq-silent-fallback-must-mirror-to-sentry (check what a Python plugin script on a customer machine can legitimately mirror to)" | Cut List + decision row 6: layer 7, stderr only | mapped (answer: nothing but stderr) |
| 5 | "shrink the ruff baseline ... in the same PR ... Never grow a baseline" | Phase 3 steps 1-2, AC 1 | mapped |
| 6 | "PR body must use Ref #10331, never Closes/Fixes" | Phase 4 step 3 | mapped |
| 7 | "include the ruff-cache recovery hint only if it is a trivially small in-scope change, else leave for slice 2/3" | decision row 4: left for slice 2 with a tracked deferral | mapped (left) |
| 8 | "Plan only slice 1" | whole plan; slices 2-4 appear only as checklist lines | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Restructure of the 12 shipped-script handlers | "Fix the rest: replace silent handlers" | asked |
| `(Exception, SystemExit, KeyboardInterrupt)` tuples | "`except BaseException`" | asked |
| The six fixture entries | "audit the shipped plugin scripts (under plugins/soleur/ ...)" | asked (the tree ships; CTO fork 3) |
| New probe cases in the proxy and scan-ancestor suites | — | inferred - justification: `cq-write-failing-tests-before`; a narrowed tuple is only safe with a case that drives each excluded class |
| `PLANNED_TOTAL` / check10 manifest edits | — | inferred - justification: those pins fail when a case is added |
| Deferral issue for the ratchet-tool residuals | "else leave for slice 2/3" | asked (tracked per `wg-when-deferring-a-capability-create-a`) |
| #10433 / #10381 / umbrella comments | "Open drawdown tracker: #10433" | inferred - justification: the counts quoted in those trackers change with this PR |

### Split Assessment

- Subsystems touched: 1 (`plugins/soleur`) plus `scripts/` baseline file = 2 roots
- Planned files: 13 | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. (Note #10433 advises one shipped-script fix per PR with its own tests; this slice keeps one behavior-identical rewrite class per script and runs each script's suite after each edit, and the CTO accepted the grouping.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `python3 scripts/lint-ratchet.py ruff --check` exits 0; the baseline has 44 entries and 52 lines (`grep -vc '^#'` gives 44); S110 count 7, S112 count 6; no per-`(path, rule)` count rose against the merge base
- [ ] `python3 scripts/lint-ratchet.py ruff --list` shows no S110/S112 under `plugins/soleur/` (all 18 target entries gone)
- [ ] `grep -rnE "except\s+BaseException|except\s*:" plugins --include=*.py` returns nothing
- [ ] The Guard 1 cases pass: proxy rc 2 with the unchanged `cannot load ...: <ClassName>` / `self-test raised <ClassName>` lines for `SystemExit` and `KeyboardInterrupt` (import, `redact_text`, `looks_like_a11y_tree`); scan-ancestor rc 3 for an injected `KeyboardInterrupt` and `Exception`
- [ ] The seven suites listed in Phase 0 step 2 are green (no new stderr line from any restructured handler; the suites that assert on `2>&1` content would catch one)
- [ ] Every proxy mutant row still lands (`make-proxy-mutant.py` exits 0 for each) and is killed on an assertion failure
- [ ] `scripts/test-all.sh --affected`, `tests/scripts/test_lint_ratchet.py` and the `lint-shell-capture-exit` baseline check are green; `scripts/lint-ratchet.py`, `ruff.toml` and the eslint baseline are untouched in the diff
- [ ] Guard 1 rows 1-5 are recorded RED in scratch copies (evidence in the PR body, not a CI gate)
- [ ] The deferral issue and the #10433 comment exist; the PR body has `Ref #10331` and no `Closes`/`Fixes`/`Resolves` (grep after `ship` rewrites it) and renders the decision-challenges table

### Post-merge

- [ ] None that need a person: the CodeQL confirmation is #10381's scheduled re-evaluation (2026-11-14), and the remaining baseline drawdown is #10433.

## Test Scenarios

- Given a redactor module that raises `SystemExit` at import, when the proxy starts, then it logs `refusing to start: cannot load ...: SystemExit` and exits 2 (same for `KeyboardInterrupt`)
- Given a redactor whose `redact_text` or `looks_like_a11y_tree` raises `KeyboardInterrupt` during `self_test`, when the proxy starts, then it refuses with rc 2 and the matching reason line
- Given scan-ancestor's `run` raises `KeyboardInterrupt` (or any `Exception`), when `main` runs, then it prints `UNRESOLVED: uncaught <ClassName>` and exits 3
- Given a tool result with non-JSON lines holding a canary, when the proxy checks for an escaped tree, then there is no `swallowed` marker, the result is still redacted, and the sentinel branch was the one taken
- Given a clean stdin-EOF proxy session, when it tears down, then no `swallowed` marker appears and `child exited rc=0` is unchanged
- Given `sys.stderr` is `None`, closed, or raising `OSError`/`ValueError` (and, in the proxy, `RuntimeError`), when any `_note` guard runs, then it returns normally (the PR2 cases, unchanged, must still pass against the `suppress` form)
- Given `redact-engine._b64_decode` is fed a non-base64 candidate, when `_b64_decode` runs, then it returns `None` and the engine's exit codes are unchanged

## Sharp Edges

- A `suppress` that wraps MORE statements than the original `try` body widens the swallowed set. Wrap exactly the original try-body statements (A4 wraps both `reconfigure` calls because they were both in the try). Do not use `suppress` for `continue` handlers.
- JSON `null` parses to `None`: the `json.loads` sentinel must be a unique `object()`, not `None`. A dead `x = None` in a handler that is never read is an F841 in the ruff set, so every sentinel/assignment must be read afterwards.
- `make-proxy-mutant.py` needs `<old>` to occur exactly once in the proxy source; re-run every mutant row after editing, because `suppress(...)` introduces repeated text and a row that stops landing is a FAIL, never a vanished row. The proxy suite pins `EXPECTED_MUTANTS`, `EXPECTED_RED_ROWS` and `MIN_ASSERTIONS`, and an import allowlist (`contextlib` must be added).
- Do not touch the proxy `log()` line (`sys.stderr.write(f"{PREFIX} {msg.translate(_LOG_SCRUB)}\n")`): the suite's log-scrub mutant matches it by exact text. In `teardown`, never write to stderr before the `os.killpg` calls (it also runs from `on_signal`); `suppress` there changes nothing about ordering - keep it that way.
- Dropping `KeyboardInterrupt` or `SystemExit` from a tuple still dies fail-closed in the proxy but changes the rc (130/traceback vs 2) and in scan-ancestor turns the "uncaught reads as rc 3" contract into rc 1 - the scan's "findings" code. The probe cases must assert the rc AND the reason line.
- Never log `str(exc)`/`repr(exc)` or any input-derived label from these scripts; this slice adds no handler output. (scan-ancestor's pre-existing `UNRESOLVED: uncaught %s: %s` line writes `exc` text by design and is unchanged.)
- `--update` removes baseline entries by identity (path, rule, anchor, n); an edited-but-still-empty handler changes its anchor and reads as one stale plus one new entry, which `--update` refuses. Fix the handler, do not edit the baseline.
- Several suites capture `2>&1` into one stream and assert on stderr content (`redact-sentinel.test.sh`, `resolve-debt.test.sh`, `scan-ancestor-signal-helpers.test.sh`); diff Phase 0 vs Phase 3 captures.
- CodeQL `py/catch-base-exception` has no comment exemption (only the type matters); `py/empty-except` exempts a commented or non-`pass` handler, which is why PR2 kept `pass`+comment. Do not claim CodeQL clean before a scan has run on the branch (#10381).
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this one carries all three lines.
- `plugins/soleur/test/resolve-debt.test.sh` is named by open code-review issue #8659 (EXIT-trap composition); do not touch its trap setup if a case is added.
