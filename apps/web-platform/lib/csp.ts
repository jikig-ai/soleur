function parseSupabaseHost(url: string): string {
  if (!url) return "";
  try {
    return new URL(url).host;
  } catch {
    return "";
  }
}

export function buildCspHeader(options: {
  nonce: string;
  isDev: boolean;
  supabaseUrl: string;
  appHost: string;
  sentryReportUri?: string;
}): string {
  const { nonce, isDev, supabaseUrl, appHost, sentryReportUri } = options;
  const supabaseHost = parseSupabaseHost(supabaseUrl);

  // In production, require an explicit Supabase URL to avoid a permissive
  // wildcard in connect-src. Fall back to *.supabase.co only in development.
  if (!supabaseHost && !isDev) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_URL must be set in production builds",
    );
  }

  const supabaseConnect = supabaseHost
    ? `https://${supabaseHost} wss://${supabaseHost}`
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
    "worker-src 'self' blob:",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "upgrade-insecure-requests",
    ...(sentryReportUri ? [`report-uri ${sentryReportUri}`] : []),
  ];

  return directives.join("; ");
}
