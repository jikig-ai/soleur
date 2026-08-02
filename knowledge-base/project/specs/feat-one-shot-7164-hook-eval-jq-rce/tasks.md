---
title: "Tasks — fix(security): eval over jq @sh in 10 PreToolUse hooks (#7164)"
plan: knowledge-base/project/plans/2026-08-02-fix-hook-input-eval-jq-rce-plan.md
issue: 7164
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-08-02
---

# Tasks — #7164 hook input `eval` RCE

Derived from `knowledge-base/project/plans/2026-08-02-fix-hook-input-eval-jq-rce-plan.md`.
Phase order is **dependency order**, not file order — do not reorder.

Ship as **one PR, two commits**: commit 1 = the 10 `eval` hooks, commit 2 = the 8 `$( )` siblings.

---

## 1. Preconditions (measure only; write no product code)

- [ ] 1.1 Re-run the #7164 reproducer against all 10 hooks from a `mktemp -d` CWD with
      `INCIDENTS_REPO_ROOT` redirected. Record `RCE CONFIRMED` per hook.
      **Never run it from the worktree root** — the payload's trailing words go to `touch`.
- [ ] 1.2 `printf '{}' | jq -j '"a","\u001e","b"' | od -c` must show `a 036 b`. If not, STOP — the
      delimiter is wrong for this jq.
- [ ] 1.3 Reproduce the plan's P8 benchmark on this machine: legacy `eval` vs the `$( )`-capture form
      at 100 B / 2 KB / 20 KB / 200 KB, 100 iters each, plus a 10 MB single shot with
      `/usr/bin/time`. The new form must win at every size. Save the table for the PR body (AC6).
- [ ] 1.4 `bash -n` all 18 Bash-matcher hooks pre-change.
- [ ] 1.5 Confirm `permissionDecision: "ask"` is still honored: re-read
      `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md` and check the running CC major version has not
      passed the probe's `2.1.142`. If it has, re-probe per that document before designing around `ask`.
- [ ] 1.6 Confirm the file lists: `git grep -lE 'eval "\$\(echo "\$INPUT" \| jq -r .@sh' .claude/hooks/*.sh`
      → 10; and the 8 `$( )` siblings + 2 OpenHands mirrors named in the plan's `Files to Edit`.

## 2. Telemetry first (must precede the first `emit_incident`)

- [ ] 2.1 Add `map(select(startswith("hook-input-") | not))` to the `$orphan_ids` pipeline in
      `scripts/rule-metrics-aggregate.sh`, commented in the shape of the existing
      `context-reviewed-` block.
- [ ] 2.2 Add the paired cases to `scripts/rule-metrics-aggregate.test.sh`.
- [ ] 2.3 Run the aggregator over a fixture jsonl carrying a `hook-input-parse-failure` row; assert
      `.summary.orphan_rule_ids | length == 0` (AC10).

## 3. RED first — the idiom ban

- [ ] 3.1 Create `.claude/hooks/hook-input-contract.test.sh` with the `command -v jq || SKIP`
      preflight (pure bash + jq only — the `test-scripts` CI shard has no bun and no node).
- [ ] 3.2 Add assertion 1 (idiom ban): for every non-`*.test.sh` file under `.claude/hooks/` and
      `.openhands/hooks/`, `grep -vE '^[[:space:]]*#' | grep -cE 'eval[[:space:]]+"\$\('` is 0.
      Allow-list the two `eval "exec ${fd}>&-"` lines in `lib/session-state.sh` **by exact string**,
      not by file.
- [ ] 3.3 **Observe it FAIL on the unmodified tree** and record the output
      (`cq-write-failing-tests-before`). Do not proceed until it has been seen RED.

## 4. The extractor (contract)

- [ ] 4.1 Create `.claude/hooks/lib/hook-input.sh` with `hook_parse_input` and
      `hook_input_fault_respond`, per the plan's Phase 3 design table.
