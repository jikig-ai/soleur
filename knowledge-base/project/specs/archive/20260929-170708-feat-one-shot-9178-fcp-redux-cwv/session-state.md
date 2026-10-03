# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-28-perf-dashboard-fcp-redux-cwv-observability-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors

- Planning ran sequential-fallback inline (no Task/Skill fan-out in this runtime); disclosed in plan "Research agents used" + Domain Review.
- Exec shells default CWD was the repo root, not the worktree — all writes verified under worktree-absolute paths.
- webfetch denied in background mode; substituted web_search + installed `@sentry/browser@10.59.0` source inspection (produced the plan's key correction: `webVitalsIntegration` never covers FCP/TTFB, so `browserTracingIntegration` + `tracesSampler` is required).
- `.pen` UX gate satisfied by referencing committed `dashboard-load-states.pen`; recorded as decision-challenge #2.
- `lane:` defaulted to cross-domain (no spec.md; fail-closed default).

### Decisions

- Dedup is migration to existing SWR + `swrKeys` + `dedupingInterval` (ADR-067), not new machinery; 17 raw `fetch("/api/` sites baseline; adds `usePostFcp` null-key deferral primitive + census guard test.
- `middleware.ts` excluded from diff — ADR-253 fail-closed gates untouched (verify-only leg).
- RUM via `browserTracingIntegration()` + `tracesSampler` (1.0 under localStorage probe marker, 0.1 otherwise) + beforeSendTransaction/beforeSendSpan scrub reuse.
- Skill encoding: `plugins/soleur/skills/plan/references/webapp-cwv-observability.md` recipe + pointers in plan/SKILL.md Phase 2.9 and spec-templates/SKILL.md; perf-probe extension covers live-verify.
- ADR deliverables: amend ADR-067 (mount-fetch contract) + new field-RUM ADR; `model.c4` webapp→sentry edge prose. `closes: [9178, 8985]`.

### Components Invoked

- soleur:plan (inline), soleur:deepen-plan (inline); no agents spawned (unavailable in subagent runtime).

### Collision-gate re-probe (post-plan, lead)

- #9178 OPEN; #8985 OPEN; `in:body` open/merged probes clean for both.
- Anchor probe over ~24 planned files vs all open PRs: zero hits.
- Sibling worktree noun check: only stale merged-PR worktrees (`feat-one-shot-dashboard-load-latency` → merged PR 8903; `feat-one-shot-8978-cold-load-first-paint` → merged PR 8984). No live collision.

## Work Phase

- 4 parallel agents (Tier B fan-out): perf-probe (52d6c0af), Sentry RUM (16af5a9a), followthrough (08871636), skills/ADR (a886cc13); lead implemented the SWR core (tasks 1.2–1.7).
- All 20 implementation tasks complete; Phase 4.2/4.3 remain post-deploy arms.

### Work-phase findings worth carrying

- `org-switcher-container` last-known latch: `clearSwrCache` at the RPC-commit boundary now nulls the memberships SWR data — without a `useRef` latch the switch chrome unmounted mid-flow and the offline post-RPC park dialog never rendered. Caught by two-phase-commit tests; memberships are principal-scoped (safe to keep through the clear).
- SWR `focusThrottleInterval` (default 5s) suppresses early focus revalidations — tests asserting focus re-fetch need `focusThrottleInterval: 0` in the provider value.
- Badge/consumer tests that mock `useSWR` and assert call[0] now see `null` first (post-FCP gate) — pin `usePostFcp: () => true` via vi.mock.
- `SENTRY_ACTIONS_RO_TOKEN` is the GitHub-secret name (sweeper env), NOT a Doppler name — Doppler carries `SENTRY_API_TOKEN`/`SENTRY_ISSUE_RO_TOKEN`.
- Followthrough scripts are NOT glob-discovered — `test-all.sh` needs an explicit `run_suite` line per new `*.test.sh` (added `cwv-field-rum-9178`).
- Quota check: `stats_v2` 7d jikigai-eu — transactions accepted 3,569 / client_discard 382,935 (old sample rate 0). At 0.1 → ~5.5k tx/day; recorded in PR body, sampler is the dial.
- `--affected` degraded to MODE=full because `scripts/test-all.sh` itself is in the diff (runner-changed) — long battery; commit hook's bun-test run must not overlap (sibling full-gate refusal).

## Review Phase Complete

Commit: f9ec82f53a (review fixes on top of 9687670d41). Panel: 9 seats + 3 design-validity (architecture/perf/simplicity) — all returned; 3 seats resumed after rate-limit kill.

### P1 (fixed)

- security-sentinel: client transaction envelopes lacked the server's sanitizeRequestForSentry layer — invite/shared bearer tokens in pageload request.url + transaction names shipped raw at 10% sampling. Fixed: lib/sentry-url-sanitize.ts shared by server+client (query/hash strip, TOKEN_PATH_PREFIXES tails → <token>, query_string deleted, request.data string scrub, beforeBreadcrumb wired). Pinned by sentry-client-webvitals.test.ts.

### P2 (all fixed inline — cost-of-filing gate)

- usePostFcp rIC unbounded → {timeout: 2000} + rAF→setTimeout Safari fallback.
- probe duplicates keyed on safePath → sha256 dupKey (method|pathname|param-names); designed-repeat paths → expectedRepeats channel (active-repo exclusion no longer masks the headline path); dupKey stripped at PERF_JSON emit.
- swrConfig errorRetryCount: 3 (retry+Sentry-mirror amplification bound).
- DASHBOARD_FOUNDATION_STATUS_KEY → swrKeys.dashboardFoundationStatus() (ADR-067 contract parity).
- useOnboarding PostgREST mount read → swrKeys.onboardingState() (page + tour-provider pair coalesces; 2 files, inline fix per gate).
- Followthrough: PASS arm requires vital-bearing PAYLOAD rows (nav-vitals can't mask dark pageloads); tracker directive moved to issue body + PR body now uses "Tracks #9178" not "Closes"; plan secrets line corrected (SENTRY_ACTIONS_RO_TOKEN).
- use-team-names: mutations revalidate shared key + res.ok checked (phantom-save class).
- useActiveRepo: poll interval 2.1s (outside dedup window) + onError warn mirror.
- Census guard: SCAN_DIRS widened to full mount-rendered dir set; evasion boundaries (fetch(var), fetcher-invoked-outside-useSWR) pinned by self-tests; command-palette documented exclusion.
- Marker localStorage → sessionStorage; 11 freshCache wrappers → SwrTestProvider; test pins added (null-key direction, poll floor, config pins, cancel-spy unmount arms).

### Semgrep (real run, EIO_BACKEND=posix)

222 rules / 22 changed files → 1 INFO (unsafe-formatstring on pre-existing console.error template). Clean.

### Deferred / documented

- `<img src="/api/...">` mount GETs (leader-avatar, workspace-identity-tile) — browser transport, no fetch( token; documented in census header.
- command-palette lazy GETs — documented exclusion (classifier can't express laziness).
- Census parser's hand-rolled TS heuristics — boundary self-tests pin the gaps; AST rewrite is a follow-up (Medium effort, guard-only).
- refreshInterval equality boundary → resolved via 2.1s.

### Verification

- vitest touched suites: 245/245 + perf-probe 22/22 + followthrough 19/19 arms.
- eslint-config baseline: clean after orphaned-import sweep (15/15).
- test-all --affected (TEST_GROUP=webplat): 3/4 suites pass + component suite green after baseline fix.
- middleware.ts: 0-line diff vs origin/main (NFR1 holds). merge-tree --write-tree: clean (0 conflicts).

Review-Panel: 12 seats | P1×1 fixed | P2×~10 fixed inline | P3 documented/deferred | Semgrep clean
