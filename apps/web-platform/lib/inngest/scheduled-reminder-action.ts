// Shared validation for the generic scheduled-reminder primitive
// (event-scheduled-reminder.ts + app/api/internal/schedule-reminder/route.ts).
//
// Lives in lib/ (NOT the route file) per cq-nextjs-route-files-http-only-exports
// AND so the SAME allowlist runs at BOTH the emit endpoint (pre-send 400) and the
// Inngest handler (post-receive guard) — defense-in-depth. Carries NO octokit /
// server-only import, so the Next.js route can import it freely. The server-only
// CHECK_REGISTRY membership check lives in the handler, not here (see the handler
// header for the intentional route↔handler asymmetry).

// Discriminated union, ALLOWLISTED. Any other `type` is rejected. issue-comment
// only posts a comment; named-check runs a registered check that may post a
// comment AND (v1.1) close — but ONLY the action's own report_to_issue, via the
// boolean `close` on the check result (an arbitrary-issue close is structurally
// unrepresentable; see the handler's close-PATCH and ADR-063).
export type ReminderAction =
  | { type: "issue-comment"; issue: number; body: string }
  | {
      type: "named-check";
      check: string;
      params?: Record<string, unknown>;
      report_to_issue: number;
    };

// GitHub's hard comment-body limit is 65536 chars; cap below it with headroom.
export const MAX_COMMENT_BODY = 65000;

export interface ReminderEventData {
  reminder_id: string;
  fire_at: string; // ISO instant; validated as a real date
  actor: "platform";
  action: ReminderAction;
}

export type ValidateResult =
  | { ok: true; action: ReminderAction }
  | { ok: false; reason: string };

function isPositiveInt(n: unknown): n is number {
  return typeof n === "number" && Number.isInteger(n) && n > 0;
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/**
 * Validate a raw `action` payload against the allowlist. Used by the endpoint
 * (pre-send) and the handler (post-receive). Returns the narrowed action on
 * success or a stable `reason` string on rejection. The `reason` values double
 * as the handler's `{ ok:false, reason }` discriminators + Sentry `op` tags.
 */
export function validateReminderAction(raw: unknown): ValidateResult {
  if (!isPlainObject(raw)) {
    return { ok: false, reason: "action-not-allowlisted" };
  }
  switch (raw.type) {
    case "issue-comment": {
      if (!isPositiveInt(raw.issue)) {
        return { ok: false, reason: "invalid-issue-comment" };
      }
      if (typeof raw.body !== "string" || raw.body.length === 0) {
        return { ok: false, reason: "invalid-issue-comment" };
      }
      if (raw.body.length > MAX_COMMENT_BODY) {
        return { ok: false, reason: "invalid-issue-comment" };
      }
      return {
        ok: true,
        action: { type: "issue-comment", issue: raw.issue, body: raw.body },
      };
    }
    case "named-check": {
      if (typeof raw.check !== "string" || raw.check.length === 0) {
        return { ok: false, reason: "invalid-named-check" };
      }
      if (!isPositiveInt(raw.report_to_issue)) {
        return { ok: false, reason: "invalid-named-check" };
      }
      if (raw.params !== undefined && !isPlainObject(raw.params)) {
        return { ok: false, reason: "invalid-named-check" };
      }
      return {
        ok: true,
        action: {
          type: "named-check",
          check: raw.check,
          report_to_issue: raw.report_to_issue,
          ...(raw.params !== undefined ? { params: raw.params } : {}),
        },
      };
    }
    default:
      // Any non-allowlisted action.type (including missing) is rejected.
      return { ok: false, reason: "action-not-allowlisted" };
  }
}

/** True iff `s` parses as a real ISO date/instant (rejects "not-a-date"). */
export function isValidIsoInstant(s: unknown): s is string {
  return typeof s === "string" && s.length > 0 && !Number.isNaN(Date.parse(s));
}
