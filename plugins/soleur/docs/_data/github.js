import MarkdownIt from "markdown-it";

const md = new MarkdownIt();

const RELEASES_URL =
  "https://api.github.com/repos/jikig-ai/soleur/releases?per_page=30";

export default async function () {
  const headers = { Accept: "application/vnd.github+json" };
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  let releases;
  try {
    const res = await fetch(RELEASES_URL, { headers });
    if (!res.ok) throw new Error(`GitHub API ${res.status}: ${res.statusText}`);
    releases = await res.json();
  } catch (err) {
    if (process.env.CI) {
      throw new Error(`GitHub API unreachable in CI: ${err.message}`);
    }
    console.warn(`[github.js] GitHub API failed, using fallback: ${err.message}`);
    return { version: null, changelog: { html: "" } };
  }

  // Filter out drafts
  releases = releases.filter((r) => !r.draft);

  const version = releases[0]?.tag_name?.replace(/^v/, "") ?? null;

  const changelogMd = releases
    .map((r) => {
      const date = r.published_at?.slice(0, 10) ?? "";
      const tag = r.tag_name ?? "";
      return `## ${tag} — ${date}\n\n${r.body ?? ""}`;
    })
    .join("\n\n");

  return { version, changelog: { html: md.render(changelogMd) } };
}
