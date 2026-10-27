/**
 * #11303 (originally #4672 / plan 2026-10-27-feat-durable-action-bound-approval-requests Phase 0.1) - real-SDK probe of the gated-tool
 * permission chain, against the production option composition.
 *
 * QUESTION: for each of the eight gated platform tools (email_send, email_reply, email_suppress, github_push_branch,
 * create_pull_request, github_trigger_workflow, kb_share_create, workspace_set_autonomous), does the Claude Agent SDK invoke the
 * production `canUseTool` (so the review card can appear), or does the SDK `allowedTools` option approve the call first? The SDK approves
 * a bare `allowedTools` entry BEFORE it consults `canUseTool`; the legacy runner (server/agent-runner.ts) used to pass every
 * `platformToolNames` entry there, so no gated tool ever reached its gate (#11303). The fix is `buildAllowedTools` (server/tool-tiers.ts),
 * which keeps only auto-approve platform tools. Unit tests mock the SDK, so only this script can say the real chain behaves that way
 * (same reasoning as dev-probe-destroy-ask.ts, whose structure this file reuses).
 * pyramid-justified: only the real SDK can show the permission-chain order, mocks cannot.
 *
 * HOW: it drives the production option builder (`buildAgentQueryOptions`) and the production, UNCHANGED `createCanUseTool` through
 * `sdkQuery` with a real model in a throwaway workspace. The eight tools are served by an in-process MCP server that uses the SAME
 * server name (`soleur_platform`) and tool names as production, so the fully-qualified names (`mcp__soleur_platform__<tool>`) match what
 * `canUseTool` and `allowedTools` see. Their handlers are INERT stubs: they never send mail, never touch git or GitHub, never read the
 * database; they only record that they ran. Every gated call is answered Reject by the injected review-gate dep, so `canUseTool` returns
 * deny. Ten cases:
 *   <tool>:prod             (x8) `allowedTools` = `buildAllowedTools(<every legacy platform tool name derived from the real builders>,
 *                           [one plugin server])`, i.e. exactly what the legacy runner now passes, handed through the real
 *                           `buildAgentQueryOptions` (so its fail-closed allowlist assertion is exercised too). The target FQN is
 *                           asserted ABSENT before any money is spent. The prompt is a plain STRING, the shape `startAgentSession` uses.
 *   email_send:raw          CANARY. The OLD composition: the unfiltered list (every legacy name incl. the gated ones), assigned directly
 *                           onto the options after the builder returns (the builder rejects it by design). It MUST still bypass: this
 *                           ties the probe to the SDK's actual current behaviour, so a probe whose `:prod` rows pass vacuously cannot
 *                           read as green. `invoked=yes` here is a FAIL (the SDK changed or the probe is vacuous).
 *   email_send:prod-stream  diagnostic twin of email_send:prod that differs only in using a streaming-input prompt.
 * Per case the probe records: attempted (the model emitted a tool_use for the FQN), invoked (production canUseTool was called with the
 * FQN, and the tier it saw), handlerRan (the stub body executed, i.e. the call was NOT stopped), and the deny honoured
 * (invoked && !handlerRan). Registration per runner is printed from the real builders (`REGISTRATION` lines).
 *
 * Run (dev or ci Doppler config ONLY, never prd; key never printed; the agent env is allowlisted by buildAgentEnv):
 *   NODE_ENV=test doppler run -p soleur -c ci -- bun run apps/web-platform/scripts/dev-probe-approval-gate.ts
 * The probe reads no Supabase/Resend/GitHub credential and the stubs touch none of them. It refuses to run with a config named prd.
 * One paid model call per case; 10 cases by default (the cap). Re-run it after any SDK, bundled-CLI, tier-map or option-builder change.
 *
 * PROMPT SHAPE (measured, SDK 0.3.284 / CLI 2.1.284): a plain string prompt DOES reach `canUseTool` (the SDK writes it to the CLI as a
 * stdin user message and adds `--permission-prompt-tool stdio` whenever `canUseTool` is set). An older note in this family of probes said
 * only a streaming-input prompt wires the callback; that is not the case, and the legacy runner passes a string.
 *
 * WHAT THIS CANNOT SHOW: the stubs replace the real handlers, so it says nothing about handler behaviour (hash binding of the email body,
 * rate limits, protected-branch checks). It runs on the dev host (host bwrap, NODE_ENV=test), not in the hosted container. `cli=` is the SDK
 * package's DECLARED claudeCodeVersion. The behaviour depends on the model choosing to call the tool, so a green run is evidence about the
 * sampled behaviour only; a model that declines to call a tool is CANT-RUN, never a pass.
 *
 * Diagnostic env: PROBE_ONLY=<case>[,<case>] (unknown name => CANT-RUN:unknown-or-unavailable-case; any subset prints
 * `RESULT: DIAGNOSTIC`, never PASS), PROBE_TRACE=1 prints tool-result prefixes.
 *
 * Output: `PROVENANCE`, then `REGISTRATION` lines, then one `PROBE <case> invoked=<yes|no> ...` line per case and a final
 * `RESULT: PASS|FAIL|CANT-RUN:<reason>|DIAGNOSTIC (sdk=... cli=..., cases-run=N)`. Exit: 0 PASS, 1 FAIL (a crash also exits 1: require the
 * RESULT line), 3 CANT-RUN (reasons: model-did-not-attempt-tool, no-anthropic-key, no-case-selected, unknown-or-unavailable-case,
 * case-table-drift, case-count-below-floor, refuses-prd, registration-import-failed), 4 DIAGNOSTIC. Exit 4 (a subset run) is NEVER
 * treated as green by any caller. PASS needs all 10 cases: every `:prod` and `:prod-stream` case has invoked=yes, tier gated and the stub never
 * ran, AND the `:raw` canary shows invoked=no with the stub having run.
 */
