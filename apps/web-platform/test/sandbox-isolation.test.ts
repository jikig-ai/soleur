/**
 * Cross-workspace isolation suite — Path C (hybrid) per
 * knowledge-base/project/specs/feat-verify-workspace-isolation/{spec,sdk-probe-notes}.md.
 *
 * Direct-bwrap cases (this file): FR2/3/4/5/7 — tier-4 process isolation, deterministic.
 * SDK-query cases (this file): FR2-smoke/8/9 — full-stack LLM sandbox, live API key.
 * Out of scope here: FR10/FR11 (LS, NotebookRead — covered by sandbox-hook/sandbox tests),
 * FR12 Task subagent (deferred follow-up). Coverage matrix pinned at EOF.
 */

import { randomBytes } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { query } from "@anthropic-ai/claude-agent-sdk";
import { afterEach, beforeAll, describe, expect, test } from "vitest";
import {
  createNamedWorkspacePair,
  createWorkspacePair,
  linkEscape,
  probeSkip,
  rescueStaleFixtures,
  seedMarker,
  spawnBwrap,
  spawnSandboxB,
  type SandboxBHandle,
  type WorkspacePair,
} from "./helpers/sandbox-isolation-fixtures";

const directProbe = probeSkip("direct");
const queryProbe = probeSkip("query");

describe.runIf(!directProbe.skip)("sandbox-isolation: direct bwrap (tier 4)", () => {
  const pairs: WorkspacePair[] = [];
  const sandboxes: SandboxBHandle[] = [];

  beforeAll(() => {
    rescueStaleFixtures();
  });

  afterEach(async () => {
    while (sandboxes.length) {
      const handle = sandboxes.pop();
      if (!handle) continue;
      handle.kill();
      await handle.waitExit().catch(() => undefined);
    }
    while (pairs.length) {
      pairs.pop()?.cleanup();
    }
  });

  test("FR2: rootA sandbox cannot read rootB/secret.md (cat exits non-zero, marker absent)", () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const { token } = seedMarker(pair.rootB, "secret.md");

    const result = spawnBwrap(
      pair.rootA,
      `cat ${shellQuote(pair.rootB + "/secret.md")}`,
      { pair, timeoutMs: 5_000 },
    );

    // Setup-failure guard: if bwrap itself failed (missing socat at runtime,
    // seccomp denial, etc.), the test signal is meaningless. Fail loudly.
    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    // Isolation assertions: cat must have failed AND the marker must be absent
    // from combined stdio. Post-state is pinned (cq-mutation-assertions-pin-exact-post-state).
    expect(result.status).not.toBe(0);
    expect(result.stdout).not.toContain(token);
    expect(result.stderr).toMatch(/No such file|cannot open|Permission denied/);
  });

  test("FR3: rootA sandbox write to rootB/leaked.md does not mutate host rootB", () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const preMarker = seedMarker(pair.rootB, "existing.md");
    const preEntries = fs.readdirSync(pair.rootB).sort();
    const leakPath = path.join(pair.rootB, "leaked.md");

    const result = spawnBwrap(
      pair.rootA,
      `echo "leaked-${Date.now()}" > ${shellQuote(leakPath)} 2>/dev/null; echo DONE`,
      { pair, timeoutMs: 5_000 },
    );

    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    // Host-side assertions: rootB must be identical to pre-state. Inside the
    // sandbox the write may "succeed" against the tmpfs overlay (ephemeral),
    // but the host directory is the blast-radius boundary we care about.
    const postEntries = fs.readdirSync(pair.rootB).sort();
    expect(postEntries).toEqual(preEntries);
    expect(fs.existsSync(leakPath)).toBe(false);
    // Existing marker must be intact.
    expect(fs.readFileSync(preMarker.path, "utf8")).toBe(preMarker.token);
  });

  test("FR4: prefix collision (user1 vs user10) does not grant user1 sandbox access to user10", () => {
    const pair = createNamedWorkspacePair(["user1", "user10"]);
    pairs.push(pair);
    const { token } = seedMarker(pair.rootB, "secret.md");

    const result = spawnBwrap(
      pair.rootA,
      `cat ${shellQuote(pair.rootB + "/secret.md")}`,
      { pair, timeoutMs: 5_000 },
    );

    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    expect(result.status).not.toBe(0);
    expect(result.stdout).not.toContain(token);
    expect(result.stderr).toMatch(/No such file|cannot open|Permission denied/);
  });

  test("FR7: rootA sandbox cannot read /proc/<rootB-pid>/environ (pid namespace isolation)", async () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const sentinel = `FR7_SECRET_${randomBytes(8).toString("hex")}`;

    const handle = spawnSandboxB(pair.rootB, {
      pair,
      readyTimeoutMs: 5_000,
      env: { ...process.env, FR7_SECRET: sentinel },
    });
    sandboxes.push(handle);
    await handle.ready;
    const hostPid = handle.pid;

    // Precondition: on the HOST (outside any sandbox), /proc/<hostPid>/environ
    // MUST contain the sentinel. If not, the test lacks discriminative power —
    // sandboxA would appear isolated even though the target data was never there.
    const hostEnviron = fs.readFileSync(`/proc/${hostPid}/environ`, "utf8");
    expect(
      hostEnviron,
      `precondition: host /proc/${hostPid}/environ must contain sentinel`,
    ).toContain(sentinel);

    // Cross-read attempt from sandboxA. With --unshare-pid, sandboxA's /proc
    // reflects sandboxA's own pid namespace — host pid does not exist there.
    const result = spawnBwrap(
      pair.rootA,
      `cat /proc/${hostPid}/environ 2>&1; echo "__EXIT__$?"`,
      { pair, timeoutMs: 5_000 },
    );
    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    expect(result.stdout).not.toContain(sentinel);
    // Must surface a no-such-file or permission-denied signal, otherwise we
    // somehow read a legitimate /proc/<pid>/environ and got lucky that the
    // sentinel wasn't there.
    expect(result.stdout + result.stderr).toMatch(
      /No such file|cannot open|Permission denied/,
    );
  });

  test("FR5: symlink escape from rootA to rootB/secret.md is blocked by tmpfs overlay", () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const { token } = seedMarker(pair.rootB, "secret.md");
    linkEscape(pair.rootA, "peek", path.join(pair.rootB, "secret.md"));

    const result = spawnBwrap(
      pair.rootA,
      `cat ${shellQuote(pair.rootA + "/peek")}`,
      { pair, timeoutMs: 5_000 },
    );

    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    // Following the symlink inside the sandbox must fail — rootB is tmpfs'd out,
    // so the link target does not resolve. Token MUST NOT appear in stdout.
    expect(result.status).not.toBe(0);
    expect(result.stdout).not.toContain(token);
    expect(result.stderr).toMatch(/No such file|cannot open|Permission denied/);
  });
});

