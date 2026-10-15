import { afterEach, beforeEach, expect, test } from "bun:test";
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { gitFixtureEnv } from "./lib/git-fixture-env";

const sourceRoot = resolve(import.meta.dir, "../../..");
type Registration = { harness: string; event: string; matcher: string; command: string };
type Invocation = { interpreter: string; target: string; args: string[] };
type Registry = { hooks: Record<string, { matcher?: string; hooks: { type: string; command: string }[] }[]> };

function registrations(harness: string, registry: Registry): Registration[] {
  return Object.entries(registry.hooks).flatMap(([event, groups]) =>
    groups.flatMap((group) => group.hooks.filter((hook) => hook.type === "command").map((hook) => ({
      harness, event, matcher: group.matcher ?? "", command: hook.command,
    }))),
  );
}
const codex = registrations("codex", Bun.TOML.parse(readFileSync(join(sourceRoot, ".codex/config.toml"), "utf8")) as Registry);
const devin = registrations("devin", JSON.parse(readFileSync(join(sourceRoot, ".devin/config.json"), "utf8")));
const claude = registrations("claude", JSON.parse(readFileSync(join(sourceRoot, ".claude/settings.json"), "utf8")));
const affected = [...codex, ...devin];

// Frozen from the ORIGINAL registry, before the bootstrap repair. Expectations must never
// be inferred from the command under test: that would bless an interpreter/argv mutation.
const hook = (name: string) => `.claude/hooks/${name}`;
const bash = (name: string): Invocation => ({ interpreter: "bash", target: hook(name), args: [] });
const codexBaseline: Invocation[] = [bash("session-rules-loader.sh"), bash("guardrails.sh")];
const devinBaseline: Invocation[] = [
  bash("session-rules-loader.sh"), bash("supabase-loopback-warn.sh"), bash("memory-backstop-resolve.sh"),
  { interpreter: "bash", target: "scripts/ensure-kb-index.sh", args: ["--soft"] },
  ...[
    "guardrails.sh", "git-commit-secret-scan.sh", "brand-hex-commit-gate.sh", "doppler-secrets-delete-redirect.sh",
    "cla-signed-author-gate.sh", "context-reviewed-gate.sh", "follow-through-directive-gate.sh", "grep-rewrite.sh",
    "kb-domain-allowlist-guard.sh", "no-memory-write.sh", "pkill-self-match-guard.sh", "pre-merge-auto-close-scan.sh",
    "pre-merge-rebase.sh", "prod-write-defer-gate.sh", "ship-net-issue-flow-gate.sh", "ship-operator-step-gate.sh",
    "ship-runbook-ssh-gate.sh", "ship-soak-followthrough-gate.sh", "ship-unpushed-commits-gate.sh", "ship-kb-archive-gate.sh",
    "guardrails.sh", "iac-plan-write-guard.sh", "kb-domain-allowlist-guard.sh", "no-memory-write.sh",
    "new-scheduled-cron-prefer-inngest.sh", "worktree-write-guard.sh",
  ].map(bash),
  { interpreter: "python3", target: hook("security_reminder_hook.py"), args: [] },
  ...["skill-invocation-logger.sh", "post-dispatch-watch-gate.sh", "rule-incident-marker-capture.sh",
    "docs-cli-verification.sh", "phase-surface-hint.sh", "skill-context-queries.sh"].map(bash),
];
const baseline = [...codexBaseline, ...devinBaseline];

