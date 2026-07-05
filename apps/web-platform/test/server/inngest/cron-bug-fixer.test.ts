// TR9 PR-5 (#4376) — cron-bug-fixer handler unit tests.
//
// AC16 5-case test matrix:
//   (a) issue-selection cascade (p3-low → p2-medium → p1-high) with
//       open-bot-fix-PR skip-list + label/title filters
//   (b) ephemeral workspace scaffold + plugin symlink sentinel
//   (c) spawn argv shape (CLAUDE_CODE_FLAGS + prompt + cwd + GH_TOKEN env)
//   (d) auto-merge gate's 3 safety nets (bot identity, single-file diff,
//       p3-low source) + label assertion
//   (e) Sentry heartbeat URL shape on success/error
//
// Mocks: node:child_process spawn (factory pattern via mockImplementation
// per cq-write-failing-tests-before guidance), node:fs/promises (mkdtemp,
// mkdir, rm, symlink, writeFile), @/server/observability,
// @/server/github/probe-octokit (createProbeOctokit),
// @/server/github-app (generateInstallationToken).

import { EventEmitter } from "node:events";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// --- Module mocks (hoisted by vitest) --------------------------------------

interface FakeChild extends EventEmitter {
  pid?: number;
  killed: boolean;
}

const spawnSpy = vi.fn();
// execFileSync is used by the substrate's spawn-time hook self-test
// (runHookSelfTest). The mock mirrors the REAL relaxed hook's verdict map
// (#5046 PR-2 AC-P2.2): Task/Agent/Skill allow; the unknown-class probe denies.
// #5199 — cron-bug-fixer now GAINS a CRON_BASH_ALLOWLISTS entry, so
// runHookSelfTest fires its `allow[0]` Bash probe (`gh issue view`, a bare
// allowlisted verb) AND its canonical-exfil Bash probe (`cat /proc/self/environ`)
// in the SAME run. The mock must therefore distinguish by Bash COMMAND: allow the
// allowlisted verb (allow[0]) but DENY the exfil payload — a blanket
// `Bash → allow` would make the exfil probe pass-allow → runHookSelfTest throws
// "exfil NOT denied" → reds every handler test. Hook containment of the full
// verb set is covered by the pure decide() tests in
// cron-claude-eval-substrate.test.ts (AC11), not here.
const BASH_EXFIL_DENY = /\/proc\/self\/environ|eval |node -e|\$\(|\| |> \//;
const execFileSyncSpy = vi.fn(
  (_bin?: unknown, _args?: unknown, opts?: { input?: string }) => {
    const payload = JSON.parse(opts?.input ?? "{}") as {
      tool_name?: string;
      tool_input?: { command?: string };
    };
    const bashAllowed =
      payload.tool_name === "Bash" &&
      !BASH_EXFIL_DENY.test(payload.tool_input?.command ?? "");
    const allowed =
      payload.tool_name === "Task" ||
      payload.tool_name === "Agent" ||
      payload.tool_name === "Skill" ||
      bashAllowed;
    return JSON.stringify({
      hookSpecificOutput: { permissionDecision: allowed ? "allow" : "deny" },
    });
  },
);
vi.mock("node:child_process", () => ({
  spawn: spawnSpy,
  execFileSync: execFileSyncSpy,
}));

const mkdtempSpy = vi.fn();
const mkdirSpy = vi.fn();
const rmSpy = vi.fn();
const symlinkSpy = vi.fn();
const writeFileSpy = vi.fn();
vi.mock("node:fs/promises", () => ({
  mkdtemp: mkdtempSpy,
  mkdir: mkdirSpy,
  rm: rmSpy,
  symlink: symlinkSpy,
  writeFile: writeFileSpy,
}));

const existsSyncSpy = vi.fn();
// readFileSync serves runHookSelfTest's settings-registration probe (#5046
// PR-2 AC-P2.2): return a faithful spawn settings.json — the hook registered
// under a `*` matcher — so the structural-inheritance assertion passes.
const readFileSyncSpy = vi.fn(() =>
  JSON.stringify({
    hooks: {
      PreToolUse: [
        {
          matcher: "*",
          hooks: [
            {
              type: "command",
              command:
                "/usr/bin/node /spawn/apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs /spawn/.claude/cron-allow.txt",
            },
          ],
        },
      ],
    },
  }),
);
vi.mock("node:fs", () => ({
  existsSync: existsSyncSpy,
  readFileSync: readFileSyncSpy,
}));

const reportSilentFallbackSpy = vi.fn();
const warnSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  mirrorWarnWithDebounce: vi.fn(),
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: warnSilentFallbackSpy,
}));

const octokitRequestSpy = vi.fn();
const octokitGraphqlSpy = vi.fn();
const createProbeOctokitSpy = vi.fn();
vi.mock("@/server/github/probe-octokit", () => ({
  createProbeOctokit: createProbeOctokitSpy,
  PROBE_ISSUE_OWNER: "jikig-ai",
  PROBE_ISSUE_REPO: "soleur",
}));

const generateInstallationTokenSpy = vi.fn();
vi.mock("@/server/github-app", () => ({
  generateInstallationToken: generateInstallationTokenSpy,
}));

vi.mock("@/server/plugin-path", () => ({
  getPluginPath: () => "/app/shared/plugins/soleur",
  SOLEUR_PLUGIN_PATH_DEFAULT: "/app/shared/plugins/soleur",
}));

// D6 (#5018): cron-bug-fixer is Tier-2-deferred in prod (broad bash + reads
// public issue bodies → can't be a finite allowlist). These flow tests exercise
// the spawn/issue path that Tier-2 (egress firewall) will RESTORE, so force the
// defer guard OFF here; the "Tier-2 deferral" describe block below asserts the
// REAL guard defers. Everything else in _cron-shared (postSentryHeartbeat, the
// output-aware verify) stays real — only deferIfTier2Cron is overridden.
const deferSpy = vi.fn().mockResolvedValue(false);
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("@/server/inngest/functions/_cron-shared")>();
  return { ...actual, deferIfTier2Cron: deferSpy };
});

// --- Helpers ---------------------------------------------------------------

interface MockStep {
  calls: { name: string; result: unknown }[];
  run<T>(name: string, cb: () => Promise<T>): Promise<T>;
}

function makeStep(): MockStep {
  const calls: { name: string; result: unknown }[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      const result = await cb();
      calls.push({ name, result });
      return result;
    },
  };
}

function makeChild(pid = 22222): FakeChild {
  const child = new EventEmitter() as FakeChild;
  child.pid = pid;
  child.killed = false;
  return child;
}

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