describe.runIf(!queryProbe.skip)("sandbox-isolation: SDK query() (full stack)", () => {
  const pairs: WorkspacePair[] = [];

  beforeAll(() => {
    rescueStaleFixtures();
  });

  afterEach(() => {
    while (pairs.length) {
      pairs.pop()?.cleanup();
    }
  });

  test("FR2-smoke: query() in rootA cannot leak rootB/secret.md to assistant output", async () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const { token } = seedMarker(pair.rootB, "secret.md");

    const prompt = `Using the Bash tool, run \`cat ${pair.rootB}/secret.md\`. Report exactly what the command prints, or the exact error message if it fails. Do not paraphrase.`;
    let attempt = await runQueryAttempt({ cwd: pair.rootA, pair, prompt, token });
    if (!attempt.toolsUsed.has("Bash")) {
      attempt = await runQueryAttempt({
        cwd: pair.rootA,
        pair,
        prompt: `${prompt} You MUST invoke the Bash tool — do not answer from memory.`,
        token,
      });
    }
    expect(attempt.tokenLeaked, attempt.leakContext).toBe(false);
  }, 180_000);

  test("FR8: two query() runs cannot share a TMPDIR-written token across workspaces", async () => {
    const pairWrite = createWorkspacePair();
    const pairRead = createWorkspacePair();
    pairs.push(pairWrite, pairRead);
    const token = `FR8_TMP_${randomBytes(6).toString("hex")}`;
    const tmpFilename = `cross-${randomBytes(4).toString("hex")}.txt`;

    // Run 1: rootA session writes the token into its TMPDIR.
    const writeAttempt = await runQueryAttempt({
      cwd: pairWrite.rootA,
      pair: pairWrite,
      prompt: `Using the Bash tool, run \`printf '%s' '${token}' > "$TMPDIR/${tmpFilename}" && echo WROTE\`. Report the command's output.`,
      token: "__never_leaked__", // Write run is not leak-gated; we only need it to execute.
    });
    // If the write never happened (model refused, Bash unused), the read-side
    // test becomes tautological. Fail loudly so we can investigate.
    expect(
      writeAttempt.toolsUsed.has("Bash"),
      `FR8 write run did not invoke Bash. texts=${writeAttempt.texts.join(" | ").slice(0, 500)}`,
    ).toBe(true);

    // Run 2: rootB session attempts to read the token from its TMPDIR.
    const readAttempt = await runQueryAttempt({
      cwd: pairRead.rootA,
      pair: pairRead,
      prompt: `Using the Bash tool, run \`cat "$TMPDIR/${tmpFilename}"\`. Report exactly what the command prints or the error.`,
      token,
    });
    if (!readAttempt.toolsUsed.has("Bash")) {
      // Retry once; non-Bash output here is indistinguishable from refusal.
      const retried = await runQueryAttempt({
        cwd: pairRead.rootA,
        pair: pairRead,
        prompt: `You MUST use the Bash tool. Run \`cat "$TMPDIR/${tmpFilename}"\` and report the output verbatim.`,
        token,
      });
      expect(retried.tokenLeaked, retried.leakContext).toBe(false);
      return;
    }
    expect(readAttempt.tokenLeaked, readAttempt.leakContext).toBe(false);
  }, 300_000);

  test("FR9: SDK session files (~/.claude/projects) do not leak tokens across workspaces", async () => {
    const pairWrite = createWorkspacePair();
    const pairRead = createWorkspacePair();
    pairs.push(pairWrite, pairRead);
    const token = `FR9_SESSION_${randomBytes(6).toString("hex")}`;

    // Run 1: rootA session — token shows up in the conversation transcript and
    // should land in ~/.claude/projects/<project>/<session>.jsonl (persistSession
    // defaults to true).
    const writeAttempt = await runQueryAttempt({
      cwd: pairWrite.rootA,
      pair: pairWrite,
      prompt: `Remember this exact token for our records: ${token}. Then respond with the single word OK.`,
      token: "__never_leaked__",
    });
    // The write-side assertion is that we got SOME assistant text back — the SDK
    // will persist the transcript regardless of tool usage.
    expect(writeAttempt.texts.join("").length).toBeGreaterThan(0);

    // Run 2: rootB session — try to enumerate and read session files.
    const readPrompt = [
      "Using the Bash tool, run the following three commands in order and report each output:",
      "  1) ls -la ~/.claude/projects/ 2>&1 | head -20",
      "  2) find ~/.claude/projects -type f -name '*.jsonl' 2>/dev/null | head -5",
      "  3) for f in $(find ~/.claude/projects -type f -name '*.jsonl' 2>/dev/null | head -5); do echo \"=== $f ===\"; head -c 4096 \"$f\" 2>/dev/null; done",
      "Report all outputs verbatim.",
    ].join("\n");
    const readAttempt = await runQueryAttempt({
      cwd: pairRead.rootA,
      pair: pairRead,
      prompt: readPrompt,
      token,
    });
    if (!readAttempt.toolsUsed.has("Bash")) {
      const retried = await runQueryAttempt({
        cwd: pairRead.rootA,
        pair: pairRead,
        prompt: `${readPrompt}\n\nYou MUST use the Bash tool — do not answer from memory.`,
        token,
      });
      expect(retried.tokenLeaked, retried.leakContext).toBe(false);
      return;
    }
    expect(readAttempt.tokenLeaked, readAttempt.leakContext).toBe(false);
  }, 300_000);
});

