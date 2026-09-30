import { describe, it, expect, afterAll } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, basename, resolve } from "node:path";
import { buildAgentEnv } from "../server/agent-env";
import { stripStopGateMarkup } from "../server/stop-gate-markup";

// Guard: every plugin Stop hook is classified for the web runtime.
//
// The web Concierge loads the plugin's hooks.json (SDK `plugins:[{type:"local"}]`;
// `settingSources:[]` does not exclude it), so an operator-CLI Stop hook runs
// against end users and can steer the model into leaking internal vocabulary
// (`<stop>OPERATOR-GATE...` replacing a CRM question list). Scope: the `Stop`
// event only — it is the one event that can force an extra model turn and
// rewrite the visible reply. See the ADR-093 amendment (2026-09-30).
//
// The population is DERIVED from hooks.json; the registry below classifies it.
// Behaviour, not the label, is the anchor: `web-disabled` hooks are spawned with the
// env buildAgentEnv really produces, and must still BLOCK without it (the hook is real).
// Classes: `web-disabled` (opt-out proven by behaviour) and `deferred` (an open issue;
// not spawned, because the hook has host or repo side effects). There is no `web-safe`
// class: an empty temp repo proves nothing about a tenant's connected repo, so a hook
// cannot be argued safe from a fixture.

const REPO_ROOT = resolve(__dirname, "../../..");
const HOOKS_JSON = join(REPO_ROOT, "plugins/soleur/hooks/hooks.json");
const HOOKS_DIR = join(REPO_ROOT, "plugins/soleur/hooks");

type Classification =
  | { kind: "web-disabled"; optOutVar: string }
  | { kind: "deferred"; issue: string };

const REGISTRY: Record<string, Classification> = {
  // Reads `.claude/ralph-loop.<pid>.local.md` from the git root of the cwd, which in a
  // web session is the tenant's connected repo (repo-controlled content), and `rm -f`s
  // stale ones. Not spawned here: classification is tracked with the non-Stop hooks.
  "stop-hook.sh": { kind: "deferred", issue: "#9289" },
  "unkept-promise-hook.sh": { kind: "web-disabled", optOutVar: "SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK" },
  // Kills host Chrome processes; whether that can reach another tenant is unverified.
  "browser-cleanup-hook.sh": { kind: "deferred", issue: "#9281" },
};

// The incident's closing, and a differently-phrased promise, so a hook that
// allows one memorised string is not enough.
const CRM_CLOSING =
  "To enter the lead I need:\n- **lastContact**\n- **amount**, with **currency**\n\nYou can paste everything in one message. I'll show you a review before saving, and that review is the only confirmation step.";
const FORM_CLOSING = "Implementing the lead form now.";
const FIXTURES = [CRM_CLOSING, FORM_CLOSING];

function stopHookBasenames(): string[] {
  const parsed = JSON.parse(readFileSync(HOOKS_JSON, "utf8")) as {
    hooks: { Stop?: Array<{ hooks: Array<{ command: string }> }> };
  };
  return (parsed.hooks.Stop ?? []).flatMap((g) => g.hooks.map((h) => basename(h.command)));
}

const scratch = mkdtempSync(join(tmpdir(), "stop-hook-parity-"));
afterAll(() => rmSync(scratch, { recursive: true, force: true }));

function cleanGitEnv(): Record<string, string | undefined> {
  const env: Record<string, string | undefined> = {};
  for (const [k, v] of Object.entries(process.env)) if (!k.startsWith("GIT_")) env[k] = v;
  return env;
}
const REPO = join(scratch, "ws");
spawnSync("mkdir", ["-p", REPO]);
spawnSync("git", ["init", "-q", REPO], { env: cleanGitEnv() as unknown as NodeJS.ProcessEnv });

// Per-script spawn and SUT-marker counts. Only hooks that write the trace marker
// (`unkept-promise-hook.sh`) can be counted; `stop-hook.sh` writes none, so its
// rows rest on rc + verdict alone.
const spawnsBy: Record<string, number> = {};
const ranBy: Record<string, number> = {};

