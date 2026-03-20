function parseSupabaseHost(url: string): string {
  if (!url) return "";
  try {
    return new URL(url).host;
  } catch {
    return "";
  }
}

export function buildSecurityHeaders(options: {
  isDev: boolean;
  supabaseUrl: string;
}) {
  const { isDev, supabaseUrl } = options;
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

  const cspDirectives = [
    "default-src 'self'",
    `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}`,
    // unsafe-inline required for Tailwind/Next.js inline style injection
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

  return [
    { key: "Content-Security-Policy", value: cspDirectives.join("; ") },
    { key: "X-Frame-Options", value: "DENY" },
    { key: "X-Content-Type-Options", value: "nosniff" },
    {
      key: "Strict-Transport-Security",
      value: "max-age=63072000; includeSubDomains; preload",
    },
    { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
    {
      key: "Permissions-Policy",
      value: "camera=(), microphone=(), geolocation=(), browsing-topics=()",
    },
    { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
    { key: "Cross-Origin-Resource-Policy", value: "same-origin" },
    { key: "X-DNS-Prefetch-Control", value: "on" },
    // Explicitly disable the legacy XSS filter -- OWASP recommends 0 (not
    // omission) because the filter itself can introduce vulnerabilities.
    { key: "X-XSS-Protection", value: "0" },
  ];
}
