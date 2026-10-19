import { describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync, mkdirSync } from "fs";
import { tmpdir } from "os";
import { join, resolve } from "path";
import {
  BASH_GUARDS,
  claudeToolName,
  compactionDirective,
  createSetup,
  decideBash,
  decidePermission,
  decisionMessage,
  guardEnvelope,
  parseGuardOutput,
  permissionCommand,
  rulesInjection,
  stripFrontmatter,
  type PermissionEvaluateEvent,
  type ScriptRunner,
  type SetupContext,
} from "../opencode/plugin";

const pluginRoot = resolve(import.meta.dir, "..");
const repoRoot = resolve(pluginRoot, "../..");

/** A script runner that records its calls and replays canned stdout, one entry per call. */
function fakeRunner(...outputs: string[]): {
  runs: { script: string; stdin: string; cwd: string }[];
  run: ScriptRunner;
} {
  let call = 0;
  const runs: { script: string; stdin: string; cwd: string }[] = [];
  const run: ScriptRunner = (script, stdin, cwd) => {
    runs.push({ script, stdin, cwd });
    const stdout = call < outputs.length ? outputs[call] : "";
    call += 1;
    return { status: 0, stdout, stderr: "" };
  };
  return { runs, run };
}

function guardPayload(payload: unknown): string {
  return JSON.stringify(payload);
}

function denial(reason: string): string {
  return guardPayload({
    hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: reason },
  });
}

/** A context whose hooks are captured rather than registered, so they can be driven directly. */
function fakeContext(): {
  ctx: SetupContext;
  handlers: Record<string, (event: any) => unknown>;
  events: { type: string }[];
  subscribed: () => boolean;
} {
  const handlers: Record<string, (event: any) => any> = {};
  const events: { type: string }[] = [];
  let subscribed = false;
  const ctx: SetupContext = {
    location: { directory: process.cwd() },
    permission: { hook: async (name, handler) => void (handlers[`permission:${name}`] = handler) },
    session: { hook: async (name, handler) => void (handlers[`session:${name}`] = handler) },
    event: {
      subscribe: () => {
        subscribed = true;
        return {
          async *[Symbol.asyncIterator]() {
            for (const event of events) yield event;
          },
        };
      },
    },
  };
  return { ctx, handlers, events, subscribed: () => subscribed };
}

describe("opencode plugin — the load shape the runtime requires", () => {
  test("the default export carries an id and a setup function (the V1 named-export form is rejected)", async () => {
    const module = await import("../opencode/plugin");
    expect(module.default.id).toBe("soleur");
    expect(typeof module.default.setup).toBe("function");
  });

  test("the module has no runtime dependency — nothing but node: builtins is imported", () => {
    const source = readFileSync(join(pluginRoot, "opencode/plugin.ts"), "utf8");
    const imports = source.split("\n").filter((line) => /^import\b/.test(line));
    expect(imports.length).toBeGreaterThan(0);
    for (const line of imports) expect(line).toContain('from "node:');
    expect(source).not.toContain('from "@opencode');
  });
});

describe("opencode plugin — the tool map and the guard envelope", () => {
  // `shell` is the measured wire name (§12.1); `bash` is the V1 docs' permission-key spelling.
  // A stale map here is the quietest possible failure: the guards simply never fire.
  test("the measured wire name `shell` maps to Bash, and so does the documented `bash`", () => {
    expect(claudeToolName("shell")).toBe("Bash");
    expect(claudeToolName("bash")).toBe("Bash");
  });

  test("only Bash is decided, so no process is spawned for a call no guard would read", () => {
    for (const tool of ["write", "read", "edit", "grep", "glob", "task", "skill", "webfetch", "execute"]) {
      expect(guardEnvelope(tool, { command: "ls" }, "/project")).toBeUndefined();
    }
    expect(guardEnvelope("shell", { command: "ls" }, "/project")).toBeDefined();
  });

  test("the envelope is the Claude PreToolUse shape the guard scripts parse", () => {
    const parsed = JSON.parse(guardEnvelope("shell", { command: "rm -rf /" }, "/project") as string);
    expect(parsed.hook_event_name).toBe("PreToolUse");
    expect(parsed.tool_name).toBe("Bash");
    expect(parsed.tool_input).toEqual({ command: "rm -rf /" });
    expect(parsed.cwd).toBe("/project");
  });

  test("tool_input is passed through whole, so the guard can still ask on a non-string command", () => {
    const input = { command: { nested: true }, extra: 1 };
    const parsed = JSON.parse(guardEnvelope("shell", input, "/project") as string);
    expect(parsed.tool_input).toEqual(input);
    const absent = JSON.parse(guardEnvelope("shell", undefined, "/project") as string);
    expect(absent.tool_input).toEqual({});
  });

  test("the tool-name map normalises to the names the guard scripts decide on", () => {
    expect(claudeToolName("apply_patch")).toBe("Write");
    expect(claudeToolName("question")).toBe("AskUserQuestion");
    expect(claudeToolName("not-a-real-tool")).toBe("not-a-real-tool");
  });

  test("decideBash runs no guard at all for a non-Bash tool", () => {
    const { runs, run } = fakeRunner();
    expect(decideBash("write", { filePath: "/tmp/x" }, "/project", run)).toBeUndefined();
    expect(runs.length).toBe(0);
  });
});

