---
title: "Tasks — fix(security): eval over jq @sh in 10 PreToolUse hooks (#7164)"
plan: knowledge-base/project/plans/2026-08-02-fix-hook-input-eval-jq-rce-plan.md
issue: 7164
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-08-02
revision: "v3 — matches plan v3 after deepen-plan"
---

# Tasks — #7164 hook input `eval` RCE

Derived from `knowledge-base/project/plans/2026-08-02-fix-hook-input-eval-jq-rce-plan.md` **v3**.
Phase order is **dependency order** — do not reorder.

One PR, **three commits**: (1) the 10 `eval` hooks, (2) the 8 command readers + 2 blocking write
guards, (3) the OpenHands mirror.

> **Read the plan's `## Do Not Skim` block before writing any code.** Ten constraints whose violation
> no test catches unless you build the test. They are reproduced as tasks 4.x, 5.x and 9.x below.

---

## 1. Preconditions (measure only)

- [x] 1.1 Re-run the #7164 reproducer against all 10 hooks from a **fresh** `mktemp -d` CWD with
      `INCIDENTS_REPO_ROOT` redirected. Never from the worktree root. Stale `PWNED*` markers either
      false-fail or self-satisfy.
- [x] 1.2 `printf '{}' | jq -j '"a","\u001e","b"' | od -c` must show `a 036 b`. If not, STOP.
- [ ] 1.3 Reproduce both benchmark tables (micro **and** in-situ). AC8 is written against the in-situ one.
- [x] 1.4 `bash -n` all 20 hooks pre-change.
- [x] 1.5 Confirm the CC major version has not passed `2.1.142`; else re-probe `ask` per
      `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md`.
- [x] 1.6 **Port the validated prototype from the planning scratchpad — do not re-derive it.**
      23-case matrix, shellcheck-clean, in-situ splice already proven.

## 2. Telemetry surface (must precede any `emit_incident`)

- [x] 2.1 `scripts/rule-metrics-aggregate.sh` — `map(select(startswith("hook-input-") | not))` on the
      `$orphan_ids` pipeline, commented like the `context-reviewed-` block.
- [x] 2.2 **Same file** — add `summary.hook_input_fault_count` + per-`reason` counts mirroring
      `drops_jq_fail_count` / `drops_rotation_fail_count`, and print a non-zero count to stderr.
      **Without this, 2.1 makes the fault invisible** — `$enriched` left-joins over AGENTS.md ids, so
      `orphan_rule_ids` was the only surface.
- [x] 2.3 `plugins/soleur/skills/compound/SKILL.md` § 3.5 — widen the filter to admit
      `kind == "hook_self_fault"`; add the paired test assertion.
- [x] 2.4 `scripts/rule-metrics-aggregate.test.sh` — cases for 2.1 and 2.2.

## 3. Both failing tests, RED against `main`

- [x] 3.1 Create `.claude/hooks/hook-input-contract.test.sh` with the `command -v jq || SKIP`
      preflight. Pure bash + jq — the `test-scripts` CI shard has no bun and no node.
- [x] 3.2 **Idiom ban:** *any* `eval` under `.claude/hooks/**` and `.openhands/hooks/**`, allow-listing
      the two `eval "exec ${fd}>&-"` lines in `lib/session-state.sh` **by exact string**. A ban pinned
      to `eval "$(` misses `eval $(…)`, `eval "$V"`, `eval "${x}"`.
- [x] 3.3 **Guard-still-armed:** an array payload encoding a guarded command must yield `ask`.
- [x] 3.4 **Observe BOTH fail on the unmodified tree** and record the output. 3.3 is RED on `main`
      today; authoring it after the migration means it is never seen fail.

## 4. The extractor — `.claude/hooks/lib/hook-input.sh`

- [x] 4.1 **One CONSTANT jq program**, fixed accessors, no interpolation, no variadic args, no
      `printf -v`, no name denylist. Publishes `HOOK_CMD`, `HOOK_TOOL_NAME`, `HOOK_CWD`,
      `HOOK_SESSION_ID`, `HOOK_FILE_PATH`, `HOOK_INPUT_REASON`.
