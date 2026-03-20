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
}): string {
  const { nonce, isDev, supabaseUrl } = options;
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
    "img-src 'self' blob: data:",
    "font-src 'self'",
    `connect-src 'self' ${supabaseConnect}`,
    "object-src 'none'",
    "frame-src 'none'",
    "worker-src 'self'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "upgrade-insecure-requests",
  ];

  return directives.join("; ");
}