function invocation(command: string): Invocation {
  const targets = [...command.matchAll(/\/((?:\.claude\/hooks|scripts|plugins\/soleur\/hooks)\/[\w.-]+)(?:"|(?=\s|$))/g)];
  expect(targets).toHaveLength(1);
  const target = targets[0][1];
  const tail = command.slice(targets[0].index! + targets[0][0].length).trim();
  const prefix = command.slice(0, targets[0].index);
  const explicit = prefix.match(/(?:^|&&\s+)(bash|python3)\s+"[^\n]*$/);
  return { interpreter: explicit?.[1] ?? "direct", target, args: tail ? tail.split(/\s+/) : [] };
}

let temporary: string;
let environment: NodeJS.ProcessEnv;
beforeEach(() => {
  temporary = mkdtempSync(join(tmpdir(), "soleur hook launchers "));
  environment = gitFixtureEnv(temporary);
  for (const key of ["CLAUDE_PROJECT_DIR", "DEVIN_PROJECT_DIR", "BASH_ENV", "ENV", "CDPATH", "PYTHONPATH", "PYTHONHOME"]) delete environment[key];
  environment.HOME = join(temporary, "home");
  mkdirSync(environment.HOME);
  environment.INCIDENTS_REPO_ROOT = temporary;
});
afterEach(() => rmSync(temporary, { recursive: true, force: true }));

function git(cwd: string, ...args: string[]) {
  const result = Bun.spawnSync(["git", "-c", "core.hooksPath=/dev/null", ...args], { cwd, env: environment });
  if (result.exitCode !== 0) throw new Error(result.stderr.toString());
}
function directory(name: string): string {
  const path = join(temporary, name);
  mkdirSync(path, { recursive: true });
  return path;
}
function ordinary(name = "ordinary checkout"): string {
  const root = directory(name);
  git(root, "init", "-q", "-b", "fixture");
  git(root, "commit", "--allow-empty", "-qm", "synthesized fixture");
  return root;
}
function write(path: string, content: string) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content, { mode: 0o755 });
}
function marker(root: string, expected: Invocation, owner: string) {
  const path = join(root, expected.target);
  if (expected.target.endsWith(".py")) {
    write(path, `#!/usr/bin/env python3\nimport os, sys\nsys.stdout.buffer.write((${JSON.stringify(owner + "|" + expected.target + "|python3\n")} + str(len(sys.argv)-1) + "\\n" + " ".join(sys.argv[1:]) + "\\n" + os.getcwd() + "\\n").encode())\nsys.stdout.buffer.write(sys.stdin.buffer.read())\nsys.stderr.write("target stderr\\n")\nsys.exit(int(os.environ.get("HOOK_TARGET_EXIT", "0")))\n`);
  } else {
    write(path, `#!/bin/bash\nprintf '%s\\n' '${owner}|${expected.target}|bash' "$#" "$*" "$PWD"\n/bin/cat\nprintf 'target stderr\\n' >&2\nexit "\${HOOK_TARGET_EXIT:-0}"\n`);
  }
}
const payload = Buffer.from("synthesized input\u0000with bytes\n\n");
function run(registration: Registration, cwd: string, extra: Record<string, string> = {}, stdin = payload) {
  return Bun.spawnSync(["/bin/bash", "-c", registration.command], {
    cwd, env: { ...environment, ...extra }, stdin, timeout: 10000,
  });
}
function expectMarker(registration: Registration, expected: Invocation, cwd: string, owner: string, extra: Record<string, string> = {}, exit = 0) {
  const result = run(registration, cwd, { ...extra, HOOK_TARGET_EXIT: String(exit) });
  expect(result.exitCode).toBe(exit);
  const interpreter = expected.target.endsWith(".py") ? "python3" : "bash";
  const header = `${owner}|${expected.target}|${interpreter}\n${expected.args.length}\n${expected.args.join(" ")}\n${cwd}\n`;
  expect(result.stdout).toEqual(Buffer.concat([Buffer.from(header), payload]));
  expect(result.stderr.toString()).toBe("target stderr\n");
}

test("enumerates every actual affected registration and freezes original invocation semantics", () => {
  expect(codex).toHaveLength(2);
  expect(devin).toHaveLength(37);
  expect(affected.map((entry) => invocation(entry.command))).toEqual(baseline);
  expect(new Set(baseline.map((entry) => entry.target)).size).toBeGreaterThan(25);
});

for (const [index, entry] of affected.entries()) {
  const expected = baseline[index];
  test(`${entry.harness} ${index}: root, nested, linked checkout ownership and bare layouts`, () => {
    const root = ordinary();
    const linked = join(temporary, "linked checkout");
    git(root, "worktree", "add", "-qb", "linked", linked);
    const nested = join(root, "nested directory");
    const linkedNested = join(linked, "nested directory");
    mkdirSync(nested);
    mkdirSync(linkedNested);
    marker(root, expected, "common");
    marker(linked, expected, "linked");
    expectMarker(entry, expected, root, "common");
    expectMarker(entry, expected, nested, "common");
    expectMarker(entry, expected, linked, "linked");
    expectMarker(entry, expected, linkedNested, "linked");
    const soleurRoot = directory("soleur bare root");
    git(soleurRoot, "init", "--bare", "-q", join(soleurRoot, ".git"));
    const conventional = directory("conventional bare.git");
    git(conventional, "init", "--bare", "-q");
    for (const bare of [soleurRoot, conventional]) {
      marker(bare, expected, "bare");
      expectMarker(entry, expected, bare, "bare");
    }
  }, 30000);

  test(`${entry.harness} ${index}: preserves original argv, byte stdin, streams and target statuses`, () => {
    const root = ordinary();
    marker(root, expected, "selected");
    for (const exit of [0, 7, 42]) expectMarker(entry, expected, root, "selected", {}, exit);
  });

  test(`${entry.harness} ${index}: missing linked target never searches common checkout`, () => {
    const root = ordinary();
    const linked = join(temporary, "missing linked target");
    git(root, "worktree", "add", "-qb", "missing", linked);
    marker(root, expected, "forbidden-common");
    const result = run(entry, linked);
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout.toString()).toBe("");
    expect(result.stderr.toString()).toContain(join(linked, expected.target));
  });
}

for (const [index, entry] of devin.entries()) {
  const expected = devinBaseline[index];
  test(`devin ${index}: project override precedence, empty fallthrough and selected-path failure`, () => {
    const root = ordinary();
    const claudeRoot = directory("Claude project override");
    const devinRoot = directory("Devin project override");
    marker(root, expected, "git");
    marker(claudeRoot, expected, "claude");
    marker(devinRoot, expected, "devin");
    expectMarker(entry, expected, root, "claude", { CLAUDE_PROJECT_DIR: claudeRoot, DEVIN_PROJECT_DIR: devinRoot });
    expectMarker(entry, expected, root, "devin", { CLAUDE_PROJECT_DIR: "", DEVIN_PROJECT_DIR: devinRoot });
    expectMarker(entry, expected, root, "git", { CLAUDE_PROJECT_DIR: "", DEVIN_PROJECT_DIR: "" });
    for (const override of [join(temporary, "does not exist"), directory("exists but target missing")]) {
      for (const selected of [
        { CLAUDE_PROJECT_DIR: override, DEVIN_PROJECT_DIR: devinRoot },
        { CLAUDE_PROJECT_DIR: "", DEVIN_PROJECT_DIR: override },
      ]) {
        const result = run(entry, root, selected);
        expect(result.exitCode).not.toBe(0);
        expect(result.stdout.toString()).toBe("");
        expect(result.stderr.toString()).toContain(join(override, expected.target));
      }
    }
  });
}

// Spies intercept the TARGET interpreters, not the outer /bin/bash used by the harness.
// A real successful dispatch proves that the absence assertion is meaningful.
function interpreterSpies() {
  const bin = directory("interpreter spies");
  const log = join(temporary, "interpreter invocations");
  for (const interpreter of ["bash", "python3"]) {
    const binary = Bun.which(interpreter, { PATH: environment.PATH })!;
    write(join(bin, interpreter), `#!/bin/sh\nprintf '%s\\n' '${interpreter}' >> "$HOOK_INTERPRETER_LOG"\nexec '${binary}' "$@"\n`);
  }
  return { PATH: `${bin}:${environment.PATH}`, HOOK_INTERPRETER_LOG: log };
}
for (const [index, entry] of affected.entries()) {
  test(`${entry.harness} ${index}: failed discovery stops BEFORE target interpreter dispatch`, () => {
    const expected = baseline[index];
    const root = ordinary();
    marker(root, expected, "control");
    const spies = interpreterSpies();
    expectMarker(entry, expected, root, "control", spies);
    expect(readFileSync(spies.HOOK_INTERPRETER_LOG, "utf8")).toBe(expected.interpreter + "\n");
    rmSync(spies.HOOK_INTERPRETER_LOG);
    const outside = directory("not a repository");
    const result = run(entry, outside, spies);
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout.toString()).toBe("");
    expect(existsSync(spies.HOOK_INTERPRETER_LOG)).toBe(false);

    // Explicit failure branches: non-bare root-probe error, then bare=true with
    // an absolute-git-dir error. Neither may attempt an empty-root script path.
    const probeBin = directory("git probe stubs");
    for (const bare of ["false", "probe-error", "true"]) {
      const probeLog = join(temporary, "git probe calls");
      rmSync(probeLog, { force: true });
      const bareReply = bare === "probe-error" ? "exit 29" : `printf '%s\\n' '${bare}'`;
      write(join(probeBin, "git"), `#!/bin/sh\nprintf '%s\\n' "$*" >> "$HOOK_PROBE_LOG"\ncase "$*" in\n'rev-parse --show-toplevel') exit 23;;\n'rev-parse --is-bare-repository') ${bareReply};;\n'rev-parse --absolute-git-dir') exit 31;;\n*) exit 99;;\nesac\n`);
      const failed = run(entry, outside, { ...spies, PATH: `${probeBin}:${spies.PATH}`, HOOK_PROBE_LOG: probeLog });
      expect(failed.exitCode).not.toBe(0);
      expect(failed.stdout.toString()).toBe("");
      expect(existsSync(spies.HOOK_INTERPRETER_LOG)).toBe(false);
      expect(readFileSync(probeLog, "utf8").trim().split("\n")).toEqual([
        "rev-parse --show-toplevel", "rev-parse --is-bare-repository",
        ...(bare === "true" ? ["rev-parse --absolute-git-dir"] : []),
      ]);
    }
  });
}