- [x] 4.2 Leading `all(type=="string")` status token, computed **before** any value is emitted.
      6 slots, not 2N. Bad-path values are emitted **empty** — no `tojson`, no separator scrub, no
      payload content anywhere.
- [x] 4.3 `catch {}` — never `catch ""`. An object is non-string, so the same check handles a
      non-object `tool_input` or root. **No `err` tag, no `has("__e")` branch.**
- [x] 4.4 `raw=$(… ; printf 'X'); raw=${raw%X}` **and** the trailing separator — keep both; they are
      redundant with each other and load-bearing as a pair.
- [x] 4.5 `local o=${IFS-}`; restore with `unset IFS` when it was unset. `local o=$IFS` kills the
      shell under `set -u` when `IFS` is unset.
- [x] 4.6 Conditional glob restore: `case "$-" in *f*)` before `set -f`.
- [x] 4.7 **Slot count is the parse-failure detector**, not jq's exit code — but capture the code for
      the `internal` classifier.
- [x] 4.8 Reset `HOOK_INPUT_REASON` at the top of every call; an inherited value must not survive.
- [x] 4.9 Source `lib/incidents.sh` **idempotently** from the helper; if `emit_incident` is still
      undefined, fall through to `ask` — never continue.
- [x] 4.10 No `| grep -q` (`grep-q-pipe-guard.test.sh` sweeps `lib/*.sh`).
- [x] 4.11 `shellcheck -s bash` zero findings with exactly two justified disables: `SC2206`
      (deliberate word-split) and `SC2034` (published globals).
- [x] 4.12 bash 3.2 / jq 1.5 compatible — no `mapfile`, no `declare -n`, no `--raw-output0`.
- [x] 4.13 Classifiers: `nonstring` · `unparseable` · `separator` · `jq_missing` · `internal`
      (carry ≤120 bytes of jq stderr — our bug, no attacker content).

## 5. The response

- [x] 5.1 Three functions, **none of which calls `exit`**: `hook_input_report`,
      `hook_input_should_ask`, `hook_input_emit_ask`. The `exit` lives at the call site.
- [x] 5.2 **The `ask` envelope is a `printf` of a constant string — never `jq -n`.** One trigger is
      "jq is missing"; `emit_incident` itself needs jq.
- [x] 5.3 Every `ask` envelope carries `hookEventName: "PreToolUse"` **in the same object**.
- [x] 5.4 **`guardrails.sh` is the designated responder**; the other 17 report and exit 0.
- [x] 5.5 Kill switch `SOLEUR_DISABLE_HOOK_INPUT_ASK=1` — escalation only, never parsing.
- [x] 5.6 Telemetry payload: field name, JSON type, length. Nothing else.

## 6. The ADRs (before anything cites them)

- [x] 6.1 Re-derive both ordinals from a freshly-fetched `origin/main`.
- [x] 6.2 **ADR-156** — the trust boundary (durable; cited by `model.c4`).
- [x] 6.3 **ADR-157** — *a hook that cannot fully parse its input asks* (operational; cites 155; owns
      the Alternatives table; supersedes the silent-absorb reading of
      `2026-03-18-stop-hook-jq-invalid-json-guard.md`; cites ADR-070 as the only prior fail-open
      sanction — an additive advisory hook, the complement of this case; records the surrogate
      limitation and the designated-responder invariant).
- [x] 6.4 `AP-NNN` in `principles-register.md` linked to ADR-156.

## 7. Commit 1 — the 10 `eval` hooks

- [x] 7.1 `guardrails.sh` · 7.2 `cla-signed-author-gate.sh` · 7.3 `context-reviewed-gate.sh` ·
      7.4 `follow-through-directive-gate.sh` · 7.5 `prod-write-defer-gate.sh` ·
      7.6 `ship-net-issue-flow-gate.sh` · 7.7 `ship-operator-step-gate.sh` ·
      7.8 `ship-runbook-ssh-gate.sh` · 7.9 `ship-soak-followthrough-gate.sh` ·
      7.10 `ship-unpushed-commits-gate.sh`