const ORIGINAL_ENV = {
  SENTRY_INGEST_DOMAIN: process.env.SENTRY_INGEST_DOMAIN,
  SENTRY_PROJECT_ID: process.env.SENTRY_PROJECT_ID,
  SENTRY_PUBLIC_KEY: process.env.SENTRY_PUBLIC_KEY,
  INNGEST_SIGNING_KEY: process.env.INNGEST_SIGNING_KEY,
  INNGEST_EVENT_KEY: process.env.INNGEST_EVENT_KEY,
  INNGEST_DEV: process.env.INNGEST_DEV,
  RESEND_API_KEY: process.env.RESEND_API_KEY,
  RESEND_RECEIVING_API_KEY: process.env.RESEND_RECEIVING_API_KEY,
  GITHUB_APP_ID: process.env.GITHUB_APP_ID,
  GITHUB_APP_PRIVATE_KEY: process.env.GITHUB_APP_PRIVATE_KEY,
  ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
};

function restoreEnv(key: keyof typeof ORIGINAL_ENV) {
  if (ORIGINAL_ENV[key] === undefined) delete process.env[key];
  else process.env[key] = ORIGINAL_ENV[key];
}

// Default Octokit shape: spawning step.run callbacks rely on
// octokit.request and octokit.graphql.
function defaultOctokit() {
  return { request: octokitRequestSpy, graphql: octokitGraphqlSpy };
}

beforeEach(() => {
  vi.resetModules();
  spawnSpy.mockReset();
  mkdtempSpy.mockReset();
  mkdirSpy.mockReset();
  rmSpy.mockReset();
  symlinkSpy.mockReset();
  writeFileSpy.mockReset();
  existsSyncSpy.mockReset();
  reportSilentFallbackSpy.mockReset();
  warnSilentFallbackSpy.mockReset();
  octokitRequestSpy.mockReset();
  octokitGraphqlSpy.mockReset();
  createProbeOctokitSpy.mockReset();
  generateInstallationTokenSpy.mockReset();
  logger.info.mockReset();
  logger.warn.mockReset();
  logger.error.mockReset();

  // Default healthy fixtures.
  mkdtempSpy.mockResolvedValue("/tmp/soleur-cron-bug-fixer-XXXX");
  mkdirSpy.mockResolvedValue(undefined);
  rmSpy.mockResolvedValue(undefined);
  symlinkSpy.mockResolvedValue(undefined);
  writeFileSpy.mockResolvedValue(undefined);
  existsSyncSpy.mockImplementation((p: string) => {
    // claude binary + plugin sentinel resolve to true by default.
    if (p.endsWith("/node_modules/.bin/claude")) return true;
    if (p.includes(".claude-plugin/plugin.json")) return true;
    // Ephemeral workspace cwd guard (added for TR9 PR-5 P2.1 try/finally
    // refactor — spawnClaudeEval re-checks existsSync(spawnCwd) before
    // spawning to defend against container-restart-between-steps).
    if (p.includes("soleur-cron-bug-fixer-") && p.endsWith("/repo")) return true;
    return false;
  });

  createProbeOctokitSpy.mockImplementation(async () => defaultOctokit());
  generateInstallationTokenSpy.mockResolvedValue("ghs_TESTTOKEN_REDACT_ME");

  // Default Octokit responses.
  octokitRequestSpy.mockImplementation(async (route: string, params: Record<string, unknown>) => {
    if (route === "GET /repos/{owner}/{repo}/installation") {
      return { data: { id: 12345 } };
    }
    if (route === "GET /repos/{owner}/{repo}/pulls") {
      return { data: [] };
    }
    if (route === "GET /repos/{owner}/{repo}/issues") {
      return { data: [] };
    }
    if (route === "POST /repos/{owner}/{repo}/labels") {
      return { data: { name: params.name } };
    }
    if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}") {
      return { data: { user: { login: "app/claude" } } };
    }
    if (route === "GET /repos/{owner}/{repo}/issues/{issue_number}/labels") {
      return { data: [] };
    }
    if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}/files") {
      return { data: [] };
    }
    return { data: {} };
  });

  octokitGraphqlSpy.mockResolvedValue({
    enablePullRequestAutoMerge: {
      pullRequest: { autoMergeRequest: { enabledAt: "2026-05-24T06:00:00Z" } },
    },
  });

  vi.stubGlobal("fetch", vi.fn(async () => new Response("", { status: 200 })));

  process.env.SENTRY_INGEST_DOMAIN = "ingest.sentry.io";
  process.env.SENTRY_PROJECT_ID = "999";
  process.env.SENTRY_PUBLIC_KEY = "abc123def4567890abc123def4567890";
  process.env.INNGEST_SIGNING_KEY =
    "signkey-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.INNGEST_EVENT_KEY =
    "evtkey-test-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  process.env.INNGEST_DEV = "1";
  process.env.RESEND_API_KEY = "re_test_key";
  process.env.RESEND_RECEIVING_API_KEY = "re_test_receiving_key";
  process.env.GITHUB_APP_ID = "12345";
  process.env.GITHUB_APP_PRIVATE_KEY =
    "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----";
  process.env.ANTHROPIC_API_KEY = "sk-ant-test-key";
});

afterEach(() => {
  vi.unstubAllGlobals();
  (Object.keys(ORIGINAL_ENV) as Array<keyof typeof ORIGINAL_ENV>).forEach(
    restoreEnv,
  );
});

async function importHandler() {
  const mod = await import("@/server/inngest/functions/cron-bug-fixer");
  return mod;
}

// Configure spawn to handle BOTH git-clone and claude calls:
// - "git" spawn → emit exit 0 immediately
// - "claude" spawn → emit exit per the `claudeExit` argument
function wireSpawn(claudeExitCode: number | null = 0): FakeChild {
  const claudeChild = makeChild();
  spawnSpy.mockImplementation((cmd: string) => {
    if (cmd === "git") {
      const gitChild = makeChild();
      queueMicrotask(() => gitChild.emit("exit", 0, null));
      return gitChild;
    }
    // assumed claude binary
    queueMicrotask(() => claudeChild.emit("exit", claudeExitCode, null));
    return claudeChild;
  });
  return claudeChild;
}

