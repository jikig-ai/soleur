/**
 * Health-check endpoint — returns 200 OK.
 */
export async function GET() {
  const upstream = await fetch("https://api.example.com/healthz");
  return new Response(JSON.stringify({ ok: true, upstream: upstream.status }), {
    headers: { "content-type": "application/json" },
    status: 200,
  });
}