describe("opencode plugin — a permission event becomes a decision", () => {
  test("a shell call's command is the joined resource list (measured shape: exactly one string)", () => {
    expect(permissionCommand(["echo hello-from-probe"])).toBe("echo hello-from-probe");
    // Joining rather than indexing cannot lose text if a call ever carries more than one.
    expect(permissionCommand(["a", "b"])).toBe("a\nb");
    expect(permissionCommand(["a", 7, null, "b"])).toBe("a\nb");
  });

  test("a shell action decides; any other action spawns nothing", () => {
    const { runs, run } = fakeRunner(denial("nope"));
    expect(decidePermission("shell", ["rm -rf /"], "/project", run)?.decision).toBe("deny");
    expect(runs.length).toBe(1);

    const read = fakeRunner(denial("nope"));
    expect(decidePermission("read", ["probe.txt"], "/project", read.run)).toBeUndefined();
    expect(read.runs.length).toBe(0);

    const glob = fakeRunner(denial("nope"));
    expect(decidePermission("glob", ["**/x"], "/project", glob.run)).toBeUndefined();
    expect(glob.runs.length).toBe(0);
  });

  test("a non-string action is declined rather than thrown on", () => {
    const { runs, run } = fakeRunner(denial("nope"));
    expect(decidePermission(undefined, ["rm -rf /"], "/project", run)).toBeUndefined();
    expect(decidePermission(42, ["rm -rf /"], "/project", run)).toBeUndefined();
    expect(runs.length).toBe(0);
  });

  test("the command reaches the guard in the Claude envelope", () => {
    const { runs, run } = fakeRunner("");
    decidePermission("shell", ["rm -rf /"], "/project", run);
    const envelope = JSON.parse(runs[0].stdin);
    expect(envelope.tool_name).toBe("Bash");
    expect(envelope.tool_input).toEqual({ command: "rm -rf /" });
  });
});

describe("opencode plugin — decisions", () => {
  test("a deny payload is read out of the guard's stdout", () => {
    expect(parseGuardOutput(denial("nope"))).toEqual({ decision: "deny", reason: "nope" });
  });

  test("an ask payload is read as an ask, so it can be delivered as an ask", () => {
    const stdout = guardPayload({
      hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: "confirm" },
    });
    expect(parseGuardOutput(stdout)).toEqual({ decision: "ask", reason: "confirm" });
  });

  test("no output, a non-decision payload and garbage are all 'no decision', never an allow-with-reason", () => {
    expect(parseGuardOutput("")).toBeUndefined();
    expect(parseGuardOutput("   \n")).toBeUndefined();
    expect(parseGuardOutput(guardPayload({ hookSpecificOutput: { hookEventName: "PreToolUse" } }))).toBeUndefined();
    expect(parseGuardOutput("not json at all")).toBeUndefined();
    expect(parseGuardOutput(guardPayload([]))).toBeUndefined();
  });

  test("a diagnostic line before the JSON does not hide the decision", () => {
    expect(parseGuardOutput(`warning: something\n${denial("r")}\n`)).toEqual({ decision: "deny", reason: "r" });
  });

  test("the first guard to decide ends the walk, and its id is recorded", () => {
    const { runs, run } = fakeRunner(denial("first"));
    const decision = decideBash("shell", { command: "x" }, "/project", run);
    expect(decision).toEqual({ guard: BASH_GUARDS[0].id, decision: "deny", reason: "first" });
    expect(runs.length).toBe(1);
    expect(runs[0].script).toBe(join(pluginRoot, BASH_GUARDS[0].script));
  });

  test("a guard that declines falls through to the next one", () => {
    const { runs, run } = fakeRunner("", denial("second"));
    const decision = decideBash("shell", { command: "x" }, "/project", run);
    expect(decision?.guard).toBe(BASH_GUARDS[1].id);
    expect(runs.length).toBe(2);
  });

  test("every guard declining means the call proceeds unchanged", () => {
    const { run } = fakeRunner("", "");
    expect(decideBash("shell", { command: "ls -la" }, "/project", run)).toBeUndefined();
  });

  test("a decision's message names the guard and carries the reason verbatim", () => {
    const message = decisionMessage({ guard: "destructive-command-guard", decision: "deny", reason: "the reason" });
    expect(message).toContain("destructive-command-guard");
    expect(message).toContain("the reason");
  });

  test("an empty reason still produces a message", () => {
    expect(decisionMessage({ guard: "g", decision: "ask", reason: "" }).length).toBeGreaterThan(0);
  });
});

