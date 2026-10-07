import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, basename, resolve, delimiter } from "node:path";
import { buildAgentEnv, type AgentCredential, type BuildAgentEnvOptions } from "../server/agent-env";

// Guard: every plugin PreToolUse hook is classified for the web runtime.
//
// The web Concierge loads the plugin's hooks.json (SDK `plugins:[{type:"local"}]`;
// `settingSources:[]` does not exclude it), so a PreToolUse hook written for a person at a
// terminal also runs inside hosted sessions (ADR-093). Hosted Bash is already sandboxed and
// gated by `permission-callback.ts`, and the web runtime has no `ask` prompt for these hooks
// to reach, so a hook that answers there stalls or blocks the agent. Each such hook reads a
// kill switch that `buildAgentEnv` sets in `AGENT_ENV_OVERRIDES`; this census makes the next
// hook author classify theirs, and the behavioural runs prove the override really silences it.
//
// The population is DERIVED from hooks.json; the registry below classifies it. An unlisted
// hook fails. Behaviour, not the label, is the anchor: a `web-disabled` hook is spawned with
// the env `buildAgentEnv` really produces (the override value is never hand-keyed here) and
// must exit 0 with EMPTY stdout and stderr on a destructive envelope, while the same hook
// with the override removed from that same env must ANSWER (so a silent run is the override's
// doing, not a broken harness). W2 protects customer-machine plugin users, not hosted founders.

const REPO_ROOT = resolve(__dirname, "../../..");
const HOOKS_JSON = join(REPO_ROOT, "plugins/soleur/hooks/hooks.json");
const HOOKS_DIR = join(REPO_ROOT, "plugins/soleur/hooks");

type Envelope = Record<string, unknown>;

type Classification =
  | {
      kind: "web-disabled";
      optOutVar: string;
      // An envelope the hook answers on WITHOUT its opt-out, beyond the shared destructive one
      // (a hook may be a no-op on the destructive Bash call and answer on another shape).
      control: (home: string) => Envelope;
      // True when the hook still answers (degraded) with jq absent from PATH.
      answersWithoutJq: boolean;
    }
  | { kind: "web-active"; reason: string };

const writeTo = (path: string): Envelope => ({ tool_name: "Write", tool_input: { file_path: path } });

const REGISTRY: Record<string, Classification> = {
  "destructive-command-guard.sh": {
    kind: "web-disabled",
    optOutVar: "SOLEUR_DISABLE_DESTRUCTIVE_GUARD",
    control: () => bash("terraform destroy"),
    answersWithoutJq: true,
  },
  "operator-stage-approval.sh": {
    kind: "web-disabled",
    optOutVar: "SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK",
    // A write into the receipt directory is what this hook denies; a plain Bash destroy is a no-op for it.
    control: (home) => writeTo(join(home, ".local", "state", "soleur", "appro" + "vals", "receipt")),
    answersWithoutJq: false,
  },
  "browser-snapshot-credential-guard.sh": {
    kind: "web-active",
    reason: "withholds credential-bearing browser snapshots from the model; a safety control that must stay on in hosted sessions",
  },
};

function bash(command: string): Envelope {
  return { tool_name: "Bash", tool_input: { command } };
}

function preToolUseBasenames(): string[] {
  const parsed = JSON.parse(readFileSync(HOOKS_JSON, "utf8")) as {
    hooks: { PreToolUse?: Array<{ hooks: Array<{ command: string }> }> };
  };
  const names = (parsed.hooks.PreToolUse ?? []).flatMap((g) => g.hooks.map((h) => basename(h.command)));
  return [...new Set(names)];
}

// Hermetic: the spawn env is what buildAgentEnv produced, with PATH/HOME replaced by a minimal
// explicit set. buildAgentEnv's allowlist copies only HOME, PATH and a handful of non-SOLEUR
// names from the ambient env; it never copies a SOLEUR_DISABLE_* value, so an ambient one
// cannot reach the hook (vitest's unstubAllEnvs cannot clear an inherited var either).
const scratch = mkdtempSync(join(tmpdir(), "pretooluse-web-parity-"));
afterAll(() => rmSync(scratch, { recursive: true, force: true }));

const HOME = join(scratch, "home");
const CWD = join(scratch, "cwd");
const NOJQ_BIN = join(scratch, "nojq-bin");
for (const d of [HOME, CWD, NOJQ_BIN]) mkdirSync(d, { recursive: true });

const SYSTEM_PATH = ["/usr/local/bin", "/usr/bin", "/bin"].join(delimiter);

// A PATH holding what the hooks need to start, minus jq, to prove a jq-less host is silent too.
function resolveOnSystemPath(tool: string): string | undefined {
  for (const dir of SYSTEM_PATH.split(delimiter)) {
    const p = join(dir, tool);
    if (existsSync(p)) return p;
  }
  return undefined;
}
const NOJQ_TOOLS = [
  "bash", "cat", "dirname", "basename", "grep", "sed", "tr", "cut", "head", "tail", "readlink",
  "realpath", "perl", "git", "env", "mkdir", "rm", "date", "wc", "sort", "uname",
];
for (const t of NOJQ_TOOLS) {
  const p = resolveOnSystemPath(t);
  if (p) symlinkSync(p, join(NOJQ_BIN, t));
}

