/**
 * The docs-site agents page renders exactly the registry, each agent under its own domain and
 * subcategory, with per-domain counts that match (#8317).
 *
 * `docs/_data/agents.js` groups agents by directory. It used to iterate a hand-kept subcategory
 * list, so `engineering/discovery/` was silently dropped from the page and the domain count (65
 * shown, 67 in the registry).
 */

import { describe, test, expect } from "bun:test";
import { EXPECTED_SOLEUR_AGENT_COUNT, discoverAgentEntries } from "../lib/agent-registry";
import agentsData from "../docs/_data/agents.js";

type Card = { name: string };
type Domain = { key: string; count: number; agents: Card[]; subcategories: { key: string; agents: Card[] }[] };

describe("docs agents page", () => {
  const { domains } = agentsData() as { domains: Domain[] };
  const placed = domains.flatMap((d) => [
    ...d.agents.map((a) => ({ name: a.name, domain: d.key, sub: null as string | null })),
    ...d.subcategories.flatMap((s) => s.agents.map((a) => ({ name: a.name, domain: d.key, sub: s.key as string | null }))),
  ]);
  // Expected placement comes from the registry path, not from the page's own walk.
  const expected = discoverAgentEntries().map((e) => {
    const parts = e.path.replace(/^agents\//, "").split("/");
    return { name: e.name, domain: parts[0], sub: parts.length > 2 ? parts[1] : null };
  });

  test("renders every registry agent exactly once, under its own domain and subcategory", () => {
    const key = (p: { name: string; domain: string; sub: string | null }) => `${p.domain}/${p.sub ?? "-"}/${p.name}`;
    expect(placed.map(key).sort()).toEqual(expected.map(key).sort());
    expect(placed.length).toBe(EXPECTED_SOLEUR_AGENT_COUNT);
  });

  // Cards are human-read (ADR-226 §4): a summary must be real prose, never an agent-read marker
  // block or a raw registry id.
  test("every card summary is non-empty prose with no marker block or registry id", () => {
    type Full = { name: string; description: string };
    const cards = domains.flatMap((d) => [...d.agents, ...d.subcategories.flatMap((s) => s.agents)]) as Full[];
    const bad = cards
      .filter((c) => !c.description || c.description.startsWith("<!--") || /soleur:|operator-typed/i.test(c.description))
      .map((c) => `${c.name}: ${JSON.stringify(c.description)}`);
    expect(bad).toEqual([]);
  });

  test("each domain's count equals the registry agents under that domain", () => {
    for (const d of domains) {
      expect(`${d.key}: ${d.count}`).toBe(`${d.key}: ${expected.filter((e) => e.domain === d.key).length}`);
    }
  });
});
