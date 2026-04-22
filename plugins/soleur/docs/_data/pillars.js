// Eleventy _data module. Export shape matches sibling files
// (agents.js, stats.js, skills.js) — default-exported function called at
// build time. Static today; keeps the door open for deriving members from
// collections.blog in a later PR.
export default function () {
  return {
    "billion-dollar-solo-founder": {
      title: "The Billion-Dollar Solo Founder Stack",
      description:
        "How one person builds a billion-dollar company in 2026 — the stack, the proof, and the open questions.",
      members: [
        {
          url: "/blog/billion-dollar-solo-founder-stack/",
          title: "The Billion-Dollar Solo Founder Stack (2026)",
          relation: "pillar",
        },
        {
          url: "/blog/one-person-billion-dollar-company/",
          title:
            "The One-Person Billion-Dollar Company: Why It's an Engineering Problem",
          relation: "cluster",
        },
      ],
    },
  };
}
