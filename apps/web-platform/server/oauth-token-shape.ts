// Shape predicates for the operator's stored subscription ("oauth") token (#11086). One module serves both boundaries that
// touch the `anthropic_oauth` row: the write boundary (app/api/keys/route.ts, strict allowlist) and the lease boundary
// (byok-lease.ts, a NEGATIVE predicate over classes the bundled CLI was measured to drop).
//
// Why this exists: the bundled Claude CLI silently drops a subscription-token value that is not shaped like a real one and
// then replies "Not logged in · Please run /login" (it does not send the dropped value as a credential; only a blank value is
// answered with no inference request at all), so a stored API key or a wrapped copy of the token produced a total outage
// with a message pointing at nothing. The measured table lives in
// test/agent-auth-cli-contract.test.ts and in the plan's Research Insights; RE-DERIVE ON EVERY SDK BUMP.
//
// Safety: nothing here returns, logs or throws a part of the value. The classifier returns a member of a closed list.
// This module must not name the CLI's credential environment variable (test/oauth-token-injection-site.test.ts pins who may).

/** What `claude setup-token` prints: `sk-ant-oat` + two digits + `-` + a non-empty URL-safe tail. */
const SUBSCRIPTION_TOKEN_ALLOWLIST = /^sk-ant-oat\d{2}-[A-Za-z0-9_-]+$/;

/** The closed set of reasons the lease refuses a stored value. Telemetry carries only one of these. */
export type CliDroppedClass = "api_key_shaped" | "embedded_whitespace" | "blank";

/** Write-boundary check: does the (trimmed) value have the shape a real subscription token has? */
export function isAcceptableSubscriptionToken(value: string): boolean {
  return SUBSCRIPTION_TOKEN_ALLOWLIST.test(value.trim());
}

/**
 * Lease-boundary check: is the (trimmed) value of a class the bundled CLI was MEASURED to drop? Negative on purpose: it
 * claims only the measured classes so a future valid token shape already stored is never locked out. An embedded newline is
 * deliberately not claimed (the CLI uses that value and fails loudly, which the friendly rewrite already covers). Shapes
 * such as `sk-proj-` or a dash-less `sk-ant-oat` are caught only by the strict write-time allowlist.
 */
export function classifyCliDroppedValue(value: string): CliDroppedClass | null {
  const t = value.trim();
  if (t === "") return "blank";
  if (/^sk-ant-(?:api|admin)/.test(t)) return "api_key_shaped";
  if (t.startsWith("sk-") && /[ \t]/.test(t)) return "embedded_whitespace";
  return null;
}
