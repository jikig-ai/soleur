# Security Review — PR #11780 (feat-one-shot-11772-next-dev-server-crash)

**Reviewer:** soleur:engineering:review:security-sentinel (report-only)
**Diff base:** `origin/main...HEAD` (fetched fresh)
**Scope:** `crash-handlers.ts` benign-abort classifier, `next ~16.3.8 → ~16.4.1` (resolves 16.4.3), dependabot-drain guard rows, version pin test.

## Verdict: APPROVE — ship. 0×P1, 0×P2, 3×P3.

The DoS trade-off direction is correct: this PR **removes** an unauthenticated
one-request restart-DoS (exact-pair abort → `captureException` → `close(2s)` →
`exit(1)` → supervisor restart) and replaces it with a warn-level mirror and
continued serving. The residual cost is bounded, visible signal volume rather
than process churn.

## Masked-fatal producer census (the core risk)

The predicate `err instanceof Error && err.message === "aborted" && err.code === "ECONNRESET"`
(`server/crash-handlers.ts:74-80`) can only be satisfied by the exact pair. Full
in-repo census of producers:

| Producer | Mints pair? | Evidence |
|---|---|---|
| `server/dsar-export.ts` | **No** — 48× `new Error("aborted")`, zero `.code` assignments | `grep -c 'new Error("aborted")'` = 48; sites at e.g. :466, :480, :2245 (`abort(new Error("job_timeout"))` — different message, no code) |
| `server/dsar-export-co-uploader.ts` | **No** — 4× `new Error("aborted")`, code-less | :32, :48, :63, :87 |
| `server/dsar-export-allowlist.ts` | No — no throwers | grep clean |
| `.code = "ECONNRESET"` writers | **None exist in-repo** — all `ECONNRESET` hits are *readers* | `compound-promote-create-arm.ts:194` (CAUSE_CODES set), `github-retry.ts:31` (retryable-code list) — classification, never assignment |
| `AbortController.abort(reason)` call sites | **No** — all reasons are `SessionAbortError(kind)` or literals | `agent-session-registry.ts:276,287,299,432,455,554`, `agent-runner.ts:1252`, `dsar-export.ts:2245`, `cc-dispatcher.ts:1752,3079`; `classifyAbortReason` reads but does not rethrow the pair |
| `reject(signal.reason)` | Reason is `SessionAbortError`/literal; even if it were the pair, it *is* a client abort — correct class | `review-gate.ts:140,154` |
| `middleware.ts:83` | Reads `e.hint.includes("aborted")` only | n/a |
| Test fixtures | Test-only | `test/helpers/fake-github-trees.ts:224,253` |
| Node `connResetException("aborted")` | **Yes — the intended producer**, inbound request-abort shape | the target of vercel/next.js#49587 comment |

**Residual theoretical path:** Node's `connResetException` can also mint the
pair on *outbound* `http.request` aborts (not fetch/undici — undici uses
`UND_ERR_*` codes and "Request aborted"/"The operation was aborted" messages,
which fail the exact match). No `http.request`/`https.request` call sites exist
in `server/`/`lib/` (only `createServer`, `IncomingMessage` types). Even if one
landed, a socket-level abort reaching the process handler is still not
undefined-state corruption — warn-and-continue remains the right class. No
fatal path can mint the pair.

**Predicate-ordering note:** classification runs before `reportFatalAndExit`'s
`handling` guard, so a benign abort arriving *during* an in-flight fatal flush
is correctly downgraded rather than force-exiting — defensible and consistent
with the comment's intent.

## err-object handling in the warn path

- `warnSilentFallback` → `redactErrorForEmit` (`server/observability.ts:291-316`)
  → `redactError` copies via `Object.create(getPrototypeOf(err))` with own data
  properties, so `.code` survives to Sentry — the `ECONNRESET` tag fidelity is
  preserved. Redaction failure degrades to a placeholder `Error`, never throws.
- `Sentry.captureException` call is `typeof`-guarded + try/catch — safe in the
  partially-shimmed dev bundle (where this fires most).
- `logger.warn` is unwrapped — same exposure shape as `reportSilentFallback`;
  err is a guaranteed `Error` here, so pino serialization is safe.
- No PII surface: message is the constant `"aborted"`, code `"ECONNRESET"`;
  nothing request-derived reaches the sinks.

## Lockfile supply-chain shape — clean

- 30 changed `(version|resolved|integrity)` triplets, all confined to
  `node_modules/next`, `node_modules/@next/env`, and the eight `@next/swc-*`
  platform packages, plus `sharp` range `^0.35.4 → ^0.35.5` inside next's own
  `optionalDependencies` (transitive).
- Every `resolved` URL is `registry.npmjs.org` — no git deps, no tarball URLs,
  no alternate registries introduced.
- Every entry carries `sha512` integrity; none stripped.
- `assert-dependabot-drain.py` re-adds `("web-platform", "next", 16, "16.4.1")`
  to REQUIRED + FLOOR_ANCHORS + WATCHED_PACKAGES, bumps MIN_ROWS/MIN_RESOLVED
  35→36, and the test shell pins all three numbers plus a `next:16:16.4.1`
  anchor — the guard cannot be silently weakened by this PR itself.

## Settled rulings — confirmed, no contradictions

Exact-pair scope ✓ · prod-wide (single `installCrashHandlers` at
`server/index.ts:83`, dev+prod same module) ✓ · warnSilentFallback choice ✓ ·
defense-in-depth (near-miss tests keep code-less `aborted` and mismatched-code
fatals on the exit path) ✓.

## Findings

- **[P3/info] Unbounded warn-path cardinality.** Each aborted request = 1 pino
  warn + 1 Sentry `warning`-level `captureException`, unauthenticated-triggerable
  at request rate. Strictly better than restart-DoS, but a flood burns Sentry
  quota/log volume. `mirrorWarnWithDebounce` (`observability.ts:588`) exists for
  bursty paths if volume ever warrants it — not a blocker, the event is per-attack
  not per-healthy-request.
- **[P3/info] Spec/lock drift.** `package.json` `~16.4.1` resolves to **16.4.3**
  in the lockfile. `~` permits it and the drain-guard floor is 16.4.1, so both
  hold — noted only so the PR description's "~16.4.1" isn't read as the pinned
  bytes.
- **[P3/info] Getter-safety in predicate.** `err.message`/`.code` reads happen
  inside the process handler; an Error subclass with a throwing getter would
  throw inside the handler itself. Node-minted errors carry own data props, so
  this is exotic-paranoid — a `try` around `isBenignClientAbort` would close it
  at near-zero cost. Not a blocker.

## Other diff surface

- `test/crash-handlers.test.ts` — 6 new tests pin both handlers and the three
  near-miss classes. Good.
- `test/egress-audit-ingest.test.ts` — version pin `^16\.3\.` → `^16\.4\.` keeps
  the header-injection re-measure sentinel aligned.
- KB/plan docs — `plan.md`, `tasks.md`, `decision-challenges.md`,
  `session-state.md`, ADR-101 doc: no secrets, no actionable code claims beyond
  the mechanism described above.
