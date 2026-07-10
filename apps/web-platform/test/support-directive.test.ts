// RED→GREEN for the support-persona scoping constants (Phase 3.1).
// Deterministic unit test — no SDK/LLM invocation
// (learning 2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md).

import { describe, it, expect } from "vitest";

import {
  SUPPORT_SYSTEM_DIRECTIVE,
  SUPPORT_SKILL_ALLOWLIST,
  SUPPORT_EXTRA_DISALLOWED_TOOLS,
  SUPPORT_SKILLS_OPTION,
  normalizeSkillName,
  isSupportAllowedSkill,
} from "@/server/support-directive";

describe("support-directive constants", () => {
  it("allowlist is exactly {kb-search} (help excluded — it enumerates the engineering surface)", () => {
    expect(SUPPORT_SKILL_ALLOWLIST.has("kb-search")).toBe(true);
    expect(SUPPORT_SKILL_ALLOWLIST.has("help")).toBe(false);
    expect(SUPPORT_SKILL_ALLOWLIST.has("one-shot")).toBe(false);
    expect(SUPPORT_SKILL_ALLOWLIST.size).toBe(1);
  });

  it("SDK skills option loads only kb-search into the main-session prompt", () => {
    expect(SUPPORT_SKILLS_OPTION).toEqual(["kb-search"]);
  });

  it("extra-disallowed pins the write/fan-out surface but KEEPS Bash (kb-search shells out)", () => {
    for (const t of ["Edit", "Write", "MultiEdit", "NotebookEdit", "Task", "Agent"]) {
      expect(SUPPORT_EXTRA_DISALLOWED_TOOLS).toContain(t);
    }
    expect(SUPPORT_EXTRA_DISALLOWED_TOOLS).not.toContain("Bash");
  });

  it("directive forbids engineering workflows and repo writes, names kb-search", () => {
    expect(SUPPORT_SYSTEM_DIRECTIVE).toMatch(/Soleur Support/i);
    expect(SUPPORT_SYSTEM_DIRECTIVE).toMatch(/kb-search/);
    expect(SUPPORT_SYSTEM_DIRECTIVE).toMatch(/never (edit|touch|run)/i);
  });
});

describe("normalizeSkillName (bare↔FQN)", () => {
  it("strips a leading soleur: prefix (anchored)", () => {
    expect(normalizeSkillName("soleur:kb-search")).toBe("kb-search");
    expect(normalizeSkillName("kb-search")).toBe("kb-search");
  });

  it("only strips the anchored leading prefix, not a mid-string occurrence", () => {
    expect(normalizeSkillName("x-soleur:kb-search")).toBe("x-soleur:kb-search");
  });

  it("tolerates non-string / empty input", () => {
    expect(normalizeSkillName(undefined as unknown as string)).toBe("");
    expect(normalizeSkillName("")).toBe("");
  });
});

describe("isSupportAllowedSkill", () => {
  it("allows kb-search in BOTH bare and FQN forms", () => {
    expect(isSupportAllowedSkill("kb-search")).toBe(true);
    expect(isSupportAllowedSkill("soleur:kb-search")).toBe(true);
  });

  it("denies everything else, including help and engineering skills", () => {
    expect(isSupportAllowedSkill("help")).toBe(false);
    expect(isSupportAllowedSkill("soleur:one-shot")).toBe(false);
    expect(isSupportAllowedSkill("")).toBe(false);
  });
});
