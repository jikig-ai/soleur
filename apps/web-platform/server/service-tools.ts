// Pure functions for third-party service API interactions.
// Zero SDK dependencies — MCP tool handlers in agent-runner.ts delegate here.
// See learning: mcp-adapter-pure-function-extraction-testability-20260329.md

const PLAUSIBLE_BASE = "https://plausible.io";
const PLAUSIBLE_TIMEOUT_MS = 5_000;

// Restrict site_id/domain to safe characters (no path traversal).
// See learning: 2026-03-13-plausible-goals-api-provisioning-hardening.md
const SAFE_ID_RE = /^[a-zA-Z0-9._-]+$/;

export interface PlausibleResult {
  success: boolean;
  data?: unknown;
  error?: string;
}

function validateSiteId(siteId: string): string | null {
  if (!SAFE_ID_RE.test(siteId)) {
    return "Invalid site ID format";
  }
  return null;
}

async function plausibleFetch(
  apiKey: string,
  endpoint: string,
  options: RequestInit,
): Promise<PlausibleResult> {
  // HTTPS enforcement before transmitting bearer token.
  // See learning: 2026-03-13-plausible-goals-api-provisioning-hardening.md
  const url = `${PLAUSIBLE_BASE}${endpoint}`;
  if (!url.startsWith("https://")) {
    return { success: false, error: "HTTPS required for API calls" };
  }

  let res: Response;
  try {
    res = await fetch(url, {
      ...options,
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        ...options.headers,
      },
      signal: AbortSignal.timeout(PLAUSIBLE_TIMEOUT_MS),
    });
  } catch (err) {
    if (err instanceof DOMException && err.name === "TimeoutError") {
      return { success: false, error: "Request timeout (5s)" };
    }
    return { success: false, error: "Network error" };
  }

  // Validate JSON response body before parsing.
  // Plausible can return non-JSON (HTML/text) with 2xx status codes.
  // See learning: 2026-04-02-plausible-api-response-validation-prevention.md
  let body: unknown;
  try {
    body = await res.json();
  } catch {
    return { success: false, error: `Non-JSON response (HTTP ${res.status})` };
  }

  if (!res.ok) {
    return { success: false, error: `API error (HTTP ${res.status})` };
  }

  return { success: true, data: body };
}

export async function plausibleCreateSite(
  apiKey: string,
  domain: string,
  timezone = "UTC",
): Promise<PlausibleResult> {
  const idError = validateSiteId(domain);
  if (idError) return { success: false, error: `Invalid domain format` };

  return plausibleFetch(apiKey, "/api/v1/sites", {
    method: "POST",
    body: JSON.stringify({ domain, timezone }),
  });
}

export async function plausibleAddGoal(
  apiKey: string,
  siteId: string,
  goalType: "event" | "page",
  value: string,
): Promise<PlausibleResult> {
  const idError = validateSiteId(siteId);
  if (idError) return { success: false, error: "Invalid site ID format" };

  if (goalType !== "event" && goalType !== "page") {
    return { success: false, error: "goal_type must be 'event' or 'page'" };
  }

  // PUT with upsert semantics — safely idempotent (find-or-create).
  // See learning: 2026-03-13-plausible-goals-api-provisioning-hardening.md
  const body =
    goalType === "event"
      ? { site_id: siteId, goal_type: goalType, event_name: value }
      : { site_id: siteId, goal_type: goalType, page_path: value };

  return plausibleFetch(apiKey, "/api/v1/sites/goals", {
    method: "PUT",
    body: JSON.stringify(body),
  });
}

export async function plausibleGetStats(
  apiKey: string,
  siteId: string,
  period: "day" | "7d" | "30d" = "30d",
): Promise<PlausibleResult> {
  const idError = validateSiteId(siteId);
  if (idError) return { success: false, error: "Invalid site ID format" };

  const VALID_PERIODS = ["day", "7d", "30d"];
  if (!VALID_PERIODS.includes(period)) {
    return { success: false, error: "Invalid period (must be day, 7d, or 30d)" };
  }

  const params = new URLSearchParams({
    site_id: siteId,
    period,
    metrics: "visitors,pageviews,bounce_rate,visit_duration",
  });

  return plausibleFetch(apiKey, `/api/v1/stats/aggregate?${params}`, {
    method: "GET",
  });
}
