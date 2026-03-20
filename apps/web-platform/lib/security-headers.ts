interface SecurityHeader {
  key: string;
  value: string;
}

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
}): SecurityHeader[] {
  const { isDev, supabaseUrl } = options;
  const supabaseHost = parseSupabaseHost(supabaseUrl);

  const supabaseConnect = supabaseHost
    ? `https://${supabaseHost} wss://${supabaseHost}`
    : "https://*.supabase.co wss://*.supabase.co";

  const cspDirectives = [
    "default-src 'self'",
    `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' blob: data:",
    "font-src 'self'",
    `connect-src 'self' ${supabaseConnect}`,
    "object-src 'none'",
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
    { key: "X-DNS-Prefetch-Control", value: "on" },
    { key: "X-XSS-Protection", value: "0" },
  ];
}
