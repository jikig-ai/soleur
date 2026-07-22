// Structured, WARN-level, fail-open GitHub Pages cert-reissue step marker (#6698).
//
// WHY THIS EXISTS: `cron-gh-pages-cert-reissue` was observationally dark on its
// SUCCESS path. Two independent gates stacked, and both had to be avoided:
//
//   H-T1 — the injected Inngest ctx `logger` is gated off. `server/inngest/
//   client.ts` constructs `new Inngest({...})` with no `logger` option, so
//   inngest@3.54.2 falls back to `DefaultLogger` wrapped in `ProxyLogger`.
//   `ProxyLogger.info()` begins `if (!this.enabled) return;` and `enabled` flips
//   true only in `beforeExecution()`. Inngest re-runs the function body from the
//   top on every HTTP request and memoizes completed steps, so a `logger.info`
//   on a memoization/discovery pass is silently swallowed.
//
//   H-T2 — Vector drops pino INFO. `[transforms.app_container_warn_filter]`
//   keeps `level_int >= 40` only, so any pino `info` line never leaves the host.
//
// This module avoids BOTH: it is a module-scope pino instance (never the ctx
// logger) emitting at WARN (level 40). That exactly explains the reported
// asymmetry — the failure path shipped rows because `reportSilentFallback`
// mirrors through module-scope pino at ERROR, while the success path used the
// ctx logger and vanished.
//
// Observability layer (hr-observability-layer-citation) — the full chain a
// marker traverses:
//   pino (level >= 40) → container stdout → Docker `--log-driver journald`
//   → host journal `CONTAINER_NAME=soleur-web-platform` → Vector
//   `[sources.app_container_journald]` → `[transforms.app_container_warn_filter]`
//   → the `pii_scrub_*` transforms → `[transforms.tag_journald]`
//   → `[sinks.betterstack]` → Better Stack source `soleur-inngest-vector-prd`
//   → read back via `scripts/betterstack-query.sh`.
// Source 3 keys on `CONTAINER_NAME`, NOT the `SYSLOG_IDENTIFIER` allowlist, so
// no `vector.toml` change is required for this marker to ship.
//
// Mirrors `claude-cost-marker.ts` (ADR-108). The silent `catch` below is the
// sanctioned observability-of-observability exemption to
// `cq-silent-fallback-must-mirror-to-sentry`: a logging failure must NEVER red a
// cron, and mirroring it to Sentry would re-enter the same broken path.
import pino from "pino";

// Dedicated instance — NO `hooks.logMethod`. `logger.ts` installs a hook that
// mirrors every WARN+ line into a Sentry breadcrumb; this routine emits ~15
// per-poll-tick WARNs per fire, which would evict genuine diagnostics from the
// shared-scope ring buffer. Level WARN is still required so the Vector filter
// ships it.
//
// ‼️ BOUNDARY: this instance has NO `formatters.log` renameUserIdToHash
// (ADR-029 PII pseudonymization) and NO `redact` paths — both are
// shared-logger-only. The marker interface below MUST therefore stay free of any
// user id, email, secret, or other regulated field. It carries ONLY infrastructure
// facts: phase, cert state, record counts, resolver answers, booleans, durations.
// Adding a user-scoped field here would silently bypass ADR-029 + redaction.
const log = pino({ base: { component: "cert-reissue" } });

/**
 * Every step the routine can emit from. The union is the enforcement surface:
 * AC4 drives the orchestration with fakes and compares the OBSERVED phase set
 * against `CERT_REISSUE_PHASES`, so a new step without a marker fails the test.
 *
 * `pre-flip-dns` is load-bearing: without a marker of the DNS state BEFORE the
 * flip, propagation-delay is indistinguishable from never-propagated.
 *
 * `onfailure-restore` is load-bearing because `cronGhPagesCertReissueOnFailure`
 * is NOT part of `runReissueSteps`. Without it, a body throw reproduces the exact
 * asymmetry this module exists to fix: Sentry-visible but marker-dark, and
 * indistinguishable from "telemetry broken".
 */
