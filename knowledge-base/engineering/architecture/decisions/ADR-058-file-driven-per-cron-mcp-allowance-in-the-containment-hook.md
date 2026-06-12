# ADR-058: File-driven per-cron `mcp__*` allowance in the cron containment hook

- **Status:** Accepted
- **Date:** 2026-06-12
- **Issue:** #5199 (restore cron-ux-audit — the first cron needing an `mcp__*` tool)
- **Lineage:** ADR-052 (container egress firewall), #5018/#5046 (deny-by-default containment hook + relax-minimal Task/Skill allow). This ADR governs the FIRST `mcp__*` egress allowance through that hook.

## Context

The cron containment hook (`apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`) is the sole fail-closed PreToolUse gate for `claude --print` agents spawned by Inngest crons, beneath the L3 egress firewall and the per-cron GitHub-App token scope. Its hard contract: **the hook never receives `cronName`** — its only input is `argv[2]`, the per-cron allowlist file path. The file is delivered under the spawn's `.claude/` (which the hook itself read- and write-denies), so policy in the file is tamper-proof to the agent; policy in an arg/env would be readable via `ps`/`/proc`. Until #5199 the catch-all denied every `mcp__*` tool: "no restored cron needs them."

`cron-ux-audit` needs five `mcp__playwright__browser_*` tools to screenshot live routes. It drives Playwright against the live prod app as an authenticated bot whose Supabase session tokens live in the browser context — so `browser_navigate` (arbitrary URL) + the firewall allowing `api.soleur.ai` is a clean secret-in-URL exfil leg the content-blind firewall cannot see.

## Decision

**Per-cron `mcp__*` policy is encoded as directive lines inside the same per-cron `cron-allow.txt`, parsed by the hook; it is NOT keyed on `cronName`.** Two directive shapes extend the bash-prefix grammar:

- `mcp-allow <tool>` — that exact `mcp__*` tool is permitted for this cron.
- `navigate-origin <origin>` — the ONLY origin `mcp__playwright__browser_navigate` may load.

A cron whose file carries no directive lines (every cron except ux-audit) gets an empty allow-set → every `mcp__*` stays catch-all denied. The substrate (`CRON_MCP_ALLOWLISTS` in `_cron-claude-eval-substrate.ts`) is the sole producer of directive lines; the hook is a pure consumer; `runHookSelfTest` re-probes the *written clone* per spawn (app-origin navigate must ALLOW; off-origin, off-list mcp, and WebFetch must DENY) and aborts the cron on a missing guard.

### Why file-driven, not `cronName`

A `cronName` arg/env would force the hook to duplicate `CRON_MCP_ALLOWLISTS` inside the `.mjs` (a second source of truth in another module) AND would be agent-readable via `ps`. A separate mcp-allow file doubles the fail-closed load surface for no gain — the policy is per-cron exactly like the bash prefixes, so it belongs in the same per-cron artifact. The file-driven design is the only one where per-cron scoping is **structurally** true rather than test-asserted-but-globally-true; the cross-cron negative test (and the per-spawn self-test) exist precisely to catch a regression to a global allow.

### The two enforced bounds on `browser_navigate`

1. **URL-origin guard (load-bearing):** deny any navigation whose origin ≠ the `NEXT_PUBLIC_APP_URL` origin pinned in the file (resolved at spawn time by the substrate, which refuses to relax without a resolvable pin), reject embedded userinfo, and scan path + query + fragment for prefix-shaped secrets.
2. **Session-secret read-deny:** `storage-state.json`, `tmp/ux-audit/`, and `playwright-mcp-profile/` are added to `SECRET_PATH_PATTERNS` so the agent can never Read the bot session into context to then encode it into an allowlisted egress call. This is the primary control; the URL-scan is best-effort defense-in-depth (it cannot match opaque Supabase refresh tokens).

## Consequences

- Adding an `mcp__*`-using cron = add a `CRON_MCP_ALLOWLISTS` entry (+ `navigateOriginEnv` if it navigates) and a `--allowedTools` parity assertion; the hook needs no edit.
- The `mcp__playwright__*` tool set is declared in two producers (the cron's `--allowedTools` string and `CRON_MCP_ALLOWLISTS`); a parity test (`cron-ux-audit.test.ts`) keeps them in lockstep.
- The Chromium baked in the image must match `@playwright/mcp`'s `playwright-core` (registry + CDN are off the egress allowlist); a drift guard (`playwright-mcp-version-pin.test.ts`) enforces the Dockerfile↔lockfile pin. The pinned version (`@playwright/mcp@0.0.75`) is the newest **stable** release clearing the repo's bun `minimum-release-age` supply-chain floor (3 days) so both lockfiles resolve it; the Dockerfile bakes its `playwright-core@1.61.0-alpha-1778188671000`.
- Brand-survival threshold for the restored cron is single-user incident; this primitive widens the containment posture's attack surface, so any new `mcp__*` allowance is a CPO/security-sign-off-class change.