describe("opencode plugin — the guards themselves fire through the plugin (live)", () => {
  test("a recursive delete of / is refused, and a benign listing is not", () => {
    const destructive = decidePermission("shell", ["rm -rf /"], process.cwd());
    expect(destructive?.decision).toBe("deny");
    expect(destructive?.guard).toBe("destructive-command-guard");

    expect(decidePermission("shell", ["ls -la"], process.cwd())).toBeUndefined();
  });

  test("an unrouted agent-browser snapshot is refused by the credential guard", () => {
    const decision = decidePermission("shell", ["agent-browser snapshot"], process.cwd());
    expect(decision?.guard).toBe("browser-snapshot-credential-guard");
    expect(decision?.decision).toBe("deny");
  });

  test("at least one guard reaches `ask`, or the ask half of the contract is untested", () => {
    // The ask path is the one a throw-based binding would have destroyed, so its existence
    // has to be pinned against the real script, not only against a fake runner.
    const asks = ["terraform destroy", "git push --force origin main"].filter(
      (command) => decidePermission("shell", [command], process.cwd())?.decision === "ask",
    );
    expect(asks.length).toBeGreaterThan(0);
  });

  test("every bound guard script exists in the plugin", () => {
    for (const guard of BASH_GUARDS) expect(existsSync(join(pluginRoot, guard.script))).toBe(true);
  });
});

