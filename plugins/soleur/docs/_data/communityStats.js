import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// Derive the Discord invite code from site.discord so the two references to
// the same public URL (landing page link + build-time stats fetch) stay in
// sync. When the invite rotates in site.json, the stats fetch follows.
const __dirname = dirname(fileURLToPath(import.meta.url));
const site = JSON.parse(readFileSync(join(__dirname, "site.json"), "utf8"));
const DISCORD_INVITE_CODE = site.discord?.split("/").pop() ?? "";
const DISCORD_INVITE_API = `https://discord.com/api/v9/invites/${DISCORD_INVITE_CODE}?with_counts=true&with_expiration=true`;

// Build-time fetch timeout — a hung Discord endpoint otherwise stalls the
// full Eleventy build. Manual AbortController per cq-abort-signal-timeout-vs-fake-timers.
const FETCH_TIMEOUT_MS = 5000;

let cached;

export default async function () {
  if (cached) return cached;

  let discord = null;
  if (DISCORD_INVITE_CODE) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    try {
      const res = await fetch(DISCORD_INVITE_API, { signal: controller.signal });
      if (res.ok) {
        const body = await res.json();
        discord = {
          members: body.approximate_member_count ?? null,
          online: body.approximate_presence_count ?? null,
        };
      }
    } catch (err) {
      // Soft dep: Discord uptime is not part of Soleur's CI contract, so fall
      // through to `discord: null` and let the template hide the row. Do NOT
      // mirror the GitHub fail-fast branch — the plan's CI asymmetry is
      // intentional.
      console.warn(
        `[communityStats.js] Discord invite API failed, continuing without Discord stats: ${err.message}`,
      );
    } finally {
      clearTimeout(timer);
    }
  }

  cached = { discord };
  return cached;
}
