import { describe, test, expect } from "vitest";
import { buildToolLabel } from "../server/tool-labels";

describe("buildToolLabel (#2428)", () => {
  const workspacePath = "/workspaces/abc123";

  describe("Read tool", () => {
    test("extracts relative file path from Read input", () => {
      const label = buildToolLabel(
        "Read",
        { file_path: `${workspacePath}/knowledge-base/overview/vision.md` },
        workspacePath,
      );
      expect(label).toBe("Reading knowledge-base/overview/vision.md...");
    });

    test("strips workspace path prefix", () => {
      const label = buildToolLabel(
        "Read",
        { file_path: `${workspacePath}/docs/readme.md` },
        workspacePath,
      );
      expect(label).not.toContain(workspacePath);
    });

    test("falls back when input is undefined", () => {
      const label = buildToolLabel("Read", undefined, workspacePath);
      expect(label).toBe("Reading file...");
    });

    test("falls back when file_path is missing from input", () => {
      const label = buildToolLabel("Read", {}, workspacePath);
      expect(label).toBe("Reading file...");
    });
  });

  describe("Bash tool", () => {
    test("shows command text", () => {
      const label = buildToolLabel(
        "Bash",
        { command: "git log --oneline -5" },
        workspacePath,
      );
      expect(label).toBe("Running: git log --oneline -5");
    });

    test("truncates long commands at 60 chars", () => {
      const longCmd = "a".repeat(100);
      const label = buildToolLabel("Bash", { command: longCmd }, workspacePath);
      expect(label.length).toBeLessThanOrEqual(75); // "Running: " + 60 + "..."
      expect(label).toContain("...");
    });

    test("replaces newlines with spaces", () => {
      const label = buildToolLabel(
        "Bash",
        { command: "echo hello\necho world" },
        workspacePath,
      );
      expect(label).not.toContain("\n");
      expect(label).toContain("echo hello echo world");
    });

    test("falls back when input is undefined", () => {
      const label = buildToolLabel("Bash", undefined, workspacePath);
      expect(label).toBe("Running command...");
    });
  });

  describe("Grep tool", () => {
    test("shows search pattern", () => {
      const label = buildToolLabel(
        "Grep",
        { pattern: "import.*React" },
        workspacePath,
      );
      expect(label).toBe('Searching for "import.*React"...');
    });

    test("falls back when input is undefined", () => {
      const label = buildToolLabel("Grep", undefined, workspacePath);
      expect(label).toBe("Searching code...");
    });
  });

  describe("Glob tool", () => {
    test("shows glob pattern", () => {
      const label = buildToolLabel(
        "Glob",
        { pattern: "**/*.tsx" },
        workspacePath,
      );
      expect(label).toBe("Finding **/*.tsx...");
    });

    test("falls back when input is undefined", () => {
      const label = buildToolLabel("Glob", undefined, workspacePath);
      expect(label).toBe("Finding files...");
    });
  });

  describe("other tools", () => {
    test("Edit shows 'Editing file...' with path", () => {
      const label = buildToolLabel(
        "Edit",
        { file_path: `${workspacePath}/src/app.tsx` },
        workspacePath,
      );
      expect(label).toBe("Editing src/app.tsx...");
    });

    test("Write shows 'Writing file...' with path", () => {
      const label = buildToolLabel(
        "Write",
        { file_path: `${workspacePath}/src/new-file.ts` },
        workspacePath,
      );
      expect(label).toBe("Writing src/new-file.ts...");
    });

    test("WebSearch shows 'Searching web...'", () => {
      const label = buildToolLabel("WebSearch", {}, workspacePath);
      expect(label).toBe("Searching web...");
    });

    test("unknown tool falls back to 'Working...'", () => {
      const label = buildToolLabel("SomeUnknownTool", {}, workspacePath);
      expect(label).toBe("Working...");
    });
  });

  describe("security: workspace path never leaks", () => {
    test("Read label never contains absolute workspace path", () => {
      const label = buildToolLabel(
        "Read",
        { file_path: `${workspacePath}/secret/data.json` },
        workspacePath,
      );
      expect(label).not.toContain(workspacePath);
    });

    test("Bash label strips workspace path from command text", () => {
      const label = buildToolLabel(
        "Bash",
        { command: `cat ${workspacePath}/secret/data.json` },
        workspacePath,
      );
      expect(label).not.toContain(workspacePath);
    });

    test("Edit label never contains absolute workspace path", () => {
      const label = buildToolLabel(
        "Edit",
        { file_path: `${workspacePath}/src/app.tsx` },
        workspacePath,
      );
      expect(label).not.toContain(workspacePath);
    });
  });
});