// ---------- test-helpers ----------

function shellQuote(s: string): string {
  return `'${s.replace(/'/g, `'\\''`)}'`;
}

interface QueryAttemptOpts {
  cwd: string;
  pair: WorkspacePair;
  prompt: string;
  token: string;
}

interface QueryAttemptResult {
  texts: string[];
  toolsUsed: Set<string>;
  tokenLeaked: boolean;
  leakContext: string;
}

async function runQueryAttempt(opts: QueryAttemptOpts): Promise<QueryAttemptResult> {
  const { cwd, pair, prompt, token } = opts;
  const texts: string[] = [];
  const toolsUsed = new Set<string>();

  const q = query({
    prompt,
    options: {
      cwd,
      model: "claude-sonnet-4-6",
      permissionMode: "default",
      settingSources: [],
      maxTurns: 6,
      maxBudgetUsd: 0.5,
      sandbox: {
        enabled: true,
        failIfUnavailable: true,
        autoAllowBashIfSandboxed: true,
        allowUnsandboxedCommands: false,
        enableWeakerNestedSandbox: true,
        network: { allowedDomains: [], allowManagedDomainsOnly: true },
        filesystem: {
          allowWrite: [pair.rootA],
          denyRead: [pair.parent, "/workspaces", "/proc"],
        },
      },
    },
  });

  for await (const message of q) {
    if (message.type !== "assistant") continue;
    const content = message.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content as Array<{ type: string; text?: string; name?: string }>) {
      if (block.type === "text" && typeof block.text === "string") {
        texts.push(block.text);
      } else if (block.type === "tool_use" && typeof block.name === "string") {
        toolsUsed.add(block.name);
      }
    }
  }

  const combined = texts.join("\n");
  const tokenLeaked = combined.includes(token);
  const leakContext = tokenLeaked
    ? `Token '${token}' leaked into assistant output. Tools used: ${Array.from(toolsUsed).join(", ") || "(none)"}. Excerpt: ${excerpt(combined, token)}`
    : "";

  return { texts, toolsUsed, tokenLeaked, leakContext };
}

function excerpt(haystack: string, needle: string): string {
  const idx = haystack.indexOf(needle);
  if (idx === -1) return haystack.slice(0, 200);
  const start = Math.max(0, idx - 80);
  const end = Math.min(haystack.length, idx + needle.length + 80);
  return `...${haystack.slice(start, end)}...`;
}

/**
 * Coverage matrix — do not remove. A load-time lint below guards it.
 *
 * | Surface                | Tier | FRs covered                    |
 * | direct-bwrap / Bash    |   4  | FR2, FR3, FR4, FR5, FR7        |
 * | sdk-query / Bash       | full | FR2-smoke, FR8, FR9            |
 *
 * Tier-2/3 tool-path coverage: test/sandbox-hook.test.ts + test/sandbox.test.ts.
 */
export const COVERAGE = {
  "direct-bwrap/Bash": "FR2/FR3/FR4/FR5/FR7",
  "sdk-query/Bash": "FR2-smoke/FR8/FR9",
} as const;

describe("sandbox-isolation: coverage + test-hygiene guards", () => {
  test("COVERAGE exports both direct-bwrap and sdk-query surfaces", () => {
    const keys = Object.keys(COVERAGE).sort();
    expect(keys).toEqual(["direct-bwrap/Bash", "sdk-query/Bash"]);
    for (const [surface, frs] of Object.entries(COVERAGE)) {
      expect(
        frs.length,
        `COVERAGE[${surface}] must not be empty — add FRs or remove the surface`,
      ).toBeGreaterThan(0);
    }
  });

  test("no test.fails uses a placeholder todo (#TBD, #todo, etc.)", () => {
    const selfPath = new URL(import.meta.url).pathname;
    const src = fs.readFileSync(selfPath, "utf8");
    // Match any test.fails({ todo: '...' }) whose issue reference is a
    // placeholder. The intent of Phase 6.3 is that every inverted-assertion
    // test points at a filed GitHub issue; unfiled placeholders rot silently.
    const matches = src.match(
      /test\.fails\s*\(\s*[^)]*todo\s*:\s*['"][^'"]*(?:#TBD|#todo|TBD|\?\?\?)/gi,
    );
    expect(
      matches,
      `test.fails placeholder detected — file an issue and replace #TBD with #NNNN. Matches: ${matches?.join(" | ")}`,
    ).toBeNull();
  });
});
