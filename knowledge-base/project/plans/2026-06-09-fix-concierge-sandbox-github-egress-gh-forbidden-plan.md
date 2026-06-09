---
date: 2026-06-09
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_prs: [5041, 5031, 4946, 5067, 5018]
module: apps/web-platform/server
---

# fix: Concierge `gh` still Forbidden — sandbox network plane denies GitHub egress (token plane is already swept)

## Enhancement Summary

**Deepened on:** 2026-06-09 (inline pass — pipeline context, no subagent fan-out available; all verifications executed directly against the worktree + installed SDK)
**Sections enhanced:** gates 4.6/4.7/4.8/4.9 evaluated; verify-the-negative pass; consumer enumeration; line-citation audit

### Key Improvements

1. **Verify-the-negative pass (all claims confirmed against code):**
   - "legacy `startAgentSession` never passes `ghToken`" — CONFIRMED: `grep -c "ghToken" apps/web-platform/server/agent-runner.ts` returns 0; `buildAgentQueryOptions` has exactly two production consumers (`cc-dispatcher.ts:1779`, `agent-runner.ts:1775`), so the `Boolean(args.ghToken)` derivation is provably fail-closed on the legacy path.
   - "`GH_TOKEN` is not in `ALLOWED_SERVICE_ENV_VARS`" — CONFIRMED at `agent-env.ts:59,80` (a BYOK `GITHUB_TOKEN` row cannot clobber or substitute the minted token at higher gh precedence).
   - "Edit/Write SDK tools remain hard-blocked on the cc path" — CONFIRMED: `CC_PATH_DISALLOWED_TOOLS = ["Edit", "Write"]` (`cc-dispatcher.ts:857`); note Bash is sandbox-gated, NOT in this list (hence the Phase 3 stale-comment fix).
2. **Line-citation audit:** spot-verified `cc-dispatcher.ts:1470` (mint from `effectiveInstallationId`), `Dockerfile:95` (`gh=2.93.0`), `cc-dispatcher-real-factory.test.ts:341` (`allowedDomains: []` shape assertion), `agent-runner-query-options.ts:173` (`sandbox:` option) — all current on this branch.
3. **Halt-gate results:** 4.6 User-Brand Impact (present, `single-user incident`) PASS; 4.7 Observability (5/5 fields, no-ssh discoverability) PASS; 4.8 PAT-shape sweep zero hits PASS; 4.9 UI-wireframe N/A (no UI surface). No rule-ID citations in plan body (zero fabrication exposure).

### New Considerations Discovered

- **Type-level no-op:** `AgentSandboxConfig.network.allowedDomains` is already `string[]` — the egress variant needs no type widening; `GITHUB_EGRESS_DOMAINS` as `Object.freeze([...] as const)` spread via `[...GITHUB_EGRESS_DOMAINS]` satisfies it (readonly-tuple → string[] copy).
- **Test discovery:** all three new test groups land in EXISTING files under `apps/web-platform/test/` — within vitest's `test/**/*.test.ts` include glob; no discovery-glob risk (the #4634 co-located-test trap does not apply).
- **Precedent diff (Phase 4.4):** the conditional-env precedent is `buildAgentEnv`'s askpass both-or-nothing guard (`agent-env.ts:168` — inject the set only when ALL inputs present, empty string counts as absent); the egress derivation adopts the same shape including the empty-string case (`Boolean("")` → false). The canonical-literal drift-guard test pattern (`agent-runner-helpers.test.ts` T17) is the cited precedent for the new egress-variant test. No novel patterns introduced.
- **Runtime-shape rule honored:** SDK semantics were grepped from the INSTALLED bundle (`@anthropic-ai/claude-agent-sdk@0.2.85` `cli.js`/`sdk.mjs`), not docs/memory, per learning `2026-05-14-plan-prescribed-runtime-shapes-must-be-grepped-against-installed-version.md`; Phase 0.1 re-runs the same greps at /work time to catch an SDK bump between plan and work.

## Overview

Despite PR #5041 (merged 2026-06-08) fixing the gh-403 → "No Git Repository in
Workspace" cascade, `gh issue view 4826 -R jikig-ai/soleur` inside the hosted
Concierge workspace still fails with:

```text
Post "https://api.github.com/graphql": Forbidden
```

**The task's hypothesis ("the GH_TOKEN mint is another unswept consumer of
`effectiveInstallationId`") is REFUTED by the code.** Research shows the token
plane is fully swept (see Research Reconciliation). The actually-unswept
"consumer" is one layer down: the **sandbox network plane**. The Concierge SDK
session runs with:

