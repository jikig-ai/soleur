import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { PLUGIN_ROOT } from "./helpers";

const SKILLS_DIR = resolve(PLUGIN_ROOT, "skills");
const WORKFLOW_PATH = join(SKILLS_DIR, "review/workflows/review.workflow.js");

const MAP_FENCE_START = "<!-- harness-model-map:start -->";
const MAP_FENCE_END = "<!-- harness-model-map:end -->";

describe("saturation fallback execution (Issue #12529)", () => {
  let savedWarn: typeof console.warn;
  let warnings: string[] = [];

  beforeEach(() => {
    savedWarn = console.warn;
    warnings = [];
    console.warn = (...args: unknown[]) => {
      warnings.push(args.map(String).join(" "));
    };
  });

  afterEach(() => {
    console.warn = savedWarn;
  });

  function loadFence(env: Record<string, string>, hostAgent: unknown) {
    const src = readFileSync(WORKFLOW_PATH, "utf-8");
    const start = src.indexOf(MAP_FENCE_START);
    const end = src.indexOf(MAP_FENCE_END);
    const body = src.slice(src.lastIndexOf("\n", start) + 1, end);
    const fn = new Function(
      "process",
      "agent",
      `${body}\nreturn { resolveWorkflowModel, agent };`,
    ) as (proc: unknown, a: unknown) => {
      resolveWorkflowModel: (t: string) => string;
      agent: (p: unknown, o?: Record<string, unknown>) => Promise<unknown> | unknown;
    };
    return fn({ env }, hostAgent);
  }

  test("mechanical step ('standard') falls back to 'cheap' on HTTP 429 and emits sentinel", async () => {
    const callHistory: Array<{ model?: string; attempt: number }> = [];
    let attempts = 0;

    const mockHostAgent = async (_prompt: unknown, opts?: { model?: string }) => {
      attempts++;
      callHistory.push({ model: opts?.model, attempt: attempts });
      if (attempts === 1) {
        const err = new Error("Rate limit exceeded");
        (err as { status?: number }).status = 429;
        throw err;
      }
      return { success: true, finishedOnAttempt: attempts };
    };

    const fence = loadFence({ CLAUDECODE: "1" }, mockHostAgent);

    const result = await fence.agent("classify diff", {
      phase: "Classify",
      label: "classify",
      model: "standard",
    });

    expect(result).toEqual({ success: true, finishedOnAttempt: 2 });
    expect(callHistory.length).toBe(2);
    // Initial call was standard -> sonnet
    expect(callHistory[0].model).toBe("sonnet");
    // Fallback call was cheap -> haiku
    expect(callHistory[1].model).toBe("haiku");

    // Sentinel emission verified
    const sentinel = warnings.find((w) => w.includes("SOLEUR_SATURATION_FALLBACK"));
    expect(sentinel).toBeDefined();
    expect(sentinel).toContain("from=standard");
    expect(sentinel).toContain("to=cheap");
    expect(sentinel).toContain("phase=Classify");
    expect(sentinel).toContain("label=classify");
    expect(sentinel).toContain("model=haiku");
  });

  test("judgment tier ('strong') strictly refuses downgrade on 429 and re-throws error", async () => {
    const callHistory: Array<{ model?: string }> = [];

    const mockHostAgent = async (_prompt: unknown, opts?: { model?: string }) => {
      callHistory.push({ model: opts?.model });
      const err = new Error("429 Too Many Requests");
      (err as { status?: number }).status = 429;
      throw err;
    };

    const fence = loadFence({ CLAUDECODE: "1" }, mockHostAgent);

    // Call with strong tier
    let caughtError: unknown;
    try {
      await fence.agent("security audit", {
        phase: "Review",
        label: "security",
        model: "strong",
      });
    } catch (err) {
      caughtError = err;
    }

    expect(caughtError).toBeDefined();
    expect((caughtError as { status?: number }).status).toBe(429);
    // Only one attempt made, never downgraded to sonnet or haiku
    expect(callHistory.length).toBe(1);
    expect(callHistory[0].model).toBe("opus");
    // No fallback sentinel emitted
    expect(warnings.some((w) => w.includes("SOLEUR_SATURATION_FALLBACK"))).toBe(false);
  });

  test("unpinned / inherit call strictly refuses downgrade on 429 and re-throws error", async () => {
    const callHistory: Array<{ model?: string }> = [];

    const mockHostAgent = async (_prompt: unknown, opts?: { model?: string }) => {
      callHistory.push({ model: opts?.model });
      const err = new Error("resource_exhausted: quota reached");
      throw err;
    };

    const fence = loadFence({ CLAUDECODE: "1" }, mockHostAgent);

    let caughtError: unknown;
    try {
      await fence.agent("general judgment step", {
        phase: "Verify",
        label: "verify:1",
      });
    } catch (err) {
      caughtError = err;
    }

    expect(caughtError).toBeDefined();
    expect(callHistory.length).toBe(1);
    expect(callHistory[0].model).toBeUndefined();
    expect(warnings.some((w) => w.includes("SOLEUR_SATURATION_FALLBACK"))).toBe(false);
  });

  test("non-saturation error (e.g. 500 or SyntaxError) re-throws immediately without fallback", async () => {
    const callHistory: Array<{ model?: string }> = [];

    const mockHostAgent = async (_prompt: unknown, opts?: { model?: string }) => {
      callHistory.push({ model: opts?.model });
      throw new Error("Internal Server Error (500)");
    };

    const fence = loadFence({ CLAUDECODE: "1" }, mockHostAgent);

    let caughtError: unknown;
    try {
      await fence.agent("classify diff", {
        phase: "Classify",
        label: "classify",
        model: "standard",
      });
    } catch (err) {
      caughtError = err;
    }

    expect(caughtError).toBeDefined();
    expect((caughtError as Error).message).toContain("Internal Server Error");
    expect(callHistory.length).toBe(1);
    expect(callHistory[0].model).toBe("sonnet");
    expect(warnings.some((w) => w.includes("SOLEUR_SATURATION_FALLBACK"))).toBe(false);
  });

  test("synchronous host agent 429 also catches and falls back cleanly", () => {
    let attempts = 0;
    const mockHostAgentSync = (_prompt: unknown, opts?: { model?: string }) => {
      attempts++;
      if (attempts === 1) {
        const err = new Error("Rate limit exceeded");
        (err as { status?: number }).status = 429;
        throw err;
      }
      return { syncDone: true, model: opts?.model };
    };

    const fence = loadFence({ CLAUDECODE: "1" }, mockHostAgentSync);

    const result = fence.agent("classify diff", {
      phase: "Classify",
      label: "classify",
      model: "standard",
    });

    expect(result).toEqual({ syncDone: true, model: "haiku" });
    expect(attempts).toBe(2);
    expect(warnings.some((w) => w.includes("SOLEUR_SATURATION_FALLBACK"))).toBe(true);
  });
});
