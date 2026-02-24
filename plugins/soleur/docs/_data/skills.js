import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import yaml from "yaml";

// Category mapping -- update here when skills are added/reorganized
// Source of truth: plugins/soleur/docs/pages/skills.html
// Last verified: 2026-02-24 (4 categories, 51 skills)
const SKILL_CATEGORIES = {
  // Content & Release (16)
  "brainstorm-techniques": "Review & Planning",
  changelog: "Content & Release",
  compound: "Content & Release",
  "compound-capture": "Content & Release",
  "content-writer": "Content & Release",
  "deploy-docs": "Content & Release",
  "discord-content": "Content & Release",
  "every-style-editor": "Content & Release",
  "feature-video": "Content & Release",
  "file-todos": "Content & Release",
  "gemini-imagegen": "Content & Release",
  growth: "Content & Release",
  "legal-audit": "Content & Release",
  "legal-generate": "Content & Release",
  "release-announce": "Content & Release",
  "release-docs": "Content & Release",
  "seo-aeo": "Content & Release",
  triage: "Content & Release",

  // Development (11)
  "agent-native-architecture": "Development",
  "agent-native-audit": "Development",
  "andrew-kane-gem-writer": "Development",
  "atdd-developer": "Development",
  "dhh-rails-style": "Development",
  "docs-site": "Development",
  "dspy-ruby": "Development",
  "frontend-design": "Development",
  "skill-creator": "Development",
  "spec-templates": "Development",
  "user-story-writer": "Development",

  // Review & Planning (6)
  brainstorm: "Review & Planning",
  "deepen-plan": "Review & Planning",
  "heal-skill": "Review & Planning",
  plan: "Review & Planning",
  "plan-review": "Review & Planning",
  review: "Review & Planning",

  // Workflow (16)
  "agent-browser": "Workflow",
  "archive-kb": "Workflow",
  deploy: "Workflow",
  "git-worktree": "Workflow",
  "merge-pr": "Workflow",
  "one-shot": "Workflow",
  rclone: "Workflow",
  "reproduce-bug": "Workflow",
  "resolve-parallel": "Workflow",
  "resolve-pr-parallel": "Workflow",
  "resolve-todo-parallel": "Workflow",
  ship: "Workflow",
  work: "Workflow",
  "test-browser": "Workflow",
  "test-fix-loop": "Workflow",
  "xcode-test": "Workflow",
};

// CSS variable for category dot color
const CATEGORY_CSS_VARS = {
  "Content & Release": "var(--cat-content)",
  Development: "var(--cat-tools)",
  "Review & Planning": "var(--cat-review)",
  Workflow: "var(--cat-workflow)",
};

// Slug for anchor IDs
const CATEGORY_SLUGS = {
  "Content & Release": "content-release",
  Development: "development",
  "Review & Planning": "review-planning",
  Workflow: "workflow",
};

function parseFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return {};
  return yaml.parse(match[1]);
}

function cleanDescription(desc) {
  if (!desc) return "";
  // Remove common skill description prefixes
  let cleaned = desc
    .replace(/^This skill should be used when\s+/i, "")
    .replace(/^This skill should be used before\s+/i, "")
    .replace(/^Use this skill when\s+/i, "")
    .replace(/^Use this when\s+/i, "");
  // Take first sentence
  const sentence = cleaned.split(". ")[0];
  // Capitalize first letter
  return sentence.charAt(0).toUpperCase() + sentence.slice(1);
}

export default function () {
  const skillsDir = resolve("plugins/soleur/skills");
  const entries = readdirSync(skillsDir, { withFileTypes: true });

  const skillsByCategory = {};

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const skillPath = join(skillsDir, entry.name, "SKILL.md");
    try {
      statSync(skillPath);
    } catch {
      continue; // No SKILL.md
    }

    const content = readFileSync(skillPath, "utf-8");
    const data = parseFrontmatter(content);
    const name = data.name || entry.name;
    const category = SKILL_CATEGORIES[name] || "Uncategorized";

    const skill = {
      name,
      description: cleanDescription(data.description),
      category,
      cssVar: CATEGORY_CSS_VARS[category] || "var(--accent)",
      slug: CATEGORY_SLUGS[category] || category.toLowerCase().replace(/\s+&\s+/g, "-").replace(/\s+/g, "-"),
    };

    if (!skillsByCategory[category]) {
      skillsByCategory[category] = [];
    }
    skillsByCategory[category].push(skill);
  }

  // Sort skills within each category
  for (const skills of Object.values(skillsByCategory)) {
    skills.sort((a, b) => a.name.localeCompare(b.name));
  }

  // Build ordered output
  const categoryOrder = [
    "Content & Release",
    "Development",
    "Review & Planning",
    "Workflow",
  ];

  const categories = [];
  for (const name of categoryOrder) {
    const skills = skillsByCategory[name] || [];
    categories.push({
      name,
      slug: CATEGORY_SLUGS[name],
      count: skills.length,
      cssVar: CATEGORY_CSS_VARS[name],
      skills,
    });
  }

  // Include any uncategorized skills at the end
  if (skillsByCategory["Uncategorized"]) {
    categories.push({
      name: "Uncategorized",
      slug: "uncategorized",
      count: skillsByCategory["Uncategorized"].length,
      cssVar: "var(--accent)",
      skills: skillsByCategory["Uncategorized"],
    });
  }

  return { categories };
}