test("bootstrap-discoverability: registered Codex SessionStart executes bare-root hook", () => {
  const entry = codex.find((item) => item.event === "SessionStart")!;
  expect(entry).toBeDefined();
  const root = directory("discoverable bare root");
  git(root, "init", "--bare", "-q", join(root, ".git"));
  marker(root, codexBaseline[0], "discovery");
  expectMarker(entry, codexBaseline[0], root, "discovery");
  console.log("REPO_HOOK_BOOTSTRAP_OK");
});

test("Claude/Grok compatibility uses actual env-based registrations; Cursor remains empty", () => {
  expect(claude.length).toBeGreaterThan(40);
  const root = directory("Claude compat project");
  const cwd = directory("unrelated invocation directory");
  for (const entry of claude) {
    const expected = invocation(entry.command);
    expect(entry.command).toContain("$CLAUDE_PROJECT_DIR");
    marker(root, expected, "compat");
    expectMarker(entry, expected, cwd, "compat", { CLAUDE_PROJECT_DIR: root });
  }
  expect(readFileSync(join(sourceRoot, ".grok/config.toml"), "utf8")).toContain(".claude/settings*.json");
  expect(JSON.parse(readFileSync(join(sourceRoot, "plugins/soleur/cursor/hooks-empty.json"), "utf8"))).toEqual({ hooks: {} });
});