- [ ] 4.2 jq program: `try (<expr>) catch {__e:true}` per field; `err` / `ok` / `anom` tagging;
      `contains("\u001e")`-guarded strip on the `anom` branch only. **No `explode`** (measured
      8.55 s / 180 MB on 10 MB vs 0.70 s / 43 MB for the code being replaced).
- [ ] 4.3 Bash side: `raw=$(... ; printf 'X'); raw=${raw%X}`, then `set -f; IFS=$'\x1e'; slots=($raw); set +f`
      with `IFS` restored. **No `read -d` / `mapfile -d`** (measured 2.5× regression at 200 KB).
- [ ] 4.4 `(( $# % 2 == 0 )) || { zero_all; return 1; }` — an odd argument count must NOT return success.
- [ ] 4.5 Zero every out-parameter before **every** `return 1` / `return 2`.
- [ ] 4.6 Variable-name guard: `^[A-Za-z_][A-Za-z0-9_]*$` **plus** the denylist
      `IFS PATH PS4 BASH_ENV SHELLOPTS BASHOPTS CDPATH GLOBIGNORE LD_PRELOAD PROMPT_COMMAND`.
- [ ] 4.7 Oversize refusal before the jq fork: `(( ${#input} > 262144 ))` ⇒ `reason=oversize`.
- [ ] 4.8 Use `printf '%s' "$input"`, never `echo "$INPUT"` (echo interprets backslashes and
      `-n`/`-e` — a second, previously unreported input-mangling bug in all 18 hooks; call it out in
      the PR body).
- [ ] 4.9 Set `HOOK_INPUT_STATUS` (`ok|transport|anomalous`) and `HOOK_INPUT_REASON`
      (`jq_missing|surrogate|structural|oversize|nonstring|argc`).
- [ ] 4.10 `hook_input_fault_respond` emits the incident + stderr; prints the `ask` envelope **with
      `hookEventName: "PreToolUse"`** and exits 0 for anomalous / jq-missing / escalated cases;
      returns 0 (caller continues fail-open) for a plain transport fault.
- [ ] 4.11 Per-session parse-failure counter via `.claude/hooks/lib/session-state.sh`; escalate to
      `ask` after 3 faults in one session.
- [ ] 4.12 Must NOT source `lib/incidents.sh` (source ordering of `headless_or_stderr` is load-bearing).
- [ ] 4.13 Must contain no `| grep -q` (`grep-q-pipe-guard.test.sh` sweeps `lib/*.sh`).
- [ ] 4.14 `shellcheck -s bash -x` must be **zero findings**, including `SC2034` (drop unused locals).
- [ ] 4.15 Header comment in ADR-116 form (`<file> › <symbol>()`, never `<file>:NNN`), stating the
      contract and marking jq exprs as **source literals only**.

## 5. Lone-surrogate recovery

- [ ] 5.1 On the **failure path only**, retry once after
      `perl -pe 's/\\u[dD][89abAB][0-9a-fA-F]{2}(?!\\u[dD][c-fC-F])/\\ufffd/g'`.
- [ ] 5.2 On a successful retry set `reason=surrogate` and proceed with the guards **armed**.
- [ ] 5.3 On a still-failed parse, take the transport-fault path with `reason=structural`.
- [ ] 5.4 Verify against real harness output:
      `node -e 'process.stdout.write(JSON.stringify({tool_input:{command:"git \ud800 stash"},cwd:"/x"}))'`.

## 6. Commit 1 — migrate the 10 `eval` hooks

