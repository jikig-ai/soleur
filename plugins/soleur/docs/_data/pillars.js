// Eleventy _data module. Export shape matches sibling files
// (agents.js, stats.js, skills.js) — default-exported function called at
// build time.
//
// Members list URLs in display order with a relation flag ("pillar" | "cluster").
// Titles are NOT stored here — `pillar-series.njk` looks them up in
// collections.blog by URL so a blog post's `title:` frontmatter stays the
// single source of truth.
export default function () {
  return {
    "billion-dollar-solo-founder": {
      title: "The Billion-Dollar Solo Founder Stack",
      description:
        "How one person builds a billion-dollar company in 2026 — the stack, the proof, and the open questions.",
      members: [
        { url: "/blog/billion-dollar-solo-founder-stack/", relation: "pillar" },
        { url: "/blog/one-person-billion-dollar-company/", relation: "cluster" },
      ],
    },
    "soleur-comparisons": {
      title: "Soleur vs. the Alternatives",
      description:
        "Head-to-head comparisons of Soleur against AI coding agents, agent frameworks, and agentic platforms — where each tool fits and where an AI organization wins.",
      members: [
        { url: "/blog/soleur-vs-devin/", relation: "pillar" },
        { url: "/blog/soleur-vs-anthropic-cowork/", relation: "cluster" },
        { url: "/blog/soleur-vs-notion-custom-agents/", relation: "cluster" },
        { url: "/blog/soleur-vs-cursor/", relation: "cluster" },
        { url: "/blog/soleur-vs-polsia/", relation: "cluster" },
        { url: "/blog/soleur-vs-paperclip/", relation: "cluster" },
        { url: "/blog/soleur-vs-tanka/", relation: "cluster" },
        { url: "/blog/soleur-vs-crewai/", relation: "cluster" },
      ],
    },
    "agentic-solo-founder": {
      title: "The Agentic Solo Founder",
      description:
        "How one person runs a whole company on AI agents — the tools, the compounding knowledge, and the loops that keep the org working from your real codebase.",
      members: [
        { url: "/blog/ai-agents-for-solo-founders/", relation: "pillar" },
        { url: "/blog/why-most-agentic-tools-plateau/", relation: "cluster" },
        {
          url: "/blog/knowledge-compounding-in-ai-development/",
          relation: "cluster",
        },
        {
          url: "/blog/your-ai-team-works-from-your-actual-codebase/",
          relation: "cluster",
        },
        { url: "/blog/best-ai-tools-for-solo-founders-2026/", relation: "cluster" },
        {
          url: "/blog/loop-engineering-for-your-whole-company/",
          relation: "cluster",
        },
      ],
    },
  };
}
