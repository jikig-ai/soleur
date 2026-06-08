// feat-debug-mode-stream — the debug stream's OWN redaction-fallthrough probe.
//
// WHY a separate probe (P0-5): the shared `REDACTION_FALLTHROUGH_PROBES` in
// `cc-dispatcher.ts` covers only FOUR of the ~8 `[redacted-*]` kinds the
// `redaction-allowlist.ts` redactor produces (it was scoped to the
// command_stream threat model). The debug stream's DROP-first design depends
// on the probe TRIPPING whenever a secret survives redaction — so the probe
// MUST be a SUPERSET of every shape the redactor recognizes, or a surviving
// `sk-ant-`/Stripe/AWS/JWT/generic-ENV secret would silently ride the wire.
//
// We deliberately do NOT widen the shared `REDACTION_FALLTHROUGH_PROBES`
// (blast radius to command_stream + message-bubble — HIGH-B): command_stream
// keeps its narrow shared probe; the debug stream owns this superset.
//
// Each probe matches the RAW (pre-redaction) shape. We run them over the
// ALREADY-redacted output: a match means the redactor MISSED that shape, so
// `buildDebugEvent` DROPs the frame's body (fail-closed). Because the redactor
// replaces every recognized shape with a `[redacted-<kind>]` marker that none
// of these patterns match, a probe trip is an unambiguous redaction miss.
//
// Synthesized patterns only — these are SHAPES, never literal secret values.

export interface DebugRedactionProbe {
  /**
   * The `[redacted-<kind>]` marker this probe guards. The AC4b coverage test
   * enumerates every `[redacted-*]` literal the redactor emits and asserts
   * each kind appears here — so the superset can never silently fall behind a
   * future redactor shape.
   */
  redactedKind: string;
  /** RAW secret shape. `.test()` over redacted output → redaction miss. */
  probe: RegExp;
}

// NB: every RegExp is NON-global. A `/g` flag makes `.test()` stateful
// (advancing `lastIndex` across calls) — a correctness hazard for a reused
// module-level array. These mirror the `redaction-allowlist.ts` source REs
// with the `/g` dropped.
export const DEBUG_REDACTION_PROBES: DebugRedactionProbe[] = [
  // ---- [redacted-key]: API-key sentinels + AWS/ENV credential assignments --
  { redactedKind: "[redacted-key]", probe: /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_-]{20,}/ },
  { redactedKind: "[redacted-key]", probe: /\bgithub_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59,}/ },
  { redactedKind: "[redacted-key]", probe: /\b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}/ },
  { redactedKind: "[redacted-key]", probe: /\bsk-ant-[A-Za-z0-9_-]{20,}/ },
  { redactedKind: "[redacted-key]", probe: /\bsk-[A-Za-z0-9]{32,}/ },
  { redactedKind: "[redacted-key]", probe: /\bAKIA[0-9A-Z]{16}/ },
  { redactedKind: "[redacted-key]", probe: /\bxox[abprs]-[0-9]+-[0-9]+-[A-Za-z0-9-]+/ },
  {
    redactedKind: "[redacted-key]",
    probe: /\baws[_-]?secret[_-]?access[_-]?key\s*[:=]\s*['"]?[A-Za-z0-9/+=]{40}/i,
  },
  {
    redactedKind: "[redacted-key]",
    probe: /\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*_(?:TOKEN|KEY|SECRET|PASSWORD|PAT)\s*=\s*['"]?[^\s'"]+/,
  },
  // ---- [redacted-token]: HTTP Authorization header literal ------------------
  {
    redactedKind: "[redacted-token]",
    probe: /\bAuthorization\s*:\s*(?:Bearer|Basic|token)\s+\S/i,
  },
  // ---- [redacted-jwt]: header.payload.sig -----------------------------------
  {
    redactedKind: "[redacted-jwt]",
    probe: /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/,
  },
  // ---- [redacted-password]: connection-string userinfo ----------------------
  {
    redactedKind: "[redacted-password]",
    probe: /\b[a-z][a-z0-9+.\-]*:\/\/[^:@\s/]+:[^@\s/\]]+@/i,
  },
  // ---- [redacted-email] -----------------------------------------------------
  {
    redactedKind: "[redacted-email]",
    probe: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,24}\b/,
  },
  // ---- [redacted-uuid] ------------------------------------------------------
  {
    redactedKind: "[redacted-uuid]",
    probe: /\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b/,
  },
  // ---- [redacted-phone] -----------------------------------------------------
  {
    redactedKind: "[redacted-phone]",
    probe: /(?<![\d])\+?\d{1,3}[-.\s]?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}(?![\d])/,
  },
  // ---- [redacted-ip]: IPv4 + IPv6 -------------------------------------------
  {
    redactedKind: "[redacted-ip]",
    probe: /\b(?:25[0-5]|2[0-4]\d|[01]?\d{1,2})(?:\.(?:25[0-5]|2[0-4]\d|[01]?\d{1,2})){3}\b/,
  },
  {
    redactedKind: "[redacted-ip]",
    probe: /\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b/,
  },
];

/**
 * True if ANY probe matches `redacted` — i.e. a recognized secret shape
 * SURVIVED redaction. Callers DROP the frame's body on a trip (fail-closed).
 */
export function debugRedactionProbeTrips(redacted: string): boolean {
  return DEBUG_REDACTION_PROBES.some(({ probe }) => probe.test(redacted));
}
