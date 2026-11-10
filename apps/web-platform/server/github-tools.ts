// In-process MCP tool definitions for the GitHub App family (PR creation,
// CI status reads, workflow log reads, workflow triggers, branch pushes).
// Factored out of agent-runner.ts following the kb-share-tools.ts /
// conversations-tools.ts precedent so each tool's wiring has a single call
// site and unit tests can exercise the handlers in isolation.
//
// The handlers delegate the full implementation to
// github-app/ci-tools/trigger-workflow/push-branch — this module only
// glues SDK `tool()` calls to those delegates and stringifies results.

import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
import { createPullRequest, createIssue } from "./github-app";
import { readCiStatus, readWorkflowLogs } from "./ci-tools";
import {
  readIssue,
  readIssueComments,
  readPullRequest,
  listPullRequestComments,
  listPullRequests,
} from "./github-read-tools";
import { GitHubApiError, type GithubGetOpts } from "./github-api";
import { hardenReadResult } from "./github-read-sanitize";
import { SAFE_SEGMENT_RE } from "./resolve-protected-branches";
import { triggerWorkflow, type createRateLimiter } from "./trigger-workflow";
import { pushBranch } from "./push-branch";
import { checkGrant, grantRefusalResponse, reportGrantRefused, type ExecutionGrants } from "./approval/grants";
import { validateBranchFormat } from "./branch-validation";
import { untrustedRowsResponse, type UntrustedSource } from "./untrusted-content";

interface BuildGithubToolsOpts {
  installationId: number;
  owner: string;
  repo: string;
  defaultBranch: string;
  workspacePath: string;
  workflowRateLimiter: ReturnType<typeof createRateLimiter>;
  /**
   * #4672 per-session execution grants (shared by closure with the approval gate). REQUIRED, so a forgotten wiring is a
   * compile error. Once the approval flow ran in this session, a push without a matching grant is refused and the
   * approved commit is what gets pushed. An instance that never becomes enforcing (flag never on) = legacy behaviour.
   */
  grants: ExecutionGrants;
}

/**
 * Options of the exported push builder (#11636). Everything but `branch`/`force` is CLOSED OVER here, never model input.
 * `grants` is REQUIRED (a forgotten wiring is a compile error) and `requireGrant` is a REQUIRED boolean: the cc dispatcher
 * passes `true`, so a call that reaches the handler without a gate-written grant is refused even when the sticky
 * `enforcing` bit never turned on; the legacy runner (`buildGithubTools`) passes `false` and keeps its legacy parity.
 */
export interface BuildGithubPushBranchToolOpts {
  installationId: number;
  owner: string;
  repo: string;
  defaultBranch: string;
  workspacePath: string;
  readonly grants: ExecutionGrants;
  requireGrant: boolean;
}

/**
 * Appended (strict cc path only) to a push failure that happened AFTER the Owner's approval was consumed. Used by the push tool's
 * error path alone. Static: no input, path or git output. Without it the model retries the identical call, which opens a fresh
 * Owner approval for nothing. Worded "may or may not have been pushed": a timeout or a killed child can fail the call after the
 * remote already accepted the ref, and the model has no tool to read a remote branch, so the user is the one asked to check.
 */
export const PUSH_FAILED_APPROVAL_SPENT =
  "The Owner's approval for this push is spent. A retry needs a new Owner approval. The branch may or may not have been pushed: tell the user the push failed and why, and ask them to check the remote branch before you ask for a new approval.";

/** The soleur_platform FQN of the approval-gated push tool (the gate, the tier map and the cc registrar key on it). */
export const GITHUB_PUSH_BRANCH_TOOL_FQN = "mcp__soleur_platform__github_push_branch";