// ---------------------------------------------------------------------------
// wireOctokit — parameterized factory that replaces ~15 inline
// octokitRequestSpy.mockImplementation blocks across the test suite.
//
// Every parameter is optional; sensible defaults produce the minimal
// "installation + empty issues + empty pulls" shape used by most tests.
// ---------------------------------------------------------------------------
interface WireOctokitOpts {
  /** Issues returned when the request label filter includes "priority/p3-low". */
  p3Issues?: Array<Record<string, unknown>>;
  /** Issues returned when the request label filter includes "priority/p2-medium". */
  p2Issues?: Array<Record<string, unknown>>;
  /** Issues returned when the request label filter includes "priority/p1-high". */
  p1Issues?: Array<Record<string, unknown>>;
  /**
   * PRs returned on the FIRST /pulls call (skip-list build).
   * Defaults to [].
   */
  skipListPRs?: Array<Record<string, unknown>>;
  /**
   * PR returned on the SECOND /pulls call (detect-pr after claude-eval).
   * When undefined, the second /pulls call also returns [].
   */
  detectedPR?: Array<Record<string, unknown>>;
  /** Author login returned by GET /pulls/:pull_number. Default: "app/claude". */
  prAuthor?: string;
  /** Labels on the detected PR (by issue_number = PR number). */
  prLabels?: Array<{ name: string }>;
  /** Files changed in the detected PR. */
  prFiles?: Array<{ filename: string }>;
  /** Labels on the source issue (by issue_number matching the source). */
  issuePriorityLabels?: Array<{ name: string }>;
  /**
   * Source issue number used to distinguish label lookups between the PR
   * and its source issue. Only needed when prLabels or issuePriorityLabels
   * are specified; defaults to undefined (label route returns []).
   */
  sourceIssueNumber?: number;
  /** PR number used for label/files lookups. Defaults to undefined. */
  prNumber?: number;
}

function wireOctokit(opts: WireOctokitOpts = {}): void {
  const {
    p3Issues = [],
    p2Issues = [],
    p1Issues = [],
    skipListPRs = [],
    detectedPR,
    prAuthor = "app/claude",
    prLabels,
    prFiles,
    issuePriorityLabels,
    sourceIssueNumber,
    prNumber,
  } = opts;

  let pullsCallCount = 0;

  octokitRequestSpy.mockImplementation(
    async (
      route: string,
      params: {
        labels?: string;
        pull_number?: number;
        issue_number?: number;
        name?: string;
      },
    ) => {
      if (route === "GET /repos/{owner}/{repo}/installation") {
        return { data: { id: 12345 } };
      }

      if (route === "GET /repos/{owner}/{repo}/pulls") {
        pullsCallCount++;
        if (pullsCallCount === 1) return { data: skipListPRs };
        return { data: detectedPR ?? [] };
      }

      if (route === "GET /repos/{owner}/{repo}/issues") {
        if (params.labels?.includes("priority/p3-low")) return { data: p3Issues };
        if (params.labels?.includes("priority/p2-medium")) return { data: p2Issues };
        if (params.labels?.includes("priority/p1-high")) return { data: p1Issues };
        return { data: [] };
      }

      if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}") {
        return { data: { user: { login: prAuthor } } };
      }

      if (route === "GET /repos/{owner}/{repo}/issues/{issue_number}/labels") {
        if (issuePriorityLabels && params.issue_number === sourceIssueNumber) {
          return { data: issuePriorityLabels };
        }
        if (prLabels && params.issue_number === prNumber) {
          return { data: prLabels };
        }
        return { data: [] };
      }

      if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}/files") {
        return { data: prFiles ?? [] };
      }

      if (route === "POST /repos/{owner}/{repo}/labels") {
        return { data: { name: params.name } };
      }

      return { data: {} };
    },
  );
}

// ===========================================================================
// (a) Issue-selection cascade
// ===========================================================================

