# Decision challenges — feat-one-shot-playwright-mcp-stability

Plan: `knowledge-base/project/plans/2026-10-04-fix-playwright-mcp-browser-closing-on-its-own-plan.md`
Raised during headless planning (no operator available); for `ship` to render in the PR body.

## 2026-10-04 — User-Challenge 1: the ping-timeout env var is not the fix

- **Operator direction:** the heartbeat (`PLAYWRIGHT_MCP_PING_TIMEOUT_MS`) is the likely cause; add the setting to both registrations and a test asserting it.
- **Finding:** `@playwright/mcp` 0.0.78 and 0.0.83 start the heartbeat only on the HTTP session path; stdio (our launch) passes `runHeartbeat=false`. The setting is inert today, and the observed failure shape (tool-level "Target page ... closed", server still answering) contradicts a closed server.
- **Plan's resolution:** the operator's direction is honoured (setting added to both registrations, regression row asserts it) but it is labelled an inert latent-hazard guard, never the fix. The PR must not claim it fixes the symptom.
- **Decision for the operator:** keep as a labelled guard (default), or drop it entirely to avoid a no-op setting.

## 2026-10-04 — User-Challenge 2: scope extends to the plugin Stop hook

- **Operator direction:** scope is `.mcp.json`, `plugins/soleur/.mcp.json`, the config, the proxy, and matching tests; "No hook or script kills it."
- **Finding:** `plugins/soleur/hooks/browser-cleanup-hook.sh` (registered on `Stop`, which fires every turn) SIGTERMs every Playwright Chrome on the host; 14 of 15 failures on 2026-10-04 correlate with a hook kill.
- **Plan's resolution:** delete the hook plus the four registry/ledger/breadcrumb mirrors it requires (`hooks.json`, `.claude/hooks/devin-dispositions.tsv`, `plugin-stop-hooks-web-parity.test.ts`, `scripts/retired-rule-ids.txt`). Without this the user's reported symptom persists.
- **Decision for the operator:** confirm the hook deletion (default) or ask for a narrower alternative.

## 2026-10-04 — Taste: conditional fallback lives in the proxy

- The brief's "add a fallback to bundled Chromium" cannot be expressed in static JSON. The plan adds an opt-in `--chromium-fallback` proxy flag (keeps real Chrome and its sandbox where present). The unconditional `--browser chromium` alternative needs no proxy change but regresses Chrome-present hosts without the bundled download. Cut seam: item C can become its own PR.

## 2026-10-04 — Taste (plan-review): ship order and size

- Reviewers (simplicity, CTO) recommend landing item A (hook removal) plus its guard test first, then B (slot lease) and C (proxy fallback) separately, because A alone explains 14 of 15 observed failures and B/C carry their own semantics risk.
- Plan keeps one PR per the brief and names the seam. Decision for the operator: one PR (default) or A first.
- Also surfaced: ADR-271 vs learning-only (the brief allows either; plan keeps both because Phase 2.10 treats the lifetime invariant as an architectural decision); numbered slots kept over a pid-keyed fallback because the latter never gets reaped.

## 2026-10-04 — User-Challenge (CTO): slot 0 reconnect wait

- A `/mcp` reconnect's old proxy holds the slot-0 lock for up to 5 seconds, so a naive lease would move a reconnect to an empty profile and lose persistent logins. Plan adds a 7-second wait on slot 0 only; the cost is a 7-second slower start when a parallel session truly holds slot 0. Operator may prefer no wait.

## 2026-10-04 — Review resolutions (PR #9494, 13-seat panel)

- **Sandbox of the Chrome-less fallback (CTO ruling, Option 2).** The review found that `--chromium-fallback` silently selected an
  unsandboxed bundled Chromium on Linux (a persistent logged-in profile, arbitrary pages). Ruling: keep the flag in the plugin
  registration and have the proxy append `--browser chromium --sandbox`; where the host cannot run the sandbox the first browser
  call fails closed and the remedy is to install Google Chrome. `--no-sandbox`, `PLAYWRIGHT_MCP_SANDBOX` and config
  `chromiumSandbox:false` stay refused. Supersedes the plan's documented residual and risk R5; recorded in ADR-271 decision 4 and
  the ADR-213 addendum. The opt-in-env, drop-the-flag and `--config` alternatives were rejected (ADR-271 Alternatives).
- **Operator-asked ping-timeout env var: kept.** The simplicity seat proposed dropping the inert `PLAYWRIGHT_MCP_PING_TIMEOUT_MS=0`.
  It was an operator request (User-Challenge 1 above); it stays, labelled an inert latent-hazard guard and never the fix (ADR-271
  decision 5). The operator may still ask to drop it.
- **One PR: kept.** The simplicity seat recommended splitting the hook removal from the lease and the fallback. The operator's brief
  chose one PR and the lease is justified by the multi-session dogfood setup; the cut seams named above stand. The slot-script
  header's premise was corrected instead (the pinned server already refuses a second server on a locked profile; the lease exists
  because the old reaper killed siblings and a concurrent session needs a usable browser).
- **Guard 1: kept and widened, not cut.** The simplicity seat suggested replacing the dynamic hook scan with a grep. The test-design
  seat showed each scanner axis had one fixture member; the dynamic execution under a pgrep/pkill shim is the control, so it was
  widened (one hostile row per axis, wider population, slack floors that name the constant to lower) and its header claim softened
  to what it proves.
- **Plugin registration has no lease: documented, not fixed here.** Putting the lease inside the proxy would cover both
  registrations; it is recorded as the follow-up (ADR-271 Alternatives) and the limitation is in ADR-271 Consequences and the
  agent-browser playbook.

