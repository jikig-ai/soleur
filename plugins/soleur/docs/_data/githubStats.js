const REPO_URL = "https://api.github.com/repos/jikig-ai/soleur";
const CONTRIBUTORS_URL = `${REPO_URL}/contributors?per_page=1&anon=1`;

// Build-time fetch timeout — a hung GitHub endpoint otherwise stalls the
// full Eleventy build. Manual AbortController per cq-abort-signal-timeout-vs-fake-timers.
const FETCH_TIMEOUT_MS = 5000;

let cached;

function parseLastPage(linkHeader) {
  if (!linkHeader) return null;
  const match = linkHeader.match(
    /<[^>]*[?&]page=(\d+)[^>]*>;\s*rel="last"/,
  );
  return match ? Number.parseInt(match[1], 10) : null;
}

function __resetCache() {
  cached = undefined;
}

async function fetchGithubStats() {
  if (cached) return cached;

  const headers = { Accept: "application/vnd.github+json" };
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

  try {
    const [repoRes, contribRes] = await Promise.all([
      fetch(REPO_URL, { headers, signal: controller.signal }),
      fetch(CONTRIBUTORS_URL, { headers, signal: controller.signal }),
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
      `[githubStats.js] GitHub API failed, using fallback: ${err.message}`,
    );
    cached = {
      stars: null,
      forks: null,
      openIssues: null,
      contributors: null,
    };
    return cached;
  } finally {
    clearTimeout(timer);
  }
}

// Exported for test isolation: sibling _data modules (e.g. communityStats.js)
// statically import this file, so the module-scope `cached` persists across
// test reloads of the importer. Tests call `default.__resetCache()` in
// beforeEach to guarantee a fresh fetch per scenario.
fetchGithubStats.__resetCache = __resetCache;

export default fetchGithubStats;