describe("cron-bug-fixer — (a) issue-selection cascade", () => {
  it("selects oldest p3-low type/bug issue when no skip conditions hit", async () => {
    const p3Issues = [
      {
        number: 100,
        title: "fix: legitimate p3-low bug",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
    ];
    wireOctokit({ p3Issues });

    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.selectedIssue).toBe(100);
  });

  it("cascades to p2-medium when no qualifying p3-low exists", async () => {
    const p2Issues = [
      {
        number: 200,
        title: "fix: p2 bug",
        labels: [{ name: "priority/p2-medium" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
    ];
    wireOctokit({ p2Issues });

    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.selectedIssue).toBe(200);
  });

  it("skips issues with open bot-fix PRs (skip-list)", async () => {
    const p3Issues = [
      {
        number: 300,
        title: "fix: already has bot-fix PR",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
      {
        number: 301,
        title: "fix: qualifying",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-02T00:00:00Z",
      },
    ];
    wireOctokit({
      p3Issues,
      skipListPRs: [
        {
          number: 999,
          node_id: "PR_existing",
          head: { ref: "bot-fix/300-slug" },
          created_at: "2026-05-01T01:00:00Z",
        },
      ],
      detectedPR: [
        {
          number: 1000,
          node_id: "PR_new",
          head: { ref: "bot-fix/301-fix" },
          created_at: "2026-05-02T01:00:00Z",
        },
      ],
    });

    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.selectedIssue).toBe(301);
  });

  it("filters out title-regex skip patterns (test:, flaky, Content Publisher)", async () => {
    const p3Issues = [
      {
        number: 400,
        title: "test: flake in parallel runs",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
      {
        number: 401,
        title: "[Content Publisher] post LinkedIn update",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-02T00:00:00Z",
      },
      {
        number: 402,
        title: "fix: real bug",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-03T00:00:00Z",
      },
    ];
    wireOctokit({ p3Issues });

    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.selectedIssue).toBe(402);
  });

  it("returns null and emits ?status=ok heartbeat when no qualifying issue at any priority", async () => {
    wireOctokit();

    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.selectedIssue).toBeNull();
    expect(result.ok).toBe(true);

    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
    const sentryCall = fetchMock.mock.calls.find(([url]) =>
      typeof url === "string" && url.includes("/cron/scheduled-bug-fixer/"),
    );
    expect(sentryCall).toBeDefined();
    expect(sentryCall![0] as string).toContain("status=ok");
  });
});

// ===========================================================================
// (b) Ephemeral workspace scaffold + symlink sentinel
// ===========================================================================

describe("cron-bug-fixer — (b) ephemeral workspace + sentinel", () => {
  it("mkdtemp + git clone + .claude/settings.json + sentinel (no plugin symlink — #5091)", async () => {
    const p3Issues = [
      {
        number: 500,
        title: "fix: scaffold check",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
    ];
    wireOctokit({ p3Issues });

    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    await cronBugFixerHandler({ step, logger });

    expect(mkdtempSpy).toHaveBeenCalled();
    const mkdtempCall = mkdtempSpy.mock.calls[0]![0] as string;
    expect(mkdtempCall).toContain("cron-bug-fixer-");

    // git clone --depth=1 happened
    const gitCloneCall = spawnSpy.mock.calls.find(([cmd]) => cmd === "git");
    expect(gitCloneCall).toBeDefined();
    const gitArgs = gitCloneCall![1] as string[];
    expect(gitArgs[0]).toBe("clone");
    expect(gitArgs).toContain("--depth=1");

    // #5091 — NO symlink: the clone's own tracked plugins/soleur is used
    // directly (the old rm+symlink swap made clone-git see every tracked
    // plugin file as deleted — the #5026 destructive-PR contamination).
    expect(symlinkSpy).not.toHaveBeenCalled();

    // .claude/settings.json written
    const settingsWrite = writeFileSpy.mock.calls.find(
      ([p]) => typeof p === "string" && p.endsWith(".claude/settings.json"),
    );
    expect(settingsWrite).toBeDefined();
    const settingsContent = settingsWrite![1] as string;
    // #5018/#5000/#5004 (v3.1) — sandbox disabled (drops the bwrap-userns
    // dependency); containment is the deny-by-default PreToolUse hook registered
    // under a `*` matcher, NOT bypassPermissions (the v1 P1-blocked exfil
    // primitive). See buildCronEvalSettings in _cron-claude-eval-substrate.ts.
    const parsedSettings = JSON.parse(settingsContent);
    expect(parsedSettings).toMatchObject({
      permissions: { allow: [], defaultMode: "default" },
      sandbox: { enabled: false },
    });
    expect(settingsContent).not.toContain("bypassPermissions");
    expect(parsedSettings.hooks.PreToolUse[0].matcher).toBe("*");
    expect(parsedSettings.hooks.PreToolUse[0].hooks[0].command).toContain(
      "cron-bash-allowlist-hook.mjs",
    );

    // #5199 — the per-cron Bash allowlist file is written with bug-fixer's
    // finite, evidence-gated verb set (now a restored Tier-1 cron). allow[0] is
    // the bare `gh issue view` probe verb runHookSelfTest requires.
    const allowWrite = writeFileSpy.mock.calls.find(
      ([p]) => typeof p === "string" && p.endsWith(".claude/cron-allow.txt"),
    );
    expect(allowWrite).toBeDefined();
    const allowLines = (allowWrite![1] as string)
      .split("\n")
      .filter((l) => l.length > 0);
    expect(allowLines[0]).toBe("gh issue view");
    expect(allowLines).toContain("git push");
    expect(allowLines).toContain("./node_modules/.bin/vitest run");
    // F4a: arbitrary-method gh api must NOT be allowlisted.
    expect(allowLines).not.toContain("gh api");
  });

  it("aborts run + emits Sentry status=error when plugin sentinel manifest missing", async () => {
    const p3Issues = [
      {
        number: 510,
        title: "fix: sentinel-check",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
    ];
    wireOctokit({ p3Issues });

    // Sentinel fails: plugin.json does NOT exist on disk after symlink.
    existsSyncSpy.mockImplementation((p: string) => {
      if (p.endsWith("/node_modules/.bin/claude")) return true;
      if (p.includes(".claude-plugin/plugin.json")) return false; // sentinel fail
      return false;
    });

    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.ok).toBe(false);
    expect(reportSilentFallbackSpy).toHaveBeenCalled();
    const setupErr = reportSilentFallbackSpy.mock.calls.find(
      ([, ctx]) => (ctx as { op?: string }).op === "setup-ephemeral-workspace",
    );
    expect(setupErr).toBeDefined();

    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
    const sentryCall = fetchMock.mock.calls.find(([url]) =>
      typeof url === "string" && url.includes("/cron/scheduled-bug-fixer/"),
    );
    expect(sentryCall![0] as string).toContain("status=error");
  });
});

// ===========================================================================
// (c) Spawn argv shape
// ===========================================================================

describe("cron-bug-fixer — (c) spawn argv shape", () => {
  it("spawns claude with --print, --max-turns 55, --, prompt at last index, GH_TOKEN env", async () => {
    const p3Issues = [
      {
        number: 600,
        title: "fix: argv check",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
    ];
    wireOctokit({ p3Issues });

    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    await cronBugFixerHandler({ step, logger });

    const claudeSpawn = spawnSpy.mock.calls.find(
      ([cmd]) => typeof cmd === "string" && cmd.endsWith("/claude"),
    );
    expect(claudeSpawn).toBeDefined();
    const args = claudeSpawn![1] as string[];
    const opts = claudeSpawn![2] as { cwd?: string; env?: NodeJS.ProcessEnv };

    expect(args).toContain("--print");
    expect(args).toContain("--max-turns");
    expect(args).toContain("55");
    expect(args).toContain("--model");
    expect(args).toContain("claude-sonnet-5");

    // Regression guard for #4017 bug 8/8: `--` MUST be immediately before
    // the prompt (the last argument).
    const lastIdx = args.length - 1;
    expect(args[lastIdx - 1]).toBe("--");
    expect(args[lastIdx]).toContain("/soleur:fix-issue 600");
    expect(args[lastIdx]).toContain("--exclude-label ux-audit");

    // cwd is the cloned repo path under ephemeral root
    expect(opts.cwd).toContain("repo");

    // GH_TOKEN env is the installation token, NOT process.env.GH_TOKEN
    expect(opts.env?.GH_TOKEN).toBe("ghs_TESTTOKEN_REDACT_ME");
    // ANTHROPIC_API_KEY propagated (claude needs it)
    expect(opts.env?.ANTHROPIC_API_KEY).toBe("sk-ant-test-key");
    // RESEND_API_KEY NEVER propagated to spawn (CWE-526 allowlist)
    expect(opts.env?.RESEND_API_KEY).toBeUndefined();
    // RESEND_RECEIVING_API_KEY (the #5468 receiving-scoped key) is likewise
    // denylist-by-omission — assert it never leaks into the bug-fixer sandbox.
    expect(opts.env?.RESEND_RECEIVING_API_KEY).toBeUndefined();
  });
});

// ===========================================================================
// (d) Auto-merge gate's 3 safety nets + label assertion
// ===========================================================================

describe("cron-bug-fixer — (d) auto-merge gate safety nets", () => {
  // Common shape: select p3-low issue, claude spawns, PR detected, then
  // gate runs against per-test fixtures.
  const SOURCE_ISSUE = 700;
  const PR_NUMBER = 800;
  const PR_NODE_ID = "PR_kwDOABCDEF";

  function wireOctokitForGate(opts: {
    prAuthor?: string;
    prLabels?: string[];
    prFiles?: { filename: string }[];
    issuePriorityLabels?: string[];
  }) {
    const {
      prAuthor = "app/claude",
      prLabels = ["bot-fix/auto-merge-eligible"],
      prFiles = [{ filename: "apps/web-platform/foo.ts" }],
      issuePriorityLabels = ["priority/p3-low"],
    } = opts;

    wireOctokit({
      p3Issues: [
        {
          number: SOURCE_ISSUE,
          title: "fix: gate test",
          labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
          created_at: "2026-05-01T00:00:00Z",
        },
      ],
      detectedPR: [
        {
          number: PR_NUMBER,
          node_id: PR_NODE_ID,
          head: { ref: `bot-fix/${SOURCE_ISSUE}-slug` },
          created_at: "2026-05-01T02:00:00Z",
        },
      ],
      prAuthor,
      prLabels: prLabels.map((name) => ({ name })),
      prFiles,
      issuePriorityLabels: issuePriorityLabels.map((name) => ({ name })),
      sourceIssueNumber: SOURCE_ISSUE,
      prNumber: PR_NUMBER,
    });
  }

  it("queues auto-merge when bot author + single file + p3-low + label", async () => {
    wireOctokitForGate({});
    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.autoMergeQueued).toBe(true);
    expect(octokitGraphqlSpy).toHaveBeenCalled();
    const gqlCall = octokitGraphqlSpy.mock.calls[0]!;
    const variables = gqlCall[1] as { pullRequestId: string };
    expect(variables.pullRequestId).toBe(PR_NODE_ID);
    const mutationSource = gqlCall[0] as string;
    expect(mutationSource).toContain("enablePullRequestAutoMerge");
    expect(mutationSource).toContain("SQUASH");
  });

  it("blocks auto-merge when PR author is not a bot", async () => {
    wireOctokitForGate({ prAuthor: "human-contributor" });
    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.autoMergeQueued).toBe(false);
    expect(octokitGraphqlSpy).not.toHaveBeenCalled();
  });

  it("blocks auto-merge + relabels when PR has multiple files changed", async () => {
    wireOctokitForGate({
      prFiles: [{ filename: "a.ts" }, { filename: "b.ts" }],
    });
    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.autoMergeQueued).toBe(false);
    expect(octokitGraphqlSpy).not.toHaveBeenCalled();

    // review-required label added
    const addReviewLabel = octokitRequestSpy.mock.calls.find(
      ([route, params]) =>
        route === "POST /repos/{owner}/{repo}/issues/{issue_number}/labels" &&
        Array.isArray((params as { labels?: string[] }).labels) &&
        (params as { labels: string[] }).labels.includes("bot-fix/review-required"),
    );
    expect(addReviewLabel).toBeDefined();
  });

  it("blocks auto-merge when source issue is not p3-low", async () => {
    wireOctokitForGate({ issuePriorityLabels: ["priority/p2-medium"] });
    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.autoMergeQueued).toBe(false);
    expect(octokitGraphqlSpy).not.toHaveBeenCalled();
  });

  it("blocks auto-merge when PR is missing bot-fix/auto-merge-eligible label", async () => {
    wireOctokitForGate({ prLabels: ["bot-fix/review-required"] });
    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.autoMergeQueued).toBe(false);
    expect(octokitGraphqlSpy).not.toHaveBeenCalled();
  });
});