- [ ] 6.1 `guardrails.sh` (`COMMAND`, `TOOL_NAME`, `FILE_PATH` incl. the `notebook_path` fallback)
- [ ] 6.2 `cla-signed-author-gate.sh` (`CMD`, `WORK_DIR`)
- [ ] 6.3 `context-reviewed-gate.sh` (`CMD`)
- [ ] 6.4 `follow-through-directive-gate.sh` (`CMD`, `WORK_DIR`)
- [ ] 6.5 `prod-write-defer-gate.sh` (`CMD`, `SESSION_ID`)
- [ ] 6.6 `ship-net-issue-flow-gate.sh` (`CMD`, `WORK_DIR`)
- [ ] 6.7 `ship-operator-step-gate.sh` (`CMD`, `WORK_DIR`)
- [ ] 6.8 `ship-runbook-ssh-gate.sh` (`CMD`, `WORK_DIR`)
- [ ] 6.9 `ship-soak-followthrough-gate.sh` (`CMD`, `WORK_DIR`)
- [ ] 6.10 `ship-unpushed-commits-gate.sh` (`CMD`, `WORK_DIR`)
- [ ] 6.11 Source the helper **fail-hard** — no `|| true` on the `source` line, in any of the 10.
- [ ] 6.12 Keep/add the `: "${VAR:=}"` belt-and-braces defaults at every call site.
- [ ] 6.13 Correct the four false in-source comments (`guardrails.sh`, `ship-unpushed-commits-gate.sh`,
      `cla-signed-author-gate.sh`, `prod-write-defer-gate.sh`). Say "no shell evaluation of hook
      input" — never "input is now safe".
- [ ] 6.14 Append a dated correction to
      `knowledge-base/project/learnings/2026-05-15-deterministic-permissions-empirical-probes-and-review-gaps.md`
      citing #7164 + ADR-155. Do **not** delete the historical finding.
- [ ] 6.15 Do **not** edit `knowledge-base/project/plans/2026-04-18-refactor-drain-pr2213-review-backlog-plan.md`
      or its archived spec — point-in-time records, cited by the ADR.

## 7. Commit 2 — the 8 `$( )` siblings + the OpenHands mirror

- [ ] 7.1 `background-poll-prefer-monitor.sh`
- [ ] 7.2 `brand-hex-commit-gate.sh`
- [ ] 7.3 `doppler-secrets-delete-redirect.sh`
- [ ] 7.4 `git-commit-secret-scan.sh`
- [ ] 7.5 `kb-domain-allowlist-guard.sh` — reads `.tool_input.command` inside a larger `//` chain;
      read the expression before porting, do not pattern-match on the others.
- [ ] 7.6 `no-memory-write.sh` — same `//`-chain caveat.
- [ ] 7.7 `pre-merge-auto-close-scan.sh`
- [ ] 7.8 `pre-merge-rebase.sh`
- [ ] 7.9 `.openhands/hooks/guardrails.sh` + `.openhands/hooks/pre-merge-rebase.sh`: **minimal
      in-place non-string guard only**, no helper (different envelope: `.working_dir`,
      `.tool_input.path`; different deny shape `{"decision":"deny"}`).
- [ ] 7.10 Extend `tests/hooks/test_openhands_guardrails.sh` with the array-payload case.
- [ ] 7.11 File the helper-convergence follow-up issue
      (`domain/engineering`, `type/security`, `priority/p3-low`, `--milestone`), referencing this PR.

## 8. The gate — behavioural assertions

- [ ] 8.1 RCE regression, all 10 (no marker file, no `TOOL_NAME=Bash` / `FILE_PATH=` / `SESSION_ID=` stray).
- [ ] 8.2 **Guard-still-armed, all 18** — array payloads encoding guarded commands yield `ask`, not
      allow. Includes `["git","stash"]` and `["gh","pr","merge","--admin"]`. This is the assertion a
      coerce-and-continue fix fails.
- [ ] 8.3 Loud disarm: `not-json-at-all` ⇒ `rule_id=hook-input-parse-failure`, `event_type=warn`,
      `schema=1`, `kind=hook_self_fault`, non-empty `reason=`, and `command_snippet` free of the payload.
