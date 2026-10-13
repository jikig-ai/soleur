---
title: "fix: SSRF hardening for cron-follow-through-monitor"
branch: feat-one-shot-4068-ssrf-hardening
plan: knowledge-base/project/plans/2026-05-26-fix-ssrf-hardening-cron-follow-through-monitor-plan.md
lane: single-domain
---

# Tasks: SSRF hardening for cron-follow-through-monitor

## Phase 0: Preconditions

- [ ] 0.1 Verify `ipaddr.js` API (after Phase 1 install): `ipaddr.process("::ffff:10.0.0.1").range()` -> `"private"`, `ipaddr.process("8.8.8.8").range()` -> `"unicast"`
- [ ] 0.2 Verify `node:dns/promises` is available: `dns.lookup()`, `dns.resolve4()`, `dns.resolveTxt()` (verified 2026-05-26)
- [ ] 0.3 Verify `new URL()` edge cases (verified 2026-05-26): `.username` for userinfo, `[::1]` brackets in `.hostname`, numeric IP normalization (`0x7f000001` -> `127.0.0.1`)
- [ ] 0.4 Verify YAML parser available transitively: `require("yaml")` from `apps/web-platform/node_modules`

## Phase 1: Add dependency

- [ ] 1.1 Add `ipaddr.js` to `apps/web-platform/package.json` dependencies
- [ ] 1.2 Run `npm install` in `apps/web-platform/`

## Phase 2: Create predicate validator module

- [ ] 2.1 Create `apps/web-platform/server/inngest/functions/_predicate-validator.ts`
  - [ ] 2.1.1 Export `ALLOWED_PREDICATE_HOSTS: Set<string>` with `app.soleur.ai`, `api.github.com`, `api.doppler.com`
  - [ ] 2.1.2 Export `isPublicIp(ip: string): boolean` using `ipaddr.process(ip).range() === "unicast"` (allowlist unicast, not denylist non-public)
  - [ ] 2.1.3 Export `validatePredicateUrl(rawUrl: string): Promise<ValidationResult>` with: (a) URL parse, (b) HTTPS-only check, (c) userinfo rejection (`url.username || url.password`), (d) IPv6 bracket strip from `url.hostname`, (e) host allowlist (`Set.has(hostname.toLowerCase())`), (f) `dns.lookup()` resolution (NOT `dns.resolve4()`), (g) `isPublicIp()` on resolved IP
  - [ ] 2.1.4 Export `executeHttpPredicate(url: string): Promise<HttpPredicateResult>` using `fetch()` with `redirect: "error"` and `AbortSignal.timeout(10_000)`
  - [ ] 2.1.5 Export `executeDnsPredicate(type, domain, expected): Promise<DnsPredicateResult>` using `dns/promises` with 10s timeout
  - [ ] 2.1.6 Export `validateAndExecutePredicates(issues): Promise<ValidatedPredicate[]>` that orchestrates per-issue validation + execution. Handle all predicate types: `http-200` (validate + execute), `dns-txt`/`dns-a` (validate + execute), `manual`/`api-curl`/`http-headers`/`cli`/`auto`/unknown (skip as manual with `{ skipped: true }`)
  - [ ] 2.1.7 Export `parsePredicateYaml(issueBody: string): ParsedPredicate | null` that extracts YAML from `## Verification` heading
  - [ ] 2.1.8 Export `formatPredicateResults(results): string` that generates the `## Pre-Validated Predicate Results` markdown block

## Phase 3: Update cron-follow-through-monitor

- [ ] 3.1 Add `"validate-predicates"` step.run before `"claude-eval"`
  - [ ] 3.1.1 Spawn `gh issue list --label follow-through --state open --json number,title,body,createdAt,author`
  - [ ] 3.1.2 Parse JSON output, extract YAML predicates from each issue body
  - [ ] 3.1.3 Call `validateAndExecutePredicates()` on parsed predicates
  - [ ] 3.1.4 Return validated results for prompt injection
- [ ] 3.2 Update `CLAUDE_CODE_FLAGS`: remove `Bash(curl:*)` and `Bash(dig:*)` from `--allowedTools`
- [ ] 3.3 Update `FOLLOW_THROUGH_PROMPT`:
  - [ ] 3.3.1 Remove step 3c (curl/dig execution instructions)
  - [ ] 3.3.2 Add instruction to read `## Pre-Validated Predicate Results` block
  - [ ] 3.3.3 Keep all state-transition logic (Guards A/B/C) unchanged