// ===========================================================================
// (e) Sentry heartbeat URL shape
// ===========================================================================

describe("cron-bug-fixer — (e) Sentry heartbeat URL shape", () => {
  it("happy path emits ?status=ok with scheduled-bug-fixer slug", async () => {
    const p3Issues = [
      {
        number: 900,
        title: "fix: heartbeat-ok",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
    ];
    wireOctokit({
      p3Issues,
      detectedPR: [
        {
          number: 901,
          node_id: "PR_n1",
          head: { ref: "bot-fix/900-fix" },
          created_at: "2026-05-01T01:00:00Z",
        },
      ],
      prAuthor: "app/claude",
      prLabels: [{ name: "priority/p3-low" }, { name: "bot-fix/auto-merge-eligible" }],
      prFiles: [{ filename: "fix.ts" }],
      issuePriorityLabels: [{ name: "priority/p3-low" }, { name: "bot-fix/auto-merge-eligible" }],
      sourceIssueNumber: 900,
      prNumber: 901,
    });

    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    await cronBugFixerHandler({ step, logger });

    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
    const sentryCall = fetchMock.mock.calls.find(([url]) =>
      typeof url === "string" && url.includes("/cron/scheduled-bug-fixer/"),
    );
    expect(sentryCall).toBeDefined();
    const url = sentryCall![0] as string;
    expect(url).toContain("ingest.sentry.io");
    expect(url).toContain("/api/999/");
    expect(url).toContain("/cron/scheduled-bug-fixer/");
    expect(url).toContain("status=ok");
  });

  it("claude non-zero exit (no fix landed) → ?status=ok (monitor liveness, not claude success)", async () => {
    // A non-zero claude --print exit (max-turns exhaustion / no-fix terminal
    // state) is the NORMAL best-effort outcome for an autonomous fixer, NOT an
    // operational error. The cron monitor's liveness contract is "the pipeline
    // fired and ran end-to-end without an infrastructure fault" — decoupled
    // from whether claude shipped a PR today. So a clean end-to-end run with a
    // non-zero claude exit and no detected PR must post ?status=ok and the
    // handler must return ok:true. Genuine infra faults keep their strict
    // status=error early-returns (see the (b) sentinel and parse-event tests).
    // Root-cause: H1 in plan 2026-06-01-fix-scheduled-bug-fixer-cron-error-checkin.
    const p3Issues = [
      {
        number: 950,
        title: "fix: heartbeat-ok-on-no-fix",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
    ];
    wireOctokit({ p3Issues });

    wireSpawn(1); // non-zero exit (claude found no fix)
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.ok).toBe(true);
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
    const sentryCall = fetchMock.mock.calls.find(([url]) =>
      typeof url === "string" && url.includes("/cron/scheduled-bug-fixer/"),
    );
    expect(sentryCall).toBeDefined();
    expect(sentryCall![0] as string).toContain("status=ok");
    // No infra-fault breadcrumb on a benign no-fix run — only the (kept-strict)
    // setup-workspace / parse-event paths page as errors.
    const infraReport = reportSilentFallbackSpy.mock.calls.find(([, ctx]) => {
      const op = (ctx as { op?: string }).op;
      return op === "setup-ephemeral-workspace" || op === "parse-event-data";
    });
    expect(infraReport).toBeUndefined();
    // But the no-fix exit IS surfaced as a queryable WARNING-level Sentry event
    // (off-host-visible, non-paging) so a chronically-broken-but-live fixer is
    // diff-able — a bare logger.warn would be invisible without SSH.
    const noFixWarn = warnSilentFallbackSpy.mock.calls.find(
      ([, ctx]) => (ctx as { op?: string }).op === "claude-eval-nonzero-nofix",
    );
    expect(noFixWarn).toBeDefined();
    expect((noFixWarn![1] as { extra?: { selectedIssue?: number } }).extra?.selectedIssue).toBe(950);
  });

  it("claude non-zero exit WITH a detected PR → ?status=ok (final-heartbeat branch; agent opened a PR despite non-zero exit)", async () => {
    // The H1 decoupling must also hold on the FINAL heartbeat branch, reached
    // when claude exits non-zero but detect-pr nonetheless finds a PR the agent
    // opened before exiting. Distinct from the no-PR early-return branch above.
    const p3Issues = [
      {
        number: 970,
        title: "fix: nonzero-with-pr",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
    ];
    wireOctokit({
      p3Issues,
      detectedPR: [
        {
          number: 971,
          node_id: "PR_n970",
          head: { ref: "bot-fix/970-fix" },
          created_at: "2026-05-01T01:00:00Z",
        },
      ],
      prAuthor: "app/claude",
      prLabels: [{ name: "priority/p3-low" }, { name: "bot-fix/auto-merge-eligible" }],
      prFiles: [{ filename: "fix.ts" }],
      issuePriorityLabels: [{ name: "priority/p3-low" }, { name: "bot-fix/auto-merge-eligible" }],
      sourceIssueNumber: 970,
      prNumber: 971,
    });

    wireSpawn(1); // non-zero exit, but a PR was opened
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.ok).toBe(true);
    expect(result.prNumber).toBe(971);
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
    const sentryCall = fetchMock.mock.calls.find(([url]) =>
      typeof url === "string" && url.includes("/cron/scheduled-bug-fixer/"),
    );
    expect(sentryCall).toBeDefined();
    expect(sentryCall![0] as string).toContain("status=ok");
    // The non-zero exit is still surfaced as a queryable warning even though a
    // PR landed (claude exited non-zero but opened a PR before exiting).
    const noFixWarn = warnSilentFallbackSpy.mock.calls.find(
      ([, ctx]) => (ctx as { op?: string }).op === "claude-eval-nonzero-nofix",
    );
    expect(noFixWarn).toBeDefined();
  });

  it("claude-eval aborted by 50-min timeout → ?status=error (FATAL class — monitor flips red; #5674 classify-fatal)", async () => {
    // #5674 reclassifies the AbortController timeout as a FATAL class (folded
    // into resolveBestEffortEvalOk): a chronically-timing-out fixer that ships
    // nothing is an infrastructure-shaped failure the operator must see, so the
    // monitor now flips RED and routine_runs records the reason. This supersedes
    // the prior "timeout stays green" policy (the old claude-eval-timeout
    // breadcrumb is folded into the single op=claude-eval-fatal signal).
    vi.useFakeTimers();
    try {
      const p3Issues = [
        {
          number: 960,
          title: "fix: timeout-stays-green",
          labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
          created_at: "2026-05-01T00:00:00Z",
        },
      ];
      wireOctokit({ p3Issues });

      // git exits 0; claude NEVER exits on its own → forces the substrate's
      // AbortController timeout. Capture the claude child so we can emit its
      // signal-killed exit after the abort fires. Use an implausibly-high pid:
      // the abort handler issues `process.kill(-pid, "SIGTERM")` (a process
      // GROUP signal); the default fake pid (22222) could collide with a real
      // group on a busy CI runner, so pick one no runner will own.
      const FAKE_CLAUDE_PID = 999_999_999;
      let claudeChild: FakeChild | null = null;
      spawnSpy.mockImplementation((cmd: string) => {
        if (cmd === "git") {
          const gitChild = makeChild();
          queueMicrotask(() => gitChild.emit("exit", 0, null));
          return gitChild;
        }
        claudeChild = makeChild(FAKE_CLAUDE_PID);
        return claudeChild; // no auto-exit
      });

      const { cronBugFixerHandler } = await importHandler();
      const step = makeStep();
      const resultPromise = cronBugFixerHandler({ step, logger });

      // Let setup-workspace + claude-eval spawn run so claudeChild exists.
      await vi.advanceTimersByTimeAsync(0);
      // Guard against silent vacuity: if the spawn ordering ever changes so the
      // claude child was never created, fail legibly instead of NPE-ing below.
      expect(claudeChild).not.toBeNull();
      // Cross the 50-min budget → ac.abort() → abortedByTimeout = true, SIGTERM.
      await vi.advanceTimersByTimeAsync(50 * 60 * 1000 + 1);
      // The SIGTERM'd child exits (null code, signal SIGTERM) → spawnResult.ok=false.
      claudeChild!.emit("exit", null, "SIGTERM");
      await vi.advanceTimersByTimeAsync(0);

      const result = await resultPromise;

      expect(result.ok).toBe(false);
      expect(result.errorSummary).toMatch(/timeout/i);
      const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
      const sentryCall = fetchMock.mock.calls.find(([url]) =>
        typeof url === "string" && url.includes("/cron/scheduled-bug-fixer/"),
      );
      expect(sentryCall).toBeDefined();
      expect(sentryCall![0] as string).toContain("status=error");
      // FATAL-class signal — the timeout reports under the single fatal op.
      const fatalReport = reportSilentFallbackSpy.mock.calls.find(
        ([, ctx]) => (ctx as { op?: string }).op === "claude-eval-fatal",
      );
      expect(fatalReport).toBeDefined();
      expect((fatalReport![1] as { extra?: { fatalClass?: string } }).extra?.fatalClass).toBe("timeout");
    } finally {
      vi.useRealTimers();
    }
  });

  it("validates SENTRY_DOMAIN, project, public key — malformed env skips heartbeat", async () => {
    process.env.SENTRY_INGEST_DOMAIN = "ingest.sentry.io/x?leak="; // malformed
    wireOctokit();

    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    await cronBugFixerHandler({ step, logger });

    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
    const sentryCall = fetchMock.mock.calls.find(([url]) =>
      typeof url === "string" && url.includes("/cron/scheduled-bug-fixer/"),
    );
    expect(sentryCall).toBeUndefined();
  });
});

// ===========================================================================
// Registration
// ===========================================================================

describe("cron-bug-fixer — registration", () => {
  it("registers BOTH cron trigger (0 6 * * *) AND manual-trigger event", async () => {
    const { cronBugFixer } = await importHandler();
    const cf = cronBugFixer as unknown as {
      opts?: { triggers?: Array<Record<string, unknown>> };
      triggers?: Array<Record<string, unknown>>;
    };
    const triggers = cf.opts?.triggers ?? cf.triggers ?? [];
    expect(triggers).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ cron: "0 6 * * *" }),
        expect.objectContaining({ event: "cron/bug-fixer.manual-trigger" }),
      ]),
    );
  });

  it("MAX_TURN_DURATION_MS = 50min, KILL_ESCALATION_MS = 5s (exported for parity)", async () => {
    const mod = await importHandler();
    expect(mod.MAX_TURN_DURATION_MS).toBe(50 * 60 * 1000);
    expect(mod.KILL_ESCALATION_MS).toBe(5_000);
  });
});

