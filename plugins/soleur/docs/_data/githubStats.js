const REPO_URL = "https://api.github.com/repos/jikig-ai/soleur";
const CONTRIBUTORS_URL = `${REPO_URL}/contributors?per_page=1&anon=1`;

let cached;

function parseLastPage(linkHeader) {
  if (!linkHeader) return null;
  const match = linkHeader.match(
    /<[^>]*[?&]page=(\d+)[^>]*>;\s*rel="last"/,
  );
  return match ? Number.parseInt(match[1], 10) : null;
}

export default async function () {
  if (cached) return cached;

  const headers = { Accept: "application/vnd.github+json" };
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  try {
    const [repoRes, contribRes] = await Promise.all([
      fetch(REPO_URL, { headers }),
      fetch(CONTRIBUTORS_URL, { headers }),
    ]);
    if (!repoRes.ok) {
      throw new Error(`GitHub API ${repoRes.status}: ${repoRes.statusText}`);
    }
    const repo = await repoRes.json();
    const linkHeader = contribRes.headers.get("link") ?? "";
    const contributorCount = parseLastPage(linkHeader) ?? 1;
    cached = {
      stars: repo.stargazers_count ?? null,
      forks: repo.forks_count ?? null,
      openIssues: repo.open_issues_count ?? null,
      contributors: contributorCount,
    };
    return cached;
  } catch (err) {
    if (process.env.CI) {
      throw new Error(`GitHub stats unreachable in CI: ${err.message}`);
    }
    console.warn(
      `[github-stats.js] GitHub API failed, using fallback: ${err.message}`,
    );
    cached = {
      stars: null,
      forks: null,
      openIssues: null,
      contributors: null,
    };
    return cached;
  }
}