type ToolTextResponse = {
  content: Array<{ type: "text"; text: string }>;
  isError?: true;
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- SDK uses any for heterogeneous tool arrays
type GithubTool = ReturnType<typeof tool<any>>;

export interface BuildGithubToolsResult {
  tools: GithubTool[];
  toolNames: string[];
}

/**
 * Shared tool-handler scaffold: runs `fn`, JSON-stringifies the result, and
 * on exception returns an isError response with `prefix: <message>`. Extracts
 * the try/JSON/catch boilerplate duplicated across every `tool()` handler in
 * this file so a future change to the error contract (e.g., adding errorCode)
 * touches one site instead of nine. `pretty` controls `JSON.stringify` indent —
 * match the per-tool precedent (read tools use 2-space indent for agent
 * readability; write tools use compact JSON).
 */
async function wrapToolHandler<T>(
  errorPrefix: string,
  fn: () => Promise<T>,
  pretty = true,
  source?: UntrustedSource,
): Promise<ToolTextResponse> {
  try {
    const result = await fn();
    if (source) {
      // Third-party text (issue/PR/comment/CI-log): the source's untrusted-data preamble
      // goes in its own block ahead of the JSON, which is COMPACT here (`pretty` applies to
      // the unframed path only). Stringify runs inside this try, so a cyclic value lands in
      // the catch as a bare isError; an `undefined` result would stringify to nothing and
      // leave a malformed block, so it is refused explicitly.
      if (result === undefined) throw new Error("reader returned no result");
      return untrustedRowsResponse(source, result);
    }
    const indent = pretty ? 2 : undefined;
    return { content: [{ type: "text", text: JSON.stringify(result, null, indent) }] };
  } catch (err) {
    return {
      content: [{ type: "text", text: `${errorPrefix}: ${(err as Error).message}` }],
      isError: true,
    };
  }
}

/** Read-tool variant: results carry third-party text, so frame them as untrusted data. */
const wrapGithubRead = <T>(errorPrefix: string, fn: () => Promise<T>): Promise<ToolTextResponse> =>
  wrapToolHandler(errorPrefix, fn, true, "github");

/**
 * The approval-gated `github_push_branch` tool (#1929, #4672, #11636). Exported so the cc dispatcher can register exactly this
 * tool (through `cc-github-push.ts`) without taking the rest of the GitHub family. `buildGithubTools` builds it with
 * `requireGrant: false`, so the legacy runner's tool list and behaviour are unchanged.
 */
export function buildGithubPushBranchTool(opts: BuildGithubPushBranchToolOpts): GithubTool {
  const { installationId, owner, repo, defaultBranch, workspacePath, grants, requireGrant } = opts;
  return tool(
    "github_push_branch",
    "Push the current workspace HEAD to a feature branch on the remote. " +
      "Requires the workspace Owner's approval. Force-push and push to " +
      "main/master are blocked unconditionally.",
    {
      branch: z.string().describe("Target branch name (must not be main, master, or default branch)"),
      force: z.boolean().default(false).describe("Force-push (always rejected — included for explicit error messaging)"),
    },
    async (args): Promise<ToolTextResponse> => {
      const toolName = GITHUB_PUSH_BRANCH_TOOL_FQN;
      const grant = checkGrant(grants, toolName, args);
      if (grant.kind === "refuse") return grantRefusalResponse("grant_missing");
      // cc (#11636): a `legacy` outcome means no gate-written grant exists for this call (the gate never ran, or another allow
      // source handed the call to the handler): refuse and report, never the legacy HEAD push. A separate statement so the
      // refuse line above stays intact.
      if (grant.kind === "legacy" && requireGrant) {
        reportGrantRefused(toolName, "grant_missing");
        return grantRefusalResponse("grant_missing");
      }
      // A grant that does not carry the approved commit cannot say WHAT was approved: refuse, never fall back to HEAD.
      if (grant.kind === "granted" && !grant.binding.headSha) {
        reportGrantRefused(toolName, "commit_mismatch");
        return grantRefusalResponse("commit_mismatch");
      }
      let commitUnavailable = false;
      const result = await wrapToolHandler("Error pushing branch", async () => {
        try {
          const pushed = await pushBranch({
            installationId,
            owner,
            repo,
            workspacePath,
            branch: args.branch,
            force: args.force,
            defaultBranch,
            // The exact commit the Owner approved (not whatever HEAD is now); undefined on the legacy path.
            commitSha: grant.kind === "granted" ? grant.binding.headSha : undefined,
            // The strict (cc) builder pushes in the hardened form; the legacy runner's call is unchanged (key absent).
            ...(requireGrant ? { hardened: true as const } : {}),
          });
          // With a grant the result names the commit that landed (the one the Owner approved), so the model reports THAT commit
          // and not whatever HEAD is by now; without one (the legacy path) the shape is unchanged.
          return grant.kind === "granted" ? { ...pushed, commit: grant.binding.headSha } : pushed;
        } catch (err) {
          // By name, not instanceof: the class lives in push-branch.ts and a module double of it must not break the refusal.
          if (err instanceof Error && err.name === "ApprovedCommitUnavailableError") commitUnavailable = true;
          throw err;
        }
      }, /* pretty */ false);
      if (commitUnavailable) {
        reportGrantRefused(toolName, "commit_unavailable");
        return grantRefusalResponse("commit_unavailable");
      }
      // The approval was consumed before the handler ran: say so on a failure, strict (cc) path only.
      if (requireGrant && result.isError) {
        const original = result.content.find((b) => b.type === "text")?.text ?? "";
        return { ...result, content: [{ type: "text", text: `${original}\n${PUSH_FAILED_APPROVAL_SPENT}` }] };
      }
      return result;
    },
  );
}

/** Fixed agent-visible text for a GitHub access fault (401/403). Names the real remedy and rules out Agent web access as the cause. */
export const GITHUB_ACCESS_NEEDS_RECONNECT =
  "GitHub access for this workspace needs reconnecting in Settings; this is not caused by Agent web access. " +
  "Tell the user to reconnect GitHub there; if it persists, the GitHub App may lack permission for this read";
/** Fixed text for GitHub rate limiting (429, or a 403 whose GitHub message names a rate limit): not a reconnect case. */
export const GITHUB_RATE_LIMITED =
  "GitHub is rate limiting this workspace; wait about a minute and try once more, otherwise tell the user it is rate limited. Do not retry in a loop";
/** Fixed refusal when the workspace's connected repo or installation no longer matches the one the tools were built with. */
export const GITHUB_REPO_CHANGED = "the connected repository changed; start a new conversation";
/** Fixed refusal when the current repo/installation could not be confirmed right now (a read blip), which is not a repo switch. */
export const GITHUB_REPO_UNVERIFIABLE =
  "could not confirm the connected repository right now; try once more, and if it persists tell the user to check the repository connection in Settings";
/** Fixed text for any fault that is not a GitHub API response (a token mint, a missing config value, a parse error): no detail. */
export const GITHUB_READ_FAILED = "GitHub could not be reached for this read; try again in a moment";
const GITHUB_REDIRECT_REFUSED = "GitHub redirected this request; the redirect was not followed";
/** Fixed text for a 404/410: GitHub's own message is scrubbed, and "request failed: 404" is not actionable for the user. */
export const GITHUB_NOT_FOUND = "not found; check the number, or the item may have been deleted";

/** A sanitized tool fault handed to the registrar's mirror: the tool name, the error class name and the HTTP status ONLY. */
export interface GithubReadFault {
  tool: string;
  errName?: string;
  status?: number;
  /** Low-cardinality class name of the error a swallowed path caught (the revalidation read), so a Sentry event can tell causes apart. */
  cause?: string;
}

/**
 * The cc-only hardening of the read tools. Present => the tools are built for an entitled Command Center session:
 * results are redacted per field (title/body), stripped of invisible format characters, capped per field and per response;
 * any 3xx fails closed; every call first re-confirms the connected repo/installation; faults are mirrored (class name and
 * status only); 401/403 and the PR 404 hint get the fixed texts below. Absent => the legacy tools: the same requests, texts and
 * result shapes, except that a deleted author now reads as "ghost" instead of throwing (shared reader code).
 */
export type GithubRevalidation = "current" | "changed" | "unverifiable";

export interface GithubReadHardening {
  /** Called for faults worth a Sentry event (5xx, network, 401/403, 3xx, rate limit, repo changed). Never for plain 404/422. */
  onFault: (fault: GithubReadFault) => void;
  /**
   * Re-confirms, before every call, that the workspace's connected repo and installation still match the values the tools were
   * built with: `current` (go ahead), `changed` (a real switch) or `unverifiable` (a read blip; nothing was confirmed). Anything
   * else, or a throw, is treated as `unverifiable`: a call never proceeds unless this resolves exactly `current`.
   */
  revalidate: () => Promise<GithubRevalidation>;
  /** Redact `title`/`body` per field (data minimisation, not an exfiltration control). Default true. */
  redact?: boolean;
}

export interface BuildGithubReadToolsOpts {
  installationId: number;
  owner: string;
  repo: string;
  hardening?: GithubReadHardening;
}

/** The cc builder's options: `hardening` is REQUIRED at the type level; `buildGithubReadTools` also refuses an unhardened call at runtime. */
export interface BuildGithubReadHardenedOpts extends BuildGithubReadToolsOpts {
  hardening: GithubReadHardening;
}

/** The SHORT names (no `mcp__soleur_platform__` prefix) of the six cc read tools, in builder order. The registrar's FQN list is this list with that prefix; cc-github-read.test.ts keeps them equal. */
export const GITHUB_READ_TOOL_NAMES = [
  "github_list_pull_requests",
  "github_read_pr",
  "github_read_issue",
  "github_read_issue_comments",
  "github_list_pr_comments",
  "github_read_ci_status",
] as const;

function readFault(err: unknown, tool: string): GithubReadFault {
  const status = err instanceof GitHubApiError ? err.statusCode : undefined;
  return { tool, errName: err instanceof Error ? err.name : undefined, ...(typeof status === "number" ? { status } : {}) };
}

/** Client-input outcomes that are a normal answer, not a fault worth a Sentry event. */
function isPlainClientOutcome(status: number | undefined): boolean {
  return status === 400 || status === 404 || status === 410 || status === 422;
}

function makeReadTools(opts: BuildGithubReadToolsOpts) {
  const { installationId, owner, repo, hardening } = opts;
  if (hardening && (!SAFE_SEGMENT_RE.test(owner) || !SAFE_SEGMENT_RE.test(repo))) {
    throw new Error("buildGithubReadTools: unsafe owner or repo segment");
  }
  // Scoped to the hardened tools: any 3xx is refused instead of followed with the installation token attached.
  const fetchOpts: GithubGetOpts | undefined = hardening ? { redirect: "manual" } : undefined;
  const extra = (fetchOpts ? [fetchOpts] : []) as [] | [GithubGetOpts];
  const redact = hardening?.redact !== false;

  /** One read: legacy => the historical wrapper; hardened => revalidate, run, harden, frame; faults get the fixed texts. */
  const run = async <T>(
    toolName: string,
    errorPrefix: string,
    fn: () => Promise<T>,
    on404?: () => Promise<string | null>,
  ): Promise<ToolTextResponse> => {
    if (!hardening) return wrapGithubRead(errorPrefix, fn);
    const refuse = (text: string): ToolTextResponse => ({ content: [{ type: "text", text }], isError: true });
    // A throwing mirror must never turn a tool answer into a raw error.
    const fault = (f: GithubReadFault): void => {
      try {
        hardening.onFault(f);
      } catch {
        // review: swallowed. The mirror is best-effort; the tool answer below is the product.
      }
    };
    let verdict: GithubRevalidation = "unverifiable";
    let cause: string | undefined;
    try {
      const v = await hardening.revalidate();
      verdict = v === "current" || v === "changed" ? v : "unverifiable"; // fail closed: only an exact `current` proceeds
    } catch (err) {
      // review: swallowed. A read error is `unverifiable`; the class name rides on the fault so Sentry can tell causes apart.
      verdict = "unverifiable";
      cause = err instanceof Error ? err.name : "NonError";
    }
    if (verdict !== "current") {
      fault({ tool: toolName, errName: verdict === "changed" ? "RepoChanged" : "RevalidateUnverifiable", ...(cause ? { cause } : {}) });
      return refuse(`${errorPrefix}: ${verdict === "changed" ? GITHUB_REPO_CHANGED : GITHUB_REPO_UNVERIFIABLE}`);
    }
    try {
      const result = await fn();
      if (result === undefined) throw Object.assign(new Error("reader returned no result"), { name: "ReaderReturnedNoResult" });
      return untrustedRowsResponse("github", hardenReadResult(result, { redact }));
    } catch (err) {
      const isApiError = err instanceof GitHubApiError;
      const status = isApiError ? err.statusCode : undefined;
      const message = err instanceof Error ? err.message : "";
      // The token mint throws a plain Error carrying GitHub's status in its text. A revoked, uninstalled or suspended installation
      // answers 401/403/404 (reconnect); a transient 5xx is not a reconnect case, and a mint with no status is unknown.
      const mint = !isApiError ? /installation token request failed:?\s*(\d{3})?/i.exec(message) : null;
      if (mint) {
        const mintStatus = mint[1] ? Number(mint[1]) : undefined;
        fault({ ...readFault(err, toolName), ...(mintStatus ? { status: mintStatus } : {}) });
        if (mintStatus === 401 || mintStatus === 403 || mintStatus === 404) return refuse(GITHUB_ACCESS_NEEDS_RECONNECT);
        if (mintStatus === 429) return refuse(`${errorPrefix}: ${GITHUB_RATE_LIMITED}`);
        return refuse(`${errorPrefix}: ${GITHUB_READ_FAILED}`);
      }
      if (status === 429 || (status === 403 && /rate limit|abuse detection/i.test(message))) {
        fault(readFault(err, toolName));
        return refuse(`${errorPrefix}: ${GITHUB_RATE_LIMITED}`);
      }
      if (status === 401 || status === 403) {
        fault(readFault(err, toolName));
        return refuse(GITHUB_ACCESS_NEEDS_RECONNECT);
      }
      if (typeof status === "number" && status >= 300 && status < 400) {
        fault(readFault(err, toolName));
        return refuse(`${errorPrefix}: ${GITHUB_REDIRECT_REFUSED}`);
      }
      if (status === 404 && on404) {
        let hint: string | null = null;
        try {
          hint = await on404();
        } catch {
          // review: swallowed. The probe is a best-effort hint; the plain 404 text below is the answer when it fails.
          hint = null;
        }
        if (hint) return refuse(hint);
      }
      if (!isPlainClientOutcome(status)) fault(readFault(err, toolName));
      if (status === 404 || status === 410) return refuse(`${errorPrefix}: ${GITHUB_NOT_FOUND}`);
      // Only a GitHub API response is forwarded to the model. Anything else (a mint failure, a missing config value, a parse
      // error) can name server configuration, so it gets a fixed text.
      return refuse(isApiError ? `${errorPrefix}: ${message}` : `${errorPrefix}: ${GITHUB_READ_FAILED}`);
    }
  };

  const listPrs = tool(
    "github_list_pull_requests",
    "List pull requests on the connected repository, newest-updated first. Returns metadata only " +
      "(number, title, state, author login, label names, updated_at, html_url, draft, head_ref) and has_more; " +
      "use github_read_pr for one PR's details (closed includes merged; github_read_pr tells them apart). state is open (default), " +
      "closed or all. If has_more is true, call again with per_page 50; more than 50 is not reachable. If truncated is true the " +
      "reply was cut to fit a size budget: call again with a smaller per_page instead.",
    {
      state: z.enum(["open", "closed", "all"]).default("open").describe("Which pull requests to list: open (default), closed or all"),
      per_page: z.number().int().min(1).max(50).default(10).describe("Number of pull requests to return (max 50)"),
    },
    async (args): Promise<ToolTextResponse> =>
      run("github_list_pull_requests", "Error listing pull requests", () =>
        listPullRequests(installationId, owner, repo, { state: args.state, per_page: args.per_page }, ...extra),
      ),
  );

  const readCi = tool(
    "github_read_ci_status",
    "Read recent CI workflow run statuses for the connected repository. " +
      "Returns status (pass/fail/in-progress), commit SHA, branch, run URL, " +
      "and workflow name/ID. Optionally filter by branch.",
    {
      branch: z.string().optional().describe("Filter runs by branch name"),
      per_page: z.number().default(10).describe("Number of runs to return (max 30)"),
    },
    async (args): Promise<ToolTextResponse> =>
      run("github_read_ci_status", "Error reading CI status", () =>
        readCiStatus(installationId, owner, repo, { branch: args.branch, per_page: Math.min(args.per_page, 30) }, ...extra),
      ),
  );

  const readIssueTool = tool(
    "github_read_issue",
    "Read a single issue from the connected repository by number. " +
      `Returns number, title, state, body (${hardening ? "shortened" : "truncated at 10 KB"}), labels, ` +
      "assignees, milestone title, timestamps, author login, and html_url.",
    {
      issue_number: z.number().int().positive().describe("The issue number to read"),
    },
    async (args): Promise<ToolTextResponse> =>
      // No PR hint on a 404: GitHub serves a pull request through /issues/N with a 200, so an issue 404 never means "it is a PR".
      run("github_read_issue", "Error reading issue", () =>
        readIssue(installationId, owner, repo, args.issue_number, ...extra),
      ),
  );

  const readIssueCommentsTool = tool(
    "github_read_issue_comments",
    "Read conversation comments on an issue. Returns id, author login, " +
      `body (${hardening ? "shortened" : "truncated at 4 KB"}), created_at, and html_url. Results are ` +
      "tagged kind=\"conversation\" for symmetry with github_list_pr_comments.",
    {
      issue_number: z.number().int().positive().describe("The issue number to read comments from"),
      per_page: z.number().int().min(1).max(50).default(10).describe("Number of comments to return (max 50)"),
    },
    async (args): Promise<ToolTextResponse> =>
      run("github_read_issue_comments", "Error reading issue comments", () =>
        readIssueComments(installationId, owner, repo, args.issue_number, { per_page: args.per_page }, ...extra),
      ),
  );

  const readPrTool = tool(
    "github_read_pr",
    "Read a pull request from the connected repository by number. Returns " +
      "the issue fields plus PR-specific review state: draft, merged, " +
      "mergeable, mergeable_state, head_ref, base_ref, merged_at. Use this " +
      "to decide whether a PR needs another push or is already merged.",
    {
      pull_number: z.number().int().positive().describe("The pull request number to read"),
    },
    async (args): Promise<ToolTextResponse> =>
      run(
        "github_read_pr",
        "Error reading PR",
        () => readPullRequest(installationId, owner, repo, args.pull_number, ...extra),
        async () => {
          await readIssue(installationId, owner, repo, args.pull_number, ...extra);
          return `#${args.pull_number} is an issue; use github_read_issue`;
        },
      ),
  );

  const listPrCommentsTool = tool(
    "github_list_pr_comments",
    "List both review comments (line-specific) and conversation comments on " +
      "a pull request. Each entry is tagged kind=\"review\" or " +
      "kind=\"conversation\" so you can filter. Review comments come from " +
      "/pulls/:n/comments; conversation comments from /issues/:n/comments.",
    {
      pull_number: z.number().int().positive().describe("The pull request number to list comments for"),
      per_page: z.number().int().min(1).max(50).default(10).describe("Number of comments per kind to return (max 50)"),
    },
    async (args): Promise<ToolTextResponse> =>
      run("github_list_pr_comments", "Error listing PR comments", () =>
        listPullRequestComments(installationId, owner, repo, args.pull_number, { per_page: args.per_page }, ...extra),
      ),
  );

  return { listPrs, readCi, readIssue: readIssueTool, readIssueComments: readIssueCommentsTool, readPr: readPrTool, listPrComments: listPrCommentsTool };
}

/**
 * The six read-only GitHub tools of the Command Center (#12469): list pull requests, read a PR, read an issue, read issue
 * comments, list PR comments, read CI status. Exported so the cc dispatcher can register exactly these (through
 * `cc-github-read.ts`, which lazy-imports this module) without taking the write tools, the workflow-logs tool or the push
 * tool. Owner, repo and installation are CLOSED OVER and are not schema keys. `hardening` is what makes the set safe next to
 * open web egress; the registrar always passes it. `buildGithubTools` composes its five legacy reads from the same code with
 * no hardening.
 */
export function buildGithubReadTools(opts: BuildGithubReadHardenedOpts): BuildGithubToolsResult {
  // The type already requires it; this is the runtime half, for an `as` cast or a JS caller.
  if (!opts.hardening) throw new Error("buildGithubReadTools: hardening is required");
  const t = makeReadTools(opts);
  const tools = [t.listPrs, t.readPr, t.readIssue, t.readIssueComments, t.listPrComments, t.readCi];
  return { tools, toolNames: GITHUB_READ_TOOL_NAMES.map((n) => `mcp__soleur_platform__${n}`) };
}

export function buildGithubTools(opts: BuildGithubToolsOpts): BuildGithubToolsResult {
  const { installationId, owner, repo, defaultBranch, workspacePath, workflowRateLimiter, grants } = opts;

  const createPr = tool(
    "create_pull_request",
    "Create a pull request on the user's connected GitHub repository. " +
      "The repository is determined server-side from the user's connected repo. " +
      "The head branch must already exist on the remote (push first via git).",
    {
      head: z.string().describe("Branch name containing changes (just the name, not owner:branch)"),
      base: z.string().default("main").describe("Target branch to merge into"),
      title: z.string().describe("PR title"),
      body: z.string().optional().describe("PR description body (markdown)"),
    },
    async (args): Promise<ToolTextResponse> => wrapToolHandler("Error creating PR", async () => {
      validateBranchFormat(args.head);
      validateBranchFormat(args.base);
      if (args.head === args.base) {
        throw new Error("Head branch and base branch cannot be the same");
      }
      return await createPullRequest(
        installationId, owner, repo,
        args.head, args.base, args.title, args.body,
      );
    }, /* pretty */ false),
  );

  const createIssueTool = tool(
    "create_issue",
    "File an issue on the user's connected GitHub repository. " +
      "The repository is determined server-side from the user's connected repo.",
    {
      title: z.string().describe("Issue title"),
      body: z.string().optional().describe("Issue description body (markdown)"),
      labels: z.array(z.string()).default([]).describe("Labels to apply to the issue"),
    },
    async (args): Promise<ToolTextResponse> => wrapToolHandler("Error creating issue", () =>
      createIssue(installationId, owner, repo, args.title, args.body, args.labels),
    /* pretty */ false),
  );

  const readLogs = tool(
    "github_read_workflow_logs",
    "Read failure details for a specific workflow run. Returns check annotations " +
      "(structured failure data) when available, otherwise falls back to the last " +
      "100 lines of the first failed step. Use github_read_ci_status first to find run IDs.",
    {
      run_id: z.number().describe("The workflow run ID to inspect"),
    },
    async (args): Promise<ToolTextResponse> => wrapGithubRead("Error reading workflow logs", () =>
      readWorkflowLogs(installationId, owner, repo, args.run_id),
    ),
  );

  const triggerWf = tool(
    "github_trigger_workflow",
    "Trigger a workflow_dispatch event on the connected repository. " +
      "Requires founder approval via review gate. Rate limited to 10 triggers per session. " +
      "Use github_read_ci_status first to find workflow IDs.",
    {
      workflow_id: z.number().describe("The workflow ID to trigger (from github_read_ci_status)"),
      ref: z.string().describe("Git ref to run the workflow on (branch name or tag)"),
      inputs: z.record(z.string(), z.string()).optional().describe("Optional workflow_dispatch inputs"),
    },
    async (args): Promise<ToolTextResponse> => wrapToolHandler("Error triggering workflow", () =>
      triggerWorkflow(
        installationId, owner, repo,
        args.workflow_id, args.ref, workflowRateLimiter, args.inputs,
      ),
    ),
  );

  const pushBr = buildGithubPushBranchTool({
    installationId,
    owner,
    repo,
    defaultBranch,
    workspacePath,
    grants,
    requireGrant: false,
  });

  // Read-only issue/PR/CI tools (#2843): built by the shared read builder below, placed at their historical positions.
  // No hardening is passed, so the legacy runner's tools, bodies and error text are exactly what they were.
  const reads = makeReadTools({ installationId, owner, repo });
  const readCi = reads.readCi;
  const readIssueTool = reads.readIssue;
  const readIssueCommentsTool = reads.readIssueComments;
  const readPrTool = reads.readPr;
  const listPrCommentsTool = reads.listPrComments;

  return {
    tools: [
      createPr, createIssueTool, readCi, readLogs, triggerWf, pushBr,
      readIssueTool, readIssueCommentsTool, readPrTool, listPrCommentsTool,
    ],
    toolNames: [
      "mcp__soleur_platform__create_pull_request",
      "mcp__soleur_platform__create_issue",
      "mcp__soleur_platform__github_read_ci_status",
      "mcp__soleur_platform__github_read_workflow_logs",
      "mcp__soleur_platform__github_trigger_workflow",
      GITHUB_PUSH_BRANCH_TOOL_FQN,
      "mcp__soleur_platform__github_read_issue",
      "mcp__soleur_platform__github_read_issue_comments",
      "mcp__soleur_platform__github_read_pr",
      "mcp__soleur_platform__github_list_pr_comments",
    ],
  };
}
