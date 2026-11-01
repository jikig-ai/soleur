# Review seat: data-integrity-guardian — PR #11780

Scope: `git diff origin/main...HEAD` in `feat-one-shot-11772-next-dev-server-crash`.
Report-only; no git writes or file edits performed.

## Verdict: PASS (one P3 stale-comment nit, non-blocking)

## What was verified

### Drain-guard constant agreement (.py ↔ .test.sh) — PASS

- `WATCHED_PACKAGES` gains `"next"` (assert-dependabot-drain.py:53); `declared`
  set from REQUIRED equals it (14 packages, verified by hand-count and by the
  live run exiting 0 through the `declared != WATCHED_PACKAGES` gate).
- New REQUIRED row `("web-platform", "next", 16, "16.4.1")` at :131. Hand count
  of REQUIRED = 36 rows = MIN_ROWS=36 (:285) = MIN_RESOLVED=36 (:293). Live run
  prints "36 rows evaluated, 36 resolved to an installed version (floor 36)".
- `FLOOR_ANCHORS[("next", 16)] = "16.4.1"` (:177) matches test.sh spec
  `"next:16:16.4.1"` (test.sh:232) — exact package, major, version agreement.
- test.sh literals: `MIN_ROWS:36`, `MIN_RESOLVED:36`, `MIN_LOCKS:5` (:206);
  mutate expectations updated to `floor of 36` (:306, :314);
  `MIN_ASSERTIONS=34` (:452) equals the 34-arm asserted population
  (1 control + 1 must-pass + 3 floor greps + 12 anchor greps + 14 mutates +
  3 fixture arms).

### Suite runs — PASS

- `python3 scripts/assert-dependabot-drain.py` → exit 0, 36/36 rows OK,
  `next ['16.4.3'] >= 16.4.1 OK`, both discharged nested copies absent.
- `bash scripts/assert-dependabot-drain.test.sh` → exit 0,
  `34 passed, 0 failed, 34 assertion(s) executed (floor 34)`.

### Lockfile ↔ package.json — PASS

- `package.json` + lockfile `packages[""]` spec both `"next": "~16.4.1"`;
  `node_modules/next` resolves 16.4.3 (satisfies `~16.4.1`, ≥ 16.4.1 floor).
- `@next/env` + all 8 `@next/swc-*` optional deps at 16.4.3, consistent.
- No nested `node_modules/next/node_modules/{postcss,sharp}` — discharge
  ratchet intact; top-level sharp 0.35.5.

### Crash classifier vs settled rulings — PASS

- `isBenignClientAbort` (crash-handlers.ts:71-78) is exact-pair only
  (`message === "aborted"` && `code === "ECONNRESET"`); warnSilentFallback
  exists at observability.ts:287; ADR-062 carve-out (lines 114-135) matches
  code semantics and cites defense-in-depth + #11783 re-eval. Tests cover all
  near-misses (code-less aborted, wrong-message ECONNRESET, non-Error reason).
- Egress pin updated `/^16\.3\./` → `/^16\.4\./`, with re-measure note.

### Schema/migration surface — NONE

- No migrations, no RLS/grant/tenant-client writes in the diff. GDPR gate N/A.

## Findings

- **P3** — scripts/assert-dependabot-drain.test.sh:105-106: fixture comment
  says "`next` is not in WATCHED_PACKAGES, so the completeness sweep does not
  require a covering row" — now false (next IS watched; a covering row exists
  and the fixture entry is what lets it resolve toward MIN_RESOLVED). Harmless
  today, but the stated rationale is wrong and could mislead a future edit
  into dropping the fixture entry. Suggest updating the comment; not blocking.