- [x] 7.11 Source the helper **fail-hard** in all 10 — no `|| true`, no `|| :`, no `2>/dev/null`.
- [x] 7.12 Keep/add the `: "${VAR:=}"` defaults.
- [x] 7.13 Correct the four false in-source comments. Say "no shell evaluation of hook input" —
      **never** "input is now safe".
- [x] 7.14 Append a dated correction to
      `knowledge-base/project/learnings/2026-05-15-deterministic-permissions-empirical-probes-and-review-gaps.md`
      citing #7164 + ADR-156. Do not delete the historical finding.
- [x] 7.15 Do **not** edit `2026-04-18-refactor-drain-pr2213-review-backlog-plan.md` or its archived
      spec — point-in-time records, cited by ADR-157.

## 8. Commit 2 — sibling readers; Commit 3 — mirror

- [x] 8.1 The 8 command readers: `background-poll-prefer-monitor`, `brand-hex-commit-gate`,
      `doppler-secrets-delete-redirect`, `git-commit-secret-scan`, `kb-domain-allowlist-guard`,
      `no-memory-write`, `pre-merge-auto-close-scan`, `pre-merge-rebase`. The last two read
      `.tool_input.command` inside larger `//` chains — read each before porting.
- [x] 8.2 The 2 blocking write guards: `worktree-write-guard.sh`, `iac-plan-write-guard.sh`.
- [x] 8.3 **Commit 3:** `.openhands/hooks/{guardrails,pre-merge-rebase}.sh` get a minimal in-place
      non-string guard, **not** the helper (different envelope, different deny shape). Extend
      `tests/hooks/test_openhands_guardrails.sh` with the array payload.
- [x] 8.4 File the mirror-convergence follow-up (#7173, consolidated with the exempt-hook migration) (`domain/engineering`, `type/security`,
      `priority/p3-low`, `--milestone`).

## 9. Complete the gate

