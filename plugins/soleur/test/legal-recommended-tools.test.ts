import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "../../../");
const RECOMMENDED_TOOLS_PATH = resolve(REPO_ROOT, "knowledge-base/legal/recommended-tools.md");
const CLO_PATH = resolve(REPO_ROOT, "plugins/soleur/agents/legal/clo.md");
const LEGAL_AUDIT_PATH = resolve(REPO_ROOT, "plugins/soleur/skills/legal-audit/SKILL.md");

const EXPECTED_THRESHOLDS = 5;

function kebab(s: string): string {
  return s
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9\s-]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-");
}

function extractH2Anchors(md: string): string[] {
  return md
    .split("\n")
    .filter((line) => line.startsWith("## "))
    .map((line) => kebab(line.replace(/^##\s+/, "")));
}

function extractTableSections(md: string): { heading: string; rows: string[][] }[] {
  const lines = md.split("\n");
  const sections: { heading: string; rows: string[][] }[] = [];
  let currentHeading: string | null = null;
  let inTable = false;
  let tableRows: string[][] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.startsWith("## ")) {
      if (currentHeading && tableRows.length > 0) {
        sections.push({ heading: currentHeading, rows: tableRows });
      }
      currentHeading = line.replace(/^##\s+/, "").trim();
      tableRows = [];
      inTable = false;
      continue;
    }
    if (line.startsWith("|") && line.includes("|")) {
      const cells = line.split("|").slice(1, -1).map((c) => c.trim());
      if (cells.every((c) => /^:?-+:?$/.test(c))) {
        inTable = true;
        continue;
      }
      if (inTable) {
        tableRows.push(cells);
      }
    } else if (inTable && line.trim() === "") {
      inTable = false;
    }
  }
  if (currentHeading && tableRows.length > 0) {
    sections.push({ heading: currentHeading, rows: tableRows });
  }
  return sections;
}

function extractAnchorRefs(md: string): string[] {
  const refs: string[] = [];
  const re = /recommended-tools\.md#([a-z0-9-]+)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(md)) !== null) {
    refs.push(m[1]);
  }
  return refs;
}

describe("recommended-tools.md", () => {
  test("file exists and is readable", () => {
    expect(() => readFileSync(RECOMMENDED_TOOLS_PATH, "utf8")).not.toThrow();
  });

  const md = (() => {
    try {
      return readFileSync(RECOMMENDED_TOOLS_PATH, "utf8");
    } catch {
      return "";
    }
  })();

  test(`has exactly ${EXPECTED_THRESHOLDS} tool-table H2 sections (frozen catalog)`, () => {
    // Count H2s that are followed by a tool table — page-metadata H2s
    // (e.g., "## About this page") are intentionally excluded so the test
    // doesn't shape document structure. The five tool-table sections are
    // the load-bearing invariant.
    const sections = extractTableSections(md);
    expect(sections.length).toBe(EXPECTED_THRESHOLDS);
  });

  test("each tool-table section has at least 2 data rows", () => {
    const sections = extractTableSections(md);
    for (const section of sections) {
      expect(section.rows.length).toBeGreaterThanOrEqual(2);
    }
  });

  test("threshold-section H2 headings are lowercase-kebab (locks anchor form)", () => {
    // Anchor stability requires the heading text to BE the anchor literal
    // already (lowercase, kebab, no punctuation). A future contributor who
    // "fixes" the heading to readable English (`## Vendor MSA review`)
    // changes the rendered anchor to `vendor-msa-review` via the renderer's
    // slugger — not necessarily the same as `kebab(text)`. Locking the
    // heading form prevents silent anchor drift.
    const KEBAB_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/;
    const sections = extractTableSections(md);
    for (const section of sections) {
      expect(section.heading).toMatch(KEBAB_RE);
    }
  });

  test("no section uses claude-for-legal as the sole non-empty Tool column", () => {
    const sections = extractTableSections(md);
    for (const section of sections) {
      const nonClaudeRows = section.rows.filter(
        (row) => row[0] && !/claude-for-legal/i.test(row[0]),
      );
      expect(nonClaudeRows.length).toBeGreaterThanOrEqual(1);
    }
  });

  test("DSAR + breach sections include statutory-deadline callouts", () => {
    expect(md).toMatch(/Art\.\s*12/);
    expect(md).toMatch(/Art\.\s*33/);
    expect(md).toMatch(/72\s*h(our)?/i);
  });
});

describe("recommended-tools.md anchor resolution", () => {
  const recMd = (() => {
    try {
      return readFileSync(RECOMMENDED_TOOLS_PATH, "utf8");
    } catch {
      return "";
    }
  })();
  const cloMd = (() => {
    try {
      return readFileSync(CLO_PATH, "utf8");
    } catch {
      return "";
    }
  })();
  const auditMd = (() => {
    try {
      return readFileSync(LEGAL_AUDIT_PATH, "utf8");
    } catch {
      return "";
    }
  })();

  test("anchors referenced from clo.md resolve to H2 sections", () => {
    const expected = new Set(extractH2Anchors(recMd));
    const refs = extractAnchorRefs(cloMd);
    for (const r of refs) {
      expect(expected.has(r)).toBe(true);
    }
  });

  test("anchors referenced from legal-audit/SKILL.md resolve to H2 sections", () => {
    const expected = new Set(extractH2Anchors(recMd));
    const refs = extractAnchorRefs(auditMd);
    for (const r of refs) {
      expect(expected.has(r)).toBe(true);
    }
  });
});