function runHook(script: string, message: string, env: Record<string, string | undefined>): { blocked: boolean; rc: number | null } {
  spawnsBy[script] = (spawnsBy[script] ?? 0) + 1;
  const r = spawnSync("bash", [join(HOOKS_DIR, script)], {
    cwd: REPO,
    input: JSON.stringify({ last_assistant_message: message, stop_hook_active: false, session_id: "parity" }),
    env: { ...env, SOLEUR_HOOK_TRACE: "1" } as unknown as NodeJS.ProcessEnv,
    encoding: "utf8",
    timeout: 20_000,
  });
  if (/^SOLEUR_HOOK_RAN$/m.test(r.stderr ?? "")) ranBy[script] = (ranBy[script] ?? 0) + 1;
  let blocked = false;
  try {
    blocked = JSON.parse(r.stdout || "{}").decision === "block";
  } catch {
    blocked = /"decision"\s*:\s*"block"/.test(r.stdout ?? "");
  }
  return { blocked, rc: r.status };
}

// What the platform really hands the agent process, and the bare baseline.
const WEB_ENV = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
const BASE_ENV: Record<string, string | undefined> = { PATH: process.env.PATH, HOME: process.env.HOME };

describe("plugin Stop hooks are classified for the web runtime", () => {
  it("has bash and jq (hard failure, never a skip)", () => {
    expect(spawnSync("bash", ["--version"]).status).toBe(0);
    expect(spawnSync("jq", ["--version"]).status).toBe(0);
  });

  it("every registered Stop hook is classified, and the registry has no stale entry", () => {
    const parsed = stopHookBasenames();
    expect(parsed.length).toBeGreaterThanOrEqual(1);
    for (const name of parsed) {
      expect(REGISTRY, `Stop hook ${name} has no web classification`).toHaveProperty(name);
    }
    for (const key of Object.keys(REGISTRY)) {
      expect(parsed, `registry entry ${key} matches no Stop hook`).toContain(key);
    }
  });

  it("deferred entries cite an issue number", () => {
    for (const [name, c] of Object.entries(REGISTRY)) {
      if (c.kind === "deferred") expect(c.issue, name).toMatch(/^#\d+$/);
    }
  });

  for (const [name, c] of Object.entries(REGISTRY)) {
    if (c.kind === "web-disabled") {
      it(`${name} (web-disabled): buildAgentEnv sets ${c.optOutVar}=1`, () => {
        expect(WEB_ENV[c.optOutVar]).toBe("1");
      });
      it(`${name} (web-disabled) allows both closings under the web env`, () => {
        for (const msg of FIXTURES) {
          const r = runHook(name, msg, { ...BASE_ENV, ...WEB_ENV });
          expect(r.rc).toBe(0);
          expect(r.blocked, msg).toBe(false);
        }
      });
      it(`${name} still blocks both closings without the opt-out (the hook is real)`, () => {
        for (const msg of FIXTURES) {
          expect(runHook(name, msg, BASE_ENV).blocked, msg).toBe(true);
        }
      });
    }
  }

  it("the web-disabled hooks themselves ran (SUT-written floor, self-contained)", () => {
    // Self-contained: spawns its own fixtures so it neither depends on earlier `it`s
    // having run nor drifts from FIXTURES. Only the hook writes the marker, so a test
    // that never spawns it cannot satisfy this.
    for (const [name, c] of Object.entries(REGISTRY)) {
      if (c.kind !== "web-disabled") continue;
      const before = { spawns: spawnsBy[name] ?? 0, ran: ranBy[name] ?? 0 };
      for (const msg of FIXTURES) {
        runHook(name, msg, { ...BASE_ENV, ...WEB_ENV });
        runHook(name, msg, BASE_ENV);
      }
      expect((spawnsBy[name] ?? 0) - before.spawns, name).toBe(FIXTURES.length * 2);
      expect((ranBy[name] ?? 0) - before.ran, name).toBe(FIXTURES.length * 2);
    }
  });

  it("the runner strip removes the sentinel span in the hook's REAL block reason", () => {
    // Couples the strip to the producer: if the hook's wording changes, the boundary
    // stops matching and this reds instead of both suites staying green on copies.
    const r = spawnSync("bash", [join(HOOKS_DIR, "unkept-promise-hook.sh")], {
      cwd: REPO,
      input: JSON.stringify({ last_assistant_message: FORM_CLOSING, stop_hook_active: false, session_id: "parity" }),
      env: BASE_ENV as unknown as NodeJS.ProcessEnv,
      encoding: "utf8",
      timeout: 20_000,
    });
    const reason: string = JSON.parse(r.stdout).reason;
    expect(reason).toMatch(/<stop>\s*OPERATOR-GATE/i);
    expect(stripStopGateMarkup(reason).hadMarkup).toBe(true);
  });
});
