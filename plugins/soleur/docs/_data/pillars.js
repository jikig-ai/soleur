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
  };
}
