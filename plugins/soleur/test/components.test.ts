import { describe, test, expect } from "bun:test";
import {
  discoverAgents,
  discoverCommands,
  discoverSkills,
  parseComponent,
  getComponentName,
} from "./helpers";

const VALID_MODELS = ["inherit", "haiku", "sonnet", "opus"];
const KEBAB_CASE = /^[a-z0-9]+(-[a-z0-9]+)*$/;

// ---------------------------------------------------------------------------
// Agent Frontmatter
// ---------------------------------------------------------------------------

describe("Agent frontmatter", () => {
  const agents = discoverAgents();

  test("discovers agents", () => {
    expect(agents.length).toBeGreaterThan(0);
  });

  for (const agentPath of agents) {
    describe(agentPath, () => {
      const { frontmatter, body } = parseComponent(agentPath);

      test("has frontmatter", () => {
        expect(Object.keys(frontmatter).length).toBeGreaterThan(0);
      });

      test("has name field", () => {
        expect(frontmatter.name).toBeDefined();
        expect(String(frontmatter.name).length).toBeGreaterThan(0);
      });

      test("has description field", () => {
        expect(frontmatter.description).toBeDefined();
        expect(String(frontmatter.description).length).toBeGreaterThan(0);
      });

      test("has valid model field", () => {
        expect(frontmatter.model).toBeDefined();
        expect(VALID_MODELS).toContain(frontmatter.model);
      });

      test("description contains <example> block", () => {
        const desc = String(frontmatter.description);
        expect(desc).toContain("<example>");
      });

      test("has non-empty body", () => {
        expect(body.trim().length).toBeGreaterThan(0);
      });
    });
  }
});

// ---------------------------------------------------------------------------
// Command Frontmatter
// ---------------------------------------------------------------------------

describe("Command frontmatter", () => {
  const commands = discoverCommands();

  test("discovers commands", () => {
    expect(commands.length).toBeGreaterThan(0);
  });

  for (const cmdPath of commands) {
    describe(cmdPath, () => {
      const { frontmatter, body } = parseComponent(cmdPath);

      test("has frontmatter", () => {
        expect(Object.keys(frontmatter).length).toBeGreaterThan(0);
      });

      test("has name field", () => {
        expect(frontmatter.name).toBeDefined();
        expect(String(frontmatter.name).length).toBeGreaterThan(0);
      });

      test("has description field", () => {
        expect(frontmatter.description).toBeDefined();
        expect(String(frontmatter.description).length).toBeGreaterThan(0);
      });

      test("has argument-hint field", () => {
        expect("argument-hint" in frontmatter).toBe(true);
      });

      test("has non-empty body", () => {
        expect(body.trim().length).toBeGreaterThan(0);
      });
    });
  }
});

// ---------------------------------------------------------------------------
// Skill Frontmatter
// ---------------------------------------------------------------------------

describe("Skill frontmatter", () => {
  const skills = discoverSkills();

  test("discovers skills", () => {
    expect(skills.length).toBeGreaterThan(0);
  });

  for (const skillPath of skills) {
    describe(skillPath, () => {
      const { frontmatter, body } = parseComponent(skillPath);

      test("has frontmatter", () => {
        expect(Object.keys(frontmatter).length).toBeGreaterThan(0);
      });

      test("has name field", () => {
        expect(frontmatter.name).toBeDefined();
        expect(String(frontmatter.name).length).toBeGreaterThan(0);
      });

      test("has description field", () => {
        expect(frontmatter.description).toBeDefined();
        expect(String(frontmatter.description).length).toBeGreaterThan(0);
      });

      test("has non-empty body", () => {
        expect(body.trim().length).toBeGreaterThan(0);
      });
    });
  }
});

// ---------------------------------------------------------------------------
// Convention: Third-person voice in skill descriptions
// ---------------------------------------------------------------------------

describe("Skill description voice", () => {
  const skills = discoverSkills();

  for (const skillPath of skills) {
    test(`${skillPath} starts with "This skill"`, () => {
      const { frontmatter } = parseComponent(skillPath);
      const desc = String(frontmatter.description || "");
      expect(desc.startsWith("This skill")).toBe(true);
    });
  }
});

// ---------------------------------------------------------------------------
// Convention: Kebab-case filenames
// ---------------------------------------------------------------------------

describe("Kebab-case filenames", () => {
  const agents = discoverAgents();
  const commands = discoverCommands();
  const skills = discoverSkills();

  for (const agentPath of agents) {
    const name = getComponentName(agentPath, "agent");
    test(`agent ${name} is kebab-case`, () => {
      expect(name).toMatch(KEBAB_CASE);
    });
  }

  for (const cmdPath of commands) {
    const name = getComponentName(cmdPath, "command");
    test(`command ${name} is kebab-case`, () => {
      expect(name).toMatch(KEBAB_CASE);
    });
  }

  for (const skillPath of skills) {
    const name = getComponentName(skillPath, "skill");
    test(`skill ${name} is kebab-case`, () => {
      expect(name).toMatch(KEBAB_CASE);
    });
  }
});

// ---------------------------------------------------------------------------
// Convention: No backtick references to references/, assets/, scripts/
// ---------------------------------------------------------------------------

describe("No backtick file references in skills", () => {
  const skills = discoverSkills();

  for (const skillPath of skills) {
    test(`${skillPath} uses markdown links, not backticks`, () => {
      const { body } = parseComponent(skillPath);
      const backtickRefs = body.match(/`(?:references|assets|scripts)\/[^`]+`/g);
      expect(backtickRefs).toBeNull();
    });
  }
});