- [ ] 9.1 **Fixture factory:** one shared `git init` + local bare `origin` + one commit + a feature
      branch, reused across the 8 constructible hooks; a stub-`gh` dir prepended to `PATH` for the 3
      `gh`-gated ones. Keeps `git fetch` / `gh pr view` / `net-issue-flow.sh` off the network. Every
      fixture sets its branch explicitly and runs from its own CWD (CI-on-`main` masks gates, #5192).
- [x] 9.2 Guard-still-armed per hook, with the honest split: **7** from a bare payload, **8** via the
      git fixture, **3** via the `gh` stub. Do not silently degrade the other 11.
- [x] 9.3 RCE regression ×10 **with a positive control in the same run** (the marker *is* created
      against a pinned vulnerable stub).
- [x] 9.4 Assert `permissionDecisionReason` where normal and anomalous decisions collide
      (`kb-domain-allowlist-guard.sh`'s normal decision is already `ask`).
- [x] 9.5 Non-object `tool_input` / non-object root / non-string `cwd` / separator-in-value ⇒ `ask`.
- [x] 9.6 Lone surrogate ⇒ `ask`; assert it does **not** arm a guard against a scrubbed value. Use a
      `python3 json.dumps` payload carrying a lone high surrogate **and** a valid escaped pair.
- [x] 9.7 Unusable `jq` ⇒ `ask` with **no jq fork**. Prepend a shim dir with a non-executable `jq`;
      `PATH=/nonexistent` also removes `grep`, `git`, `mktemp`, `flock`.
- [x] 9.8 **Loud disarm end to end:** incident row **and** non-zero `summary.hook_input_fault_count`
      **and** compound pickup **and** `INCIDENTS_REPO_ROOT` honoured with the worktree ledger unchanged.
- [x] 9.9 No payload content in `command_snippet`.
- [x] 9.10 Envelope pairing asserted **per envelope** (`hookeventname-coverage.test.sh` is a per-file
      count and cannot catch this).
- [x] 9.11 `settings.json` designated-responder invariant: every `PreToolUse` matcher containing a
      migrated hook also contains `guardrails.sh`.
- [x] 9.12 Shell hygiene: `IFS` and `$-` byte-identical after every rc path; `IFS` unset under
      `set -u`; a value that is **exactly** `*` from a temp dir containing files (`rm *` cannot catch
      a missing `set -f`).
- [x] 9.13 No subshell/pipeline invocation of the three response functions; no `$` in any jq expression.
- [x] 9.14 Kill switch.
- [x] 9.15 **Mechanism ban** (replaces a comparative wall-clock assertion): zero `explode`, zero
      `read -d`, zero `mapfile -d`, exactly one `jq` in `lib/hook-input.sh`. One loose backstop only:
      median of 5 interleaved runs at 200 KB, `new <= 2 × legacy`.
- [x] 9.16 Stray-artifact assertion **inside** the test, per invocation.
- [x] 9.17 Run the **16 existing sibling suites**; write the 2 missing ones
      (`ship-soak-followthrough-gate.test.sh`, `doppler-secrets-delete-redirect.test.sh`).
- [x] 9.18 **Mutations**, each naming the protection it removed: type-assert removed · any `eval`
      restored in a **randomly selected** hook · `lib/hook-input.sh` deleted · `lib/incidents.sh`
      deleted · `catch {}` → `catch ""` · `${IFS-}` → `$IFS` · sentinel **and** trailing separator
      removed together · `slots=($raw)` → `slots=("$raw")` · `set -f` removed · restore → green.
- [x] 9.19 Static per-file sweep: each of the 20 hooks has exactly one `source .../hook-input.sh`,
      matching neither `|| true` nor `|| :` nor `2>/dev/null`.
- [x] 9.20 Suite trailer `=== hook-input-contract: N/M pass ===` plus an assertion that the run output
      contains `--- .claude/hooks/hook-input-contract.test.sh ---`.

## 10. C4, README, verify, ship

- [x] 10.1 `model.c4`: add `claude -> hooks` (untrusted stdin envelope, naming ADR-156 and ADR-157)
      and amend `platform.engine.hooks`'s description. No `views.c4` change needed.
- [x] 10.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`
- [x] 10.3 `.claude/hooks/README.md` — "Parsing hook input": `hook_parse_input`, the **scoped**
      mandate (Bash-matcher + blocking write hooks only), the 10 exempt hooks with the reason and the
      follow-up issue, the required source order, the designated responder, the kill switch, the test.
- [x] 10.4 `bash -n` every edited `.sh`; `shellcheck -s bash -x` zero findings; paste into the PR body.
- [x] 10.5 `bash scripts/test-all.sh` → 0 (246/246 suites, run 5 against the settled tree).
- [x] 10.6 `git grep -nE '@sh (shell-)?escapes|eval is safe' -- '.claude/hooks/*.sh'` → zero.
- [x] 10.7 `git ls-files --others --exclude-standard | grep -E '^(TOOL_NAME|FILE_PATH|SESSION_ID|PWNED)'` → nothing.
- [x] 10.8 Walk AC1-AC23 and record evidence for each in the PR body. **The PR body must make no
      `echo`-vs-`printf` security claim** — it was measured and did not reproduce.
- [x] 10.9 PR body carries `Closes #7164` (body, not title).

## Open questions for `/work`

- [x] Q1 **Non-object `tool_input` classification.** v3 routes it to `nonstring` ⇒ `ask` via
      `catch {}`. Confirm no legitimate MCP tool shape sends a non-object `tool_input`; if one does,
      this is still right (it asks rather than denies), but record the finding in ADR-157.
- [x] Q2 **Exemption boundary.** The 10 advisory/PostToolUse hooks are exempt because they gate
      nothing. `pencil-open-guard.sh` sits on an `mcp__*` matcher, which is the issue's own
      reachability argument — re-check at /work whether it should move in-scope.