test("actual registered SessionStart and guardrail entrypoints retain safe-envelope responses", () => {
  const root = ordinary();
  // Copy real bodies plus their sibling libraries, without executing source-root hooks.
  cpSync(join(sourceRoot, ".claude/hooks"), join(root, ".claude/hooks"), { recursive: true });
  for (const name of ["session-rules-loader.sh", "guardrails.sh"]) chmodSync(join(root, hook(name)), 0o755);
  write(join(root, "AGENTS.rules.md"), "# AGENTS Rules\n## Hard Rules\n- Synthesized portable rule [id: hr-portable-fixture].\n");
  write(join(root, "AGENTS.md"), "# Index\n## Hard Rules\n- [id: hr-portable-fixture]\n");
  const session = codex.find((entry) => entry.event === "SessionStart")!;
  const rules = run(session, root, {}, Buffer.from(JSON.stringify({ cwd: root, session_id: "portable-fixture" })));
  expect(rules.exitCode).toBe(0);
  const context = JSON.parse(rules.stdout.toString()).hookSpecificOutput;
  expect(context.hookEventName).toBe("SessionStart");
  expect(context.additionalContext).toContain("Synthesized portable rule");
  const guardrail = codex.find((entry) => entry.event === "PreToolUse")!;
  const guard = run(guardrail, root, {}, Buffer.from(JSON.stringify({ tool_name: "Bash", tool_input: { command: "git stash" } })));
  expect(guard.exitCode).toBe(0);
  expect(JSON.parse(guard.stdout.toString()).hookSpecificOutput.permissionDecision).toBe("deny");
});
