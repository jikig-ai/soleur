---
name: reproduce-bug
description: "This skill should be used when reproducing and investigating a bug using logs, console inspection, and browser screenshots. It systematically investigates GitHub issues through log analysis, code inspection, and visual reproduction with Playwright."
---

<!-- Inspired by mattpocock/skills/skills/engineering/diagnosing-bugs/SKILL.md (MIT, Copyright (c) 2026 Matt Pocock). -->
<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

# Reproduce Bug

Look at github issue #$ARGUMENTS and read the issue description and comments.

## Phase 1: Log Investigation

Think about the places it could go wrong looking at the codebase. Look for logging output to search for.

**Check the observability layer FIRST — before hypothesizing from code.** Server-side / cron / prod failures usually have the real error (the exact failing step, hostname, status, stack) already captured in Sentry or Better Stack. Pull it before theorizing — a code-trace guess can burn many cycles that one Sentry event resolves.

1. **Sentry** — query the project's issues for the error (the `incident` skill's toolchain). Tokens + slugs live in Doppler `prd`: `SENTRY_ISSUE_RW_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_API_HOST` (host needs the `https://` scheme). Example:

   ```bash
   ORG=$(doppler secrets get SENTRY_ORG -p soleur -c prd --plain)
   PROJ=$(doppler secrets get SENTRY_PROJECT -p soleur -c prd --plain)
   TOK=$(doppler secrets get SENTRY_ISSUE_RW_TOKEN -p soleur -c prd --plain)
   curl -s -H "Authorization: Bearer $TOK" \
     "https://jikigai-eu.sentry.io/api/0/projects/$ORG/$PROJ/issues/?query=<keyword>&statsPeriod=24h&limit=5" \
     | jq -r '.[]? | "\(.lastSeen) | \(.title) | n=\(.count)"'
   ```

   Then drill into the issue's latest event for `extra` (carries the operative detail — a blocked `DST=` IP, a vendor status, the failing arg). Note: a cron-monitor **error check-in** carries no stack trace; the real exception is a separate `reportSilentFallback`/`captureException` issue — query for it. **Named helper:** once you have an issue id, `doppler run -p soleur -c prd -- scripts/sentry-issue.sh <id>` (add `--latest-event` for the stack/exception) wraps this read-by-id with the least-privilege `SENTRY_ISSUE_RO_TOKEN`. Runbook: `knowledge-base/engineering/operations/runbooks/sentry-issue-read.md`.