describe("opencode plugin — the guard's decision lands on the permission event", () => {
  test("a deny sets effect=deny and carries the reason in message", async () => {
    const { ctx, handlers } = fakeContext();
    // The real runner: this is the production path, guard script and all.
    await createSetup(undefined, pluginRoot, () => {})(ctx);
    const event: PermissionEvaluateEvent = { action: "shell", resources: ["rm -rf /"], effect: "allow" };
    handlers["permission:evaluate"](event);
    expect(event.effect).toBe("deny");
    expect(event.message).toContain("destructive-command-guard");
  });

  test("an ask stays an ask — the real prompt, not a downgraded refusal", async () => {
    const stdout = guardPayload({
      hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: "confirm this" },
    });
    const { ctx, handlers } = fakeContext();
    await createSetup(fakeRunner(stdout, stdout).run, pluginRoot, () => {})(ctx);
    const event: PermissionEvaluateEvent = { action: "shell", resources: ["terraform apply"], effect: "allow" };
    handlers["permission:evaluate"](event);
    expect(event.effect).toBe("ask");
    expect(event.message).toContain("confirm this");
  });

  test("a call no guard decides is left exactly as the permission ruleset returned it", async () => {
    const { ctx, handlers } = fakeContext();
    await createSetup(fakeRunner("", "").run, pluginRoot, () => {})(ctx);
    const event: PermissionEvaluateEvent = { action: "shell", resources: ["ls -la"], effect: "allow" };
    handlers["permission:evaluate"](event);
    expect(event.effect).toBe("allow");
    expect(event.message).toBeUndefined();
  });

  test("a non-shell action is not touched", async () => {
    const { runs, run } = fakeRunner(denial("nope"));
    const { ctx, handlers } = fakeContext();
    await createSetup(run, pluginRoot, () => {})(ctx);
    const event: PermissionEvaluateEvent = { action: "read", resources: ["probe.txt"], effect: "allow" };
    handlers["permission:evaluate"](event);
    expect(event.effect).toBe("allow");
    expect(runs.length).toBe(0);
  });

  test("the session's own directory is the guard's working directory", async () => {
    const dir = mkdtempSync(join(tmpdir(), "opencode-guard-cwd-"));
    try {
      const { runs, run } = fakeRunner(denial("no"));
      const { ctx, handlers } = fakeContext();
      ctx.location = { directory: dir };
      await createSetup(run, pluginRoot, () => {})(ctx);
      handlers["permission:evaluate"]({ action: "shell", resources: ["rm -rf /"], effect: "allow" });
      expect(runs[0].cwd).toBe(dir);
      expect(JSON.parse(runs[0].stdin).cwd).toBe(dir);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("opencode plugin — the rule corpus and the compaction re-read", () => {
  test("frontmatter is stripped before injection", () => {
    expect(stripFrontmatter("---\nkey: value\n---\n\nBody\n")).toBe("\nBody\n");
    expect(stripFrontmatter("no frontmatter\n")).toBe("no frontmatter\n");
  });

  test("the corpus is read directly, with frontmatter stripped", () => {
    const dir = mkdtempSync(join(tmpdir(), "opencode-rules-"));
    try {
      writeFileSync(join(dir, "AGENTS.rules.md"), "---\ntitle: rules\n---\n\n## Rule\n\nBody\n");
      expect(rulesInjection(dir, fakeRunner().run)).toBe("\n## Rule\n\nBody\n");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("a symlinked corpus is refused — the loader's prompt-injection defense is kept", () => {
    const dir = mkdtempSync(join(tmpdir(), "opencode-rules-"));
    try {
      const target = join(dir, "elsewhere.md");
      writeFileSync(target, "## Rule\n");
      symlinkSync(target, join(dir, "AGENTS.rules.md"));
      expect(rulesInjection(dir, fakeRunner().run)).toBeUndefined();
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("the canonical loader wins when the repository carries it", () => {
    const dir = mkdtempSync(join(tmpdir(), "opencode-rules-"));
    try {
      mkdirSync(join(dir, ".claude", "hooks"), { recursive: true });
      writeFileSync(join(dir, ".claude", "hooks", "session-rules-loader.sh"), "#!/usr/bin/env bash\nexit 0\n");
      writeFileSync(join(dir, "AGENTS.rules.md"), "---\nt: r\n---\n\ndirect\n");
      const { runs, run } = fakeRunner(
        JSON.stringify({
          hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: "from the canonical loader" },
        }),
      );
      expect(rulesInjection(dir, run)).toBe("from the canonical loader");
      expect(runs.length).toBe(1);
      const envelope = JSON.parse(runs[0].stdin);
      expect(envelope.hook_event_name).toBe("SessionStart");
      expect(envelope.cwd).toBe(dir);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("no corpus and no loader is no injection — not an empty one", () => {
    const dir = mkdtempSync(join(tmpdir(), "opencode-rules-"));
    try {
      expect(rulesInjection(dir, fakeRunner().run)).toBeUndefined();
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("the compaction directive names the corpus and says why a summary is not enough", () => {
    expect(compactionDirective()).toContain("AGENTS.rules.md");
    expect(compactionDirective()).toContain("checkpoint summary");
  });

  test("rules are injected once per session, then again after a compaction", async () => {
    const dir = mkdtempSync(join(tmpdir(), "opencode-rules-"));
    try {
      writeFileSync(join(dir, "AGENTS.rules.md"), "---\nt: r\n---\n\nBODY\n");
      const { ctx, handlers } = fakeContext();
      ctx.location = { directory: dir };
      await createSetup(fakeRunner().run, pluginRoot, () => {})(ctx);
      const context = handlers["session:context"];
      const compaction = handlers["session:compaction"];

      const first: { system: { text: string }[]; sessionID: string } = { system: [], sessionID: "ses_1" };
      context(first);
      expect(first.system.length).toBe(1);
      expect(first.system[0].text).toContain("BODY");

      const second: { system: { text: string }[]; sessionID: string } = { system: [], sessionID: "ses_1" };
      context(second);
      expect(second.system.length).toBe(0);

      compaction({ sessionID: "ses_1" });
      const third: { system: { text: string }[]; sessionID: string } = { system: [], sessionID: "ses_1" };
      context(third);
      expect(third.system.length).toBe(2);
      expect(third.system[0].text).toContain("checkpoint summary");
      expect(third.system[1].text).toContain("BODY");

      const fourth: { system: { text: string }[]; sessionID: string } = { system: [], sessionID: "ses_1" };
      context(fourth);
      expect(fourth.system.length).toBe(0);

      const other: { system: { text: string }[]; sessionID: string } = { system: [], sessionID: "ses_2" };
      context(other);
      expect(other.system.length).toBe(1);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("the compaction hook itself injects nothing — its event reaches only the summary call", async () => {
    const { ctx, handlers } = fakeContext();
    await createSetup(fakeRunner().run, pluginRoot, () => {})(ctx);
    const event = { system: [] as { text: string }[], sessionID: "ses_1", messages: [] };
    handlers["session:compaction"](event);
    expect(event.system.length).toBe(0);
  });
});

describe("opencode plugin — the completion observer cannot enforce anything", () => {
  test("session lifecycle events are recorded with the advisory marker; nothing else is", async () => {
    const { ctx, events, subscribed } = fakeContext();
    events.push({ type: "session.inbox.delivered" }, { type: "model.updated" }, { type: "session.execution.started" });
    const lines: string[] = [];
    await createSetup(fakeRunner().run, pluginRoot, (line) => void lines.push(line))(ctx);
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 20));
    expect(subscribed()).toBe(true);
    expect(lines.length).toBe(2);
    for (const line of lines) {
      expect(line).toContain("advisory-completion-marker-not-enforceable");
      expect(line).toContain("session.");
    }
  });

  test("a broken event stream is recorded, not thrown into the session", async () => {
    const ctx = {
      location: { directory: process.cwd() },
      permission: { hook: async () => ({}) },
      session: { hook: async () => ({}) },
      event: {
        subscribe: () => ({
          async *[Symbol.asyncIterator]() {
            throw new Error("stream died");
          },
        }),
      },
    } as unknown as SetupContext;
    const lines: string[] = [];
    await createSetup(fakeRunner().run, pluginRoot, (line) => void lines.push(line))(ctx);
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 20));
    expect(lines.length).toBe(1);
    expect(lines[0]).toContain("event-stream-error");
  });
});

describe("opencode hook disposition ledger", () => {
  const ledger = readFileSync(join(repoRoot, ".claude/hooks/opencode-dispositions.tsv"), "utf8")
    .split("\n")
    .filter((line) => line !== "" && !line.startsWith("#"))
    .map((line) => line.split("\t"));

  test("every row is exactly 7 TAB-separated fields with no empty field", () => {
    expect(ledger.length).toBeGreaterThan(0);
    for (const row of ledger) {
      expect(row.length).toBe(7);
      for (const field of row) expect(field).not.toBe("");
    }
  });

  test("every row carries a disposition from the closed set", () => {
    const allowed = new Set(["bind", "downgraded", "already-covered-by-config", "absent-with-reason"]);
    for (const row of ledger) expect(allowed.has(row[4])).toBe(true);
  });

  test("every guard the plugin binds has exactly one row, and the binding is the measured one", () => {
    for (const guard of BASH_GUARDS) {
      const rows = ledger.filter((row) => row[5].includes(`${guard.id}.sh`));
      expect(rows.length).toBe(1);
      expect(rows[0][1]).toBe('ctx.permission.hook("evaluate")');
      expect(rows[0][4]).toBe("bind");
    }
  });

  test("the surfaces that were considered and rejected are recorded, not left implicit", () => {
    const rows = ledger.map((row) => row.join("\t"));
    // A Stop contract does not exist on this harness (measurement §6.6).
    const stop = rows.filter((row) => row.includes("\tStop\t"));
    expect(stop.length).toBe(1);
    expect(stop[0]).toContain("absent-with-reason");
    // operator-stage-approval needs a rewrite AND an ask, and no single surface offers both.
    const operatorStage = rows.filter((row) => row.includes("operator-stage-approval.sh"));
    expect(operatorStage.length).toBe(1);
    expect(operatorStage[0]).toContain("absent-with-reason");
    // tool.execute.before was measured able to block yet is deliberately unbound.
    expect(rows.some((row) => row.includes("tool.execute.before"))).toBe(true);
  });

  test("the one downgrade that matters is recorded by name", () => {
    const downgrades = ledger.filter((row) => row[4] === "downgraded").map((row) => row.join("\t"));
    expect(downgrades.some((row) => row.includes("compaction"))).toBe(true);
  });

  test("every canonical hook in hooks.json is named somewhere in the ledger", () => {
    const { hooks } = JSON.parse(readFileSync(join(pluginRoot, "hooks/hooks.json"), "utf8")) as {
      hooks: Record<string, { hooks: { command: string }[] }[]>;
    };
    const commands = new Set<string>();
    for (const registrations of Object.values(hooks)) {
      for (const registration of registrations) {
        for (const hook of registration.hooks) {
          const match = hook.command.match(/hooks\/([a-z-]+)\.sh/);
          if (match) commands.add(match[1]);
        }
      }
    }
    const ledgerText = ledger.map((row) => row.join("\t")).join("\n");
    for (const name of commands) expect(ledgerText).toContain(`${name}.sh`);
  });
});
