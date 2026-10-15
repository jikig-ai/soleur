---
title: "chore(quality): guarded class-name-only exception notes in shipped plugin scripts (PR2 of #10331)"
date: 2026-10-15
slug: code-quality-empty-except-note-pr2
branch: feat-one-shot-10331-pr2-empty-except-note
issue: 10331
pr: 10375
lane: cross-domain
type: chore
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore(quality): guarded class-name-only exception notes in shipped plugin scripts (PR2 of #10331)

## Overview

Second slice of the #10331 umbrella (GitHub Code Quality triage). PR1 merged on 2026-10-15
(`084a5b0dda`, #10342). This branch carries PR2 only, on draft PR #10375. The archived umbrella plan
(`knowledge-base/project/plans/archive/20261015-112151-2026-10-15-chore-code-quality-linters-triage-plan.md`)
already holds the research and decisions; this plan scopes them to one slice and adds the CTO rulings
that PR2's concrete code forced (recorded in
`knowledge-base/project/specs/feat-one-shot-10331-pr2-empty-except-note/decision-challenges.md`).

Shipped plugin scripts swallow exceptions without a trace. PR2 adds, per script, a guarded helper
`_note(exc, site)` that writes `type(exc).__name__` and a static site label to stderr and nothing
else, and calls it from the handlers that swallow a genuine one-shot failure. Handlers that are
expected-negative probes stay silent with a justification comment. No fail-closed path changes.

PR body carries `Ref #10331` and no closing keyword; this is not the last slice.

### Umbrella checklist (kept on #10331; update as slices merge)

- [x] PR1: comparison findings (#10342, merged 2026-10-15)
- [ ] PR2: shipped-script exception notes (this plan, PR #10375)
- [ ] PR3a: ruff baseline ratchet in the required test battery, and eslint scope over the unscanned test dirs
- [ ] PR3b: narrow plugin `work`/`review` detect-and-run of a project's own installed linters (operator override of the CPO deferral)
- [ ] PR4: rule-overlap table, then a dated ADR-276 Decision 6 amendment with CLO and CTO sign-off, plus the expenses row

PR3a, PR3b and PR4 are not implemented here; the checklist is the only artifact PR2 leaves for them.
Ownership: the Phase 4 comment posts it; the PR3a author ticks PR2 when it merges, and `ship` of the
last slice sweeps the whole list.

## Research Insights

**Premise Validation.** Checked 2026-10-15. Held: #10331 is OPEN; PR1 `084a5b0dda` is on `main`;
draft PR #10375 is OPEN; the three archive paths exist; `uvx ruff==0.17.0` runs and reproduces the
work list below (30 findings over the 16 shipped scripts: 19 S110/S112/BLE001 in the five target
scripts, plus 7 BLE001 in `gemini-imagegen/scripts/*` and 4 in `skill-creator/scripts/*`). Corrected
against the brief: the issue body names the redaction proxy, the security hook, `founder-check.py`
and `resolve-debt.py`; the security hook is `.claude/hooks/` (repo-only, falls under PR3a's baseline)
and `scan-ancestor-signal-helpers.py` comes from the audit's S-class sample, so the "four named" are
proxy, founder-check, resolve-debt and scan-ancestor, plus `redact-engine.py` from the ruff run (the
audit's list is a first-page sample, per
`2026-10-15-a-sampled-list-was-restated-as-a-universal-claim-in-the-audits-own-summary.md`).
ADR corpus check (mechanism = logging inside swallowed handlers): ADR-095 line 32 records
"Per-candidate decode errors are swallowed (never bubble to the exit-2 catch-all)" as a deliberate
redact-engine design, so redact-engine's two S112 sites are a documented exception, not a defect.
**CodeQL premise resolved at plan time** (the archived plan carried it as unverified): the query
source `python/ql/src/Exceptions/EmptyExcept.ql` on `github/codeql` `main` (fetched 2026-10-15 with
`gh api repos/github/codeql/contents/python/ql/src/Exceptions/EmptyExcept.ql`) flags an `except` only
when every body statement is `pass`, the `try` has no `else`, and no comment lies between the
`except` line and the end of its last body statement. So a comment (trailing included) or any
non-`pass` body clears it, and `continue` bodies are never flagged. Code Quality may run a pinned
older pack, so the post-merge scan stays the confirmation (Phase 4), but the design no longer rests on
a guess.

**Property List.** P1: every remaining S110/S112 handler in the five scripts is either noted or
carries a written justification (nothing unjustified); the claim is about that set, not about every
swallowing return in the files. P2: a note never carries exception text, input text or a computed
label, so the redaction property survives. P3: `_note` never raises on a closed or failing stderr
(it does not claim the surrounding unguarded writes are safe). P4: every fail-closed path (exit code,
verdict line, withheld result) is byte-identical before and after, and a note can never delay or skip
the proxy's process-group kill.

**Cut List.**

- Per-process dedupe inside `_note` (mechanism) buys nothing the silent-probe rule does not: the
  noisy sites are the probes, which stay silent (CTO ruling; dedupe adds mutable state to five
  standalone scripts).
- A shared `_note` module, and a shared probe fixture for the four unit copies (mechanism): scripts
  are invoked standalone by path, `founder-check.py` has an AST-pinned import surface, and a shared
  fixture would re-couple five suites and need new `test-affected-paths.sh` edges (CTO ruling 11).
- Pinned per-script `_note` call counts, the hyphen/digit label PASS row, the redact-engine lock-in
  test and its `redact-sentinel.test.sh` edit, and the `c4-count-parity` run as a PR2 gate (all
  review cuts: the counts live in the same diff as the code, a lock-in on a file with no helper
  cannot fail, and the diff touches no architecture file; `scripts/test-all.sh --affected` runs
  whatever is selected anyway).
- "Restructure a bare `pass` to a non-empty form" and `# noqa` markers on silent handlers (the CodeQL
  query accepts a comment, and ruff `noqa` is PR3a's call).
- Rewriting the `str(e)` fail-closed arms: out of PR2, tracked as a follow-up (below).
- Any ruff/CodeQL config: PR3a owns `ruff.toml`; PR2 pins the version inline in the derivation command.

**Institutional learnings applied.**
`2026-10-15-a-sampled-list-was-restated-as-a-universal-claim-in-the-audits-own-summary.md` (derive
the work list by running the tool, not from the audit sample);
`2026-09-14-my-proxy-allowlisted-the-messages-it-relayed-and-relayed-them-verbatim.md` (the proxy's
stderr is persisted by Claude Code, so nothing derived from input may reach it);
`2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` (the canary
test needs a must-PASS row that is not the canonical, handled in Guard 1).

**CTO rulings (2026-10-15, full text in `decision-challenges.md`).** (1) Expected-negative probe
handlers stay silent with a justification comment; only genuine failure handlers are noted. (2) The
helper takes a static string site label. (3) The `str(e)` fail-closed arms are out of PR2 and go to
one follow-up issue, redact-engine first. (4) Extend the five existing suites; no new file. (5) The
helper's guard is `except (OSError, ValueError)`; the proxy's adds `RuntimeError` because it runs in
signal context. (6) founder-check's best-effort `--out` write failure inside its fail-closed arm is
noted; scan-ancestor's `reconfigure` capability probe stays silent. (7) Proxy `teardown` notes are
collected and emitted after the kill ladder. (8) The proxy note set is five sites; `teardown-sigterm`
(a `ProcessLookupError` on every clean exit) and `teardown-stdin-wait` (the designed route into
escalation) stay silent. (9) Silent handlers keep `pass` plus a greppable justification comment, no
`noqa`. (10) Trimmed test design with per-suite copies of identical assertion text.

## Research Reconciliation — Spec vs. Codebase

| Spec / brief claim | Reality | Plan response |
|---|---|---|
| "5 shipped Python scripts ... add `_note(exc)` logging" including `redact-engine.py` | Both redact-engine swallows are documented expected-negative decode probes (ADR-095) and its only other handler is the fail-closed arm | redact-engine gets ADR-095 justification comments, no `_note` call; recorded as an `operator (scope)` row with an assumed default and a veto path |
| `_note(exc)` signature | CTO: a bare class name is not attributable across several sites in one file | `_note(exc, site)` with a string-literal site label |
| "guarded" means an `OSError` guard (archived plan) | A closed stderr raises `ValueError`; the proxy's teardown runs in a signal handler where a reentrant write raises `RuntimeError` | guard is `except (OSError, ValueError)`, proxy adds `RuntimeError` |
| Teardown handlers all call `_note` (archived plan) | `os.killpg(SIGTERM)` raises `ProcessLookupError` on every clean exit (suite case B10) and `wait_group_empty` polls every 50 ms; `escaped_tree_in` probes every page-text line | those stay silent with a comment (CTO rulings 1 and 8) |
| Whether a log call or a comment clears CodeQL `py/empty-except` (archived plan: unverified) | Verified against the query source: a comment or any non-`pass` body clears it; `continue` bodies are never flagged | silent handlers keep `pass` plus a comment; tracking issue shrinks to a post-merge confirmation |
| 20 `py/empty-except` alerts across 9 files | The audit list is a first-page sample; ruff finds more `pass` handlers than the sample names | the ruff run is the work list; each of the 20 alerts is mapped in the Phase 3 PR-body table (PR2 site, PR3a baseline, or out of scope) |

## Open Code-Review Overlap

One match. Queried 93 open `code-review` issues against every file in `## Files to Edit`.

- #8659 (`review: 33 test suites replace test-helpers' composed EXIT trap and leak the incident sandbox on direct runs`) names `plugins/soleur/test/resolve-debt.test.sh`. **Acknowledge:** a different concern (EXIT-trap composition in 33 suites); PR2 adds assertions to that suite and does not touch its trap setup. The issue stays open.

## Work list and site classification

Derived with the version pinned inline (PR3a lands `ruff.toml`):

```bash
uvx ruff==0.17.0 check --isolated --no-cache --select S110,S112,BLE001 \
  --config 'lint.flake8-bandit.check-typed-exception = true' --output-format concise \
  $(git ls-files 'plugins/soleur/**/*.py' | grep -v '/test/')
```

Result at plan time: S110/S112 only in the five target scripts (proxy 8 S110 + 1 S112, scan-ancestor
2 S110, founder-check 2 S110, resolve-debt 1 S110, redact-engine 2 S112 = 16). BLE001 also fires in
`gemini-imagegen/scripts/*` (7) and `skill-creator/scripts/*` (4): those handlers print the error and
are not silent, so they stay out of PR2 (one sentence in the PR body). Classification rule (CTO
rulings 1 and 8): note a handler that swallows an OS, I/O or process failure that is not the normal
outcome of its call; stay silent on a per-item probe inside a loop, a capability probe, or a step of
an escalation ladder whose negative result is the designed path. **The clean-session no-marker row
(Phase 1) is the empirical arbiter:** any noted site that fires in a clean session is reclassified
silent before merge.

| Script | Handler (content anchor) | Disposition |
|---|---|---|
| `playwright-mcp-redact-proxy.py` | server-request reply: `write_line(self.child.stdin, jsonrpc_error(... -32601 ...))` `except (OSError, ValueError)` | `_note(exc, "reply-unrelayed-request")` (main loop, direct call) |
| | `escaped_tree_in`: `json.loads(cand)` `except (ValueError, RecursionError): continue` | silent, comment: per-line probe over page text, negative is the normal result |
| | `wait_group_empty`: `self.child.wait(timeout=0.05)` `except subprocess.TimeoutExpired` | silent, comment: 50 ms poll |
| | `teardown`: stdin `close()` `except OSError` | deferred note `"teardown-stdin-close"` |
| | `teardown`: `child.wait(timeout=STDIN_CLOSE_WAIT_S)` `TimeoutExpired` | silent, comment: the designed route into the SIGTERM step |
| | `teardown`: `os.killpg(self.pgid, signal.SIGTERM)` `ProcessLookupError` | silent, comment: the group is already empty after a clean exit |
| | `teardown`: `os.killpg(self.pgid, signal.SIGKILL)` `ProcessLookupError` | deferred note `"teardown-sigkill"` (reached only after SIGTERM failed to empty the group) |
| | `teardown`: `child.wait(timeout=self.grace)` `TimeoutExpired` | deferred note `"teardown-final-wait"` (the direct child survived the ladder) |
| | `teardown`: `self.out.flush()` `except (OSError, ValueError)` | deferred note `"teardown-flush"` |
| `founder-check.py` | `_clear_outputs`: `os.unlink(p)` `except OSError` | `_note(exc, "clear-output")` |
| | `main`: best-effort `--out` write inside the fail-closed `except Exception` arm, `except OSError` | `_note(exc, "out-file-write")`; rc 4 and the stdout verdict line stay byte-identical |
| `resolve-debt.py` | atomic-write cleanup: `os.unlink(tmp_path)` `except OSError` before `raise` | `_note(exc, "tmp-cleanup")` |
| `scan-ancestor-signal-helpers.py` | `flush_stdout`: `sys.stdout.flush()` `except (OSError, ValueError)` | `_note(exc, "flush-stdout")`; the `UNRESOLVED:` line and rc 3 stay unchanged |
| | `main`: `sys.stdout.reconfigure(...)` `except AttributeError` | silent, comment names the replaced-stream case |
| `redact-engine.py` | `_b64_decode` and the hex loop in `_scan_encoded`: `except (binascii.Error, ValueError): continue` | silent, comment cites ADR-095; no helper in this file |

Nine `_note` call paths (proxy 5, founder-check 2, resolve-debt 1, scan-ancestor 1). Silent
handlers: seven (proxy 4, scan-ancestor 1, redact-engine 2). The expected ruff remainder after PR2 is
therefore seven silent S110/S112 handlers plus four helper guards (the one deliberate silent handler
per helper, documented in a comment) plus three BLE001 fail-closed arms (scan-ancestor, redact-engine,
founder-check); the table is the source of truth and the Phase 3 re-run states the measured number.

Helper shape (illustrative; each script uses its own prefix and style):

```python
def _note(exc, site):
    # Class name and a static site label only. Never str(exc)/repr(exc)/input text: exception text can
    # carry the content a redaction path exists to remove. `site` is a string literal at every call site.
    try:
        sys.stderr.write("founder-check: swallowed %s at %s\n" % (type(exc).__name__, site))
        sys.stderr.flush()
    except (OSError, ValueError):
        pass  # a closed or full stderr must not turn a swallowed error into a crash
```

Proxy variant (CTO ruling 7): `_note` routes through the existing `log()` (unmodified) inside a guard
that also catches `RuntimeError`. Inside `teardown`, handlers append `(exc, "<literal>")` to a local
`pending` list and a loop emits `_note(...)` for each after the kill ladder, immediately before the
existing `child exited rc=...` log, so a note can never run before `os.killpg` and `teardown` (which
`on_signal` also calls) cannot raise ahead of the kill.

## Implementation Phases

### Phase 0 - Precondition and baseline

1. Re-run the derivation command above; the S110/S112 set must equal the table (a script found
   outside the five is justified in the PR body and added to the table). Save the output into the
   scratchpad for the PR body.
2. Run the suites that execute the five scripts on the unchanged tree and keep their green baselines
   and their captured outputs: the agent-browser proxy suite, `playwright-mcp-lifetime.test.sh` and
   `redact-a11y-snapshot.test.sh` (both spawn the proxy), `incident/test/redact-sentinel.test.sh`,
   `plugins/soleur/test/preflight-founder-check.test.ts`, `plugins/soleur/test/resolve-debt.test.sh`,
   `plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh`.
3. Run a clean real proxy session (EOF teardown) and record which noted sites fire; any that do move
   to the silent column before Phase 1.
4. Confirm `scripts/test-all.sh --affected` selects the `resolve-debt` and `scan-ancestor` suites from
   a diff to their scripts (no explicit edge exists; they rely on derivation from `$SCRIPT` literals).

### Phase 1 - Tests first (RED), `cq-write-failing-tests-before`

Extend the four suites whose scripts gain a helper (proxy, founder-check, resolve-debt,
scan-ancestor); per-suite copies carry identical assertion text (CTO ruling 10). redact-engine's suite
is not edited. Per suite:

1. **Unit, via import.** Load the script with `importlib.util.spec_from_file_location` (all five
   import side-effect free under `python3 -I`, verified at plan time; the founder-check TS suite
   spawns `python3 -I` like its existing harness). Assert: the line reads
   `<prefix>: swallowed <ClassName> at <site>`; an exception whose message carries a canary string
   leaves the canary absent from stderr; no raise when `sys.stderr.write` raises `OSError` and when
   `sys.stderr` is a closed file (one case); a user-defined `OSError` subclass prints its own name.
2. **AST census (the leak guard).** Every `_note(` call in the script, and in the proxy every
   `pending.append((exc, <label>))` tuple inside a handler, has a string-literal label; the census
   finds at least one call (a floor, so zero found fails; no per-script pinned count, PR3a's ratchet
   owns handler drift). A harness row feeds it `_note(exc, site="x")` and `_note(str(exc), "a")` and
   states the verdict (both fail).
3. **Per-site behaviour where an existing trigger reaches the site.** scan-ancestor `flush-stdout`
   via the suite's stdout-on-`/dev/full` case, asserting the note appears and the `UNRESOLVED:` line
   and rc 3 are unchanged; founder-check `out-file-write` via an `--out` that is a directory
   combined with the existing internal-error trigger, asserting rc 4 and the stdout verdict line
   byte-identical to a literal captured on the unchanged script, plus one extra stderr line. The
   other sites (`clear-output`, `tmp-cleanup`, the proxy deferred notes beyond one) are covered by
   the census only, and the plan says so.
4. **Proxy, real subprocess.** (a) A clean EOF session emits no `swallowed` marker (characterization:
   passes today, fails if a noted site turns out to fire on a clean exit, and fails if a note is added
   to a probe). (b) A session whose child ignores EOF and needs the SIGKILL step: the marker set is
   fixed per fixture before the test is written (expected: `teardown-sigkill`, possibly
   `teardown-final-wait`), the canary in the client input is absent from stderr, and the existing
   `child exited rc=...` and `survived SIGTERM` rows are unchanged. (c) A result with non-JSON
   candidate lines containing the canary ends with no marker and a still-redacted result. (d) A unit
   case where `sys.stderr.write` raises `RuntimeError` inside `teardown`, asserting the group kill
   still happens (the deferred emit). Only extend `fake-playwright-mcp.py` if no existing switch
   (`FAKE_PW_HOLD`, `FAKE_PW_RESULT_FILE`) reaches (b) or (c); decide in Phase 0.
5. The cases in 1-3 and 4(b), 4(d) are RED before Phase 2; 4(a) and 4(c) are characterization cases
   and are labelled as such. New bash assertions must satisfy `scripts/lint-shell-capture-exit.py`
   (the baseline must not gain a key). The resolve-debt suite gains a case labelled
   `T-note: swallowed note carries the class name only` so its `PASS: T-note` line is the
   discoverability signal.

### Phase 2 - Implement

1. Add `_note(exc, site)` to the four scripts that call it, beside their existing small helpers
   (follow each script's own stderr style), and call it from the sites in the table. Keep every
   `except` clause's type tuple and control flow unchanged; the note (or the `pending.append`) is the
   only added statement.
2. Add the greppable justification comment to the seven silent handlers (cite ADR-095 in
   redact-engine); keep the bare `pass`/`continue`, no `noqa`, no restructuring.
3. Do not touch `log()` (a mutation target in the proxy suite), any fail-closed arm's message or exit
   code, or `founder-check.py`'s imports (an AST test pins its import surface; `_note` uses the
   already-imported `sys`).

### Phase 3 - Verify

1. Phase 1 cases GREEN; the suites pass with pre-existing assertions unchanged; diff the captured
   outputs of the merged-stream suites (`redact-sentinel`, `resolve-debt`, `preflight-founder-check`,
   `scan-ancestor`) against the Phase 0 baselines.
2. Re-run the derivation command; the remainder equals the table as updated in Phase 0 step 3.
   Build the PR-body table mapping each of the 20 audit `py/empty-except` alerts to a PR2 site, a
   PR3a baseline entry, or out of scope (the repo-only hook and tests).
3. Run `scripts/test-all.sh --affected` and `python3 scripts/lint-shell-capture-exit.py --baseline
   scripts/lint-shell-capture-exit.baseline.txt`, and run `scan-ancestor-signal-helpers.py --list`
   over the edited suites.
4. Guard 1 spot-check, informal and not an acceptance gate: apply each mutation to a scratch copy
   (the proxy via `make-proxy-mutant.py` and `MUTANT_PATH` with the anchor chosen so it occurs exactly
   once; the other three by pointing the suite's `SCRIPT` at a patched scratch copy) and confirm RED.
5. Re-run the discoverability command; once the PR's Code Quality scan has run, read its code-scanning
   result for the five files and record it in the PR body (do not claim CodeQL clean before then).

### Phase 4 - Issues, PR body, umbrella

1. File the **tracking issue** (labels `type/chore`, `priority/p3-low`; milestone `Post-MVP / Later`;
   `Re-eval by: 2026-11-14`): title `chore(quality): confirm the PR2 empty-except changes cleared CodeQL py/empty-except (PR2 of #10331)`.
   Body: the query-source finding (a comment or non-`pass` body clears it; `continue` is never
   flagged), the nine noted and seven commented sites, and the decision rule: after the first Code
   Quality scan following the merge, if the alert count for these files did not drop, read the
   rule-version the scan used and either add the missing comment form or dismiss the remainder with a
   stated reason through browser automation; `Ref #10331`.
2. File the **follow-up issue** for the `str(e)` fail-closed arms (labels `type/security`,
   `deferred-scope-out`, `priority/p2-medium`; milestone `Post-MVP / Later`; `Re-eval by:
   2026-11-14`, and before any new fail-closed arm is added to a redaction path): redact-engine
   `main()` writes `{e}` first (leak class: scanned content can reach an exception message), then
   founder-check (`str(e)[:120]` in the JSON detail) and scan-ancestor (UNRESOLVED arm) as low
   priority; list the adjacent items found in review: unguarded stderr writes that still raise on a
   closed stderr (the proxy's `log()` calls, scan-ancestor's `Unresolved` arm exits rc 1 instead of
   3), and `founder-check` `clear-output` leaving a stale output file a caller could read as a fresh
   verdict. No duplicate exists (searched 2026-10-15).
3. PR body: `Ref #10331`, no closing keyword; state "PR2 adds `_note` beside the unchanged `str(e)`
   arm in redact-engine"; list the remaining ruff handlers by pointing at the Phase 3 output; render
   the `operator (scope)` row from `decision-challenges.md` (redact-engine has no `_note`); say "the
   guard catches `OSError` and `ValueError` (the proxy's also `RuntimeError`)", never "OSError guard";
   state the precondition (ruff output equals the table) and what happens if it fails (a script
   outside the five is added and justified); say plainly that the note's diagnostic value is a
   breadcrumb and an alert-clearing change, not a user-actionable message. After `ship` rewrites the
   body, run `gh pr view 10375 --json body --jq .body | grep -iE '(close[sd]?|fix(e[sd])?|resolve[sd]?) +#'`
   and require no match, and confirm both issue links appear with `Ref`.
4. Comment the updated umbrella checklist on #10331.

## Files to Edit

- `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py`
- `plugins/soleur/skills/preflight/scripts/founder-check.py`
- `plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py`
- `plugins/soleur/scripts/scan-ancestor-signal-helpers.py`
- `plugins/soleur/skills/incident/scripts/redact-engine.py` (comments only)
- `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh`
- `plugins/soleur/test/preflight-founder-check.test.ts`
- `plugins/soleur/test/resolve-debt.test.sh`
- `plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh`
- `plugins/soleur/skills/agent-browser/test/fixtures/fake-playwright-mcp.py` (only if no existing switch reaches Phase 1 case 4(b) or 4(c); decided in Phase 0)

All globs verified against `git ls-files` at plan time. `scripts/lib/test-affected-paths.sh` selects
the proxy and redact-engine suites explicitly (the proxy is listed for `playwright-mcp-lifetime.test.sh`,
which is why that suite joins the baseline); `resolve-debt` and `scan-ancestor` rely on derivation,
confirmed in Phase 0 step 4. `plugins/soleur/scripts/*.test.sh` and `plugins/soleur/test/*.test.sh`
are covered by the suite globs.

## Files to Create

None (CTO ruling 4). Planning artifacts only: this plan, `tasks.md` and `decision-challenges.md` under
`knowledge-base/project/{plans,specs}/`.

## User-Brand Impact

**If this lands broken, the user experiences:** a redaction proxy that crashes on a closed stderr or
skips its process-group kill during teardown (Chrome left running), or a `founder-check` fail-closed
verdict (rc 4) that changes shape, so an agent session sees an unredacted browser result or a
preflight that misreports.

**If this leaks, the user's data is exposed via:** a stderr note that echoes exception text or an
input-derived label from a redaction path; Claude Code persists the proxy's stderr in its MCP logs, so
a leaked fragment outlives the session.

**Brand-survival threshold:** single-user incident

The CPO sign-off from the brainstorm and the archived plan's CPO review (verdict proceed; PR3b is the
conditional part) carries forward to PR2, which is detect-free and adds no execution surface.
`soleur:engineering:review:user-impact-reviewer` runs at review time on this PR. The CLO attestation
for the proxy (`knowledge-base/legal/audits/2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md`)
does not enumerate stderr lines exhaustively and pins no file hash; the new line carries a class name
and a static label, so no addendum is owed, and the work phase greps it for stderr claims once to
confirm.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled eleven forks on 2026-10-15 (see Research Insights and `decision-challenges.md`) and reviewed the finished plan for developer experience; plan-review (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow) returned two P1 bugs (teardown notes on a normal exit; a note ahead of the kill in signal context), both fixed in this revision, and simplification cuts, applied. The slice is one subsystem root (`plugins/soleur`), about nine files and roughly 250 changed lines.

### Legal

**Status:** reviewed
**Assessment:** `soleur:gdpr-gate` run on this plan 2026-10-15 (fired by the `single-user incident` threshold, not by the path regex): path scan 10 examined, 0 matched; no finding on Art. 6, 5(1)(e), 17, Chapter V or Art. 9; one Suggestion (Art. 32 observation: the proxy's stderr is persisted by Claude Code, mitigated by the class-name-only canary tests and the literal-label AST census, Guard 1 rows 1, 3, 5); no Critical finding, nothing written to `compliance-posture.md`. No processing activity is added: the note carries a class name and a static label. The proxy's CLO attestation (#7980) needs no addendum (see User-Brand Impact). The follow-up `str(e)` issue is the legal-adjacent item.

### Product/UX Gate

**Tier:** none
**Decision:** no user-facing UI surface; no file in the Files lists matches the UI-surface term list.
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Observability

```yaml
liveness_signal:
  what: a `<script>: swallowed <ClassName> at <site>` line on the customer's terminal stderr whenever a swallowed one-shot failure occurs; the canary, closed-stderr and census cases inside the four existing suites guard the helper itself
  cadence: per occurrence at runtime; per PR in the required test battery
  alert_target: none at runtime by design (plugin scripts on a customer-hosted CLI, observability layer 7, no Sentry for privacy); required `test` check status on the PR for the tests
  configured_in: each script's `_note`; plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh, plugins/soleur/test/resolve-debt.test.sh, plugins/soleur/test/preflight-founder-check.test.ts, plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh
error_reporting:
  destination: stderr of the script (the proxy's stderr is persisted in Claude Code's MCP logs)
  fail_loud: true
failure_modes:
  - mode: a note leaks exception text, input text or a computed label
    detection: canary-in-exception-message unit case plus the AST literal-label census plus the proxy subprocess canary case
    alert_route: required test red
  - mode: `_note` raises on a closed or failing stderr (or, in the proxy, on a reentrant signal-context write) and turns a swallowed error into a crash or skips the group kill
    detection: closed-file and OSError-writing stderr unit cases in each of the four suites, plus the proxy RuntimeError-in-teardown case asserting the kill still happens
    alert_route: required test red
  - mode: a probe handler or a clean teardown starts noting and floods stderr
    detection: the proxy clean-session and non-JSON-candidate no-marker cases
    alert_route: required test red
  - mode: a new swallowed handler lands later with no note
    detection: not covered in PR2; PR3a's ruff baseline ratchet (S110/S112 with check-typed-exception) covers it
    alert_route: required test red after PR3a
logs:
  where: the user's terminal stderr; Claude Code MCP logs for the proxy; GitHub Actions run logs for the tests
  retention: GitHub default (90 days) for CI; local for the customer
discoverability_test:
  command: bash plugins/soleur/test/resolve-debt.test.sh
  expected_output: PASS: T-note
```

The smallest of the four suites: measured 2026-10-15 at 3.6 s wall time, ending in `Passed: 50`,
`Failed: 0` and `ALL TESTS PASSED`, well inside Check 10's 15 s cap (the scan-ancestor suite
measured 13 s and the proxy suite is far longer). The expected literal is the new case's own
`PASS: T-note` line, which does not exist on the unchanged tree, so the probe can fail on the feature
(the generic `ALL TESTS PASSED` line would pass with the new cases deleted). A one-line `python3 -c`
probe was rejected: Check 10 refuses `;` anywhere in the command, and a loader one-liner needs
several. The command contains none of the shell-active characters Check 10 rejects.

## Guard Contract

### Guard 1 - class-name-only note

**Property.** A `_note` call in a shipped plugin script writes only the exception class name and a
static string-literal site label, never raises, never runs before the proxy's group kill, and is absent
from every silent probe handler and from a clean proxy teardown.

**Assembly.** The four `_note` definitions (proxy, founder-check, resolve-debt, scan-ancestor), every
call to them and, in the proxy, every deferred `pending.append((exc, label))` in `teardown`; the seven
silent handlers (proxy 4, scan-ancestor 1, redact-engine 2); the four suites that test them. The
chokepoint is each script's `_note`; the AST census in each suite quantifies over every call and
every deferred tuple in its script, not the ones the tests happen to drive.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | `_note` formats `str(exc)` (or `repr(exc)`) into the line | the canary carried in the exception message appears on stderr |
| 2 | Remove the `except` guard in `_note` (or, in the proxy, drop `RuntimeError` from it) | the closed-stderr and OSError-writing unit cases raise, or the proxy RuntimeError-in-teardown case skips the kill |
| 3 | Pass a computed label at the first call site (`_note(exc, "x " + str(exc))`) | the AST census requires a string-literal label on every call |
| 4 | Delete every `_note` call in one script (own dispatch: the census) | the census floor of at least 1 fails, so a suite that finds 0 calls cannot pass |
| 5 | Add a second call after a compliant first, passing the exception message as the label | the census walks every call, not the first, and rejects the non-literal one |
| 6 | Add a `_note` call inside the proxy `escaped_tree_in` loop, or move a noted handler onto the clean-exit path | the non-JSON-candidate and clean-session no-marker cases see a `swallowed` marker |
| 7 | Make a fail-closed arm change rc or the verdict line while adding its note (founder-check) | the byte-identical rc 4 and stdout assertion against the literal captured on the unchanged script |

**Harness rows.** RED: make the unit case skip silently when the module fails to load, or let the
census report zero calls and pass; the suite must fail on a load failure and on a zero-call census,
not report zero cases. PASS (not the canonical): a user-defined `OSError` subclass prints its own
class name; stderr replaced by an object whose `write` raises `ValueError` returns normally; the
census accepts a keyword-free call whose label is a `str` constant and rejects `site="x"` and
`str(exc)` as stated in Phase 1 case 2.

**Anchor.** The census has no stored count, so the failure to chase is an unreviewed new handler or
call, not a drifted number. The independent anchors are the ruff derivation output pasted into the PR
body (re-runnable by any reviewer with the pinned command) and PR3a's baseline ratchet, which keys the
remaining S110/S112 handlers against a committed multiset that can only shrink. The matrix is verified
by the Phase 3 scratch-copy spot-check, not by a CI gate.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add guarded, class-name-only `_note(exc)` logging to 5 shipped Python scripts: the 4 named in the issue" [brief] | Phase 1 and 2, the proxy, founder-check, resolve-debt and scan-ancestor rows | mapped |
| 2 | "plus plugins/soleur/skills/incident/scripts/redact-engine.py" [brief] | Phase 2 step 2 (comments); no `_note` call, per the `operator (scope)` row in `decision-challenges.md` | mapped |
| 3 | "PR body must use `Ref #10331`, NOT a closing keyword" [brief] | Phase 4 step 3 (with a post-`ship` grep) | mapped |
| 4 | "When PR2 is opened, also file the py/empty-except tracking issue." [brief] | Phase 4 step 1 | mapped |
| 5 | "just keep them in the umbrella checklist" [brief] | Overview checklist, Phase 4 step 4 | mapped |
| 6 | "the new plan for this branch must be scoped to PR2 ONLY" [brief] | whole plan; PR3a, PR3b and PR4 appear only as unchecked checklist lines | mapped |
| 7 | "replace silent `except: pass` and `except BaseException` with logged or re-raised handling, starting with the redaction proxy and the security hook" [issue #10331] | Work list table; the `except BaseException` arms are fail-closed and stay untouched, the security hook is repo-only and falls to PR3a | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `_note` helper in four scripts, class name only, own guard | "guarded, class-name-only `_note(exc)` logging" | asked |
| Static `site` label argument | — | inferred — justification: CTO ruling 2; a bare class name is not attributable across several sites in one file |
| Guard catches `ValueError` as well as `OSError`, and `RuntimeError` in the proxy | "guarded" | inferred — justification: a closed stderr raises `ValueError` and a reentrant signal-context write raises `RuntimeError`, so a narrower guard would let the swallowed error crash the script, which is the property "guarded" names |
| Deferred emit of the proxy's teardown notes | — | inferred — justification: CTO ruling 7; `teardown` runs from the SIGTERM handler and a note ahead of `os.killpg` could skip the kill, the proxy's core invariant |
| Silent handlers with justification comments (proxy 4, scan-ancestor 1, redact-engine 2) | — | inferred — justification: CTO rulings 1, 8 and 9, and ADR-095; noting expected-negative probes would print thousands of lines or a line on every clean session, and the CodeQL query accepts a comment |
| redact-engine.py comment-only edit | "plus plugins/soleur/skills/incident/scripts/redact-engine.py" | inferred (narrowed) — justification: the ask was a `_note` call; both swallows are documented probes (ADR-095) and a helper with zero call sites would be dead code; the `operator (scope)` row carries the veto path |
| Test additions in the four suites for the scripts that gain a helper | — | inferred — justification: `cq-write-failing-tests-before`, and the redaction property is only enforced if a canary test exists |
| Proxy fixture edit (conditional) | — | inferred — justification: needed only if no existing fixture switch reaches Phase 1 case 4(b) or 4(c) |
| Tracking issue for the CodeQL confirmation | "also file the py/empty-except tracking issue" | asked |
| Follow-up issue for the `str(e)` fail-closed arms and adjacent findings | — | inferred — justification: `wg-when-deferring-a-capability-create-a`; the CTO deferred a leak-class finding out of PR2, and a deferral without an issue is invisible |
| Umbrella checklist | "keep them in the umbrella checklist" | asked |
| `decision-challenges.md` rows | — | inferred — justification: the pipeline contract requires every ruling persisted as a `Decision Classes` row for `ship` to render |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 9 (10 with the conditional fixture) | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] The pinned ruff derivation over `plugins/soleur/**/*.py` (excluding tests) shows S110/S112 only in the five scripts, and the remainder equals the plan's table as updated in Phase 0 step 3; every remaining handler is traceable to a table row with its justification (the gemini-imagegen and skill-creator BLE001 hits get one sentence in the PR body)
- [ ] Nine `_note` call paths exist (proxy 5, founder-check 2, resolve-debt 1, scan-ancestor 1), each with a string-literal site label; `redact-engine.py` has none and a clean proxy session emits no `swallowed` marker
- [ ] The Phase 1 cases pass in the four suites whose scripts gain a helper: canary absent, closed-stderr and OSError-writing stderr safe, the census finds at least one call with only literal labels, and the proxy RuntimeError-in-teardown case still performs the kill
- [ ] The proxy's existing rows (stderr marker counts, `child exited rc=...`, `survived SIGTERM`, log-scrub, the mutant rows) pass unchanged, as do `playwright-mcp-lifetime.test.sh` and `redact-a11y-snapshot.test.sh`; founder-check rc 4 and its stdout verdict are byte-identical to the literal from the unchanged script; scan-ancestor keeps its `UNRESOLVED:` line and rc 3; redact-engine output and exit codes are unchanged
- [ ] The Phase 3 spot-check recorded each Guard 1 mutation going RED in a scratch copy (informal; not a CI gate)
- [ ] `scripts/test-all.sh --affected` and the `lint-shell-capture-exit` baseline check are green, and the captured outputs of the merged-stream suites match their Phase 0 baselines apart from the new cases
- [ ] The tracking issue and the `str(e)` follow-up issue exist and are linked in the PR body; the post-`ship` body grep finds no `Closes`/`Fixes`/`Resolves` and the body has `Ref #10331`; the `operator (scope)` row is rendered in the PR body
- [ ] The umbrella checklist comment is on #10331 with PR1 checked and PR2 linked

### Post-merge

- [ ] None that require a person: the CodeQL confirmation is tracked by the tracking issue with its decision rule and a re-evaluation date

## Test Scenarios

- Given an exception whose message carries a canary, when `_note(exc, "probe")` runs, then stderr holds `<prefix>: swallowed <ClassName> at probe` and not the canary (the four scripts that gain a helper)
- Given `sys.stderr` is a closed file or its `write` raises `OSError`, when `_note` runs, then it returns normally; in the proxy a `RuntimeError` is also absorbed
- Given the proxy tears down on a clean stdin EOF, when the session ends, then no `swallowed` marker appears and `child exited rc=0` is unchanged
- Given a child that survives SIGTERM, when the proxy tears down, then the notes (for example `teardown-sigkill`) are emitted after the group kill and the canary in the client input is absent from stderr
- Given a tool result with non-JSON lines containing a canary, when the proxy checks for an escaped tree, then no `swallowed` marker appears and the result is still redacted
- Given founder-check's `--out` path is unwritable and an internal error occurs, when it runs, then rc is 4, the stdout verdict line is byte-identical to the unchanged script, and stderr gains one `out-file-write` line
- Given scan-ancestor's stdout is full, when `flush_stdout` swallows the error, then the note appears and the `UNRESOLVED:` line and rc 3 are unchanged

## Sharp Edges

- Never log `str(exc)`, `repr(exc)`, `exc.args` or any input-derived label from these scripts: exception text can carry the content a redaction path removes, and the proxy's stderr is persisted by Claude Code. The site label is a string literal.
- A closed stderr raises `ValueError`, not `OSError`, and a stderr write from the proxy's signal handler can raise `RuntimeError` (reentrant `BufferedWriter`); keep each guard as narrow as its tuple so a bug in `_note` is not masked. P3 covers `_note` only: the unguarded `log()` writes next to the new notes still raise on a closed stderr, and that is a follow-up item, not a PR2 claim.
- In `teardown`, never write to stderr before the `os.killpg` calls: collect `(exc, label)` pairs and emit after the ladder. `teardown` also runs from `on_signal`.
- Do not modify the proxy `log()` line (`sys.stderr.write(f"{PREFIX} {msg.translate(_LOG_SCRUB)}\n")`): the proxy suite's log-scrub mutant row matches it by exact text. Route the proxy's `_note` through `log()` inside the guard instead.
- `founder-check.py` has an AST-pinned import surface (`preflight-founder-check.test.ts`, "Guard 4"): `_note` may use only the already-imported `sys`, and no new `subprocess` references.
- The proxy suite counts stderr lines by marker (`assert_stderr_marker <needle> <count>`) and `make-proxy-mutant.py` requires the replaced text to occur exactly once in the file (`type(exc).__name__`, `except (OSError, ValueError):\n pass` and bare `continue` each occur several times); choose a longer anchor or have the spot-check assert the mutant landed. Only the proxy suite has a mutant mechanism; the other three need a scratch copy with `SCRIPT` pointed at it.
- Guard 1's mutation rows touch the proxy's `teardown`, which contains `os.killpg`. Apply every mutant to a scratch copy, never in place and never by inverting a signalling line; follow `plugins/soleur/skills/work/references/work-scratch-sandboxes.md` (section "Mutating a signalling or file-removing helper").
- `redact-sentinel.test.sh` and `resolve-debt.test.sh` capture `2>&1` into one stream, and `preflight-founder-check.test.ts` and `scan-ancestor-signal-helpers.test.sh` assert on stderr content, so a new stderr line can land inside assertions written before PR2. Run each suite on the unchanged tree first (Phase 0) and diff the captured outputs after Phase 2.
- CodeQL `py/empty-except` treatment is read from the query source on `main` (comment or non-`pass` body clears it); Code Quality may run a pinned older pack, so do not state in the PR body that CodeQL is clean before a scan has run on the branch. Ruff `noqa` is not honoured by CodeQL and is not used.
- The discoverability command was executed at plan time (3.6 s) and contains none of the shell-active characters preflight Check 10 rejects; re-run it after Phase 2, because the new `PASS: T-note` line only exists then.
- `plugins/soleur/test/resolve-debt.test.sh` is named by open code-review issue #8659 (EXIT-trap composition); add assertions without touching its trap setup.
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this plan's section is filled.
