/**
 * The docs-site agents page renders exactly the registry (#8317).
 *
 * `docs/_data/agents.js` groups agents by subdirectory through a hand-kept `subOrder` list, and an
 * agent in a subdirectory missing from that list is dropped silently — from the page AND from the
 * domain count. `engineering/discovery/` was missing, so the page showed 65 agents while the
 * registry, the manifest and both READMEs said 67.
 */

import { describe, test, expect } from "bun:test";
import { EXPECTED_SOLEUR_AGENT_COUNT, discoverAgentEntries } from "../lib/agent-registry";
import agentsData from "../docs/_data/agents.js";

type Card = { name: string };
type Domain = { count: number; agents: Card[]; subcategories: { agents: Card[] }[] };

describe("docs agents page", () => {
  const { domains } = agentsData() as { domains: Domain[] };
  const rendered = domains.flatMap((d) => [...d.agents, ...d.subcategories.flatMap((s) => s.agents)]).map((a) => a.name);

  test("renders every registry agent exactly once", () => {
    expect(rendered.slice().sort()).toEqual(discoverAgentEntries().map((e) => e.name).sort());
    expect(rendered.length).toBe(EXPECTED_SOLEUR_AGENT_COUNT);
  });

  test("the domain counts sum to the registry count", () => {
    expect(domains.reduce((n, d) => n + d.count, 0)).toBe(EXPECTED_SOLEUR_AGENT_COUNT);
  });
});