export const CERT_REISSUE_PHASES = [
  "preflight",
  "pre-flip-dns",
  "flip-dns-only",
  "cname-put-null",
  "cname-put-set",
  "dns-propagation",
  "poll",
  "restore",
  "terminal",
  "onfailure-restore",
] as const;

export type CertReissuePhase = (typeof CERT_REISSUE_PHASES)[number];

/**
 * ‼️ FIELD-NAME CONSTRAINT (enforced by AC7, not merely documented).
 *
 * `[transforms.pii_scrub_drop_userdata]` (`infra/vector.toml`) DELETES these
 * eight top-level keys from every parsed log object:
 *
 *     body, content, message, userMessage, prompt, chat_message,
 *     userInput, user_input
 *
 * A marker field with any of those names is silently dropped BEFORE reaching
 * Better Stack — it would look wired in code and be permanently dark in
 * practice. Hence `detail` (not `message`) and `errorDetail` (not
 * `errorMessage`... which is fine, but kept symmetric). pino's own message key
 * is `msg`, which is NOT in the dropped set.
 */
export interface CertReissueMarker {
  phase: CertReissuePhase;

  // --- correlation (Phase 1.3) ---
  // `runId` is REQUIRED for attribution: a `--since 30m` Better Stack window is
  // satisfied by rows from any earlier fire, so without it rows cannot be tied
  // to THIS fire. Threaded from HandlerArgs, never self-derived.
  runId: string | null;
  // Inngest's zero-indexed retry attempt. Threaded, never hardcoded — a constant
  // would satisfy a type-level assertion while carrying no information.
  attempt: number | null;
  // On EVERY marker, not just the terminal one, so a row read out of context can
  // never be misread as a remediation fire.
  probeOnly: boolean;
  // Poll / gate loop index where applicable.
  pollIndex?: number | null;

  // --- cert observations (Phase 1.6 / RI-7) ---
  // The ENTIRE https_certificate object is captured because `certDescription` is
  // the only in-band field that has ever carried Let's Encrypt-side detail, and
  // an advancing-vs-flat state trajectory is the only other available signal for
  // separating H-W2 (window too short) from H-W3 (LE rate limiting).
  certState?: string | null;
  certDescription?: string | null;
  certDomains?: string[] | null;
  certExpiresAt?: string | null;
  protectedDomainState?: string | null;
  pendingDomainUnverifiedAt?: string | null;
  cname?: string | null;

  // --- DNS observations ---
  recordCount?: number | null;
  proxiedCount?: number | null;
  // Public-resolver answers (1.1.1.1 / 8.8.8.8), NOT the container's resolver.
  resolved4?: string[] | null;
  resolved6?: string[] | null;
  // `ENODATA` here is the PASS condition — Let's Encrypt prefers AAAA with
  // almost no IPv4 fallback, so a surviving proxied AAAA defeats validation at
  // any window length (H-W4 / RI-1).
  resolve6Error?: string | null;
  resolve4Error?: string | null;
  acmeApexStatus?: number | null;
  acmeWwwStatus?: number | null;
  // Raw `Server` headers — the evidence behind the GitHub-shaped verdict, so a
  // failed gate says WHAT answered rather than only that it was wrong.
  acmeApexServer?: string | null;
  acmeWwwServer?: string | null;

  // --- outcome ---
  outcome?: string | null;
  detail?: string | null;
  elapsedMs?: number | null;
  ok?: boolean | null;
  errorName?: string | null;
  errorDetail?: string | null;
}

/**
 * Emit one `SOLEUR_CERT_REISSUE` WARN marker. NEVER throws — observability must
 * never break a remediation run (fail-open contract).
 */
export function emitCertReissueMarker(m: CertReissueMarker): void {
  try {
    log.warn({ SOLEUR_CERT_REISSUE: true, ...m }, "cert reissue");
  } catch {
    // fail-open: a marker-emit failure must never propagate into the caller.
  }
}