// ===========================================================================
// Manual-trigger override validation
// ===========================================================================

describe("cron-bug-fixer — manual-trigger override validation", () => {
  it("rejects non-integer issue_number + emits ?status=error", async () => {
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({
      event: { data: { issue_number: "not-a-number" } },
      step,
      logger,
    });

    expect(result.ok).toBe(false);
    expect(reportSilentFallbackSpy).toHaveBeenCalled();
    const ctx = reportSilentFallbackSpy.mock.calls.find(
      ([, c]) => (c as { op?: string }).op === "parse-event-data",
    );
    expect(ctx).toBeDefined();
  });

  it("accepts a positive integer override + bypasses cascade", async () => {
    let issuesCallCount = 0;
    wireOctokit();
    // Layer a secondary spy on top to count issues calls for assertion.
    const baseImpl = octokitRequestSpy.getMockImplementation()!;
    octokitRequestSpy.mockImplementation(async (route: string, params: Record<string, unknown>) => {
      if (route === "GET /repos/{owner}/{repo}/issues") issuesCallCount++;
      return baseImpl(route, params);
    });

    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({
      event: { data: { issue_number: 1234 } },
      step,
      logger,
    });

    expect(result.selectedIssue).toBe(1234);
    // Cascade NOT consulted when override is provided
    expect(issuesCallCount).toBe(0);
  });
});

