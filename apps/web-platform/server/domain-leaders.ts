export const DOMAIN_LEADERS = [
  {
    id: "cmo",
    name: "CMO",
    domain: "Marketing",
    title: "Chief Marketing Officer",
    description:
      "Marketing strategy, content, SEO, brand, social media, and growth.",
    agentPath: "agents/marketing/cmo.md",
    defaultIcon: "Megaphone",
  },
  {
    id: "cto",
    name: "CTO",
    domain: "Engineering",
    title: "Chief Technology Officer",
    description:
      "Technical architecture, code review, engineering practices, and infrastructure.",
    agentPath: "agents/engineering/cto.md",
    defaultIcon: "Cog",
  },
  {
    id: "cfo",
    name: "CFO",
    domain: "Finance",
    title: "Chief Financial Officer",
    description:
      "Budget planning, revenue analysis, financial reporting, and forecasting.",
    agentPath: "agents/finance/cfo.md",
    defaultIcon: "TrendingUp",
  },
  {
    id: "cpo",
    name: "CPO",
    domain: "Product",
    title: "Chief Product Officer",
    description:
      "Product strategy, specs, user research, competitive analysis, and UX.",
    agentPath: "agents/product/cpo.md",
    defaultIcon: "Boxes",
  },
  {
    id: "cro",
    name: "CRO",
    domain: "Sales",
    title: "Chief Revenue Officer",
    description:
      "Sales strategy, pipeline analysis, outbound, deal architecture, and pricing.",
    agentPath: "agents/sales/cro.md",
    defaultIcon: "Target",
  },
  {
    id: "coo",
    name: "COO",
    domain: "Operations",
    title: "Chief Operations Officer",
    description:
      "Operations, tooling, vendor management, expense tracking, and provisioning.",
    agentPath: "agents/operations/coo.md",
    defaultIcon: "Wrench",
  },
  {
    id: "clo",
    name: "CLO",
    domain: "Legal",
    title: "Chief Legal Officer",
    description:
      "Legal documents, compliance audits, privacy policies, and terms of service.",
    agentPath: "agents/legal/clo.md",
    defaultIcon: "Scale",
  },
  {
    id: "cco",
    name: "CCO",
    domain: "Support",
    title: "Chief Communications Officer",
    description:
      "Community management, support strategy, customer engagement, and communications.",
    agentPath: "agents/support/cco.md",
    defaultIcon: "Headphones",
  },
  {
    id: "system",
    name: "System",
    domain: "System",
    title: "System Process",
    description:
      "Internal system processes such as automated sync and health checks.",
    agentPath: "",
    defaultIcon: "",
    internal: true,
  },
  {
    // Command Center `/soleur:go` router voice — pre-dispatch narration
    // and tool-use chips during the routing phase, before a specific
    // domain leader is selected. Distinct from `system` (health-check
    // output, not user-visible as a conversational bubble) so the UI
    // can render router turns without conflating them with background
    // processes. See plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md
    // Stage 2 §"leaderId attribution" and ADR-022.
    id: "cc_router",
    name: "Concierge",
    domain: "System",
    title: "Soleur Concierge",
    description:
      "Greets the user, routes their request to the right Soleur workflow, and reports back.",
    agentPath: "",
    defaultIcon: "",
    internal: true,
  },
] as const;

export type DomainLeaderId = (typeof DOMAIN_LEADERS)[number]["id"];

/** Domain leaders visible to users (excludes internal leaders like "system"). */
export const ROUTABLE_DOMAIN_LEADERS = DOMAIN_LEADERS.filter(
  (l) => !("internal" in l && l.internal),
);
