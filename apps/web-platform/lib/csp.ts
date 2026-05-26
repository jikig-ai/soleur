function parseSupabaseHost(url: string): string {
  if (!url) return "";
  try {
    return new URL(url).host;
  } catch {
    return "";
  }
}

// Derives `http`/`https` from the URL itself so e2e mock servers using
// `http://localhost:<port>` are not silently CSP-blocked. In production,
// `NEXT_PUBLIC_SUPABASE_URL` is always `https://` (see verify-required-secrets.sh
// canonical-shape assertion), so this is a no-op there.
function parseSupabaseScheme(url: string): "http" | "https" {
  if (!url) return "https";
  try {
    return new URL(url).protocol === "http:" ? "http" : "https";
  } catch {
    return "https";
  }
}

// Whitelist of origins that may be added to `form-action` via the
// `formActionExtra` option. The committed manifest-POST flow
// (`/internal/github-app-init`) requires `https://github.com` so the
// operator can submit the manifest to GitHub's App-create form. Adding
// other origins requires a whitelist update + reviewer scrutiny — every
// extra origin widens the cross-origin form-POST surface and undoes the
// default-deny posture of `form-action 'self'`.
const FORM_ACTION_ALLOWLIST = new Set(["https://github.com"]);

function buildFormAction(extras: string[] | undefined): string {
  if (!extras || extras.length === 0) return "form-action 'self'";
  const uniq = Array.from(new Set(extras));
  for (const origin of uniq) {
    if (!FORM_ACTION_ALLOWLIST.has(origin)) {
      throw new Error(
        `form-action override '${origin}' is not in the allowlist. ` +
          `Add to FORM_ACTION_ALLOWLIST in apps/web-platform/lib/csp.ts ` +
          `with a code-comment rationale before using.`,
      );
    }
  }
  return `form-action 'self' ${uniq.join(" ")}`;
}

export function buildCspHeader(options: {
  nonce: string;
  isDev: boolean;
  supabaseUrl: string;
  appHost: string;
  sentryReportUri?: string;
  // Per-route additions to `form-action`. Each entry must be in
  // FORM_ACTION_ALLOWLIST; unknown entries throw at build time so a typo
  // or attacker-controlled value cannot silently widen CSP.
  formActionExtra?: string[];
}): string {
  const { nonce, isDev, supabaseUrl, appHost, sentryReportUri, formActionExtra } = options;
  const supabaseHost = parseSupabaseHost(supabaseUrl);
  const supabaseScheme = parseSupabaseScheme(supabaseUrl);
  const supabaseWsScheme = supabaseScheme === "http" ? "ws" : "wss";

  // In production, require an explicit Supabase URL to avoid a permissive
  // wildcard in connect-src. Fall back to *.supabase.co only in development.
  if (!supabaseHost && !isDev) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_URL must be set in production builds",
    );
  }

  const supabaseConnect = supabaseHost
    ? `${supabaseScheme}://${supabaseHost} ${supabaseWsScheme}://${supabaseHost}`
    : "https://*.supabase.co wss://*.supabase.co";

  // CSP 'self' does not resolve to wss:// in all browsers (MDN compat note).
  // Use ws:// in dev (HTTP) and wss:// in prod (HTTPS).
  const appWsOrigin = isDev ? `ws://${appHost}` : `wss://${appHost}`;

  // Three-tier backward-compatible script-src (MDN + Next.js with-strict-csp):
  // CSP3: 'strict-dynamic' ignores 'unsafe-inline', 'self', https: — only nonce matters
  // CSP2: 'strict-dynamic' ignored, nonce still works, https: provides allowlisting
  // CSP1: Only 'unsafe-inline' and https: apply (no regression from current behavior)
  const scriptSrc = [
    "'self'",
    "'unsafe-inline'",
    "https:",
    `'nonce-${nonce}'`,
    "'strict-dynamic'",
    ...(isDev ? ["'unsafe-eval'"] : []),
  ].join(" ");

  const directives = [
    "default-src 'self'",
    `script-src ${scriptSrc}`,
    // unsafe-inline required for Next.js inline style injection
    "style-src 'self' 'unsafe-inline'",
    `img-src 'self' blob: data: ${supabaseConnect.split(" ")[0]}`,
    "font-src 'self'",
    `connect-src 'self' ${appWsOrigin} ${supabaseConnect} https://*.ingest.sentry.io https://*.ingest.de.sentry.io https://fcm.googleapis.com https://updates.push.services.mozilla.com https://*.push.apple.com`,
    "object-src 'none'",
    "frame-src 'none'",
    "worker-src 'self' blob:", // blob: required by pdfjs-dist Web Worker (react-pdf)
    "base-uri 'self'",
    buildFormAction(formActionExtra),
    "frame-ancestors 'none'",
    "upgrade-insecure-requests",
    ...(sentryReportUri ? [`report-uri ${sentryReportUri}`] : []),
  ];

  return directives.join("; ");
}
