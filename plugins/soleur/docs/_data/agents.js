import { readdirSync, readFileSync } from "node:fs";
import { join, resolve, relative } from "node:path";
import yaml from "yaml";

// Domain metadata: single source of truth for labels, landing-page icons, and card descriptions.
// Adding a domain here (+ domainOrder + DOMAIN_CSS_VARS) is all that's needed --
// the landing page and legal docs render from this data automatically.
const DOMAIN_META = {
  engineering: {
    label: "Engineering",
    icon: "&#x1F4BB;",
    cardDescription: "Code review, architecture, security, quality testing. Specialized agents shipping production-grade code on your command.",
  },
  finance: {
    label: "Finance",
    icon: "&#x1F4CA;",
    cardDescription: "Budget planning, revenue analysis, financial reporting. Data-driven financial oversight without the back office.",
  },
  legal: {
    label: "Legal",
    icon: "&#x2696;&#xFE0F;",
    cardDescription: "Terms, privacy policies, compliance audits. Legal documents generated, reviewed, and kept current automatically.",
  },
  marketing: {
    label: "Marketing",
    icon: "&#x1F4E3;",
    cardDescription: "Brand identity, community content, release announcements. Your public presence runs on autopilot.",
  },
  operations: {
    label: "Operations",
    icon: "&#x2699;&#xFE0F;",
    cardDescription: "Vendor research, expense tracking, tool provisioning. Operational infrastructure that runs without overhead.",
  },
  product: {
    label: "Product",
    icon: "&#x1F4DA;",
    cardDescription: "Product management, competitive analysis, planning &amp; specs, UX design. From market insight to shipped experience.",
  },
  sales: {
    label: "Sales",
    icon: "&#x1F4B0;",
    cardDescription: "Outbound campaigns, deal qualification, pipeline analytics. AI-powered revenue operations from first outreach to closed-won.",
  },
  support: {
    label: "Support",
    icon: "&#x1F6E0;&#xFE0F;",
    cardDescription: "Issue triage, community management, ticket routing. Customer-facing operations that scale without headcount.",
  },
};

const SUB_LABELS = {
  design: "Design",
  infra: "Infra",
  research: "Research",
  review: "Review",
  workflow: "Workflow",
};

// CSS variable name for category dot color
const DOMAIN_CSS_VARS = {
  engineering: "var(--cat-review)",
  finance: "var(--cat-finance)",
  legal: "var(--cat-legal)",
  marketing: "var(--cat-content)",
  operations: "var(--cat-workflow)",
  product: "var(--cat-tools)",
  sales: "var(--cat-sales)",
  support: "var(--cat-support)",
};

function parseFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return { data: {}, body: "" };
  const data = yaml.parse(match[1]);
  const body = content.slice(match[0].length).trim();
  return { data, body };
}

function extractSummary(body) {
  // Get a clean, short summary from the agent body text
  const lines = body.split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    // Skip empty lines, headings, dividers, and note lines
    if (
      !trimmed ||
      trimmed.startsWith("#") ||
      trimmed.startsWith("---") ||
      /^\*\*Note:/i.test(trimmed) ||
      /^\*\*Your Core/i.test(trimmed) ||
      /^Core responsibilities/i.test(trimmed)
    ) {
      continue;
    }

    let desc = trimmed;
    // Strip bold markdown wrappers
    desc = desc.replace(/\*\*([^*]+)\*\*/g, "$1");
    // Strip "You are <Name>, <title>..." patterns (e.g. "You are David Heinemeier Hansson, creator of...")
    desc = desc.replace(
      /^You are\s+(?:the\s+)?(?:[A-Z][\w-]*(?:\s+[A-Z][\w-]*)*)(?:,\s*(?:an?|the)\s+|\.\s*|\s*[-–]\s*)/i,
      ""
    );
    // Strip simpler "You are a/an/the ..." prefixes
    desc = desc.replace(/^You are\s+(?:a|an|the)\s+/i, "");
    // Strip leftover "You are " if still present
    desc = desc.replace(/^You are\s+/i, "");
    // Strip system-prompt "Your ..." prefixes
    desc = desc.replace(/^Your (?:mission|role|primary responsibility) is to\s+/i, "");
    desc = desc.replace(/^Your expertise lies in\s+/i, "");
    desc = desc.replace(/^You think like\s+/i, "Thinks like ");

    // Take first sentence only
    const sentence = desc.split(/\.\s/)[0];
    // Remove trailing period
    const cleaned = sentence.replace(/\.$/, "").trim();
    if (!cleaned) continue;

    // Capitalize first letter
    return cleaned.charAt(0).toUpperCase() + cleaned.slice(1);
  }
  return "";
}

function walkAgents(dir) {
  const agents = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      agents.push(...walkAgents(fullPath));
    } else if (entry.name.endsWith(".md")) {
      agents.push(fullPath);
    }
  }
  return agents;
}

export default function () {
  const agentsDir = resolve("plugins/soleur/agents");
  const files = walkAgents(agentsDir);

  // Parse each agent and derive domain/sub from path
  const agentsByDomain = {};

  for (const filePath of files) {
    const rel = relative(agentsDir, filePath); // e.g. "engineering/review/code-quality-analyst.md"
    const parts = rel.split("/");

    const domain = parts[0]; // e.g. "engineering"
    const sub = parts.length > 2 ? parts[1] : null; // e.g. "review" or null
    const filename = parts[parts.length - 1].replace(".md", "");

    const content = readFileSync(filePath, "utf-8");
    const { data, body } = parseFrontmatter(content);

    const agent = {
      name: data.name || filename,
      description: extractSummary(body),
      domain: DOMAIN_META[domain]?.label || domain || domain,
      domainKey: domain,
      sub: sub ? (SUB_LABELS[sub] || sub) : null,
      subKey: sub,
      cssVar: DOMAIN_CSS_VARS[domain] || "var(--accent)",
    };

    if (!agentsByDomain[domain]) {
      agentsByDomain[domain] = { agents: [], subs: {} };
    }

    if (sub) {
      if (!agentsByDomain[domain].subs[sub]) {
        agentsByDomain[domain].subs[sub] = [];
      }
      agentsByDomain[domain].subs[sub].push(agent);
    } else {
      agentsByDomain[domain].agents.push(agent);
    }
  }

  // Sort and structure output
  const domainOrder = ["engineering", "finance", "legal", "marketing", "operations", "product", "sales", "support"];
  const subOrder = ["review", "design", "infra", "research", "workflow"];

  const domains = [];
  for (const key of domainOrder) {
    const group = agentsByDomain[key];
    if (!group) continue;

    let totalCount = group.agents.length;
    const subcategories = [];

    for (const subKey of subOrder) {
      const subAgents = group.subs[subKey];
      if (!subAgents) continue;
      subAgents.sort((a, b) => a.name.localeCompare(b.name));
      totalCount += subAgents.length;
      subcategories.push({
        name: SUB_LABELS[subKey] || subKey,
        key: subKey,
        agents: subAgents,
      });
    }

    group.agents.sort((a, b) => a.name.localeCompare(b.name));

    domains.push({
      name: DOMAIN_META[key]?.label || key,
      key,
      count: totalCount,
      icon: DOMAIN_META[key]?.icon || "",
      cardDescription: DOMAIN_META[key]?.cardDescription || "",
      agents: group.agents,
      subcategories,
      cssVar: DOMAIN_CSS_VARS[key] || "var(--accent)",
    });
  }

  return {
    domains,
    departmentList: domains.map((d) => d.name).join(", "),
  };
}
