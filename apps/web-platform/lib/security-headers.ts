// Non-CSP security headers returned by next.config.ts headers().
// CSP is now generated per-request in middleware.ts with nonce-based policy.
export function buildSecurityHeaders() {
  return [
    { key: "X-Frame-Options", value: "DENY" },
    { key: "X-Content-Type-Options", value: "nosniff" },
    {
      key: "Strict-Transport-Security",
      // Cloudflare's HSTS SSL/TLS setting overrides this header in production
      // and enforces max-age=31536000 (1 year). The source value is set to
      // match so /preflight checks see a consistent value. The HSTS Preload
      // List minimum is 31536000, so compliance is maintained.
      value: "max-age=31536000; includeSubDomains; preload",
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