// ===========================================================================
// (P2.2) Token-redaction sentinel sweep — TR9 PR-5 security HIGH-2
// ===========================================================================
//
// Sentinel: the installation token bytes MUST NEVER reach any observability
// sink (reportSilentFallback, logger.{info,warn,error}, fetch body). The
// production code uses redactToken() defensively, but the strongest signal
// is a "no, really, the bytes never appeared" sweep across all mock calls.

describe("cron-bug-fixer — token-redaction sentinel sweep", () => {
  const SENTINEL_TOKEN = "ghs_TESTTOKEN_REDACT_ME";

  function assertSentinelAbsent() {
    // Stringify every mock-call argument list and grep for the sentinel.
    const allCalls = [
      ...reportSilentFallbackSpy.mock.calls,
      ...logger.info.mock.calls,
      ...logger.warn.mock.calls,
      ...logger.error.mock.calls,
      ...(globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls,
    ];
    const serialized = JSON.stringify(allCalls);
    expect(serialized).not.toContain(SENTINEL_TOKEN);
  }

  it("happy path: sentinel never appears in observability sinks", async () => {
    const p3Issues = [
      {
        number: 1100,
        title: "fix: redact sweep happy",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
    ];
    wireOctokit({ p3Issues });

    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    await cronBugFixerHandler({ step, logger });

    assertSentinelAbsent();
  });

  it("git-clone failure: sentinel never leaks via error message", async () => {
    const p3Issues = [
      {
        number: 1101,
        title: "fix: redact sweep clone-fail",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
    ];
    wireOctokit({ p3Issues });

    // Force git clone to exit non-zero — the resulting Error.message MUST
    // NOT include the token-bearing clone URL.
    spawnSpy.mockImplementation((cmd: string) => {
      const child = makeChild();
      if (cmd === "git") {
        queueMicrotask(() => child.emit("exit", 128, null));
      } else {
        queueMicrotask(() => child.emit("exit", 0, null));
      }
      return child;
    });

    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    await cronBugFixerHandler({ step, logger });

    assertSentinelAbsent();
  });
});

// ===========================================================================
// (P2.3) Workspace cleanup — try/finally teardown
// ===========================================================================

describe("cron-bug-fixer — workspace cleanup (try/finally)", () => {
  it("happy path: teardown rm called with recursive+force on ephemeral root", async () => {
    const p3Issues = [
      {
        number: 1200,
        title: "fix: teardown happy",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
    ];
    wireOctokit({ p3Issues });

    wireSpawn(0);
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    await cronBugFixerHandler({ step, logger });

    // Find the teardown call: rm(ephemeralRoot, {recursive:true, force:true}).
    // (Other rm calls happen during setupEphemeralWorkspace for the plugin
    // dir — those target a path containing "plugins/soleur".)
    const teardownCall = rmSpy.mock.calls.find(([p, opts]) => {
      const path = p as string;
      const o = opts as { recursive?: boolean; force?: boolean } | undefined;
      return (
        path.includes("soleur-cron-bug-fixer-") &&
        !path.includes("plugins/soleur") &&
        o?.recursive === true &&
        o?.force === true
      );
    });
    expect(teardownCall).toBeDefined();
  });

  it("claude-eval non-zero exit: teardown still runs (try/finally)", async () => {
    const p3Issues = [
      {
        number: 1201,
        title: "fix: teardown after claude-fail",
        labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
        created_at: "2026-05-01T00:00:00Z",
      },
    ];
    wireOctokit({ p3Issues });

    wireSpawn(1); // claude exits non-zero
    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    await cronBugFixerHandler({ step, logger });

    const teardownCall = rmSpy.mock.calls.find(([p, opts]) => {
      const path = p as string;
      const o = opts as { recursive?: boolean; force?: boolean } | undefined;
      return (
        path.includes("soleur-cron-bug-fixer-") &&
        !path.includes("plugins/soleur") &&
        o?.recursive === true &&
        o?.force === true
      );
    });
    expect(teardownCall).toBeDefined();
  });
});

// ===========================================================================
// (P2.4) Auto-merge gate idempotency under Inngest replay
// ===========================================================================

describe("cron-bug-fixer — auto-merge gate idempotency", () => {
  const SOURCE_ISSUE = 1300;
  const PR_NUMBER = 1301;
  const PR_NODE_ID = "PR_idempotent";

  function wireOctokitForReplay() {
    const p3Issue = {
      number: SOURCE_ISSUE,
      title: "fix: idempotent replay",
      labels: [{ name: "priority/p3-low" }, { name: "type/bug" }],
      created_at: "2026-05-01T00:00:00Z",
    };
    // Per-handler-invocation call counter: the skip-list build is the first
    // /pulls call in each run, detect-pr is the second. Multiple consecutive
    // handler runs (simulating Inngest replay) reset this via the modulo
    // pattern below — the bot-fix PR is "already open" on the second run's
    // skip-list scan too, so selectIssue would return null. Instead we
    // return the bot-fix PR ONLY on detect-pr calls (odd-indexed within
    // a 2-call cycle), and an empty list on skip-list scans.
    let pullsCallCount = 0;
    octokitRequestSpy.mockImplementation(async (route: string, params: { labels?: string; issue_number?: number }) => {
      if (route === "GET /repos/{owner}/{repo}/installation") return { data: { id: 12345 } };
      if (route === "GET /repos/{owner}/{repo}/pulls") {
        pullsCallCount++;
        // Even-indexed call (1st of each run) = skip-list scan → empty
        if (pullsCallCount % 2 === 1) return { data: [] };
        return {
          data: [
            {
              number: PR_NUMBER,
              node_id: PR_NODE_ID,
              head: { ref: `bot-fix/${SOURCE_ISSUE}-fix` },
              created_at: "2026-05-01T01:00:00Z",
            },
          ],
        };
      }
      if (route === "GET /repos/{owner}/{repo}/issues") {
        if (params.labels?.includes("priority/p3-low")) return { data: [p3Issue] };
        return { data: [] };
      }
      if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}") {
        return { data: { user: { login: "app/claude" } } };
      }
      if (route === "GET /repos/{owner}/{repo}/issues/{issue_number}/labels") {
        if (params.issue_number === SOURCE_ISSUE) {
          return { data: [{ name: "priority/p3-low" }] };
        }
        if (params.issue_number === PR_NUMBER) {
          return { data: [{ name: "bot-fix/auto-merge-eligible" }] };
        }
        return { data: [] };
      }
      if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}/files") {
        return { data: [{ filename: "fix.ts" }] };
      }
      return { data: {} };
    });
  }

  it("returns queued: true twice when mutation succeeds idempotently (stable enabledAt)", async () => {
    wireOctokitForReplay();
    wireSpawn(0);

    // GraphQL returns the same enabledAt on both calls (GitHub's documented
    // idempotent behavior — repeated enable returns the original timestamp).
    const stableEnabledAt = "2026-05-24T06:00:00Z";
    octokitGraphqlSpy.mockResolvedValue({
      enablePullRequestAutoMerge: {
        pullRequest: { autoMergeRequest: { enabledAt: stableEnabledAt } },
      },
    });

    const { cronBugFixerHandler } = await importHandler();
    const step1 = makeStep();
    const r1 = await cronBugFixerHandler({ step: step1, logger });
    expect(r1.autoMergeQueued).toBe(true);

    // Reset only the run-scoped spies that should drift between runs;
    // keep the octokit wiring (Inngest replay re-invokes step.run callbacks
    // against the same external state).
    const step2 = makeStep();
    const r2 = await cronBugFixerHandler({ step: step2, logger });
    expect(r2.autoMergeQueued).toBe(true);
  });

  it("treats 'auto-merge is already enabled' GraphQL error as queued: true", async () => {
    wireOctokitForReplay();
    wireSpawn(0);

    octokitGraphqlSpy.mockRejectedValueOnce(
      new Error("Pull request Auto merge is already enabled"),
    );

    const { cronBugFixerHandler } = await importHandler();
    const step = makeStep();
    const result = await cronBugFixerHandler({ step, logger });

    expect(result.autoMergeQueued).toBe(true);
    // The idempotent path MUST NOT emit a Sentry breadcrumb for the
    // expected-replay error (otherwise replays would inflate noise).
    const enableAutoMergeErr = reportSilentFallbackSpy.mock.calls.find(
      ([, ctx]) => (ctx as { op?: string }).op === "enable-auto-merge",
    );
    expect(enableAutoMergeErr).toBeUndefined();
  });
});

