import MarkdownIt from "markdown-it";

const md = new MarkdownIt({ html: false });

const RELEASES_URL =
  "https://api.github.com/repos/jikig-ai/soleur/releases?per_page=30";

// Build-time fetch timeout — a hung GitHub endpoint otherwise stalls the
// full Eleventy build. Manual AbortController per cq-abort-signal-timeout-vs-fake-timers.
const FETCH_TIMEOUT_MS = 5000;

let cached;

export default async function () {
  if (cached) return cached;

  const headers = { Accept: "application/vnd.github+json" };
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

  let releases;
  try {
    const res = await fetch(RELEASES_URL, { headers, signal: controller.signal });
    if (!res.ok) throw new Error(`GitHub API ${res.status}: ${res.statusText}`);
    const json = await res.json();
    if (!Array.isArray(json)) {
      throw new Error(`Expected array from GitHub API, got ${typeof json}`);
    }
    releases = json;
  } catch (err) {
    if (process.env.CI) {
      throw new Error(`GitHub API unreachable in CI: ${err.message}`);
    }
    console.warn(`[github.js] GitHub API failed, using fallback: ${err.message}`);
    cached = { version: null, changelog: { html: "" } };
    return cached;
  } finally {
    clearTimeout(timer);
  }

  releases = releases.filter((r) => !r.draft);

  const version = releases[0]?.tag_name?.replace(/^v/, "") ?? null;

  const changelogMd = releases
    .map((r) => {
      const date = r.published_at?.slice(0, 10) ?? "";
      const tag = r.tag_name ?? "";
      return `## ${tag} — ${date}\n\n${r.body ?? ""}`;
    })
    .join("\n\n");

  cached = { version, changelog: { html: md.render(changelogMd) } };
  return cached;
}
