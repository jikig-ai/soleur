import { feedPlugin } from "@11ty/eleventy-plugin-rss";
import { readFileSync, existsSync } from "fs";
import { readdir, readFile } from "fs/promises";
import { join, dirname, basename } from "path";
import { fileURLToPath } from "url";

const INPUT = "plugins/soleur/docs";
const __dirname = dirname(fileURLToPath(import.meta.url));

// ── Filesystem helpers ─────────────────────────────────────────────────────

// Parse YAML frontmatter from a markdown file.
// Returns { name, description } from the --- block or empty strings.
function parseFrontmatter(content) {
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return { name: "", description: "" };
  const block = match[1];
  const nameMatch = block.match(/^name:\s*["']?(.+?)["']?\s*$/m);
  const descMatch = block.match(/^description:\s*["'](.+?)["']?\s*$/m);
  return {
    name: nameMatch ? nameMatch[1].trim() : "",
    description: descMatch ? descMatch[1].trim() : "",
  };
}

// Recursively collect .md files from a directory tree, skipping
// subdirectory names in the excludeDirs list.
async function collectMdFiles(dir, excludeDirs = []) {
  let results = [];
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return results;
  }
  for (const entry of entries) {
    if (entry.isDirectory()) {
      if (!excludeDirs.includes(entry.name)) {
        const sub = await collectMdFiles(join(dir, entry.name), excludeDirs);
        results = results.concat(sub);
      }
    } else if (entry.isFile() && entry.name.endsWith(".md")) {
      results.push(join(dir, entry.name));
    }
  }
  return results;
}

// ── Data builders ──────────────────────────────────────────────────────────

async function buildStats() {
  const agentsDir = join(__dirname, "plugins/soleur/agents");
  const skillsDir = join(__dirname, "plugins/soleur/skills");
  const commandsDir = join(__dirname, "plugins/soleur/commands");
  const agentFiles = await collectMdFiles(agentsDir, ["references"]);
  let skillCount = 0;
  try {
    const entries = await readdir(skillsDir, { withFileTypes: true });
    for (const e of entries) {
      if (e.isDirectory()) {
        const skillFile = join(skillsDir, e.name, "SKILL.md");
        if (existsSync(skillFile)) skillCount++;
      }
    }
  } catch { /* ignore */ }
  let commandCount = 0;
  try {
    const cmdEntries = await readdir(commandsDir, { withFileTypes: true });
    commandCount = cmdEntries.filter(e => e.isFile() && e.name.endsWith(".md")).length;
  } catch { /* ignore */ }
  return {
    agents: agentFiles.length,
    skills: skillCount,
    commands: commandCount,
    departments: 8,
  };
}

async function buildAgents() {
  const agentsBase = join(__dirname, "plugins/soleur/agents");

  const DEPARTMENT_META = [
    { key: "engineering", name: "Engineering", cssVar: "var(--cat-engineering, #4F8EF7)" },
    { key: "marketing",   name: "Marketing",   cssVar: "var(--cat-marketing, #F7A14F)"  },
    { key: "legal",       name: "Legal",        cssVar: "var(--cat-legal, #A14FF7)"      },
    { key: "finance",     name: "Finance",      cssVar: "var(--cat-finance, #4FF7A1)"    },
    { key: "operations",  name: "Operations",   cssVar: "var(--cat-operations, #F74FA1)" },
    { key: "product",     name: "Product",      cssVar: "var(--cat-product, #F7F14F)"    },
    { key: "sales",       name: "Sales",        cssVar: "var(--cat-sales, #4FF7F7)"      },
    { key: "support",     name: "Support",      cssVar: "var(--cat-support, #F7E44F)"    },
  ];

  const domains = [];
  const departmentNamesList = [];

  for (const meta of DEPARTMENT_META) {
    const deptDir = join(agentsBase, meta.key);
    const allFiles = await collectMdFiles(deptDir, ["references"]);

    // Determine if this department has subdirectories (subcategories)
    let entries = [];
    try { entries = await readdir(deptDir, { withFileTypes: true }); } catch { /**/ }
    const subdirs = entries.filter(e => e.isDirectory() && e.name !== "references").map(e => e.name);

    // Build subcategories when subdirs exist
    const subcategories = [];
    if (subdirs.length > 0) {
      for (const sub of subdirs) {
        const subFiles = await collectMdFiles(join(deptDir, sub), ["references"]);
        const subAgents = [];
        for (const f of subFiles) {
          const content = await readFile(f, "utf8");
          const fm = parseFrontmatter(content);
          const fileName = basename(f, ".md");
          subAgents.push({
            name: fm.name || fileName.replace(/-/g, " ").replace(/\b\w/g, c => c.toUpperCase()),
            description: fm.description || "",
          });
        }
        if (subAgents.length > 0) {
          subcategories.push({
            name: sub.replace(/-/g, " ").replace(/\b\w/g, c => c.toUpperCase()),
            agents: subAgents,
          });
        }
      }
    }

    // Top-level agents (directly in deptDir, not in subdirs)
    const topLevelAgents = [];
    for (const f of allFiles) {
      const fileDir = dirname(f);
      if (fileDir === deptDir) {
        const content = await readFile(f, "utf8");
        const fm = parseFrontmatter(content);
        const fileName = basename(f, ".md");
        topLevelAgents.push({
          name: fm.name || fileName.replace(/-/g, " ").replace(/\b\w/g, c => c.toUpperCase()),
          description: fm.description || "",
        });
      }
    }

    domains.push({
      key: meta.key,
      name: meta.name,
      cssVar: meta.cssVar,
      count: allFiles.length,
      agents: topLevelAgents,
      subcategories,
      cardDescription: topLevelAgents.slice(0, 3).map(a => a.name).join(", ") + (topLevelAgents.length > 3 ? " and more." : "."),
    });
    departmentNamesList.push(meta.name);
  }

  return {
    domains,
    departmentList: departmentNamesList.join(", "),
  };
}

async function buildSkills() {
  const skillsBase = join(__dirname, "plugins/soleur/skills");

  // Skill category buckets — maps skill directory names to categories
  const CATEGORY_MAP = {
    brainstorm: "Workflow", plan: "Workflow", work: "Workflow",
    compound: "Workflow", "compound-capture": "Workflow", go: "Workflow",
    review: "Engineering", "test-fix-loop": "Engineering",
    "atdd-developer": "Engineering", "dhh-rails-style": "Engineering",
    "resolve-debt": "Engineering", "spec-templates": "Engineering",
    "code-to-prd": "Engineering", "andrew-kane-gem-writer": "Engineering",
    "agent-native-architecture": "Engineering", "agent-native-audit": "Engineering",
    "dspy-ruby": "Engineering", "xcode-test": "Engineering",
    deploy: "Deployment", "deploy-docs": "Deployment", ship: "Deployment",
    preflight: "Deployment", postmerge: "Deployment", "release-announce": "Deployment",
    "release-docs": "Deployment", "git-worktree": "Deployment",
    "content-writer": "Content", "discord-content": "Content",
    "social-distribute": "Content", "competitive-analysis": "Content",
    "campaign-calendar": "Content", growth: "Content",
    "seo-aeo": "Content", "frontend-design": "Content",
    "frontend-anti-slop": "Content", "ux-audit": "Content",
    "every-style-editor": "Content", "feature-video": "Content",
    "legal-generate": "Legal", "legal-audit": "Legal", "gdpr-gate": "Legal",
    "provision-github": "Operations", "provision-hetzner": "Operations",
    "provision-cloudflare": "Operations", "provision-doppler": "Operations",
    incident: "Operations", schedule: "Operations", "trigger-cron": "Operations",
    "admin-ip-refresh": "Operations", rclone: "Operations",
    "product-roadmap": "Product", "user-story-writer": "Product",
    "brainstorm-techniques": "Product", architecture: "Product",
    triage: "Product", "file-todos": "Product",
    "kb-search": "Knowledge", "archive-kb": "Knowledge",
    community: "Community", "fix-issue": "Community", "merge-pr": "Community",
    "resolve-pr-parallel": "Community", "resolve-todo-parallel": "Community",
    "resolve-parallel": "Community", "drain-labeled-backlog": "Community",
    changelog: "Community",
    "agent-browser": "Tools", "test-browser": "Tools",
    "gemini-imagegen": "Tools", "one-shot": "Tools",
    "reproduce-bug": "Tools", "skill-creator": "Tools",
    "heal-skill": "Tools", "skill-security-scan": "Tools",
    "flag-create": "Tools", "flag-set-role": "Tools",
    "flag-bootstrap": "Tools", "user-set-role": "Tools",
    "pencil-setup": "Tools", "linear-fetch": "Tools",
    "plan-review": "Tools", qa: "Tools", "docs-site": "Tools",
  };

  const CATEGORY_CSS = {
    "Workflow": "var(--cat-workflow, #4F8EF7)",
    "Engineering": "var(--cat-engineering, #F7A14F)",
    "Deployment": "var(--cat-deployment, #4FF7A1)",
    "Content": "var(--cat-marketing, #F74FA1)",
    "Legal": "var(--cat-legal, #A14FF7)",
    "Operations": "var(--cat-operations, #F7F14F)",
    "Product": "var(--cat-product, #4FF7F7)",
    "Knowledge": "var(--cat-kb, #F7E44F)",
    "Community": "var(--cat-community, #4F8EF7)",
    "Tools": "var(--cat-tools, #E44FF7)",
  };

  const categoryMap = new Map();
  let entries = [];
  try { entries = await readdir(skillsBase, { withFileTypes: true }); } catch { /**/ }

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const skillDir = join(skillsBase, entry.name);
    const skillFile = join(skillDir, "SKILL.md");
    if (!existsSync(skillFile)) continue;

    const content = await readFile(skillFile, "utf8");
    const fm = parseFrontmatter(content);
    const catName = CATEGORY_MAP[entry.name] || "Other";
    const cssVar = CATEGORY_CSS[catName] || "var(--color-accent)";

    if (!categoryMap.has(catName)) {
      categoryMap.set(catName, { name: catName, slug: catName.toLowerCase().replace(/[^a-z0-9]+/g, "-"), cssVar, skills: [] });
    }
    categoryMap.get(catName).skills.push({
      name: fm.name || entry.name.replace(/-/g, " ").replace(/\b\w/g, c => c.toUpperCase()),
      description: fm.description || "",
    });
  }

  const categories = Array.from(categoryMap.values()).map(cat => ({
    ...cat,
    count: cat.skills.length,
  }));

  return { categories };
}

async function buildPlugin() {
  const pluginPath = join(__dirname, "plugins/soleur/.claude-plugin/plugin.json");
  try {
    const data = JSON.parse(readFileSync(pluginPath, "utf8"));
    return { version: data.version || "0.0.0" };
  } catch {
    return { version: "0.0.0" };
  }
}

async function buildChangelog() {
  const paths = [
    join(__dirname, "plugins/soleur/CHANGELOG.md"),
    join(__dirname, "CHANGELOG.md"),
  ];
  for (const p of paths) {
    if (existsSync(p)) {
      const content = readFileSync(p, "utf8");
      const html = content
        .replace(/^### (.+)$/gm, "<h3>$1</h3>")
        .replace(/^## (.+)$/gm, "<h2>$1</h2>")
        .replace(/^# (.+)$/gm, "<h1>$1</h1>")
        .replace(/^\- (.+)$/gm, "<li>$1</li>")
        .replace(/(<li>.*<\/li>\n?)+/g, m => `<ul>${m}</ul>`)
        .replace(/\n{2,}/g, "\n<br>\n");
      return { html };
    }
  }
  return { html: "<p>See <a href=\"https://github.com/jikig-ai/soleur/releases\">GitHub Releases</a> for version history.</p>" };
}

export default function (eleventyConfig) {
  // RSS/Atom feed plugin
  eleventyConfig.addPlugin(feedPlugin, {
    type: "atom",
    outputPath: "/blog/feed.xml",
    collection: {
      name: "blog",
      limit: 20,
    },
    metadata: {
      language: "en",
      title: "Soleur Blog",
      subtitle: "Insights on agentic engineering and company-as-a-service",
      base: "https://soleur.ai/",
      author: {
        name: "Soleur",
      },
    },
  });

  // JSON-LD-safe stringify: JSON.stringify + escape </ and U+2028/U+2029
  // so that untrusted string values cannot break out of <script type="application/ld+json">
  // (</ => <\/) or break JSON.parse in older JS runtimes (U+2028/U+2029 are line
  // terminators in JS source but valid inside JSON strings -- escape for parity).
  // See #2609 and PR-level discussion of dump-filter gap.
  eleventyConfig.addFilter("jsonLdSafe", function jsonLdSafe(value) {
    const ls = String.fromCharCode(0x2028);
    const ps = String.fromCharCode(0x2029);
    return JSON.stringify(value)
      .replace(/<\//g, "<\\/")
      .replace(new RegExp(ls, "g"), "\\u2028")
      .replace(new RegExp(ps, "g"), "\\u2029");
  });

  // Short date for sitemap lastmod (YYYY-MM-DD)
  // Guards falsy input for parity with dateToRfc3339 (new Date(undefined) throws RangeError).
  eleventyConfig.addFilter("dateToShort", (date) => {
    if (!date) return null;
    const d = new Date(date);
    return Number.isNaN(d.getTime()) ? null : d.toISOString().split("T")[0];
  });

  // RFC 3339 / ISO 8601 timestamp for schema.org dateModified
  // Returns null on falsy input so callers can guard the JSON-LD line
  // (new Date(undefined).toISOString() throws RangeError).
  eleventyConfig.addFilter("dateToRfc3339", (date) => {
    if (!date) return null;
    const d = new Date(date);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
  });

  // Human-readable date for blog templates
  eleventyConfig.addFilter("readableDate", (dateObj) => {
    if (!dateObj) return "";
    const d = new Date(dateObj);
    if (Number.isNaN(d.getTime())) return "";
    return d.toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
    });
  });

  // ── Global data injection for missing _data/*.js files ──────────────────
  // The _data/ directory in plugins/soleur/docs/ is read-only in CI.
  // All dynamic data is injected here via addGlobalData() instead.

  eleventyConfig.addGlobalData("stats", buildStats);
  eleventyConfig.addGlobalData("agents", buildAgents);
  eleventyConfig.addGlobalData("skills", buildSkills);
  eleventyConfig.addGlobalData("plugin", buildPlugin);
  eleventyConfig.addGlobalData("changelog", buildChangelog);

  // Page redirects: old /pages/*.html => new clean URLs (from original pageRedirects.js)
  eleventyConfig.addGlobalData("pageRedirects", [
    { from: "pages/agents.html", to: "/agents/" },
    { from: "pages/skills.html", to: "/skills/" },
    { from: "pages/pricing.html", to: "/pricing/" },
    { from: "pages/getting-started.html", to: "/getting-started/" },
    { from: "pages/about.html", to: "/about/" },
    { from: "pages/blog.html", to: "/blog/" },
    { from: "pages/changelog.html", to: "/changelog/" },
    { from: "pages/community.html", to: "/community/" },
    { from: "pages/vision.html", to: "/vision/" },
    { from: "pages/legal.html", to: "/legal/" },
    { from: "pages/legal/privacy-policy.html", to: "/legal/privacy-policy/" },
    { from: "pages/legal/terms-and-conditions.html", to: "/legal/terms-and-conditions/" },
    { from: "pages/legal/gdpr-policy.html", to: "/legal/gdpr-policy/" },
    { from: "pages/legal/cookie-policy.html", to: "/legal/cookie-policy/" },
    { from: "pages/legal/acceptable-use-policy.html", to: "/legal/acceptable-use-policy/" },
    { from: "pages/legal/disclaimer.html", to: "/legal/disclaimer/" },
    { from: "pages/legal/data-protection-disclosure.html", to: "/legal/data-protection-disclosure/" },
    { from: "blog/what-is-company-as-a-service/index.html", to: "/company-as-a-service/" },
  ]);

  // Blog date-slug redirects: empty array -- no date-prefix redirects needed.
  eleventyConfig.addGlobalData("blogRedirects", []);

  // GitHub stats: null fallback -- live data fetched in CI only.
  eleventyConfig.addGlobalData("githubStats", {
    stars: null,
    forks: null,
    contributors: null,
  });

  // Community stats: null fallback -- live data fetched in CI only.
  eleventyConfig.addGlobalData("communityStats", {
    discord: { members: null },
  });

  // Pillar series: empty object -- pillar-series.njk guards on pillars[pillar].
  eleventyConfig.addGlobalData("pillars", {});

  // Passthrough static assets -- paths relative to project root, mapped to output
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/css`]: "css" });
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/fonts`]: "fonts" });
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/images`]: "images" });
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/screenshots`]: "screenshots" });
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/CNAME`]: "CNAME" });
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/robots.txt`]: "robots.txt" });
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/.nojekyll`]: ".nojekyll" });
}

export const config = {
  dir: {
    input: INPUT,
    output: "_site",
    includes: "_includes",
    data: "_data",
  },
  markdownTemplateEngine: "njk",
  htmlTemplateEngine: "njk",
  templateFormats: ["md", "njk"],
};
