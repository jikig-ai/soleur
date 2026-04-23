import { describe, test, expect, vi, beforeEach } from "vitest";

// Mock reportSilentFallback at module scope. Vitest hoists `vi.mock` before
// imports; keep the factory self-contained.
const reportSilentFallbackMock = vi.fn();
vi.mock("../server/observability", () => ({
  reportSilentFallback: (...args: unknown[]) => reportSilentFallbackMock(...args),
  warnSilentFallback: vi.fn(),
  APP_URL_FALLBACK: "https://app.soleur.ai",
}));

import { buildToolLabel, SANDBOX_PATH_PATTERNS } from "../server/tool-labels";

beforeEach(() => {
  reportSilentFallbackMock.mockClear();
});

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
    test("maps recognized verb to activity label (FR1)", () => {
      const label = buildToolLabel(
        "Bash",
        { command: "git log --oneline -5" },
        workspacePath,
      );
      expect(label).toBe("Checking git log");
    });

    test("unknown long command collapses to 'Working…' (FR1 safe default)", () => {
      const longCmd = "zzunknownzz " + "a".repeat(100);
      const label = buildToolLabel("Bash", { command: longCmd }, workspacePath);
      // Verb label replaces the command entirely — no leaked text, no ellipsis.
      expect(label).toBe("Working…");
      expect(label).not.toContain(longCmd);
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

// ---------------------------------------------------------------------------
// FR2: Sandbox-path stripping (#2861)
// ---------------------------------------------------------------------------

describe("sandbox path stripping (FR2 #2861)", () => {
  const workspacePath = "/workspaces/abc123def456";
  const sandboxPrefix =
    "/tmp/claude-1000/-workspaces-abc123def456-7e8f9a2b1c3d4e5f6a7b8c9d0e1f2a3b";

  test("SANDBOX_PATH_PATTERNS is exported as an array of RegExp", () => {
    expect(Array.isArray(SANDBOX_PATH_PATTERNS)).toBe(true);
    expect(SANDBOX_PATH_PATTERNS.length).toBeGreaterThan(0);
    for (const p of SANDBOX_PATH_PATTERNS) {
      expect(p).toBeInstanceOf(RegExp);
    }
  });

  test("Read: strips host /workspaces/<uuid>/ prefix", () => {
    const label = buildToolLabel(
      "Read",
      { file_path: `${workspacePath}/knowledge-base/overview/vision.md` },
      workspacePath,
    );
    expect(label).toBe("Reading knowledge-base/overview/vision.md...");
    expect(label).not.toContain(workspacePath);
  });

  test("Bash: sandbox /tmp/claude-<uid>/-workspaces-<uuid>/ prefix never leaks into label", () => {
    const label = buildToolLabel(
      "Bash",
      { command: `cat ${sandboxPrefix}/knowledge-base/vision.md` },
      workspacePath,
    );
    // FR1 maps `cat` to a verb label — the raw command (and any path it
    // carried) is replaced entirely. This is exactly the guarantee: the
    // sandbox prefix cannot leak via the Bash branch at all.
    expect(label).not.toContain("/tmp/claude-");
    expect(label).not.toContain(sandboxPrefix);
    expect(label).toBe("Reading file");
  });

  test("Read: strips sandbox prefix when file_path is sandbox-form", () => {
    const label = buildToolLabel(
      "Read",
      { file_path: `${sandboxPrefix}/knowledge-base/vision.md` },
      workspacePath,
    );
    expect(label).not.toContain("/tmp/claude-");
    expect(label).toContain("knowledge-base/vision.md");
  });

  test("no workspacePath: input is unchanged", () => {
    const label = buildToolLabel(
      "Read",
      { file_path: "/some/absolute/path.md" },
      undefined,
    );
    expect(label).toBe("Reading /some/absolute/path.md...");
  });

  test("idempotency: Read label on already-scrubbed path is stable", () => {
    const raw = `${workspacePath}/knowledge-base/vision.md`;
    const onceLabel = buildToolLabel(
      "Read",
      { file_path: raw },
      workspacePath,
    );
    // Feed the already-scrubbed path back through — stripping a workspace
    // prefix that is no longer present must be a no-op.
    const already = onceLabel.replace(/^Reading /, "").replace(/\.\.\.$/, "");
    const twiceLabel = buildToolLabel(
      "Read",
      { file_path: already },
      workspacePath,
    );
    expect(twiceLabel).toBe(onceLabel);
  });

  test("unmatched /workspaces/ shape fires reportSilentFallback", () => {
    // Host-like prefix that does NOT match workspacePath or canonical patterns.
    buildToolLabel(
      "Bash",
      { command: "cat /workspaces/not-a-uuid-shape/file.md" },
      workspacePath,
    );
    expect(reportSilentFallbackMock).toHaveBeenCalled();
    const [, opts] = reportSilentFallbackMock.mock.calls[0];
    expect(opts).toMatchObject({
      feature: "command-center",
      op: "tool-label-scrub",
    });
  });

  test("unmatched /tmp/claude- shape fires reportSilentFallback", () => {
    buildToolLabel(
      "Bash",
      { command: "cat /tmp/claude-weird-shape/file.md" },
      workspacePath,
    );
    expect(reportSilentFallbackMock).toHaveBeenCalled();
    const [, opts] = reportSilentFallbackMock.mock.calls[0];
    expect(opts).toMatchObject({
      feature: "command-center",
      op: "tool-label-scrub",
    });
  });

  test("matched sandbox prefix does NOT fire reportSilentFallback", () => {
    buildToolLabel(
      "Bash",
      { command: `cat ${sandboxPrefix}/vision.md` },
      workspacePath,
    );
    expect(reportSilentFallbackMock).not.toHaveBeenCalled();
  });

  test("benign content with no path-shape does NOT fire reportSilentFallback", () => {
    buildToolLabel(
      "Bash",
      { command: "git log --oneline -5" },
      workspacePath,
    );
    expect(reportSilentFallbackMock).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// FR1: Bash verb allowlist (#2861)
// ---------------------------------------------------------------------------

describe("Bash verb allowlist (FR1 #2861)", () => {
  const workspacePath = "/workspaces/abc123";

  test.each([
    ["ls", "Exploring project structure"],
    ["ls -la", "Exploring project structure"],
    ["find . -name '*.ts'", "Searching code"],
    ["rg 'pattern' .", "Searching code"],
    ["grep -r 'pattern'", "Searching code"],
    ["cat package.json", "Reading file"],
    ["npm install", "Running package command"],
    ["bun install", "Running package command"],
    ["pnpm run build", "Running package command"],
    ["doppler secrets get X", "Fetching secrets"],
    ["terraform plan", "Running Terraform"],
  ])("maps verb: %s → %s", (command, expected) => {
    const label = buildToolLabel("Bash", { command }, workspacePath);
    expect(label).toBe(expected);
  });

  test("git subcommand produces 'Checking git <sub>'", () => {
    const label = buildToolLabel(
      "Bash",
      { command: "git log --oneline -5" },
      workspacePath,
    );
    expect(label).toBe("Checking git log");
  });

  test("gh subcommand produces 'Querying GitHub'", () => {
    const label = buildToolLabel(
      "Bash",
      { command: "gh issue view 2861" },
      workspacePath,
    );
    expect(label).toBe("Querying GitHub");
  });

  test("env-var assignment before verb is stripped", () => {
    const label = buildToolLabel(
      "Bash",
      { command: "FOO=bar ls" },
      workspacePath,
    );
    expect(label).toBe("Exploring project structure");
  });

  test("pipeline preserves leading verb mapping", () => {
    const label = buildToolLabel(
      "Bash",
      { command: "find . | head" },
      workspacePath,
    );
    expect(label).toBe("Searching code");
  });

  describe("unknown-verb fallbacks fire reportSilentFallback", () => {
    const reportSpy = reportSilentFallbackMock;

    test("sudo verb → Working…", () => {
      const label = buildToolLabel(
        "Bash",
        { command: "sudo ls /etc" },
        workspacePath,
      );
      expect(label).toBe("Working…");
      expect(reportSpy).toHaveBeenCalled();
      const [, opts] = reportSpy.mock.calls[reportSpy.mock.calls.length - 1];
      expect(opts).toMatchObject({
        feature: "command-center",
        op: "tool-label-fallback",
      });
    });

    test("bash -c wrapper → Working…", () => {
      const label = buildToolLabel(
        "Bash",
        { command: 'bash -c "ls /tmp"' },
        workspacePath,
      );
      expect(label).toBe("Working…");
      expect(reportSpy).toHaveBeenCalled();
    });

    test("subshell $(...) → Working…", () => {
      const label = buildToolLabel(
        "Bash",
        { command: "$(ls)" },
        workspacePath,
      );
      expect(label).toBe("Working…");
      expect(reportSpy).toHaveBeenCalled();
    });

    test("fallback reports extra.verb for diagnostics", () => {
      reportSpy.mockClear();
      buildToolLabel(
        "Bash",
        { command: "somerandomverb --flag" },
        workspacePath,
      );
      expect(reportSpy).toHaveBeenCalled();
      const [, opts] = reportSpy.mock.calls[0];
      expect(opts.extra).toBeDefined();
      expect(opts.extra.verb).toBe("somerandomverb");
    });
  });
});