- [ ] 3.4 Inject validated predicate results by appending `formatPredicateResults()` output to the prompt at runtime
- [ ] 3.5 Update file-header SSRF comment: "DUAL" -> "TRIPLE", document Layer 3
- [ ] 3.6 Add `reportSilentFallback` call for validation failures (feature: "predicate-validation")

## Phase 4: Update existing tests

- [ ] 4.1 Update `cron-follow-through-monitor.test.ts` T1:
  - [ ] 4.1.1 Assert `Bash(curl` and `Bash(dig` absent from claude spawn args
  - [ ] 4.1.2 Assert step.calls includes `"validate-predicates"` before `"claude-eval"`
  - [ ] 4.1.3 Mock the `gh issue list` spawn in validate-predicates step
  - [ ] 4.1.4 Update spawn call count (now includes validate-predicates gh call)

## Phase 5: New predicate validator tests

- [ ] 5.1 Create `apps/web-platform/test/server/inngest/predicate-validator.test.ts`
  - [ ] 5.1.1 Test `isPublicIp`: public IPv4 -> true
  - [ ] 5.1.2 Test `isPublicIp`: loopback 127.0.0.1 -> false
  - [ ] 5.1.3 Test `isPublicIp`: private 10.x -> false
  - [ ] 5.1.4 Test `isPublicIp`: private 172.16.x -> false
  - [ ] 5.1.5 Test `isPublicIp`: private 192.168.x -> false
  - [ ] 5.1.6 Test `isPublicIp`: link-local 169.254.x -> false
  - [ ] 5.1.7 Test `isPublicIp`: loopback ::1 -> false
  - [ ] 5.1.8 Test `isPublicIp`: link-local fe80:: -> false
  - [ ] 5.1.9 Test `isPublicIp`: unique-local fc00:: -> false
  - [ ] 5.1.10 Test `isPublicIp`: IPv4-mapped ::ffff:127.0.0.1 -> false
  - [ ] 5.1.11 Test `isPublicIp`: IPv4-mapped ::ffff:10.0.0.1 -> false
  - [ ] 5.2.1 Test `validatePredicateUrl`: allowed host + public IP -> valid
  - [ ] 5.2.2 Test `validatePredicateUrl`: disallowed host -> invalid
  - [ ] 5.2.3 Test `validatePredicateUrl`: non-HTTPS scheme -> invalid
  - [ ] 5.2.4 Test `validatePredicateUrl`: URL with userinfo -> invalid
  - [ ] 5.2.5 Test `validatePredicateUrl`: DNS lookup timeout -> invalid with error
  - [ ] 5.3.1 Test `executeHttpPredicate`: 200 -> passed
  - [ ] 5.3.2 Test `executeHttpPredicate`: non-200 -> not passed
  - [ ] 5.3.3 Test `executeHttpPredicate`: fetch timeout -> error
  - [ ] 5.4.1 Test `executeDnsPredicate`: dns-txt expected found -> passed
  - [ ] 5.4.2 Test `executeDnsPredicate`: dns-a expected found -> passed
  - [ ] 5.4.3 Test `executeDnsPredicate`: expected not found -> not passed
  - [ ] 5.5.1 Test `parsePredicateYaml`: valid YAML extraction (type: http-200 with url)
  - [ ] 5.5.2 Test `parsePredicateYaml`: malformed YAML -> null
  - [ ] 5.5.3 Test `parsePredicateYaml`: missing Verification heading -> null
  - [ ] 5.5.4 Test `parsePredicateYaml`: type: api-curl -> parsed but treated as manual
  - [ ] 5.5.5 Test `parsePredicateYaml`: type: manual -> parsed, no URL validation needed
  - [ ] 5.6.1 Test `validatePredicateUrl`: numeric IP `https://0x7f000001/` -> invalid (URL parser normalizes to 127.0.0.1, loopback)
  - [ ] 5.6.2 Test `validatePredicateUrl`: IPv6 bracketed `https://[::1]/` -> invalid (bracket stripped, loopback)
  - [ ] 5.6.3 Test `isPublicIp`: unparseable string -> false (fail-closed)

## Phase 6: Final verification

- [ ] 6.1 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/predicate-validator.test.ts`
- [ ] 6.2 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-follow-through-monitor.test.ts`
- [ ] 6.3 Run full test suite: `cd apps/web-platform && npm test`
- [ ] 6.4 Verify `grep -c 'Bash(curl' apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` returns 0
- [ ] 6.5 Verify `grep -c 'Bash(dig' apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` returns 0