const SCHEMES: Array<{ label: string; credential: AgentCredential; tokens?: Record<string, string>; opts?: BuildAgentEnvOptions }> = [
  { label: "api_key", credential: { value: "sk-ant-test", scheme: "api_key" } },
  { label: "oauth_token", credential: { value: "oauth-test", scheme: "oauth_token" } },
  {
    // The widest env buildAgentEnv can hand a run: GH_TOKEN, the raw-git askpass set
    // (GIT_CONFIG_GLOBAL=/dev/null changes what `git` reads inside the guard) and the plugin root.
    label: "api_key + gh token + git askpass + plugin root",
    credential: { value: "sk-ant-test", scheme: "api_key" },
    opts: {
      ghToken: "ghs_test",
      gitAskpassScriptPath: join(CWD, "askpass.sh"),
      gitInstallationToken: "ghs_test",
      pluginPath: HOOKS_DIR.replace(/\/hooks$/, ""),
    },
  },
];

function webEnv(s: (typeof SCHEMES)[number], path: string): Record<string, string> {
  const real = buildAgentEnv(s.credential, s.tokens, s.opts);
  return { ...real, PATH: path, HOME };
}

function runHook(script: string, envelope: Envelope, env: Record<string, string>) {
  const r = spawnSync(env.PATH === NOJQ_BIN ? join(NOJQ_BIN, "bash") : (resolveOnSystemPath("bash") as string), [join(HOOKS_DIR, script)], {
    cwd: CWD,
    input: JSON.stringify({ ...envelope, cwd: CWD, session_id: "web-parity", hook_event_name: "PreToolUse" }),
    env: env as unknown as NodeJS.ProcessEnv,
    encoding: "utf8",
    timeout: 20_000,
  });
  return { rc: r.status, stdout: r.stdout ?? "", stderr: r.stderr ?? "" };
}

function withoutOptOut(env: Record<string, string>, optOutVar: string): Record<string, string> {
  const copy = { ...env };
  delete copy[optOutVar];
  return copy;
}

const DESTRUCTIVE = bash("terraform destroy");

describe("plugin PreToolUse hooks are classified for the web runtime", () => {
  beforeAll(() => {
    // Hard failure, never a skip: the behavioural rows below are meaningless without these.
    for (const tool of ["bash", "jq", "perl", "git"]) {
      expect(resolveOnSystemPath(tool), `${tool} must be on ${SYSTEM_PATH}`).toBeTruthy();
    }
    expect(existsSync(join(NOJQ_BIN, "bash"))).toBe(true);
    expect(existsSync(join(NOJQ_BIN, "jq"))).toBe(false);
  });

  it("every registered PreToolUse hook is classified, and the registry has no stale entry", () => {
    const names = preToolUseBasenames();
    expect(names.length).toBeGreaterThanOrEqual(3);
    for (const name of names) {
      expect(REGISTRY, `PreToolUse hook ${name} has no web classification: add it to REGISTRY as web-disabled (with an AGENT_ENV_OVERRIDES entry) or web-active (with a reason)`).toHaveProperty(name);
    }
    for (const key of Object.keys(REGISTRY)) {
      expect(names, `registry entry ${key} matches no PreToolUse hook`).toContain(key);
    }
  });

  it("every web-active entry states a reason", () => {
    for (const [name, c] of Object.entries(REGISTRY)) {
      if (c.kind === "web-active") expect(c.reason.length, name).toBeGreaterThan(20);
    }
  });

  for (const [name, c] of Object.entries(REGISTRY)) {
    if (c.kind !== "web-disabled") continue;

    it(`${name} (web-disabled): the hook reads ${c.optOutVar}`, () => {
      const text = readFileSync(join(HOOKS_DIR, name), "utf8");
      expect(text.split(c.optOutVar).length - 1, `${name} must read ${c.optOutVar}`).toBeGreaterThanOrEqual(1);
    });

    for (const s of SCHEMES) {
      describe(`${name} under buildAgentEnv [${s.label}]`, () => {
        it("buildAgentEnv sets the opt-out", () => {
          expect(webEnv(s, SYSTEM_PATH)[c.optOutVar], c.optOutVar).toBeTruthy();
        });

        it("exits 0 with no output on a destructive Bash envelope and on the hook's own control envelope", () => {
          const env = webEnv(s, SYSTEM_PATH);
          for (const envelope of [DESTRUCTIVE, c.control(HOME)]) {
            const r = runHook(name, envelope, env);
            expect(r, JSON.stringify(envelope)).toEqual({ rc: 0, stdout: "", stderr: "" });
          }
        });

        it("the same env minus the opt-out DOES answer on the control envelope (the silence is the override's)", () => {
          const env = withoutOptOut(webEnv(s, SYSTEM_PATH), c.optOutVar);
          expect(env[c.optOutVar]).toBeUndefined();
          const r = runHook(name, c.control(HOME), env);
          expect(r.rc).toBe(0);
          expect(r.stdout).toMatch(/"permissionDecision"\s*:\s*"(ask|deny)"/);
        });

        if (c.answersWithoutJq) {
          it("with jq absent: silent under the opt-out, and still answering without it", () => {
            const on = runHook(name, DESTRUCTIVE, webEnv(s, NOJQ_BIN));
            expect(on).toEqual({ rc: 0, stdout: "", stderr: "" });
            const off = runHook(name, DESTRUCTIVE, withoutOptOut(webEnv(s, NOJQ_BIN), c.optOutVar));
            expect(off.rc).toBe(0);
            expect(off.stdout).toMatch(/"permissionDecision"\s*:\s*"(ask|deny)"/);
          });
        }
      });
    }
  }

  it("the control run is not vacuous: a bare env with no opt-out answers on a destructive envelope", () => {
    const bare = { PATH: SYSTEM_PATH, HOME };
    const r = runHook("destructive-command-guard.sh", DESTRUCTIVE, bare);
    expect(r.rc).toBe(0);
    expect(r.stdout).toMatch(/"permissionDecision"\s*:\s*"ask"/);
  });
});