2. **Better Stack** logs (the app's pino stream, historical) via the repo-root [betterstack-query.sh](../../../../scripts/betterstack-query.sh) helper (ClickHouse SQL over the Telemetry warehouse). Runbook: `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`. The failing fetch's error (with the HOSTNAME) lives here.

3. **Supabase platform logs** (postgres / auth / postgrest / supavisor — the database side of the failure, not the app's own pino stream) via `doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh --ref <project-ref> --source <src> --since <window>`. Runbook: `knowledge-base/engineering/operations/runbooks/supabase-log-query.md`. The helper never reports a zero row count without a coverage verdict, so an empty answer tells you whether the source is quiet or simply uninstrumented.

4. Check recent commits related to the affected area, then inspect the relevant code paths — now anchored on the real error, not a guess. Without an anchor (a local-only surface), read code only for what Phase 2's loop needs: the entry point, its input shape, and what it writes as a side effect (a hook's incident ledger, a script's cache) — never to explain the bug.

**Why (#5088):** a cron silently failed to publish; several turns went to code hypotheses before pulling the Sentry `egress-blocked` event, which pinpointed the firewall dropping a GitHub clone IP in one read. The observability layer already had the answer. See `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` for the egress-specific diagnosis path.

**Blind execution surface (Concierge agent-sandbox, cron worker, container readiness gate) with NO usable observability yet — instrument the deployed code, never ask the operator to run diagnostics.** When the failure lives on a surface you cannot run commands in AND Sentry/Better Stack don't already carry the operative detail, the correct move is to ADD structured, grep-able diagnostics to the deployed code (e.g. what a lock file actually is: type/stat/mount/`rm` errno) so the NEXT occurrence self-reports into the surface's own debug stream — then read that. NEVER ask a (non-technical) Soleur operator to run `ls`/`stat`/`findmnt`/`git config`/etc. — that violates `hr-no-dashboard-eyeball-pull-data-yourself` and `hr-no-ssh-fallback-in-runbooks`. The deployed code is your instrument; the operator is not. Corollary: instrumenting a plugin-runtime surface only helps once it DEPLOYS — verify the delivery path (for Concierge, a web-platform image rebuild re-seeds `/mnt/data/plugins/soleur`), because a merged fix is not a deployed fix. **Why (#5888 / PR #5880 follow-up):** two sessions asked the operator to run sandbox diagnostics for a wedged `.git/config.lock`; the correct fix was to instrument `worktree-manager.sh` so the sweep self-reports the lock's true nature. See `knowledge-base/project/learnings/workflow-patterns/2026-07-02-merged-is-not-deployed-on-concierge-instrument-dont-ask.md`.

**Even when observability EXISTS, self-pull it — do not ask the operator to paste error output.** The operator's role in a diagnostic loop is DECISIONS, not data retrieval. Query Better Stack `SOLEUR_*` markers yourself (`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since <N> --grep <marker>`) and Sentry rather than asking the operator to paste logs or run probes — and if the needed signal is missing from telemetry, ADD a monitored stdout `SOLEUR_*` marker in the emitting code (per the blind-surface bullet above), never escalate to the operator for it. **Why (#5934 worktree-wedge):** the diagnosis twice asked the operator to paste `grep`/`stat` output that the observability layer held (or, once instrumented, would hold — `SOLEUR_GIT_CONFIG_TARGET_MASKED`, `SOLEUR_GIT_WORKTREE_VERIFY_FAILED`). See `knowledge-base/project/learnings/workflow-patterns/2026-07-08-self-pull-observability-in-diagnostic-loops-never-ask-operator-to-fetch.md`.

Phase 1 ends when telemetry has named the operative error, or you have measured that it does not carry one (the helper's coverage verdict, not an empty result), or the failing surface is local-only — a CLI hook, a script, a test harness — and no telemetry layer covers it: say so in one line and move on, do not query a layer that cannot hold the error. Either way, Phase 2's gate is the completion criterion — telemetry tells you where to point the loop; it is not the loop.

## Phase 2: Build a feedback loop

**This is the skill.** Everything else is mechanical. If you have a **tight** pass/fail signal for the bug (one that goes red on *this* bug), you will find the cause; bisection, hypothesis-testing, and instrumentation all just consume it. If you don't have one, no amount of staring at code will save you.

Spend disproportionate effort here. **Be aggressive. Be creative. Refuse to give up.**

**Redact.** This phase has you show commands, outputs and captured artifacts. **Redact every secret first**: write `<REDACTED>` in its place. Build loops against env vars, so the credential stays in the environment rather than in what you show. Captured artifacts carry auth headers: quote only the lines that carry the signal. Two places where redaction is otherwise left to memory are mechanical here: a fixture derived from a captured trace (rung 5's Sentry payload or Better Stack rows — an exception value can carry an email or a token; `apps/web-platform/server/sentry-scrub.ts` strips keyed fields, not message text) is synthesized or redacted before it is committed in Phase 9 (`cq-test-fixtures-synthesized-only`); and the whole Phase 8 comment body, the `--cmd` string included, goes through `bash "${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh" <file>` — the repo's redactor (exit 1 = redaction needed, 2 = cannot evaluate) — and is posted only on exit 0. `CLAUDE_PLUGIN_ROOT` unset means no Soleur install is loaded in this session: the call fails closed (exit 127, nothing posted) — install the plugin and start a new session; never substitute a repo checkout path (ADR-179). **Its ceiling is the mechanical part, not the whole job**: it matches vendor-prefixed and fixed-format tokens, emails and keys; an opaque `Authorization: Bearer …` value, a non-vendor `DATABASE_URL=…`, an internal hostname, a customer name or phone pass it. Phase 8 names the structural check that closes the first two; the rest you redact by hand before the file exists.

**Completion criterion: a tight loop that goes red.** Phase 2 is done when you can name **one command** (a script path, a test invocation, a curl) that you have **already run at least once** (show the invocation and its output, redacted), and that is:

- [ ] **Red-capable**: it drives the actual bug code path and asserts the **user's exact symptom**, so it can go red on this bug and green once fixed. Not "runs without erroring"; it must be able to *catch this specific bug*.
- [ ] **Deterministic**: same verdict every run (flaky bugs: a pinned, high reproduction rate, per below).
- [ ] **Fast**: seconds, not minutes.
- [ ] **Agent-runnable**: you start everything the loop needs yourself — a dev server (backgrounded, then wait on the port with an until-loop), fixtures, containers — and never ask the founder to start a server or paste output (`hr-exhaust-all-automated-options-before`).

If you catch yourself reading code to build a theory before this command exists, **stop: jumping straight to a hypothesis is the exact failure this skill prevents.** Reading code to find the loop's entry point and side effects is building the loop; reading it to explain the bug is not. **No red-capable command, no Phase 5.**

**When you genuinely cannot build a loop.** Stop and say so explicitly. List what you tried, rung by rung. Then take the first option that applies; each is a decision with a default, and the default is option 1:

1. **Add instrumentation (default).** Where a loop will follow once the signal exists, add a temporary `[DEBUG-<hex4>]` probe (Phase 6 spelling) and build the loop on its output. Where the failure lives on a blind production surface, apply Phase 1's blind-surface bullet: add a permanent `SOLEUR_*` marker so the next occurrence self-reports, write `no loop buildable yet; instrumentation added: SOLEUR_<…>; re-run soleur:reproduce-bug on the next occurrence` into the Phase 8 comment, and end the run.
2. **Environment access — non-shell only.** Only when option 1 cannot carry the signal. Name the one environment that reproduces it and what you need from it: a preview or staging deploy to drive, a flag to flip, `soleur:trigger-cron` to fire. SSH and `docker exec` are never an ask (`hr-no-ssh-fallback-in-runbooks`); a blind production surface takes option 1. Carry the ask verbatim into Phase 8 item 6 and end the run.
3. **A redacted captured artifact** (HAR file, log dump, core dump, screen recording with timestamps). The one data-retrieval ask permitted, and only after the ladder, option 1 and option 2 are exhausted: a founder's local device state is the one thing no instrumentation can capture. Carry the ask into Phase 8 item 6 and end the run; on the next run the artifact lands in a directory you create with `mktemp -d` — **never inside the repository** (`.gitignore` is not a control; `soleur:test-fix-loop` stages with `git add -A`). You perform the redaction, not the founder: for a HAR, drop every `headers[]` and `cookies[]` entry (request and response), `queryString[]`, `postData`, `content.text` and `_webSocketMessages`, keeping `url` path (no query), `status`, `time` and `mimeType`; for a log dump, keep only the lines that carry the signal. The artifact is never attached to the issue, never lands under `knowledge-base/`, and is deleted when the run ends (Phase 9 greps for it).

Headless (one-shot, cloud, no TTY): take option 1; if the temporary-probe arm applies, build the loop and continue; otherwise add the permanent marker, write the Phase 8 line, and end the run. Never substitute a founder clicking for rung 10. **For a UI bug, Phase 3 is how rung 4 is built — go there and come back before declaring that no loop exists.**

### Ways to construct one, in roughly this order

1. **Write a failing test** at whatever seam reaches the bug: unit, integration, e2e.
2. **Script a curl / HTTP call** against a running dev server.
3. **Script a CLI invocation** with a fixture input, diffing stdout against a known-good snapshot. For a hook or script defect this is the Phase 7 mechanism bullet's form — `jq -nc '{tool_name, tool_input}' | bash .claude/hooks/<hook>.sh` — with `INCIDENTS_REPO_ROOT=<scratch dir>` (the hooks' incident ledger resolves from the hook's OWN location, not from `CLAUDE_PROJECT_DIR` or cwd) so a synthetic deny/bypass never lands in the live `.claude/.rule-incidents.jsonl` and the rule-metrics aggregate.
4. **Headless browser script** (Playwright / Puppeteer) that drives the UI and asserts on DOM/console/network. Phase 3 builds this rung.
5. **Replay a captured trace.** Save a real network request / payload / event log to disk; replay it through the code path in isolation. The Sentry event payload or Better Stack rows you pulled in Phase 1 are a captured trace.
6. **Throwaway harness.** Spin up a minimal subset of the system (one service, mocked deps) that exercises the bug code path with a single function call.
7. **Property / fuzz loop.** If the bug is "sometimes wrong output", run 1000 random inputs and look for the failure mode.
8. **Bisection harness.** If the bug appeared between two known states (commit, dataset, version), automate "boot at state X, check, repeat" so you can `git bisect run` it.
9. **Differential loop.** Run the same input through old-version vs new-version (or two configs) and diff outputs.
10. **Scripted interactive session** via `soleur:agent-browser`. Last resort: when only a full session reaches the bug, the agent drives it — ref-based clicks, captured output fed back into the loop. Never a human clicking.

Build the right feedback loop, and the bug is 90% fixed.

### Tighten the loop

Treat the loop as a product. Once you have *a* loop, **tighten** it:

- Can I make it faster? (Cache setup, skip unrelated init, narrow the test scope.)
- Can I make the signal sharper? (Assert on the specific symptom, not "didn't crash".)
- Can I make it more deterministic? (Pin time, seed RNG, isolate filesystem, freeze network.)

A 30-second flaky loop is barely better than no loop; a 2-second deterministic one is tight, a debugging superpower.

### Non-deterministic bugs

The goal is not a clean repro but a **higher reproduction rate**. Loop the trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable; 1% is not, so keep raising the rate until it's debuggable.

Nothing is posted to the issue in this phase — every line destined for the founder (the command, its redacted output, what you tried, the instrumentation note) is carried to the single Phase 8 comment.

## Phase 3: Visual Reproduction with Playwright

This is rung 4 of the Phase 2 ladder. A screenshot is evidence; the loop is the script whose assertion goes red.

If the bug is UI-related or involves user flows, use Playwright to visually reproduce it:

### Step 1: Verify Server is Running

```
mcp__plugin_soleur_playwright__browser_navigate({ url: "http://localhost:3000" })
mcp__plugin_soleur_playwright__browser_snapshot({})
```

If the server is not running, start it yourself in the background (`cd apps/web-platform && npm run dev` here; the target repo's dev script elsewhere) and poll until it answers — never ask the founder to start it (`hr-exhaust-all-automated-options-before`).

If `mcp__plugin_soleur_playwright__*` tools are absent (the plugin server did
not register or is toggled off), take the file-form path: use whatever
`mcp__<server>__*` Playwright registration answers, treated as a separate —
possibly unwrapped — registration under the §Wrapping rules below, or
`agent-browser` when no Playwright registration exists at all.

### Step 2: Navigate to Affected Area

Based on the issue description, navigate to the relevant page:

```
mcp__plugin_soleur_playwright__browser_navigate({ url: "http://localhost:3000/[affected_route]" })
mcp__plugin_soleur_playwright__browser_snapshot({})
```

### Step 3: Capture Screenshots

Take screenshots at each step of reproducing the bug:

### Preflight: verify the plugin install before any snapshot

The redactor is reached through `${CLAUDE_PLUGIN_ROOT}`. An ambient value pointing at a
directory that is not a Soleur install would resolve to a path that does not exist — or, worse,
to one an attacker chose. Verify plugin IDENTITY and halt if it does not hold (ADR-179 decision 2);
a `test -f` on the script alone is a shape check and was measured bypassable.

```bash
[ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] \
  && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" \
  || { echo "SOLEUR_SNAPSHOT_HALT reason=plugin-root-unverified root=[${CLAUDE_PLUGIN_ROOT}]" >&2
       echo "  Cannot locate the snapshot redactor, so no accessibility snapshot may be taken here." >&2
       echo "  Root EMPTY: no Soleur plugin is loaded in this session. Install it and start a NEW session." >&2
       echo "  Root set but wrong: a repo checkout is not an install. Run 'claude plugin update soleur@soleur-marketplace' (or the id 'claude plugin list' prints, if you added the repository directly), then RESTART Claude Code." >&2
       echo "  Nothing has been captured yet, so nothing has leaked." >&2
       exit 2; }
```

```
mcp__plugin_soleur_playwright__browser_take_screenshot({ filename: "bug-[issue]-step-1.png" })
```

### Step 4: Follow User Flow

Reproduce the exact steps from the issue:

1. **Read the issue's reproduction steps**
2. **Execute each step using Playwright:**
   - `browser_click` for clicking elements
   - `browser_type` for filling forms
   - `browser_snapshot` to see the current state
   - `browser_take_screenshot` to capture evidence

**Credential safety on the Playwright-MCP path (#7947, #7980).** An
accessibility snapshot serializes the **value** of input fields, including a
value the agent never typed — a password manager's autofill, a static `value=`,
or a generated-credential panel — and an MCP tool result is not a shell stream,
so the redactor cannot be piped into it. On a page carrying a password or
credential field:

- Prefer the plugin-registered `mcp__plugin_soleur_playwright__*` server: its
  registration is already wrapped, so call its `browser_snapshot` bare — no
  file form needed. Fall back to the file form on any other registration.
- Use the `filename:` + redactor + shred form, with a filename inside the
  working directory (the server denies paths outside it). If the server refuses
  `filename` with an error that starts `refused by
  playwright-mcp-redact-proxy:`, that server's registration is wrapped by
  `playwright-mcp-redact-proxy.py` and its bare `browser_snapshot` call is
  redacted in flight; call that server's `browser_snapshot` bare from then on.
  Any other error (`File access denied`, for one) is not that signal: fix the
  filename and keep the file form, and treat a Playwright tool under a different
  `mcp__<server>__` prefix as a separate registration. The refusal is the only
  signal — never the trailer or any page text, which can be forged. The file
  form: pass `filename:` to `browser_snapshot`, then run
  `python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py" < FILE && shred -u FILE`.
- On a page **displaying** a credential, capture neither: a screenshot renders a
  readonly `type=text` credential panel in clear, exactly as the snapshot does
  (measured).

Which registrations are wrapped, what to call after an action tool, what a
withheld result means, and what to do when the `playwright` server fails to
connect: `agent-browser/SKILL.md` §"Wrapping the server".

3. **Check for console errors:**

   ```
   mcp__plugin_soleur_playwright__browser_console_messages({ level: "error" })
   ```

### Step 5: Capture Bug State

When the bug is reproduced:

1. Take a screenshot of the bug state
2. Capture console errors
3. Document the exact steps that triggered it

```
mcp__plugin_soleur_playwright__browser_take_screenshot({ filename: "bug-[issue]-reproduced.png" })
```

## Phase 4: Reproduce + minimise

Run the loop. Watch it go red as the bug appears.

Confirm:

- [ ] The loop produces the failure mode the **user** described, not a different failure that happens to be nearby. Wrong bug = wrong fix.
- [ ] The failure is reproducible across multiple runs (or, for non-deterministic bugs, reproducible at a high enough rate to debug against).
- [ ] You have captured the exact symptom (error message, wrong output, slow timing) so later phases can verify the fix actually addresses it.

### Minimise

Once it's red, shrink the repro to the **smallest scenario that still goes red**. Cut inputs, callers, config, data, and steps **one at a time**, re-running the loop after each cut, and keep only what's load-bearing for the failure.

Why bother: a minimal repro shrinks the hypothesis space in Phase 5 (fewer moving parts left to suspect) and becomes the clean regression test at the seam Phase 7 names.

Done when **every remaining element is load-bearing**: removing any one of them makes the loop go green.

Do not proceed until you have reproduced **and** minimised. If the loop is green on HEAD (the fix already landed; the trigger is state you cannot recreate), get the red from rung 8 or 9 — bisect, or run the same loop against the pre-fix commit (`git show <sha>^:<path>` into scratch) — and minimise against that.

## Phase 5: Hypothesise

Generate **3–5 ranked hypotheses** before testing any of them. Single-hypothesis generation anchors on the first plausible idea. Each hypothesis must be **falsifiable**: state the prediction it makes.

> Format: "If <X> is the cause, then <changing Y> will make the bug disappear / <changing Z> will make it worse."

If you cannot state the prediction, the hypothesis is a vibe: discard or sharpen it.

Record the set as a table (the technical record; the founder notice below is a second rendering of the same rows in symptom language); every row fills every column, and `Verdict` starts `UNKNOWN` (Phase 6 upgrades it; `CONFIRMED` only with the discriminating observation quoted):

| # | Hypothesis (If X is the cause, then …) | Discriminator (what observation decides it, and where it is read) | Verdict |
|---|---|---|---|

**Founder notice, in this turn, without a question tool.** Render the table in symptom language (what the founder would see; never a code path), with `Discriminator` rendered as *"what else you'd see if this is it"*, then continue in the same turn with: *"Here are the 3–5 likeliest causes, ranked; each says what else you would see if it were true. I will test them in this order unless you tell me one is wrong or you saw something that changes the order — proceed / re-rank / add a fact."* Do not call AskUserQuestion and do not wait: the default is your ranking and the founder's reply is an interrupt — it usually lands after the first probe has run, so it re-orders what is left rather than vetoing the first test. **Headless (one-shot, cloud, no TTY):** the Phase 8 comment carries `founder notice not presented (headless); proceeded with the agent's ranking` so the decision is auditable.

## Phase 6: Instrument

Each probe must map to a specific prediction from Phase 5. **Change one variable at a time.**

Tool preference:

1. **Debugger / REPL inspection** if the env supports it. One breakpoint beats ten logs.
2. **Targeted logs** at the boundaries that distinguish hypotheses.
3. Never "log everything and grep".

**Removable probes.** Mint one tag per investigation with `printf '[DEBUG-%04x]\n' "$RANDOM"` and prefix every debug log with it. Spelling: `[DEBUG-<hex4>]`, exactly four hex characters, never a `SOLEUR_` prefix — the permanent class is defined by `MARKER_RE` in `apps/web-platform/server/git-lock-marker-telemetry.ts` and its drift guard, and a `SOLEUR_*DEBUG*` spelling on any emit call-form Soleur uses (`echo`/`printf`/`log "`, `console.<level>(`, pino `log.<level>({ KEY:`, `logger.<level>(`, `process.stdout.write(`, `print(`) fails Soleur's CI. Decision rule: the signal dies with the fix → `[DEBUG-<hex4>]`; the signal must outlive the fix (a blind surface, a recurring class) → a permanent `SOLEUR_*` marker via Phase 1's blind-surface bullet. Payload: the discriminator only — booleans, lengths, ids, hashes. Never an env value, a header, a request body, PII, or a raw user-controlled string (a probe removed before merge has already reached Better Stack/Sentry retention if a preview deploy ran in between — CWE-532; interpolating user input into a log line is CWE-117). Probes are removed before any **push**, not only before commit. Cleanup is one grep, run in Phase 9 and expected to print nothing: `git grep -niE --untracked '\[DEBUG-[0-9a-f]{4}\]' -- ':/' ':(top,exclude)knowledge-base/**/*.md'` (top-anchored: it scans the whole repo from any cwd — Phase 3 leaves you in `apps/web-platform`). In prose write the placeholder `<hex4>`, never a minted tag. Two-class table and rationale: ADR-230.

**Perf branch.** For performance regressions, logs are usually wrong. Instead: establish a baseline measurement (timing harness, `performance.now()`, profiler, query plan), then bisect. Measure first, fix second.

## Phase 7: Document Findings

**Reference Collection:**

- [ ] Document all research findings with specific file paths (e.g., `app/services/example_service.rb:42`)
- [ ] Include screenshots showing the bug reproduction
- [ ] List console errors if any
- [ ] Document the exact reproduction steps
- [ ] **Execute the mechanism, do not infer it.** A reproduction confirms the *symptom*, not the story attached to it. Before recording a root cause, run the mechanism itself. If it has a quantitative precondition (buffer size, timeout, rate limit, row count), check the repro's own numbers actually clear it; and A/B a **single** variable — a comparison whose two cases differ in two ways names no cause. State confidence explicitly ("symptom reproduced; mechanism inferred, not tested"), because an untested mechanism written in the indicative becomes fact on the next read. For hook defects specifically, drive the real hook with a synthetic payload (`jq -nc '{tool_name, tool_input}' | bash .claude/hooks/<hook>.sh`) instead of reasoning about it — seconds of work, and it exercises the actual code path. **Why:** #6501 — `iac-plan-write-guard`'s broken ack bypass was diagnosed as SIGPIPE+`pipefail`, reproduced ("48KB plan → denied / small doc → allowed"), documented, and wrong: pipe capacity is 64KB so the blamed 48KB never blocks, and the two cases differed in *tool* (`Edit` vs `Write`), not bytes. The recorded fix would have changed nothing. See `knowledge-base/project/learnings/2026-07-15-a-reproduced-symptom-does-not-validate-the-mechanism-you-attached-to-it.md`.
- [ ] **Regression seam verdict.** Name the seam where the fix's regression test will exercise the real bug pattern as it occurs at the call site (file + entry point). If the only seam available is too shallow — a single-caller test when the bug needs the chain, a unit that cannot replicate the trigger — write **`no correct seam`** as the finding. If no correct seam exists, that itself is the finding: the architecture is preventing the bug from being locked down. Spawn `soleur:engineering:review:legacy-code-expert` (Task) with this prompt shape:

  ```text
  Change point: <file:entry point>, reached via <call-site chain, outermost → innermost>.
  Symptom (Phase 4): <expected> vs <actual>. Minimised repro: `<command>`; files: <list>.
  Seams already rejected as too shallow: <seam — why it cannot replicate the trigger>.
  Return your standard Change Analysis and Recommended Approach: the seam to break, the characterization tests to write first, the safe transformation path.
  ```

  Carry its seam analysis and characterization-test plan into the Phase 8 comment, then label the issue (`<N>` is the number from `$ARGUMENTS`): `gh label create "action-required" --description "Needs a human action" --color "B60205" 2>/dev/null || true; gh issue edit <N> --add-label action-required` — create-then-add, never a flag that rewrites a founder's existing label. `soleur:operator-digest` reads that label when it runs against this repo (today: Soleur's own), and the digest is where a non-technical founder reads it as **"we cannot yet add an automatic test that keeps this bug from coming back"**; elsewhere the Phase 8 comment (item 8) is the only place the founder sees it, so say it there in those words.

## Phase 8: Report Back

This is the **single** issue comment of the run — nothing was posted in Phases 1–7. Add a comment to the issue with:

1. **Findings** - What was discovered about the cause
2. **Reproduction Steps** - Exact steps to reproduce (verified)
3. **Screenshots** - Visual evidence of the bug (upload captured screenshots). A screenshot never passes through the redactor: review each for another person's name, email, amount or an internal hostname first — crop it or leave it out.
4. **Relevant Code** - File paths and line numbers
5. **Suggested Fix** - If one exists. Name the next step: *after Phase 9, commit the loop script yourself and hand it to `soleur:test-fix-loop --cmd '<the command>' --max 5` so the fix iterates on the user's symptom, not on a proxy* — after cleanup, never before, because `soleur:test-fix-loop` requires a clean tree and would otherwise hand the founder a git instruction.
6. **The red-capable command** - Its redacted invocation and output, framed for the founder as *"a command your agent re-runs on request — red before the fix, green after — and shows you the result"*. When Phase 2 ended on option 1, 2 or 3 instead, this item carries that arm's line: `no loop buildable yet; instrumentation added: SOLEUR_<…>; re-run soleur:reproduce-bug on the next occurrence`, or the one environment ask, or the one artifact ask (what to capture and that it is handed to the agent, never attached here).
7. **The ranked hypotheses with verdicts** - The Phase 5 table; `UNKNOWN` is allowed, `CONFIRMED` only with the discriminating observation quoted. When the notice was not presented, add `founder notice not presented (headless); proceeded with the agent's ranking`.
8. **The regression seam verdict** - The seam (file + entry point), or `no correct seam` with the characterization-test plan from `soleur:engineering:review:legacy-code-expert`.

Write the whole body — the `--cmd` string included — with the Write tool to a file in your scratchpad directory (never the repo), then two gates before `gh issue comment`, each its own Bash call with the literal path (no `$( )`, no variables — the ship skill's convention). The structural check first: it catches what the redactor cannot (an opaque header value, a credential in a query string) — show a header's env-var NAME, never its value:

```bash
grep -niE '(authorization|proxy-authorization|cookie|set-cookie|apikey|x-api-key)[[:space:]]*:|[?&](token|access_token|apikey|key|secret|sig|signature)=' /path/to/scratchpad/reproduce-bug-<N>.md   # expected: no output; any line is a redaction to do by hand
```

Then the redactor, and post only on exit 0 (exit 1 = redaction needed: fix the body and re-run; exit 2 = cannot evaluate: do not post). Run Phase 3's §Preflight plugin-identity check first on every run, UI bug or not — an unset `CLAUDE_PLUGIN_ROOT` fails closed (exit 127), but a wrong-shaped root carrying a script that exits 0 would post an unredacted body (ADR-179 decision 2):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh" /path/to/scratchpad/reproduce-bug-<N>.md \
  && gh issue comment <N> --body-file /path/to/scratchpad/reproduce-bug-<N>.md
```

## Phase 9: Cleanup

After uploading screenshots to the issue comment, remove local screenshot artifacts. Playwright MCP writes to the main repo root when invoked from a worktree.

```bash
# Remove bug reproduction screenshots from current working directory
rm -f bug-*.png

# If in a worktree, also clean the main repo root
MAIN_REPO=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
if [[ -n "$MAIN_REPO" ]]; then
  rm -f "$MAIN_REPO"/bug-*.png
fi
```

Then walk the checklist; every box is required before declaring done:

- [ ] Original repro no longer reproduces (re-run the Phase 2 loop against the original, un-minimised scenario) — when a fix was applied in this run; otherwise this box transfers to `soleur:test-fix-loop`'s success row, where the fix lands
- [ ] Regression test passes (same transfer rule), or the seam's absence is documented in the Phase 7 verdict
- [ ] **No temporary probe ships with the fix** — the shape grep prints nothing (whole repo from any cwd; tracked and untracked files, either case, binaries included; `knowledge-base/**/*.md` is excluded only because a learning may quote a real tag):

  ```bash
  git grep -niE --untracked '\[DEBUG-[0-9a-f]{4}\]' -- ':/' ':(top,exclude)knowledge-base/**/*.md'   # expected: no output
  ```

- [ ] Throwaway harness deleted, or moved to a clearly-marked debug location
- [ ] **No production payload in the committed loop script or fixture** — a fixture derived from a captured trace is synthesized or redacted (`cq-test-fixtures-synthesized-only`); a captured artifact from Phase 2's option 3 is deleted, and nothing of its shape is left for a later `git add -A` to sweep up:

  ```bash
  git ls-files --others --exclude-standard | grep -iE '\.(har|webm|mp4|mov|dmp|core)$'   # expected: no output
  ```

- [ ] The hypothesis that turned out correct is stated in the Phase 8 comment, so the next debugger learns
- [ ] The loop script is committed — it is what `soleur:test-fix-loop --cmd '<the command>' --max 5` iterates on