```ts
// apps/web-platform/server/agent-runner-sandbox-config.ts:66-69
network: {
  allowedDomains: [],          // ← no outbound network, ever
  allowManagedDomainsOnly: true,
},
```

Every Bash subprocess of the Concierge (including `gh` 2.93.0, installed by
`apps/web-platform/Dockerfile:95`) runs inside the SDK's bwrap sandbox where
all egress is forced through the sandbox HTTP proxy. With `allowedDomains: []`
the proxy denies CONNECT to `api.github.com`, and Go's HTTP transport surfaces
the CONNECT response status text verbatim — producing exactly
`Post "https://api.github.com/graphql": Forbidden`. (A GitHub-side 403 would
render as `HTTP 403: <message>` or `GraphQL: <message>` in gh's output, never
the transport-wrapped `Post "...": <status-text>` shape.)

This explains the whole incident arc:

- The operator screenshot (2026-06-09) shows the session-start preamble
  succeeding — `worktree-manager.sh cleanup-merged`, `git worktree list` are
  **local** git operations; the clone itself runs **server-side** (outside the
  sandbox) and was fixed by #5041. The `gh` call is the first **in-sandbox
  network** operation, and it has been structurally dead since the sandbox
  shipped with `allowedDomains: []` (#2901, never widened — verified via
  `git log -S "allowedDomains"`).
