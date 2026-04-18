import githubStats from "./githubStats.js";

// Discord invite-with-counts endpoint — works on the public invite code and
// does not require server-side widget enablement. Returns approximate_member_count
// and approximate_presence_count. No auth required.
const DISCORD_INVITE_CODE = "PYZbPBKMUY";
const DISCORD_INVITE_API = `https://discord.com/api/v9/invites/${DISCORD_INVITE_CODE}?with_counts=true&with_expiration=true`;

let cached;

export default async function () {
  if (cached) return cached;

  const gh = await githubStats();

  let discord = null;
  try {
    const res = await fetch(DISCORD_INVITE_API);
    if (res.ok) {
      const body = await res.json();
      discord = {
        members: body.approximate_member_count ?? null,
        online: body.approximate_presence_count ?? null,
      };
    }
  } catch (err) {
    console.warn(
      `[communityStats.js] Discord invite API failed, continuing without Discord stats: ${err.message}`,
    );
  }

  cached = { ...gh, discord };
  return cached;
}
