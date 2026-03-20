// Non-CSP security headers returned by next.config.ts headers().
// CSP is now generated per-request in middleware.ts with nonce-based policy.
export function buildSecurityHeaders() {
  return [
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
