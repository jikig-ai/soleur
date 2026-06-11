// Model-output JSON extraction (leaf module — no transitive import weight, so
// light consumers like domain-router can use it without dragging in the
// octokit/github-app chain that _cron-shared carries).
//
// Models routinely wrap JSON output in markdown fences (```json ... ```)
// even when prompted "respond with ONLY JSON" — reproduced live against
// claude-sonnet-4-6 on 2026-06-11 (#5080 first prod fire silently fell back
// to the deterministic renderer because JSON.parse threw on the fence).
// Strips ONE outer fence (any language tag, any case); unfenced text passes
// through untouched. EVERY consumer that JSON.parses Messages-API response
// text must route through this: cron-weekly-release-digest,
// cron-compound-promote, domain-router.
export function extractModelJson(text: string): string {
  const fenced = text.match(/^\s*```[a-zA-Z]*\s*\n?([\s\S]*?)\s*```\s*$/);
  return (fenced ? fenced[1] : text).trim();
}
