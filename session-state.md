
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