- Two token-selection PRs (#4946, #5031) and one ordering PR (#5041) fixed real
  server-side consumers, but none could cure the in-sandbox `gh` symptom
  because the credential was never the binding constraint **for gh** — the
  network was.
- The in-sandbox raw-git credential path (`GIT_ASKPASS` +
  `GIT_INSTALLATION_TOKEN`, agent-env.ts:168-175) is equally dead under
  `allowedDomains: []`: an in-sandbox `git push`/`fetch` to `github.com` can
  never connect. This fix revives both surfaces with one change.

**The fix:** allow GitHub egress (`github.com`, `api.github.com`) in the
Concierge sandbox **if and only if** an entitled GitHub App installation token
was minted for the session (`ghToken` present). The token mint is already
entitlement-gated (membership gate `findRepoOwnerInstallationForUser`,
fail-closed, #4946/#5031) — deriving egress from token presence structurally
guarantees "no entitled token → no GitHub egress" (fail-closed) and never
widens the entitlement gate itself, which this plan does not touch.

### SDK semantics (verified against installed code, not docs)

Verified in `@anthropic-ai/claude-agent-sdk@0.2.85` (pinned in
`apps/web-platform/package.json`):

1. `options.sandbox` is merged into the `--settings` payload
   (sdk.mjs: `Y={sandbox:X}; J.settings=q$(Y)`) — i.e. **flag settings**, not
   managed/policy settings.
2. The sandbox domain collector (`function Cv8` in cli.js) has two branches:
   the policy-managed branch (only when `policySettings.sandbox.network.
   allowManagedDomainsOnly === true` — not our case) and the else-branch which
   reads `q.sandbox?.network?.allowedDomains || []` from merged settings —
   **our flag-settings domains ARE honored**. There is no built-in GitHub
   default for the bwrap sandbox proxy (the `github.com,...` CSV near
   `/run/ccr/session_token` in cli.js is the NO_PROXY list for the cloud "ccr"
   upstream proxy — a different subsystem; verified red herring).
3. Denied hosts are refused at the proxy (`[sandbox] Blocked network request
   to ${host}`), which Go clients surface as `Post "<url>": Forbidden`.

`allowManagedDomainsOnly: true` is kept as-is: in the flag-settings context it
is inert (the policy branch never fires), and under either branch the domains
we add ride in the same settings source and are respected.

## Hypotheses (ranked, with evidence)

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| H-B | **Sandbox proxy denies `api.github.com`** (`allowedDomains: []`) | **Primary — fix this** | Error shape is transport-level (`Post "...": Forbidden` = CONNECT denial status text); `agent-runner-sandbox-config.ts:67` ships `[]` since #2901; SDK `Cv8` else-branch confirms flag-settings domains are the effective allowlist (empty); preamble's *local* git ops succeeding while the *first network* op fails matches exactly |
| H-A | GH_TOKEN minted from raw `installationId` (unswept consumer) | Refuted | `cc-dispatcher.ts:1470` mints from `effectiveInstallationId` since #5031; test-pinned at `cc-dispatcher-real-factory.test.ts:727` ("GH_TOKEN minted for the OWNER install, not the stored one") |
| H-C | #5067 least-privilege narrowing / cache-key pollution starves the Concierge token | Refuted | The Concierge mint passes no `permissions` → full installation grant; #5067 narrowing applies only to the cron mint path (`_cron-shared.ts:143`); cache key isolates scoped vs unscoped (`installationTokenCacheKey`, github-app.ts:692-711) |
| H-D | `GH_TOKEN` absent (mint failed fail-soft) and a stale BYOK `GITHUB_TOKEN` service credential shadows it | Residual check only | gh prefers `GH_TOKEN` over `GITHUB_TOKEN`; a GitHub-side rejection would render `HTTP 401/403: ...`, not the transport shape. Post-merge live verification step 2 covers this residually |

**Pivot gate (Phase 0):** if the Phase 0 probe shows the sandbox proxy does
NOT produce the `Forbidden` transport error for a denied host, stop and
re-diagnose via the H-D path (Sentry `op:mint-gh-token` + `op:installation-self-heal-*`
queries, `mirrorSelfHealSkip` events for the affected user/date) before
touching any code.

## Research Reconciliation — task claims vs. codebase

| Task/spec claim | Reality (verified) | Plan response |
|---|---|---|
| "the GH_TOKEN mint is yet another consumer of the installation id that was not swept to effectiveInstallationId" | Mint at `cc-dispatcher.ts:1470` consumes `effectiveInstallationId` (since #5031); #5041's own comment names mint + C4 tool as already-swept consumers; covered by existing test | Reframe: the unswept plane is **network**, not credential. Keep a lockstep AC pinning all token consumers to `effectiveInstallationId` so the sweep is regression-guarded |
| "the minted installation token simply lacks the scopes gh's GraphQL endpoint needs" | Concierge mint is unscoped → full installation grant; the entitled owner install carries the full app grant (incl. `issues`) | No token-scope change. H-C refuted |
| gh-403 is GitHub rejecting the token | Error shape is a proxy CONNECT denial; sandbox ships `allowedDomains: []` | Fix = conditional GitHub egress in the sandbox allowlist |
| (implicit) in-sandbox `git push` works via the askpass path | Equally dead under `allowedDomains: []` — askpass infra (agent-env.ts:168-175) is currently unreachable theater | Same fix revives it; add `github.com` (not just `api.github.com`) |
| (sibling sweep finding) legacy leader path | `agent-runner.ts:1318` resolves `installationId` and feeds `buildGithubTools`/`githubApiGet` with the RAW stored id — **no self-heal on the legacy path** (server-side MCP tools, not gh) | Out of scope (different surface, server-side, has its own error handling). File a deferral tracking issue at ship time |

**Token-plane sweep result (the task's "find every place" ask):** the Concierge
workspace has exactly ONE GitHub-token mint feeding `gh` — `cc-dispatcher.ts:1470`
(`effectiveInstallationId`, unscoped) → `buildAgentQueryOptions.ghToken` →
`buildAgentEnv` `GH_TOKEN` (agent-env.ts:148) and the SAME token as
`GIT_INSTALLATION_TOKEN` (agent-runner-query-options.ts:168). The C4 write tool
(`cc-dispatcher.ts:1499-1529`) also consumes `effectiveInstallationId`. No other
GH_TOKEN/GITHUB_TOKEN export reaches the Concierge env (`GH_TOKEN` is
deliberately not in `ALLOWED_SERVICE_ENV_VARS`; a BYOK `GITHUB_TOKEN` service
credential is lower-precedence for gh).

## Premise Validation

Checked 2026-06-09: PR #5041 MERGED (2026-06-08T15:38Z), PR #5031 MERGED
(2026-06-08T13:26Z), PR #4946 MERGED, PR #5018 MERGED (Tier-1 cron containment
— hook + `sandbox.enabled:false` for CRONS only; no host proxy live, so no
host-level egress firewall can explain the symptom). Issue #4826 is OPEN and
unrelated in content (it is merely the issue the operator asked the Concierge
to view). The Tier-2 egress-firewall brainstorm
(`knowledge-base/project/brainstorms/2026-06-09-tier2-cron-egress-firewall-brainstorm.md`)
is not yet implemented and targets the cron fleet, not the Concierge sandbox —
no overlap with this fix's surface (the SDK sandbox proxy is per-session,
in-process).

## User-Brand Impact

- **If this lands broken, the user experiences:** the current incident persists
  — a founder's Concierge cannot run any `gh` command (`Post "...": Forbidden`)
  on a correctly-connected repo, after THREE prior fixes claimed to address
  gh-403. Repeated "we fixed it" → still broken is a trust-destroying pattern.
  Conversely, if the egress gate is mis-wired (egress without token), `gh` runs
  unauthenticated and fails with confusing 401s.
- **If this leaks, the user's workflow/data is exposed via:** widening sandbox
  egress to `github.com`/`api.github.com` creates a NEW exfiltration channel: a
  prompt-injected agent could push workspace content to an attacker-controlled
  repo using attacker-supplied credentials embedded in injected content (the
  entitled token itself can only write where the membership-gated installation
  allows). Mitigations: egress is granted **iff** an entitled token was minted
  (fail-closed derivation, no standing egress); domains are limited to the two
  GitHub hosts (no wildcards, no gist/upload hosts); filesystem stays
  workspace-confined (`allowWrite: [workspacePath]`, `denyRead` unchanged);
  Edit/Write SDK tools remain hard-blocked on the cc path. Residual risk is
  accepted and documented — it is the unavoidable cost of the already-merged
  product decision that the Concierge drives GitHub via `gh` (GH_TOKEN mint
  Issue A, askpass plan item 1, gh prompt directives, gh in the Docker image).
- **Brand-survival threshold:** `single-user incident` (same class as #5041 —
  one founder dead-in-the-water on the flagship Concierge flow). CPO sign-off
  required at plan time; `user-impact-reviewer` + `security-sentinel` must run
  at review time.

## Implementation Phases

### Phase 0 — Preconditions & probes (no code)

0.1. **Pin SDK evidence.** Record `@anthropic-ai/claude-agent-sdk@0.2.85` and
     re-grep the installed bundle to confirm the two load-bearing semantics:

```bash
# flag-settings domains are honored (else-branch of the domain collector)
grep -o 'function Cv8(q){.\{0,400\}' apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/cli.js
# options.sandbox rides the --settings payload
grep -o '.\{80\}{sandbox:X}.\{80\}' apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs
```

If either grep comes back empty (SDK bump landed between plan and work),
re-derive the semantics from the new bundle BEFORE proceeding — the fix's
mechanism depends on them.

0.2. **Best-effort deny-shape probe (skippable).** If `bwrap` + `socat` are
     available locally, run a one-off SDK `query()` with the current sandbox
     config and a Bash probe
     `curl -sS -o /dev/null -w '%{http_code}' https://api.github.com/zen` —
     expect a 403/denied result; repeat with
     `allowedDomains: ["api.github.com"]` — expect 200. If the harness is
     unavailable (no API key / no bwrap), skip — the unit-level RED→GREEN plus
     post-merge live verification carry the proof. **Pivot gate:** if the
     denied probe does NOT fail, stop — re-diagnose per H-D before coding.

### Phase 1 — Contract change: `buildAgentSandboxConfig` egress option (RED→GREEN)

`apps/web-platform/server/agent-runner-sandbox-config.ts`:

```ts
/** Exact-host egress allowlist for Concierge gh + in-sandbox git. No wildcards. */
export const GITHUB_EGRESS_DOMAINS = Object.freeze([
  "github.com",      // raw git push/fetch via GIT_ASKPASS path
  "api.github.com",  // gh REST + GraphQL
] as const);

export function buildAgentSandboxConfig(
  workspacePath: string,
  opts?: { allowGithubEgress?: boolean },
): AgentSandboxConfig {
  return {
    // ...unchanged...
    network: {
      allowedDomains: opts?.allowGithubEgress ? [...GITHUB_EGRESS_DOMAINS] : [],
      allowManagedDomainsOnly: true,
    },
    // ...unchanged...
  };
}
```

RED tests first (`apps/web-platform/test/agent-runner-helpers.test.ts`):

- `buildAgentSandboxConfig("/w", { allowGithubEgress: true })` →
  `network.allowedDomains` equals `["github.com", "api.github.com"]`, all
  other fields identical to the canonical literal (new canonical-literal test
  for the egress variant — same verbatim-deep-equal style as T17).
- Default call and `{ allowGithubEgress: false }` → `[]` (existing T17 +
  "network is locked down" tests stay GREEN untouched — this IS the
  fail-closed negative control).

### Phase 2 — Consumer derivation: egress iff entitled token (RED→GREEN)

`apps/web-platform/server/agent-runner-query-options.ts:173`:

```ts
// GitHub egress is derived from ghToken presence — both-or-nothing, same
// family as the askpass both-or-nothing guard in buildAgentEnv. An entitled
// installation token without network egress is the #5041-followup bug (gh
// dead at the proxy); egress without a token would be unauthenticated
// surface for nothing. Deriving (not a separate flag) makes the half-wired
// state unrepresentable. Legacy startAgentSession never passes ghToken →
// its sandbox stays fully closed (fail-closed, zero behavior change).
sandbox: buildAgentSandboxConfig(args.workspacePath, {
  allowGithubEgress: Boolean(args.ghToken),
}),
```

RED tests first (`apps/web-platform/test/agent-runner-query-options.test.ts`,
alongside the existing ghToken-threading tests at :150):

- `buildAgentQueryOptions({ ...base, ghToken: "ghs_install_tok" })` →
  `options.sandbox.network.allowedDomains` contains `"api.github.com"` and
  `"github.com"`.
- `buildAgentQueryOptions(base)` (no ghToken) → `allowedDomains` equals `[]`.
- Empty-string ghToken → `[]` (graceful-degradation parity with `GH_TOKEN`
  injection in `buildAgentEnv`).
- Drift-guard reconcile: the legacy↔cc shared-shape test
  (`agent-runner-helpers.test.ts:121`) compares both paths WITHOUT ghToken —
  must stay green unchanged (proves legacy sandbox profile is untouched).

### Phase 3 — Factory-level lockstep tests + observability (RED→GREEN)

`apps/web-platform/test/cc-dispatcher-real-factory.test.ts`:

- **Mismatch case (the task's RED→GREEN ask):** stored install ≠ repo owner,
  membership gate promotes → assert IN THE SAME TEST that (a) `GH_TOKEN` is
  minted from the OWNER install (existing :727 assertion style) AND (b) the
  SDK query options carry `network.allowedDomains` containing
  `api.github.com` — the egress and the entitled token move in lockstep.
- **Fail-closed case:** no connected repo (mint skipped) → `GH_TOKEN` absent
  AND `allowedDomains` equals `[]` (extends the existing :341 shape
  assertion — that existing `[]` assertion covers no-token dispatches and
  must NOT be loosened).
- **Mint-failure case:** `generateInstallationToken` throws (existing AC4
  test at :681) → dispatch continues, AND `allowedDomains` is `[]` (egress
  collapses with the token — never egress without auth).

`apps/web-platform/server/cc-dispatcher.ts` (small, additive):

- After the mint try/catch (~:1480), one structured posture log —
  `log.info({ userId: args.userId, githubEgress: Boolean(ghToken) },
  "Concierge sandbox GitHub egress posture")` — boolean only, NEVER the token
  (AC6-class guard from #5041 applies).
- Fix the stale comment at ~:1799 ("HARD-BLOCK Bash/Edit/Write" → actual
  `CC_PATH_DISALLOWED_TOOLS = ["Edit", "Write"]`; Bash is sandbox-gated, not
  blocked) — it actively misleads exactly this diagnosis class.

**Sweep of sibling suites asserting `allowedDomains: []`** (per the
allow-list-extension learning — all guard suites, not just the named one):

| File | Disposition |
|---|---|
| `test/agent-runner-helpers.test.ts:48,72` | stays `[]` (default-call canonical) + NEW egress-variant tests |
| `test/agent-runner-query-options.test.ts` | NEW derivation tests (no existing `[]` assertion found — /work re-grep to confirm) |
| `test/cc-dispatcher-real-factory.test.ts:341` | stays `[]` (dispatches without GH_TOKEN per its own :100 comment) + NEW lockstep tests |
| `test/cc-dispatcher-prefill-guard.test.ts:278,359` | expected unchanged (no-token dispatches) — /work MUST verify, not assume |
| `test/sandbox-isolation.test.ts:485` | legacy-path shape — expected unchanged — /work MUST verify |

### Phase 4 — Verification

- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT
  `npm run -w` — no root workspaces field).
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-runner-helpers.test.ts test/agent-runner-query-options.test.ts test/cc-dispatcher-real-factory.test.ts`
  then the full suite (`./node_modules/.bin/vitest run`).
- RED→GREEN evidence: run the three new test groups against a stash-free
  checkout of `origin/main`'s server files (or pre-change commit) and record
  the failures in the PR body.
- Entitlement-gate invariance: `git diff origin/main -- apps/web-platform/server/cc-dispatcher.ts`
  must show NO changes inside the self-heal block (:1338-1427) or
  `findRepoOwnerInstallationForUser` / `github-app.ts` — the gate is consumed,
  never modified.

## Files to Edit

1. `apps/web-platform/server/agent-runner-sandbox-config.ts` — `GITHUB_EGRESS_DOMAINS` const + optional `opts.allowGithubEgress` param (Phase 1).
2. `apps/web-platform/server/agent-runner-query-options.ts` — derive egress from `args.ghToken` at the `sandbox:` option (Phase 2).
3. `apps/web-platform/server/cc-dispatcher.ts` — posture log line + stale-comment fix only; NO logic changes (Phase 3).
4. `apps/web-platform/test/agent-runner-helpers.test.ts` — egress-variant canonical tests (Phase 1).
5. `apps/web-platform/test/agent-runner-query-options.test.ts` — derivation tests (Phase 2).
6. `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` — lockstep mismatch/fail-closed/mint-failure tests (Phase 3).

Verify-unchanged (no planned edits, must re-run and confirm green):
`apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts`,
`apps/web-platform/test/sandbox-isolation.test.ts`.

## Files to Create

None (plan + tasks artifacts only).

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 (contract):** `buildAgentSandboxConfig(p)` and
   `buildAgentSandboxConfig(p, { allowGithubEgress: false })` →
   `network.allowedDomains` deep-equals `[]`;
   `buildAgentSandboxConfig(p, { allowGithubEgress: true })` → deep-equals
   `["github.com", "api.github.com"]`; all other fields byte-identical to the
   canonical literal. Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-runner-helpers.test.ts`.
2. **AC2 (derivation):** `buildAgentQueryOptions` with truthy `ghToken` →
   sandbox allowlist contains both GitHub hosts; with absent/empty `ghToken` →
   `[]`. New tests demonstrably FAIL against pre-change code (RED evidence in
   PR body).
3. **AC3 (lockstep mismatch case):** real-factory test where the self-heal
   promotes asserts BOTH `generateInstallationToken` called with the OWNER
   install AND query-options egress enabled, in one test (single-test lockstep
   per the #5041 learning's "sweep every consumer" mechanical gate).
4. **AC4 (fail-closed):** no-repo and mint-failure dispatches assert
   `GH_TOKEN` absent AND `allowedDomains` `[]`. The pre-existing `[]`
   assertions at `cc-dispatcher-real-factory.test.ts:341`,
   `cc-dispatcher-prefill-guard.test.ts:278,359`, `sandbox-isolation.test.ts:485`
   remain green WITHOUT edits (legacy + no-token profiles unchanged).
5. **AC5 (entitlement-gate invariance):** `git diff origin/main --
   apps/web-platform/server/cc-dispatcher.ts apps/web-platform/server/github-app.ts`
   contains no hunk overlapping the self-heal block or
   `findRepoOwnerInstallationForUser` (egress consumes the gate's output,
   never alters it).
6. **AC6 (no token leakage):** the new posture log and all new test fixtures
   carry no `ghs_`/`gho_`/`ghp_` value into log payloads; grep the diff for
   the boolean-only invariant: `git diff origin/main | grep -n "githubEgress"`
   shows only `Boolean(ghToken)` usage.
7. **AC7 (suite health):** `./node_modules/.bin/tsc --noEmit` clean; full
   web-platform vitest suite green; `scripts/test-all.sh` green.
8. **AC8 (PR body):** `Ref` the operator incident context + `Ref #5041`
   (no `Closes` — the proof of fix is post-merge live verification).

### Post-merge (operator-free verification)

9. **AC9 (live e2e, automated):** after deploy completes (deploy-status
   webhook confirms), drive the prod Concierge chat via Playwright MCP: send
   "Run `gh issue view 4826 -R jikig-ai/soleur` and paste the literal output."
   PASS = output contains the issue title ("nav-rail position resume…"); FAIL
   = any `Forbidden`/403 string. Automation: `mcp__playwright__*` against the
   prod chat UI (bot-allowlisted route) — no operator eyeballing.
10. **AC10 (Sentry posture):** query Sentry API for new
    `op:mint-gh-token` / `op:installation-self-heal-probe` events post-deploy
    (curl with SENTRY token from Doppler, read-only). Expect zero new
    mint-failure events attributable to this change.

## Open Code-Review Overlap

Checked 2026-06-09 against open `code-review` issues (200-issue window):

- `#3243` (arch: decompose cc-dispatcher.ts into focused modules) — touches
  `cc-dispatcher.ts`. **Acknowledge:** this PR adds one log line + a comment
  fix; folding a decomposition refactor into a single-user-incident fix would
  invert the risk profile. The scope-out remains open and is easier after this
  lands (one fewer inline concern).
- `#3242` (tool_use WS event lacks raw name field) — touches
  `cc-dispatcher.ts`, unrelated concern (WS event shape). **Acknowledge:**
  no interaction with the sandbox/egress surface.

## Domain Review

**Domains relevant:** Engineering (CTO), Security, Product (CPO sign-off)

### Engineering (CTO)

**Status:** reviewed (inline — pipeline context, no subagent tool available)
**Assessment:** The egress-iff-token derivation is the right shape: it encodes
the invariant structurally (half-wired states unrepresentable) rather than as
a second flag to keep in sync, mirroring the existing askpass both-or-nothing
guard. Alternative (route gh through server-side MCP tools like the legacy
leader path) rejected: contradicts four merged PRs of product direction
(GH_TOKEN mint, askpass, gh prompt directives, gh in the image) and would
strand the askpass feature permanently. The change is additive and
default-preserving for every other consumer (legacy leader path, crons, all
no-token dispatches). Sibling gap noted: the legacy path's `buildGithubTools`
consumes the raw stored `installationId` with no self-heal — defer with a
tracking issue (different surface, server-side error handling exists).

### Security

**Status:** reviewed (inline — `security-sentinel` MUST re-review at PR time)
**Assessment:** New egress = new exfil channel (prompt-injected agent +
attacker-supplied credentials could push workspace content to attacker repos).
Bounded by: exact-host allowlist (2 hosts, no wildcards, no
`gist.githubusercontent.com`/`uploads.github.com`), egress only when the
membership-gated token exists, workspace-confined filesystem, Edit/Write still
SDK-blocked. The entitled token itself cannot write outside the gated
installation. Residual risk accepted at product level (CPO sign-off below);
fail-closed proof is AC4 + AC5.

### Product/UX Gate

**Tier:** none (no UI-surface files in Files to Edit/Create — server + tests
only; mechanical override scanned: no `components/**`, `app/**` paths)
**Decision:** N/A — but `requires_cpo_signoff: true` per the single-user-incident
threshold: CPO sign-off on restoring the Concierge gh capability with the
documented residual exfil risk is required before `/work`. Carried as the
plan-time single product-owner ack; `user-impact-reviewer` runs at review time.
**Agents invoked:** none (pipeline context — no Task tool; inline assessments above)
**Skipped specialists:** none applicable (no UI surface)
**Pencil available:** N/A (no UI surface)

## GDPR / Compliance Gate (advisory)

Trigger (b) fires (`single-user incident` threshold). Inline advisory — not
legal advice: the change introduces no new processor (GitHub already processes
the user's repo data; the egress moves a call site from server to sandbox), no
special-category data, no new retention surface, no Art. 30 register change.
The exfil-channel risk is a security posture item (handled above), not a
lawful-basis item. No Critical findings; no `compliance-posture.md` write.

## Observability

```yaml
liveness_signal:
  what: "Concierge sandbox GitHub egress posture" log.info with { userId, githubEgress: boolean } per cold dispatch
  cadence: every cold Concierge dispatch
  alert_target: none (posture line, not an alert) — failures alert via error_reporting below
  configured_in: apps/web-platform/server/cc-dispatcher.ts (Phase 3)
error_reporting:
  destination: Sentry — existing op:mint-gh-token (mint failure) and op:installation-self-heal-probe mirrors, unchanged
  fail_loud: mint failure already mirrors; egress collapses to [] with the token (fail-closed, AC4)
failure_modes:
  - mode: egress enabled without token (regression in derivation)
    detection: AC4 unit tests (mint-failure + no-repo cases) — unrepresentable by construction
    alert_route: CI red
  - mode: token minted but egress missing (re-introduction of this bug)
    detection: AC3 lockstep test; live AC9 Playwright e2e post-merge
    alert_route: CI red / post-merge verification FAIL
  - mode: SDK semantic change (sandbox settings precedence shifts on SDK bump)
    detection: Phase 0.1 greps re-run on any @anthropic-ai/claude-agent-sdk version bump (note added beside the pinned dep); AC9 e2e re-run after deploy
    alert_route: post-merge verification FAIL + GH_403 directive forces the agent to surface literal errors to the operator
logs:
  where: pino stdout → container logs (deploy-status webhook host) — no SSH path required for the posture boolean (it also rides the existing dispatch log stream)
  retention: container lifetime (existing platform default)
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-runner-helpers.test.ts test/agent-runner-query-options.test.ts
  expected_output: egress-variant + derivation tests pass (exit 0)
```

## Test Scenarios

1. Egress variant canonical shape (Phase 1) — RED first.
2. Default/false variant unchanged `[]` — existing tests untouched (negative control).
3. Derivation: truthy token → 2 hosts; absent token → `[]`; empty-string token → `[]` — RED first.
4. Lockstep mismatch case: promotion → owner-install mint + egress in one test — RED first.
5. Fail-closed: no-repo and mint-throw → no token + `[]` egress.
6. Legacy↔cc drift guard: both paths sans token byte-identical (existing, stays green).
7. Full-suite + typecheck + `scripts/test-all.sh`.
8. Post-merge: live Playwright e2e (AC9) + Sentry posture query (AC10).

## Alternative Approaches Considered

| Alternative | Verdict | Why |
|---|---|---|
| Route all Concierge GitHub ops through server-side MCP tools (legacy-path pattern); keep sandbox closed | Rejected | Contradicts merged product direction (#4946/#5031/#5041 + GH_TOKEN/askpass infra); strands the askpass feature; larger diff and a worse agent UX (gh is the lingua franca of the preamble + skills) |
| Always-on GitHub egress (unconditional allowlist) | Rejected | Violates fail-closed: sessions with no connected repo would have egress for nothing; the token-derived gate costs one `Boolean()` |
| Explicit `allowGithubEgress` flag threaded from cc-dispatcher | Rejected (chose derivation from `ghToken`) | A separate flag re-creates the half-wired-state class this incident exemplifies (token without egress); derivation makes it unrepresentable |
| Add wildcard `*.github.com` / upload + gist hosts | Rejected | Exfil-surface minimization; `gh issue/pr view`, `gh api`, and git push/fetch need exactly the two hosts. Widen later behind its own review if a concrete gh subcommand requires it (deferral note in tracking issue) |
| Also fix the legacy leader path's raw-`installationId` GitHub tools | Deferred (tracking issue at ship) | Different surface (server-side tools), no reported symptom, own blast radius |

## Risks & Mitigations

- **Risk:** SDK treats programmatic sandbox settings differently in a future
  version (policy-managed branch starts firing). **Mitigation:** domains ride
  in the same settings source as the flag → respected under both `Cv8`
  branches (verified semantics, Phase 0.1 re-grep on bump); AC9 live e2e is
  the backstop.
- **Risk:** `gh` needs a host beyond the two allowed (e.g. avatar/CDN fetch on
  some subcommand). **Mitigation:** scope is `issue/pr view`, `gh api`, git
  push/fetch — all exercised by AC9 and the preamble; any residual subcommand
  failure now produces an explainable, narrow deny (and the GH_403 directive
  forces literal error reporting), not a mystery.
- **Risk:** prompt-injection exfil via the new egress (see User-Brand Impact).
  **Mitigation:** entitlement-gated, host-limited, workspace-confined;
  security-sentinel review at PR time is mandatory.
- **Risk:** the diagnosis is wrong (H-B disproven at Phase 0.2 probe).
  **Mitigation:** explicit pivot gate — stop, run the H-D Sentry queries, do
  NOT ship a speculative egress widening.

## References

- PR #5041 — clone consumes self-healed installation (ordering fix)
- PR #5031 — self-heal hardening (transient-robust fail-closed probe)
- PR #4946 — repo-owner installation selection + membership entitlement gate
- PR #5067 — least-privilege cron token + cache-key scope isolation (H-C refutation)
- Learning: `knowledge-base/project/learnings/bug-fixes/2026-06-08-harden-computation-must-sweep-every-consumer-not-just-the-symptom-one.md`
- Post-mortem: `knowledge-base/engineering/operations/post-mortems/concierge-clone-stale-installation-gh403-postmortem.md`
- SDK evidence: `@anthropic-ai/claude-agent-sdk@0.2.85` `cli.js` (`Cv8`, `v$6`, ccr NO_PROXY red herring), `sdk.mjs` (`{sandbox:X}` → `--settings`)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  deepen-plan Phase 4.6 — section above is complete with threshold declared.
- The `test/cc-dispatcher-prefill-guard.test.ts` and
  `test/sandbox-isolation.test.ts` `[]` assertions are EXPECTED unchanged but
  must be verified-by-run, not assumed — they are the canary that the legacy
  and no-token profiles did not widen.
- Run vitest via `./node_modules/.bin/vitest run` (bunfig blocks `bun test`
  discovery in this package); typecheck via in-package `tsc --noEmit`.
