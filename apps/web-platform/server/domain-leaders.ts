export const DOMAIN_LEADERS = [
  {
    id: "cmo",
    name: "CMO",
    title: "Chief Marketing Officer",
    description:
      "Marketing strategy, content, SEO, brand, social media, and growth.",
    agentPath: "agents/marketing/cmo.md",
  },
  {
    id: "cto",
    name: "CTO",
    title: "Chief Technology Officer",
    description:
      "Technical architecture, code review, engineering practices, and infrastructure.",
    agentPath: "agents/engineering/cto.md",
  },
  {
    id: "cfo",
    name: "CFO",
    title: "Chief Financial Officer",
    description:
      "Budget planning, revenue analysis, financial reporting, and forecasting.",
    agentPath: "agents/finance/cfo.md",
  },
  {
    id: "cpo",
    name: "CPO",
    title: "Chief Product Officer",
    description:
      "Product strategy, specs, user research, competitive analysis, and UX.",
    agentPath: "agents/product/cpo.md",
  },
  {
    id: "cro",
    name: "CRO",
    title: "Chief Revenue Officer",
    description:
      "Sales strategy, pipeline analysis, outbound, deal architecture, and pricing.",
    agentPath: "agents/sales/cro.md",
  },
  {
    id: "coo",
    name: "COO",
    title: "Chief Operations Officer",
    description:
      "Operations, tooling, vendor management, expense tracking, and provisioning.",
    agentPath: "agents/operations/coo.md",
  },
  {
    id: "clo",
    name: "CLO",
    title: "Chief Legal Officer",
    description:
      "Legal documents, compliance audits, privacy policies, and terms of service.",
    agentPath: "agents/legal/clo.md",
  },
  {
    id: "cco",
    name: "CCO",
    title: "Chief Communications Officer",
    description:
      "Community management, support strategy, customer engagement, and communications.",
    agentPath: "agents/support/cco.md",
  },
  {
    id: "system",
    name: "System",
    title: "System Process",
    description:
      "Internal system processes such as automated sync and health checks.",
    agentPath: "",
    internal: true,
  },
] as const;

export type DomainLeaderId = (typeof DOMAIN_LEADERS)[number]["id"];

/** Domain leaders visible to users (excludes internal leaders like "system"). */
export const ROUTABLE_DOMAIN_LEADERS = DOMAIN_LEADERS.filter(
  (l) => !("internal" in l && l.internal),
);