// ===========================================================================
// SOLEUR_PLUGIN_PATH prefix validation (defense-in-depth, MEDIUM-1)
// ===========================================================================

describe("plugin-path — SOLEUR_PLUGIN_PATH prefix validation", () => {
  const ORIG_OVERRIDE = process.env.SOLEUR_PLUGIN_PATH;
  const ORIG_VITEST = process.env.VITEST;
  const ORIG_NODE_ENV = process.env.NODE_ENV;
  const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

  // Simulate production env by clearing test markers so the prefix
  // guard actually engages. (In production, VITEST is unset and
  // NODE_ENV=production.)
  // CI's TS resolution treats process.env.NODE_ENV as read-only (vitest 3
  // narrows it via `@types/node` augmentation). Use vi.stubEnv to mutate
  // safely across environments — also unstubs cleanly.
  beforeEach(() => {
    vi.stubEnv("VITEST", "");
    vi.stubEnv("NODE_ENV", "production");
  });

  afterEach(() => {
    if (ORIG_OVERRIDE === undefined) delete process.env.SOLEUR_PLUGIN_PATH;
    else process.env.SOLEUR_PLUGIN_PATH = ORIG_OVERRIDE;
    vi.unstubAllEnvs();
    // Restore ORIG_VITEST + ORIG_NODE_ENV explicitly when they were set
    // pre-test (vi.unstubAllEnvs reverts vi.stubEnv writes only).
    if (ORIG_VITEST !== undefined) vi.stubEnv("VITEST", ORIG_VITEST);
    if (ORIG_NODE_ENV !== undefined) vi.stubEnv("NODE_ENV", ORIG_NODE_ENV);
    warnSpy.mockClear();
  });

  it("accepts override starting with /app/", async () => {
    process.env.SOLEUR_PLUGIN_PATH = "/app/shared/plugins/soleur";
    vi.resetModules();
    vi.doUnmock("@/server/plugin-path");
    const mod = await import("@/server/plugin-path");
    expect(mod.getPluginPath()).toBe("/app/shared/plugins/soleur");
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("rejects override outside allowlisted prefix and warns (production env)", async () => {
    process.env.SOLEUR_PLUGIN_PATH = "/tmp/attacker-controlled/plugins/soleur";
    vi.resetModules();
    vi.doUnmock("@/server/plugin-path");
    const mod = await import("@/server/plugin-path");
    expect(mod.getPluginPath()).toBe("/app/shared/plugins/soleur");
    expect(warnSpy).toHaveBeenCalled();
  });

  it("falls back to default when env unset", async () => {
    delete process.env.SOLEUR_PLUGIN_PATH;
    vi.resetModules();
    vi.doUnmock("@/server/plugin-path");
    const mod = await import("@/server/plugin-path");
    expect(mod.getPluginPath()).toBe("/app/shared/plugins/soleur");
  });

  it("test bypass: accepts /tmp override when VITEST set", async () => {
    process.env.VITEST = "1";
    process.env.SOLEUR_PLUGIN_PATH = "/tmp/vitest-fixture/plugins/soleur";
    vi.resetModules();
    vi.doUnmock("@/server/plugin-path");
    const mod = await import("@/server/plugin-path");
    expect(mod.getPluginPath()).toBe("/tmp/vitest-fixture/plugins/soleur");
  });
});
