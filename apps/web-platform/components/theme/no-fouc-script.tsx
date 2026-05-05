/**
 * No-FOUC theme bootstrap. Runs synchronously in <head> BEFORE the React
 * tree mounts so the first paint matches the user's persisted theme. Reads
 * localStorage["soleur:theme"] and sets <html data-theme=...>.
 *
 * Server-rendered as an inline <script>; Next.js 15 will attach the
 * per-request CSP nonce automatically because we render this from a Server
 * Component in app/layout.tsx with `await headers()` already called above.
 *
 * The script is intentionally tiny and dependency-free — anything heavy
 * here delays Time-To-First-Contentful-Paint.
 */
const SCRIPT = `(function () {
  try {
    var v = localStorage.getItem("soleur:theme");
    if (v !== "dark" && v !== "light" && v !== "system") {
      v = "system";
    }
    document.documentElement.dataset.theme = v;
  } catch (_e) {
    document.documentElement.dataset.theme = "system";
  }
})();`;

export function NoFoucScript({ nonce }: { nonce?: string }) {
  return (
    <script
      // CSP-nonce passthrough: the middleware sets a per-request nonce on
      // the Content-Security-Policy header. Without it, this inline script
      // would be blocked by the script-src 'nonce-...' directive and the
      // page would render with the default (dark) palette regardless of
      // the user's stored preference, defeating the no-FOUC guarantee.
      nonce={nonce}
      // Use dangerouslySetInnerHTML so React renders the script content
      // as-is without escaping. The content is a static string literal —
      // no user input flows into it.
      dangerouslySetInnerHTML={{ __html: SCRIPT }}
    />
  );
}