import { mkdtempSync, mkdirSync, writeFileSync, realpathSync, rmSync, existsSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import * as Sentry from "@sentry/nextjs";
import { z } from "zod";
import { query as sdkQuery, tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { buildAgentQueryOptions } from "../server/agent-runner-query-options";
import { resolveWorkspaceMode } from "../server/workspace-mode";
import { createCanUseTool, type CanUseToolContext } from "../server/permission-callback";
import { buildAllowedTools, getToolTier } from "../server/tool-tiers";

if (/^prd/.test(process.env.DOPPLER_CONFIG ?? "")) {
  console.log("RESULT: CANT-RUN:refuses-prd");
  process.exit(3);
}
const apiKey = process.env.ANTHROPIC_API_KEY ?? "";
if (!apiKey) {
  console.log("RESULT: CANT-RUN:no-anthropic-key");
  process.exit(3);
}

const sdkMeta = (() => {
  try {
    const req = createRequire(import.meta.url);
    let dir = dirname(req.resolve("@anthropic-ai/claude-agent-sdk"));
    for (let i = 0; i < 6 && !existsSync(join(dir, "package.json")); i++) dir = dirname(dir);
    const pkg = JSON.parse(readFileSync(join(dir, "package.json"), "utf8")) as { version?: string; claudeCodeVersion?: string };
    return { version: pkg.version ?? "unknown", cli: pkg.claudeCodeVersion ?? "unknown" };
  } catch {
    return { version: "unknown", cli: "unknown" };
  }
})();
const PROV = `sdk=${sdkMeta.version} cli=${sdkMeta.cli}`;
console.log(`PROVENANCE ${PROV} node=${process.version} bun=${(globalThis as { Bun?: { version?: string } }).Bun?.version ?? "n/a"} doppler-config=${process.env.DOPPLER_CONFIG ?? "n/a"}`);

// Nothing leaves the process: placeholder DSN, transport that drops envelopes (production code under test calls Sentry helpers).
Sentry.init({
  dsn: "https://probe@probe.invalid/1",
  environment: "probe",
  defaultIntegrations: false,
  integrations: [],
  tracesSampleRate: 0,
  sendDefaultPii: false,
  transport: () => ({ send: async () => ({}), flush: async () => true }),
});

const SERVER = "soleur_platform";
const fqn = (n: string) => `mcp__${SERVER}__${n}`;

type Spec = { name: string; shape: z.ZodRawShape; args: Record<string, unknown> };
// Input schemas mirror the production zod shapes (github-tools.ts, workspace-settings-tools.ts, kb-share-tools.ts, email-triage-tools.ts).
// Arguments are synthesized, non-secret, and point at nothing real (reserved .invalid / example.invalid domains).
const SPECS: Spec[] = [
  { name: "email_send", shape: { to: z.string(), subject: z.string(), body: z.string() }, args: { to: "probe@example.invalid", subject: "probe", body: "probe body" } },
  { name: "email_reply", shape: { messageId: z.string(), subject: z.string(), body: z.string() }, args: { messageId: "probe-message-id", subject: "Re: probe", body: "probe body" } },
  { name: "email_suppress", shape: { recipient: z.string(), reason: z.string() }, args: { recipient: "probe@example.invalid", reason: "probe" } },
  { name: "github_push_branch", shape: { branch: z.string(), force: z.boolean().default(false) }, args: { branch: "probe-feature-branch", force: false } },
  { name: "create_pull_request", shape: { head: z.string(), base: z.string().default("main"), title: z.string(), body: z.string().optional() }, args: { head: "probe-feature-branch", base: "main", title: "probe PR", body: "probe" } },
  { name: "github_trigger_workflow", shape: { workflow_id: z.number(), ref: z.string(), inputs: z.record(z.string(), z.string()).optional() }, args: { workflow_id: 1, ref: "probe-feature-branch" } },
  { name: "kb_share_create", shape: { documentPath: z.string() }, args: { documentPath: "probe/README.md" } },
  { name: "workspace_set_autonomous", shape: { value: z.boolean() }, args: { value: false } },
];
const TOOL_NAMES = SPECS.map((s) => s.name);

// prod: the production composition; raw: the OLD unfiltered composition (canary, expected to bypass); stream: prod with a streaming prompt.
type Mode = "prod" | "raw" | "stream";
type Case = { name: string; tool: string; mode: Mode };
const CANARY_TOOL = "email_send";
const CASES: Case[] = [
  ...SPECS.map((s): Case => ({ name: `${s.name}:prod`, tool: s.name, mode: "prod" })),
  { name: `${CANARY_TOOL}:raw`, tool: CANARY_TOOL, mode: "raw" },
  { name: `${CANARY_TOOL}:prod-stream`, tool: CANARY_TOOL, mode: "stream" },
];
const MAX_CASES = 10;
const MIN_DEFAULT_CASES = 10;
const ALL_NAMES = new Set(CASES.map((c) => c.name));
if (CASES.length !== TOOL_NAMES.length + 2 || CASES.length > MAX_CASES || TOOL_NAMES.some((n) => getToolTier(fqn(n)) !== "gated")) {
  // The set of names must stay the eight gated tools; a drifted tier map or case table measures something else.
  console.log(`RESULT: CANT-RUN:case-table-drift (${PROV})`);
  process.exit(3);
}
const only = new Set((process.env.PROBE_ONLY ?? "").split(",").map((x) => x.trim()).filter(Boolean));
const diagnostic = only.size > 0;
const known = [...only].filter((n) => ALL_NAMES.has(n));
if (only.size > 0 && known.length === 0) {
  console.log(`RESULT: CANT-RUN:no-case-selected (${PROV})`);
  process.exit(3);
}
if (known.length !== only.size) {
  console.log(`RESULT: CANT-RUN:unknown-or-unavailable-case (${PROV})`);
  process.exit(3);
}

// --- Registration per runner, from the REAL builders (no handler is ever called). ---------------------------------------------------
// Legacy runner (agent-runner.ts startAgentSession): every builder it composes. The names are DERIVED here, never typed, so a tool the
// runner gains is in the `:prod` and `:raw` lists without editing this file. A builder that fails to import is CANT-RUN (never a silent
// fall back to the eight FQNs, which would measure a smaller list than production passes).
// cc-dispatcher (cc-soleur-go): soleurPlatformToolsForTests = narration + (flag-gated) c4 + (crm-lead only) crm. Informational only.
const LEGACY = new Set<string>();
const LEGACY_PLUGIN_SERVERS = ["context7"]; // one plugin MCP server, so the wildcard entry is part of the measured composition
async function registration(): Promise<void> {
  const cc = new Set<string>();
  const notes: string[] = [];
  const legacyFailures: string[] = [];
  const noop = {} as never;
  const legacyStep = async (label: string, add: () => Promise<void>) => {
    try { await add(); } catch (e) { legacyFailures.push(`${label}-import-failed:${e instanceof Error ? e.name : "?"}`); }
  };
  await legacyStep("github-tools", async () => {
    const { buildGithubTools } = await import("../server/github-tools");
    for (const t of buildGithubTools({ installationId: 0, owner: "o", repo: "r", defaultBranch: "main", workspacePath: "/nonexistent", workflowRateLimiter: noop } as never).toolNames) LEGACY.add(t);
  });
  await legacyStep("plausible-tools", async () => {
    const { buildPlausibleTools } = await import("../server/plausible-tools");
    for (const t of buildPlausibleTools({ plausibleKey: "probe" } as never).toolNames) LEGACY.add(t);
  });
  await legacyStep("workspace-settings", async () => {
    const { buildWorkspaceSettingsTools } = await import("../server/workspace-settings-tools");
    for (const t of buildWorkspaceSettingsTools({ userId: "probe" } as never).toolNames) LEGACY.add(t);
  });
  await legacyStep("account-tools", async () => {
    const { buildAccountTools } = await import("../server/account-tools");
    for (const t of buildAccountTools({ userId: "probe", userEmail: "probe@example.invalid", sessionId: "probe" } as never).toolNames) LEGACY.add(t);
  });
  await legacyStep("routines-tools", async () => {
    const { buildRoutineTools } = await import("../server/routines-tools");
    for (const t of buildRoutineTools({ userId: "probe" } as never).toolNames) LEGACY.add(t);
  });
  await legacyStep("workstream-tools", async () => {
    const { buildWorkstreamTools } = await import("../server/workstream/workstream-tools");
    for (const t of buildWorkstreamTools({ userId: "probe" } as never).toolNames) LEGACY.add(t);
  });
  // Builders that return a bare tool array (the runner pushes their names as literals).
  const arrayBuilders: [string, () => Promise<{ name: string }[]>][] = [
    ["kb-share-tools", async () => (await import("../server/kb-share-tools")).buildKbShareTools({ serviceClient: noop, userId: "probe", kbRoot: "/nonexistent", baseUrl: "https://probe.invalid" } as never) as { name: string }[]],
    ["email-triage-tools", async () => (await import("../server/email-triage-tools")).buildEmailTriageTools({ userId: "probe" } as never) as { name: string }[]],
    ["inbox-tools", async () => (await import("../server/inbox-tools")).buildInboxTools({ userId: "probe" } as never) as { name: string }[]],
    ["crm-tools", async () => (await import("../server/crm/crm-tools")).buildCrmTools({ userId: "probe" } as never) as { name: string }[]],
    ["auth-status-tools", async () => (await import("../server/auth-status-tools")).buildAuthStatusTools({ userId: "probe" } as never) as unknown as { name: string }[]],
  ];
  for (const [label, load] of arrayBuilders) {
    await legacyStep(label, async () => { for (const t of await load()) LEGACY.add(fqn(t.name)); });
  }
  // agent-runner registers ONE conversations tool on the allowlist (its siblings are registered but denied by canUseTool's default).
  await legacyStep("conversations-tools", async () => {
    const tools = (await import("../server/conversations-tools")).buildConversationsTools({ userId: "probe" } as never) as { name: string }[];
    if (tools.some((t) => t.name === "conversations_lookup")) LEGACY.add(fqn("conversations_lookup"));
  });
  try {
    const mod = await import("../server/cc-dispatcher");
    for (const t of mod.soleurPlatformToolsForTests({ userId: "probe", crmLead: true, c4Tools: [{ name: "edit_c4_diagram" }] })) cc.add(fqn(t.name));
  } catch (e) { notes.push(`cc-dispatcher-import-failed:${e instanceof Error ? e.name : "?"}`); }
  for (const n of TOOL_NAMES) {
    console.log(`REGISTRATION ${n} legacy=${LEGACY.has(fqn(n)) ? "yes" : "no"} cc=${cc.has(fqn(n)) ? "yes" : "no"}`);
  }
  console.log(`REGISTRATION summary legacyTools=${LEGACY.size} ccTools=${cc.size}${notes.length ? ` notes=${notes.join(",")}` : ""}${legacyFailures.length ? ` legacyFailures=${legacyFailures.join(",")}` : ""}`);
  if (legacyFailures.length > 0 || TOOL_NAMES.some((n) => !LEGACY.has(fqn(n)))) {
    console.log(`RESULT: CANT-RUN:registration-import-failed (${PROV})`);
    process.exit(3);
  }
}
await registration();

// The two compositions under test, from the one derived legacy set.
const RAW_ALLOWED = [...LEGACY, ...LEGACY_PLUGIN_SERVERS.map((s) => `mcp__plugin_soleur_${s}__*`)]; // the old, unfiltered list
const PROD_ALLOWED = buildAllowedTools([...LEGACY], LEGACY_PLUGIN_SERVERS); // what the legacy runner passes now
{
  // Pre-spend guard: a gated name that survives the filter means the fix is broken. Loud FAIL, no money spent.
  const leaked = TOOL_NAMES.filter((n) => PROD_ALLOWED.includes(fqn(n)));
  if (leaked.length > 0 || PROD_ALLOWED.some((n) => n.startsWith("mcp__soleur_platform__") && getToolTier(n) !== "auto-approve")) {
    console.log(`PROBE prod-composition leaked-gated-tools=${leaked.join(",") || "other"}`);
    console.log(`RESULT: FAIL (${PROV}, cases-run=0)`);
    process.exit(1);
  }
}
console.log(`COMPOSITION prod=${PROD_ALLOWED.length} entries (auto-approve platform tools + plugin wildcards) raw=${RAW_ALLOWED.length} entries (unfiltered)`);

const base = realpathSync(mkdtempSync(join(tmpdir(), "probe-approval-")));
const home = join(base, "home");
mkdirSync(home, { recursive: true });
process.env.HOME = home;
const ws = join(base, "ws");
mkdirSync(ws, { recursive: true });
writeFileSync(join(ws, "README.md"), "throwaway probe workspace\n");
const pluginPath = resolve(__dirname, "..", "..", "..", "plugins", "soleur");

type CaseResult = { attempted: boolean; invoked: boolean; tier: string; behaviors: string[]; gateCalls: number; handlerRan: boolean; denyMessage: string; err?: string };

async function runCase(c: Case): Promise<CaseResult> {
  const spec = SPECS.find((s) => s.name === c.tool)!;
  const target = fqn(c.tool);
  const seen: string[] = [];
  const behaviors: string[] = [];
  let tier = "n/a";
  let gateCalls = 0;
  let handlerRan = false;
  let attempted = false;
  let denyMessage = "";
  const abort = new AbortController();
  const session = { abort, reviewGateResolvers: new Map(), sessionId: null };

  // Inert stubs: SAME server name and tool names as production; the body only records that it ran.
  const stubTools = SPECS.map((s) =>
    tool(s.name, `Probe stub for ${s.name}. Inert.`, s.shape, async () => {
      if (s.name === c.tool) handlerRan = true;
      return { content: [{ type: "text" as const, text: `probe stub executed for ${s.name}; nothing was done` }] };
    }),
  );
  const server = createSdkMcpServer({ name: SERVER, version: "1.0.0", tools: stubTools });

  const ctx = {
    userId: "probe-user",
    conversationId: `probe-${c.name}`,
    leaderId: "probe_leader",
    workspacePath: ws,
    platformToolNames: [...LEGACY], // canUseTool's own allowlist is the UNFILTERED set in the legacy runner
    pluginMcpServerNames: [],
    repoOwner: "",
    repoName: "",
    session,
    controllerSignal: abort.signal,
    deps: {
      // The probe is the approver: every gate is answered Reject, so canUseTool returns deny.
      abortableReviewGate: async () => { gateCalls += 1; return "Reject"; },
      sendToClient: () => true,
      notifyOfflineUser: async () => true,
      updateConversationStatus: async () => undefined,
    },
  } as unknown as CanUseToolContext;
  const inner = createCanUseTool(ctx);

  const opts = buildAgentQueryOptions({
    workspacePath: ws,
    pluginPath,
    mode: resolveWorkspaceMode("command_center"),
    workspaceId: "probe-ws",
    sessionId: undefined,
    credential: { value: apiKey, scheme: "api_key" },
    serviceTokens: {},
    systemPrompt:
      "You are running inside a disposable test harness whose tools are inert stubs: calling one performs no real action. " +
      "Call exactly the tool the user names, once, with exactly the arguments given, then reply with one short sentence. Do not call any other tool.",
    mcpServers: { [SERVER]: server },
    // :raw is assigned directly after the builder returns (the builder rejects an unfiltered list by design).
    ...(c.mode === "raw" ? {} : { allowedTools: PROD_ALLOWED }),
    maxTurns: 4,
    maxBudgetUsd: 0.5,
    canUseTool: (async (toolName: string, input: unknown, o: unknown) => {
      seen.push(toolName);
      if (toolName === target) tier = getToolTier(toolName);
      const r = await (inner as any)(toolName, input, o);
      if (toolName === target) {
        behaviors.push(String(r?.behavior));
        if (r?.behavior === "deny") denyMessage = String(r.message ?? "").slice(0, 80);
      }
      return r;
    }) as any,
  });

  if (c.mode === "raw") (opts as { allowedTools?: string[] }).allowedTools = RAW_ALLOWED;

  let err: string | undefined;
  let release: () => void = () => undefined;
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const promptText = `Call the ${c.tool} tool (${target}) once with exactly these arguments: ${JSON.stringify(spec.args)}`;
    const done = new Promise<void>((r) => { release = r; });
    // Production shape: a plain STRING prompt (startAgentSession). Only the :prod-stream diagnostic uses a streaming-input prompt.
    async function* promptStream() {
      yield { type: "user", message: { role: "user", content: promptText }, parent_tool_use_id: null, session_id: "" } as any;
      await done;
    }
    timer = setTimeout(() => abort.abort(), 150_000);
    const q = sdkQuery({ prompt: c.mode === "stream" ? promptStream() : promptText, options: { ...opts, abortController: abort } });
    for await (const m of q as AsyncIterable<any>) {
      if (m.type === "result") release();
      if (process.env.PROBE_TRACE && m.type === "user") for (const b of m.message?.content ?? []) if (b.type === "tool_result") console.log("TRACE tool_result", JSON.stringify(b.content).slice(0, 200));
      if (m.type === "assistant") for (const b of m.message?.content ?? []) if (b.type === "tool_use" && String(b.name) === target) attempted = true;
    }
  } catch (e) {
    release();
    err = e instanceof Error ? `${e.name}:${e.message.replace(/sk-[A-Za-z0-9_-]+/g, "<key>").slice(0, 300)}` : "unknown";
  } finally {
    clearTimeout(timer);
  }
  return { attempted, invoked: seen.includes(target), tier, behaviors, gateCalls, handlerRan, denyMessage, err };
}

let failed = false;
let cantRun = false;
let cantRunReason = "model-did-not-attempt-tool";
let ran = 0;
const selected = CASES.filter((x) => only.size === 0 || only.has(x.name));
for (const c of selected) {
  const r = await runCase(c);
  ran += 1;
  const denyHonoured = r.invoked && !r.handlerRan && r.behaviors.length > 0 && r.behaviors.every((b) => b === "deny");
  let verdict: "ok" | "MODEL-DID-NOT-TRY" | "BYPASS" | "CANARY-OK" | "CANARY-NOT-BYPASSING" | "FAIL";
  if (!r.attempted) verdict = "MODEL-DID-NOT-TRY"; // also what an SDK/auth error looks like: err= says which
  else if (c.mode === "raw") {
    // The canary must STILL bypass: the SDK never asked canUseTool and the stub ran. Anything else means the SDK semantics changed
    // or this probe is vacuous, so the :prod rows prove nothing.
    verdict = !r.invoked && r.handlerRan ? "CANARY-OK" : "CANARY-NOT-BYPASSING";
  } else if (!r.invoked) verdict = "BYPASS"; // the SDK never asked canUseTool (stub ran or call was otherwise resolved without it)
  else verdict = denyHonoured && r.tier === "gated" ? "ok" : "FAIL";
  if (verdict === "BYPASS" || verdict === "FAIL" || verdict === "CANARY-NOT-BYPASSING") failed = true;
  if (verdict === "MODEL-DID-NOT-TRY") cantRun = true;
  console.log(
    `PROBE ${c.name} invoked=${r.invoked ? "yes" : "no"} verdict=${verdict} allowedToolsListsIt=${(c.mode === "raw" ? RAW_ALLOWED : PROD_ALLOWED).includes(fqn(c.tool))} prompt=${c.mode === "stream" ? "stream" : "string"} attempted=${r.attempted} tier=${r.tier} decisions=[${r.behaviors.join(",")}] gateCalls=${r.gateCalls} stubRan=${r.handlerRan} denyHonoured=${denyHonoured}${r.err ? ` err=${r.err}` : ""} ${PROV}`,
  );
}
try { rmSync(base, { recursive: true, force: true }); } catch { /* best effort */ }

if (!failed && !cantRun && !diagnostic && ran < MIN_DEFAULT_CASES) {
  cantRun = true;
  cantRunReason = "case-count-below-floor";
}
const outcome = failed ? "FAIL" : cantRun ? `CANT-RUN:${cantRunReason}` : diagnostic ? "DIAGNOSTIC" : "PASS";
console.log(`RESULT: ${outcome} (${PROV}, cases-run=${ran})`);
process.exit(failed ? 1 : cantRun ? 3 : diagnostic ? 4 : 0);
