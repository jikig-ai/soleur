// Ref #11076, #9601 — the dark PostToolUse(Bash) framing hook for cron `claude --print` spawns
// (ADR-287 addendum 2026-11-12). The hook annotates `gh` read output with the GitHub
// untrusted-content preamble. It never rewrites output and always exits 0.
//
// Triage for the one-way differential below: RED after an allowlist or `decide()` change means a
// new gh shape reached the boundary; compare with `ghReadVerbOf` before editing either side.

import { spawnSync } from "node:child_process";
import { copyFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { afterAll, describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import * as framing from "@/server/inngest/cron-gh-output-framing-hook.mjs";
import * as containment from "@/server/inngest/cron-bash-allowlist-hook.mjs";
import { GH_FRAME_VERBS, GH_READ_VERBS, ghReadVerbOf, UNTRUSTED_PREAMBLES } from "@/server/untrusted-content";
import { CRON_BASH_ALLOWLISTS } from "@/server/inngest/functions/_cron-claude-eval-substrate";

// vitest cwd is apps/web-platform.
const HOOK = join(process.cwd(), "server/inngest/cron-gh-output-framing-hook.mjs");
const FRAMED = {
  hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: UNTRUSTED_PREAMBLES.github },
};
// Minimal child env: no NODE_OPTIONS, no GH_TOKEN. (ProcessEnv in this app declares NODE_ENV.)
const MIN_ENV = { PATH: "/usr/bin:/bin" } as unknown as NodeJS.ProcessEnv;
const parser = {
  splitSegments: containment.splitSegments,
  tokenize: containment.tokenize,
  normalizeSegmentWhitespace: containment.normalizeSegmentWhitespace,
  MAX_BASH_COMMAND_CHARS: containment.MAX_BASH_COMMAND_CHARS,
};

const tmpDirs: string[] = [];
afterAll(() => {
  for (const d of tmpDirs.splice(0)) rmSync(d, { recursive: true, force: true });
});

const payload = (command: unknown, extra: Record<string, unknown> = {}): string =>
  JSON.stringify({
    hook_event_name: "PostToolUse",
    tool_name: "Bash",
    tool_input: { command },
    tool_response: { stdout: "x", stderr: "" },
    ...extra,
  });

/** Spawn the hook binary with a minimal env (no NODE_OPTIONS, no GH_TOKEN). */
function runBinary(hookPath: string, stdin: string) {
  const r = spawnSync(process.execPath, [hookPath], {
    input: stdin,
    encoding: "utf-8",
    env: MIN_ENV,
    timeout: 10_000,
  });
  return { status: r.status, stdout: r.stdout, stderr: r.stderr };
}

/** A temp dir holding only a copy of the framing hook, plus an optional sibling source. */
function isolatedHook(siblingSource: string | null): string {
  const dir = mkdtempSync(join(tmpdir(), "soleur-framing-hook-"));
  tmpDirs.push(dir);
  const hookPath = join(dir, "cron-gh-output-framing-hook.mjs");
  copyFileSync(HOOK, hookPath);
  if (siblingSource !== null) writeFileSync(join(dir, "cron-bash-allowlist-hook.mjs"), siblingSource, "utf-8");
  return hookPath;
}

describe("AC1 — verb table and preamble parity with server/untrusted-content.ts", () => {
  it("GH_READ_VERBS deep-equals the hosted table", () => {
    expect(framing.GH_READ_VERBS).toStrictEqual(GH_READ_VERBS);
  });

  it("the preamble is byte-equal to UNTRUSTED_PREAMBLES.github", () => {
    expect(framing.GITHUB_UNTRUSTED_PREAMBLE).toBe(UNTRUSTED_PREAMBLES.github);
  });

  it("behavioural census: frameDecision frames `gh <entry> 1` for every GH_FRAME_VERBS entry", () => {
    let framed = 0;
    for (const entry of GH_FRAME_VERBS) {
      expect(framing.frameDecision(payload(`gh ${entry} 1`), parser), entry).toStrictEqual(FRAMED);
      framed++;
    }
    expect(GH_FRAME_VERBS.length).toBeGreaterThan(0);
    expect(framed).toBe(GH_FRAME_VERBS.length);
  });
});

// ---- AC2 rows (CTO D4: a binary group and an in-process group, one literal census) ----------

type BinaryRow = { name: string; stdin: string; frames: boolean; hook?: () => string };
const BINARY_ROWS: BinaryRow[] = [
  { name: "frame: gh issue view 1", stdin: payload("gh issue view 1"), frames: true },
  { name: "frame: gh pr view 12", stdin: payload("gh pr view 12"), frames: true },
  {
    name: "frame: gh api repos/jikig-ai/soleur/issues/1/comments",
    stdin: payload("gh api repos/jikig-ai/soleur/issues/1/comments"),
    frames: true,
  },
  { name: "nothing: gh issue create", stdin: payload("gh issue create --title t --body b"), frames: false },
  { name: "nothing: ls", stdin: payload("ls"), frames: false },
  {
    name: "nothing: non-Bash tool (Read) carrying a gh-read command",
    stdin: JSON.stringify({
      hook_event_name: "PostToolUse",
      tool_name: "Read",
      tool_input: { file_path: "README.md", command: "gh issue view 1" },
    }),
    frames: false,
  },
  { name: "nothing: malformed JSON", stdin: "{not json", frames: false },
  { name: "nothing: empty stdin", stdin: "", frames: false },
  {
    name: "nothing: sibling missing (hook copied alone)",
    stdin: payload("gh issue view 1"),
    frames: false,
    hook: () => isolatedHook(null),
  },
  {
    name: "nothing: sibling throws at load",
    stdin: payload("gh issue view 1"),
    frames: false,
    hook: () => isolatedHook('throw new Error("x");\n'),
  },
];

type InProcessRow = { name: string; raw: string; frames: boolean };
const IN_PROCESS_ROWS: InProcessRow[] = [
  { name: "frame: --repo and --json flags", raw: payload("gh issue view 1 --repo jikig-ai/soleur --json title,body"), frames: true },
  { name: "frame: gh pr view --comments", raw: payload("gh pr view 12 --comments"), frames: true },
  { name: "frame: gh api --paginate", raw: payload("gh api repos/jikig-ai/soleur/pulls/1/comments --paginate"), frames: true },
  { name: "frame: gh issue list --label", raw: payload("gh issue list --label bug"), frames: true },
  { name: "frame: gh run view --log", raw: payload("gh run view 123 --log"), frames: true },
  { name: "frame: second segment", raw: payload("git status && gh issue view 1"), frames: true },
  { name: "frame: quoted argument", raw: payload("gh issue view 'one'"), frames: true },
  { name: "frame: mid-word # is not a comment", raw: payload("gh issue view 1#x"), frames: true },
  { name: "frame: gh search issues", raw: payload("gh search issues foo"), frames: true },
  // Review K2 / C2': containment matches the whitespace-normalised join of the tokens, so these
  // are admitted under a `gh pr view` / `gh issue view` line and must frame.
  { name: "frame, K2: an empty token before the noun", raw: payload('gh "" pr view 1'), frames: true },
  { name: "frame, K2: noun and verb inside one quoted token", raw: payload('gh issue "view 1"'), frames: true },
  { name: "frame, K2: a no-break space inside a token", raw: payload("gh issue\u00a0view 1"), frames: true },
  { name: "nothing: gh issue comment", raw: payload("gh issue comment 1 --body x"), frames: false },
  { name: "nothing: git log", raw: payload("git log -1"), frames: false },
  { name: "nothing: noun outside the table (gh label list)", raw: payload("gh label list"), frames: false },
  { name: "nothing: gh as an argument (echo gh issue view 1)", raw: payload("echo gh issue view 1"), frames: false },
  { name: "nothing: PreToolUse event", raw: payload("gh issue view 1", { hook_event_name: "PreToolUse" }), frames: false },
  { name: "nothing: command is a number", raw: payload(42), frames: false },
  {
    name: "nothing: tool_input missing",
    raw: JSON.stringify({ hook_event_name: "PostToolUse", tool_name: "Bash" }),
    frames: false,
  },
  { name: "nothing: JSON null", raw: "null", frames: false },
  { name: "nothing, prototype key: gh toString x", raw: payload("gh toString x"), frames: false },
  { name: "nothing, prototype key: gh constructor view", raw: payload("gh constructor view"), frames: false },
  { name: "nothing, prototype key: gh __proto__ view", raw: payload("gh __proto__ view"), frames: false },
  { name: "nothing, named gap: ls alias", raw: payload("gh issue ls"), frames: false },
  { name: "nothing, named gap: -R between noun and verb", raw: payload("gh issue -R jikig-ai/soleur view 1"), frames: false },
  { name: "nothing, named gap: --repo= between noun and verb", raw: payload("gh pr --repo=jikig-ai/soleur checks 1"), frames: false },
  { name: "nothing, named gap: path-qualified gh", raw: payload("/usr/bin/gh pr diff 3"), frames: false },
];

describe("AC2 — the hook binary on fixture stdin", () => {
  it.each(BINARY_ROWS)("$name", (row) => {
    const r = runBinary(row.hook ? row.hook() : HOOK, row.stdin);
    expect(r.status).toBe(0);
    expect(r.stderr).toBe("");
    if (row.frames) expect(JSON.parse(r.stdout)).toStrictEqual(FRAMED);
    else expect(r.stdout.trim()).toBe("");
  });
});

describe("AC2 — frameDecision in-process with the real containment parser", () => {
  it.each(IN_PROCESS_ROWS)("$name", (row) => {
    const d = framing.frameDecision(row.raw, parser);
    if (row.frames) expect(d).toStrictEqual(FRAMED);
    else expect(d).toBeNull();
  });

  it("never throws, even when the injected parser throws", () => {
    const throwing = {
      splitSegments: () => {
        throw new Error("boom");
      },
      tokenize: containment.tokenize,
    };
    expect(framing.frameDecision(payload("gh issue view 1"), { ...parser, ...throwing })).toBeNull();
  });
});

describe("AC2 — row census", () => {
  it("both groups together hold the literal declared row count", () => {
    expect(BINARY_ROWS.length + IN_PROCESS_ROWS.length).toBe(37);
    expect(new Set([...BINARY_ROWS, ...IN_PROCESS_ROWS].map((r) => r.name)).size).toBe(37);
  });
});

describe("import has no side effects (CTO D4)", () => {
  it("importing the module reads no stdin and writes no stdout", () => {
    // A child process imports the module with a gh-read payload waiting on stdin. If main()
    // ran on import, it would consume that payload and print the framed object.
    // A real importer file, so process.argv[1] is a path as it is for any importing module.
    const dir = mkdtempSync(join(tmpdir(), "soleur-framing-importer-"));
    tmpDirs.push(dir);
    const importer = join(dir, "importer.mjs");
    writeFileSync(
      importer,
      `await import(${JSON.stringify(pathToFileURL(HOOK).href)}); process.stdout.write("IMPORTED");\n`,
      "utf-8",
    );
    const r = spawnSync(process.execPath, [importer], {
      input: payload("gh issue view 1"),
      encoding: "utf-8",
      env: MIN_ENV,
      timeout: 10_000,
    });
    expect(r.status).toBe(0);
    expect(r.stdout).toBe("IMPORTED");
  });
});

describe("adversarial size (in-process)", () => {
  const MAX = containment.MAX_BASH_COMMAND_CHARS;
  const pad = (suffix: string): string => {
    const unit = " ;  && 'q r' ;  || ";
    let s = "";
    while (s.length + unit.length + suffix.length <= MAX) s += unit;
    s += " ".repeat(MAX - s.length - suffix.length);
    return s + suffix;
  };

  it("a MAX_BASH_COMMAND_CHARS command ending in a gh read frames", () => {
    const cmd = pad("; gh issue view 1");
    expect(cmd.length).toBe(MAX);
    expect(framing.frameDecision(payload(cmd), parser)).toStrictEqual(FRAMED);
  }, 10_000);

  it("one character over the cap emits nothing (containment denied it, so it never ran)", () => {
    const cmd = " " + pad("; gh issue view 1");
    expect(cmd.length).toBe(MAX + 1);
    expect(framing.frameDecision(payload(cmd), parser)).toBeNull();
  }, 10_000);

  it("the same length with an unbalanced quote inside the final gh segment emits nothing", () => {
    const cmd = pad("; gh issue view 'x");
    expect(cmd.length).toBe(MAX);
    expect(framing.frameDecision(payload(cmd), parser)).toBeNull();
  }, 10_000);
});

describe("one-way differential against the hosted ghReadVerbOf on admitted commands (CTO F1, C2)", () => {
  const UNION = [...new Set(Object.values(CRON_BASH_ALLOWLISTS).flat())];
  const WRITE_ROW = "gh issue create --title t --body b --label meta/machinery";
  const CHAIN_ROW = "gh issue comment 1 --body x && gh issue view 1";
  // Over-framing only: the cron hook frames while the hosted side does not.
  const KNOWN_EXTRA = [
    'gh issue comment 1 --body x #"; gh issue view 1; gh issue comment 1 --body y #"',
    "gh issue view 1" + " ".repeat(9000),
  ];
  const derived = UNION.filter((l) => l.startsWith("gh ")).map((l) => {
    if (l === "gh issue create") return WRITE_ROW;
    if (l.startsWith("gh api ")) return `${l}issues/1/comments`;
    return `${l} 1`;
  });
  const DENIED = ["gh issue view 1\ngh issue view 2", "gh issue view 1 | cat", "gh issue view $(echo 1)"];
  const corpus = [...derived, "gh issue view 'one'", 'gh issue view "one two"', CHAIN_ROW, WRITE_ROW, ...KNOWN_EXTRA, ...DENIED];

  const admitted = (cmd: string): boolean =>
    containment.decide({ tool_name: "Bash", tool_input: { command: cmd } }, UNION).hookSpecificOutput
      .permissionDecision === "allow";
  const cronFrames = (cmd: string): boolean => framing.frameDecision(payload(cmd), parser) !== null;
  const hostedRead = (cmd: string): boolean => ghReadVerbOf(cmd).kind === "verb";

  it("every derived, chain, write and known-extra row is admitted; every multiline/pipe/substitution row is denied", () => {
    for (const cmd of [...derived, CHAIN_ROW, WRITE_ROW, ...KNOWN_EXTRA]) expect(admitted(cmd), cmd).toBe(true);
    for (const cmd of DENIED) expect(admitted(cmd), cmd).toBe(false);
  });

  it("hosted read implies cron frame; every cron-only frame is a named known-extra row", () => {
    let nAdmitted = 0;
    let nDenied = 0;
    let nHostedRead = 0;
    for (const cmd of corpus) {
      if (!admitted(cmd)) {
        nDenied++;
        continue;
      }
      nAdmitted++;
      const hosted = hostedRead(cmd);
      const cron = cronFrames(cmd);
      if (hosted) {
        nHostedRead++;
        expect(cron, `hosted reads but cron is silent: ${cmd}`).toBe(true);
      } else if (cron) {
        expect(KNOWN_EXTRA, `cron frames but hosted does not: ${cmd.slice(0, 80)}`).toContain(cmd);
      }
    }
    expect(nAdmitted).toBeGreaterThan(0);
    expect(nDenied).toBeGreaterThan(0);
    expect(nHostedRead).toBeGreaterThan(0);
  });

  it("each known-extra row is admitted and framed on the cron side only", () => {
    for (const cmd of KNOWN_EXTRA) {
      expect(admitted(cmd)).toBe(true);
      expect(cronFrames(cmd)).toBe(true);
      expect(hostedRead(cmd)).toBe(false);
    }
  });

  it("the admitted write row is not framed", () => {
    expect(cronFrames(WRITE_ROW)).toBe(false);
  });
});

describe("allowlist-shape guard: every cron gh line has a shape the framing hook parses (CTO C2, C2')", () => {
  const CANONICAL = new Set([...Object.values(GH_READ_VERBS).flat(), "create", "edit", "comment", "close"]);
  const UNFRAMED_NOUNS_NAMED_IN_ADR = new Set(["label"]);
  it("every gh line in every cron is `gh api <path>/` or literal `gh <noun> <verb>` with a canonical verb", () => {
    let checked = 0;
    for (const [cron, lines] of Object.entries(CRON_BASH_ALLOWLISTS)) {
      for (const line of lines) {
        if (line.split(" ")[0] !== "gh") continue;
        checked++;
        if (/^gh api [^ ]+\/$/.test(line)) continue;
        const m = /^gh ([a-z-]+) ([a-z-]+)$/.exec(line);
        expect(m, `${cron}: ${line}`).not.toBeNull();
        expect(CANONICAL.has(m![2]), `${cron}: ${line} (verb outside the canonical set)`).toBe(true);
        // A noun outside the table is an unframed read; each one must be a named ADR-287 gap.
        expect(
          Object.hasOwn(GH_READ_VERBS, m![1]) || UNFRAMED_NOUNS_NAMED_IN_ADR.has(m![1]),
          `${cron}: ${line} (noun outside GH_READ_VERBS and not a named ADR-287 gap)`,
        ).toBe(true);
      }
    }
    expect(checked).toBeGreaterThanOrEqual(1);
  });
});

describe("cron-bash-allowlist-hook exports consumed by cron-gh-output-framing-hook.mjs", () => {
  it("splitSegments, tokenize and normalizeSegmentWhitespace are exported functions; the cap is a number", () => {
    expect(typeof containment.splitSegments).toBe("function");
    expect(typeof containment.tokenize).toBe("function");
    expect(typeof containment.normalizeSegmentWhitespace).toBe("function");
    expect(typeof containment.MAX_BASH_COMMAND_CHARS).toBe("number");
  });
});