- [ ] 8.4 Lone surrogate recovers and the guards run armed; `reason=surrogate`.
- [ ] 8.5 `PATH=/nonexistent` ⇒ `ask`, `reason=jq_missing`.
- [ ] 8.6 Known-deny canary per hook (18 fixtures) asserting each hook's characteristic decision.
- [ ] 8.7 Helper unit matrix T1-T19, incl. T16 (all fields empty → exactly 2N slots) and T15
      (odd argc / bad name / denylisted name).
- [ ] 8.8 Perf floor assertion at 200 KB (blocks a future cleanup reintroducing `explode` / `read -d`).
- [ ] 8.9 Mutation checks, transcript recorded: (a) type-assert removed → RED; (b) `eval` restored →
      RED; (c) **`lib/hook-input.sh` deleted → RED**; (d) restored → green.

## 9. Record the decision

- [ ] 9.1 Write `ADR-155-blocking-hooks-fail-open-on-transport-fault-ask-on-anomalous-shape.md`
      (`status: accepted`). Title for the **posture**, not the parser. Re-verify the ordinal against
      `origin/main` first; on renumber, sweep this file, the plan, and every AC naming it.
- [ ] 9.2 ADR `## Alternatives Considered` must name fail-closed, coerce-and-continue, per-field
      `jq -r`, and `--raw-output0`; must supersede the silent-absorb reading of
      `2026-03-18-stop-hook-jq-invalid-json-guard.md`; must cite ADR-070 as the only prior fail-open
      sanction (an *additive advisory* hook — the complement of this case); must preserve the issue's
      honest reachability framing.
- [ ] 9.3 `model.c4`: add `claude -> hooks` (untrusted stdin envelope, naming ADR-155 and
      "UNTRUSTED") and amend `platform.engine.hooks`'s description. No `views.c4` change needed —
      both endpoints are already in both views.
- [ ] 9.4 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.
- [ ] 9.5 Add a "Parsing hook input" section to `.claude/hooks/README.md` naming `hook_parse_input`
      and `hook-input-contract.test.sh`.

## 10. Verify + ship

- [ ] 10.1 `bash -n` every edited `.sh`.
- [ ] 10.2 `shellcheck -s bash -x` clean on the helper and all 18 migrated hooks; paste output into
      the PR body (CI does **not** gate `.sh` with shellcheck).
- [ ] 10.3 Re-run, and only fix if genuinely broken: `guardrails.test.sh` + each migrated hook's
      `.test.sh`; `hookeventname-coverage.test.sh` (new `ask` envelopes add `permissionDecision`s —
      each needs its paired `hookEventName`); `grep-q-pipe-guard.test.sh`; `stub-argv-fidelity.test.sh`;
      `tests/hooks/test_hook_emissions.sh`; `pre-merge-rebase-parity.test.sh`.
- [ ] 10.4 `bash scripts/test-all.sh` → 0, `N/N suites passed`, with `N ≥ pre-change + 1`.
- [ ] 10.5 `git ls-files --others --exclude-standard | grep -E '^(TOOL_NAME|FILE_PATH|SESSION_ID)='`
      returns nothing; `git status --short` shows only intended changes.
- [ ] 10.6 `git grep -nE '@sh (shell-)?escapes|eval is safe' -- '.claude/hooks/*.sh'` returns zero.
- [ ] 10.7 Walk AC1-AC18 in the plan and record evidence for each in the PR body.
- [ ] 10.8 PR body carries `Closes #7164` (body, not title).

## Open questions for `/work`

- [ ] Q1 **`ask` prompt storm.** An anomalous payload makes all 18 Bash hooks emit `ask`
      simultaneously. Default is all-emit (no ordering dependency). Measure how CC renders 18
      concurrent asks; if unusable, fall back to a designated responder (`guardrails.sh` only, since
      it covers both matchers) and record the change in ADR-155.
- [ ] Q2 **Non-object `tool_input` classification.** The plan routes it to `transport` (field
      unreadable) rather than `anomalous` (would `ask`). Confirm no legitimate MCP tool shape sends a
      non-object `tool_input`; if one does, this is right, and if none does, consider promoting it to
      `anomalous`.
