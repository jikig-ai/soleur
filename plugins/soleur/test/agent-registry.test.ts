import { describe, test, expect } from "bun:test";
import {
  pathToAgentId,
  discoverAgentEntries,
  discoverAgentPaths,
  buildAgentsManifest,
  EXPECTED_SOLEUR_AGENT_COUNT,
  agentIdToCompatFilename,
  agentIdToGrokSubagentType,
} from "../lib/agent-registry";
import { discoverAgents } from "./helpers";

describe("pathToAgentId", () => {
  test("nested review agent", () => {
    expect(pathToAgentId("agents/engineering/review/security-sentinel.md")).toBe(
      "soleur:engineering:review:security-sentinel",
    );
  });

  test("domain-level agent", () => {
    expect(pathToAgentId("agents/legal/clo.md")).toBe("soleur:legal:clo");
  });
});

describe("discoverAgentEntries", () => {
  test("count matches discoverAgents helper", () => {
    expect(discoverAgentEntries().length).toBe(discoverAgents().length);
  });

  test("count matches EXPECTED_SOLEUR_AGENT_COUNT constant", () => {
    expect(discoverAgentEntries().length).toBe(EXPECTED_SOLEUR_AGENT_COUNT);
  });

  test("all ids unique", () => {
    const ids = discoverAgentEntries().map((e) => e.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  test("excludes references directory", () => {
    const paths = discoverAgentPaths();
    expect(paths.some((p) => p.includes("/references/"))).toBe(false);
  });

  test("security-sentinel entry has description", () => {
    const entry = discoverAgentEntries().find(
      (e) => e.id === "soleur:engineering:review:security-sentinel",
    );
    expect(entry).toBeDefined();
    expect(entry!.description.length).toBeGreaterThan(10);
    expect(entry!.model).toBe("inherit");
  });
});

describe("buildAgentsManifest", () => {
  test("manifest count matches entries", () => {
    const manifest = buildAgentsManifest();
    expect(manifest.schemaVersion).toBe(1);
    expect(manifest.plugin).toBe("soleur");
    expect(manifest.count).toBe(manifest.agents.length);
    expect(manifest.count).toBe(EXPECTED_SOLEUR_AGENT_COUNT);
  });
});

describe("agentIdToCompatFilename", () => {
  test("replaces colons with dashes", () => {
    expect(agentIdToCompatFilename("soleur:engineering:review:security-sentinel")).toBe(
      "soleur-engineering-review-security-sentinel.md",
    );
  });
});

describe("agentIdToGrokSubagentType", () => {
  test("maps colon-qualified registry id to Grok spawn key", () => {
    expect(agentIdToGrokSubagentType("soleur:product:cpo")).toBe("soleur-product-cpo");
    expect(agentIdToGrokSubagentType("soleur:engineering:review:security-sentinel")).toBe(
      "soleur-engineering-review-security-sentinel",
    );
  });

  test("filename stem equals Grok subagent type", () => {
    const id = "soleur:legal:clo";
    expect(agentIdToCompatFilename(id)).toBe(`${agentIdToGrokSubagentType(id)}.md`);
  });

  test("all registry Grok stems unique and colon-free", () => {
    const entries = discoverAgentEntries();
    const stems = entries.map((e) => agentIdToGrokSubagentType(e.id));
    expect(stems.length).toBe(EXPECTED_SOLEUR_AGENT_COUNT);
    expect(new Set(stems).size).toBe(stems.length);
    for (const entry of entries) {
      const stem = agentIdToGrokSubagentType(entry.id);
      expect(stem.includes(":")).toBe(false);
      expect(agentIdToCompatFilename(entry.id)).toBe(`${stem}.md`);
    }
  });
});