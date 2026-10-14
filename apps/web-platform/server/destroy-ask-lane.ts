/**
 * #9776 / ADR-284 — the hosted must-ask lane, the helpers `permission-callback.ts` calls.
 *
 * The lane itself is ONE call site in the Bash branch of `createCanUseTool` (placed after the support-persona deny
 * and before the autonomous bypass, the first-run disclosure hold and the batched-approval cache): a match returns
 * from that branch, so none of those three can stand in for the Approve. This module holds the parts that are not
 * the chokepoint: running the classifier with its telemetry, building the card text, and the deny messages.
 *
 * TELEMETRY HYGIENE (CLO C5, asserted by test): nothing emitted from here carries the command, the matched
 * segment, a branch name or a refspec. The segment exists only in the card text. `repo` (owner/name) is pino-only.
 */
import { createChildLogger } from "./logger";
import { warnSilentFallback, reportSilentFallback } from "./observability";
import { redactCommandForDisplay } from "@/lib/safety/redaction-allowlist";
import {
  classifyDestroyFamily,
  destroyNearMiss,
  DESTROY_RULE_PREFIX,
  type DestroyMatch,
  type ProtectedBranches,
  type ResolveProtected,
} from "./destroy-ask-classifier";

const log = createChildLogger("permission");

/**
 * The lane's classifier list (CTO ruling, "Where the code goes" item 5): this classifier is its only member, and
 * ADR-264 / #9388 adds a second. The match type is `DestroyMatch`; a second member must either return the same shape or
 * generalise `DestroyMatch`, `causeLine` and the `hosted-destroy-ask` telemetry op together (they are destroy-specific).
 */
type MustAskClassifier = (command: string, resolve: ResolveProtected) => Promise<DestroyMatch | null>;
export const MUST_ASK_CLASSIFIERS: readonly MustAskClassifier[] = [classifyDestroyFamily];

const PER_CTX_BUDGET = 32;
const LEADING_TOKEN_MAX = 32;
/** A word that looks like a credential (vendor prefix, or a long digit run) is never shipped as a command name. */
const TOKEN_SHAPED_RE = /^(gh[pousr]_|github_pat_|sk-|xox[a-z]-|AKIA|eyJ)|\d{6,}/i;
const PREVIEW_MAX = 200;

type LaneState = { askEmitted: number; nearSeen: Set<string>; nearEmitted: number };
const LANE_STATE = new WeakMap<object, LaneState>();
function stateFor(ctx: object): LaneState {
  let s = LANE_STATE.get(ctx);
  if (!s) {
    s = { askEmitted: 0, nearSeen: new Set(), nearEmitted: 0 };
    LANE_STATE.set(ctx, s);
  }
  return s;
}

/** When the dep is not wired (legacy runner, tests) the lane fails toward ask: unresolved, constants only. */
const UNRESOLVED: ProtectedBranches = { names: new Set(["main", "master"]), authoritative: false };

export interface DestroyLaneContext {
  /** The `CanUseToolContext` object, used only as the WeakMap key for the per-context telemetry budget. */
  key: object;
  autonomous: boolean;
  isOwner: boolean;
  acked: boolean;
  /** `owner/name` of the connected repo, from `parseConnectedRepo` at dispatch (pino only). */
  repo: string;
  resolveProtectedBranches?: ResolveProtected;
}

/**
 * Run the classifier. Returns the match (after emitting the per-ask telemetry) or null (after emitting at most one
 * near-miss event). Never throws.
 */
export async function detectDestroyAsk(lane: DestroyLaneContext, command: string): Promise<DestroyMatch | null> {
  let match: DestroyMatch | null = null;
  for (const classify of MUST_ASK_CLASSIFIERS) {
    match = await classify(command, lane.resolveProtectedBranches ?? (async () => UNRESOLVED));
    if (match) break;
  }
  const state = stateFor(lane.key);
  if (!match) {
    emitNearMiss(state, command);
    return null;
  }
  if (match.error !== undefined) {
    // null first arg, never the Error: the pino mirror captures a passed Error first and Sentry drops the tagged second
    // capture (#8629), which would leave `op:destroy-classifier-error` unfindable. The error class lives in `extra`.
    reportSilentFallback(null, {
      feature: "cc-permissions",
      op: "destroy-classifier-error",
      message: "destroy classifier threw; failing toward ask",
      extra: { ruleId: match.ruleId, errName: match.error instanceof Error ? match.error.name : "unknown" },
    });
  }
  log.warn(
    {
      sec: true,
      decision: "destroy-ask",
      ruleId: match.ruleId,
      family: match.family,
      autonomous: lane.autonomous,
      isOwner: lane.isOwner,
      acked: lane.acked,
      authoritative: match.authoritative ?? null,
      repo: lane.repo,
    },
    "Bash command matched the hosted destroy must-ask lane — asking",
  );
  if (state.askEmitted < PER_CTX_BUDGET) {
    state.askEmitted += 1;
    warnSilentFallback(null, {
      feature: "cc-permissions",
      op: "hosted-destroy-ask",
      extra: {
        ruleId: match.ruleId,
        family: match.family,
        autonomous: lane.autonomous,
        isOwner: lane.isOwner,
        authoritative: match.authoritative ?? null,
      },
    });
  }
  return match;
}

/**
 * The command word only, never an env assignment (`GH_TOKEN=ghp_...`) or a path: the first token of an agent's command
 * routinely carries a credential or a username (CLO C5). Anything that is not a plain command name is `<other>`.
 */
function safeLeadingToken(command: string): string {
  for (const word of command.trim().split(/\s+/)) {
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(word)) continue;
    const plain = /^[a-z0-9._-]+$/i.test(word) && word.length <= LEADING_TOKEN_MAX;
    return plain && !TOKEN_SHAPED_RE.test(word) ? word : "<other>";
  }
  return "<other>";
}

function emitNearMiss(state: LaneState, command: string): void {
  const kind = destroyNearMiss(command);
  if (!kind) return;
  const leadingToken = safeLeadingToken(command);
  const key = `${kind}:${leadingToken}`;
  if (state.nearEmitted >= PER_CTX_BUDGET || state.nearSeen.has(key)) return;
  state.nearSeen.add(key);
  state.nearEmitted += 1;
  warnSilentFallback(null, {
    feature: "cc-permissions",
    op: "destroy-classifier-near-miss",
    extra: { leadingToken, kind },
  });
}

/**
 * Outcome line after the card resolves. The approver role is owner or member; never an identity. Emitted at WARN,
 * not INFO: the app-container shipper keeps WARN and above only, and the soak probe (CPO4-R5) counts these lines.
 */
export function logDestroyOutcome(
  outcome: "approved" | "rejected" | "expired",
  match: DestroyMatch,
  isOwner: boolean,
): void {
  log.warn(
    {
      sec: true,
      decision: `destroy-ask-${outcome}`,
      ruleId: match.ruleId,
      family: match.family,
      approverRole: isOwner ? "owner" : "member",
    },
    `Hosted destroy ask ${outcome}`,
  );
}

function causeLine(match: DestroyMatch): string {
  switch (match.ruleId.slice(DESTROY_RULE_PREFIX.length)) {
    case "terraform-destroy":
      return "Soleur paused this command because it can destroy infrastructure.";
    case "gh-repo-delete":
      return "Soleur paused this command because it can delete the repository itself.";
    case "gh-ref-delete-default":
      return "Soleur paused this command because it can delete or overwrite the repository's default branch.";
    case "git-push-unknown-default":
      return "Soleur paused this command because it force-pushes or deletes a branch and Soleur could not confirm which branch is the repository's default.";
    case "git-force-implicit":
      return "Soleur paused this command because it force-pushes without naming a branch, so it may overwrite the repository's default branch.";
    case "git-delete-default":
    case "git-force-default":
      return "Soleur paused this command because it can overwrite or delete the repository's default branch.";
    default:
      return "Soleur paused this command because it could not tell whether it would overwrite the repository's default branch or destroy infrastructure.";
  }
}

/** A window around the first `destroy` or `push` so a keyword past character 200 is still on the card. */
function keywordWindow(command: string): string {
  const at = command.search(/destroy|push/i);
  const start = Math.max(0, (at < 0 ? 0 : at) - PREVIEW_MAX / 2);
  return `${start > 0 ? "…" : ""}${preview(command.slice(start, start + PREVIEW_MAX))}`;
}

function preview(text: string): string {
  const redacted = redactCommandForDisplay(text);
  return redacted.length > PREVIEW_MAX ? `${redacted.slice(0, PREVIEW_MAX)}…` : redacted;
}

/**
 * The card text. LEADS with the cause and the matched segment (outside the truncated span), so a destroy segment
 * past character 200 of a `&&` chain stays visible. Neutral about who owns the repository. Says what Approve does
 * and nothing about other commands (CLO C4).
 */
export function buildDestroyAskQuestion(match: DestroyMatch, command: string): string {
  const unreadable = match.family === "fail-closed";
  const lines = [
    unreadable ? "Command paused for your approval" : "Destructive command - paused for your approval",
    "",
    causeLine(match),
  ];
  if (match.family === "git-default-branch" || match.ruleId.endsWith("gh-ref-delete-default")) {
    lines.push("This can erase the branch's history on GitHub and cannot be undone.");
  }
  lines.push("");
  if (match.segment) lines.push(`Matched: \`${preview(match.segment)}\``);
  else if (command.length > PREVIEW_MAX) lines.push(`Around the word that triggered this: \`${keywordWindow(command)}\``);
  if (!match.segment || match.segment !== command) lines.push(`Full command (first ${PREVIEW_MAX} characters): \`${preview(command)}\``);
  lines.push(
    "",
    "Approve runs the whole command. Your approval applies to this command only: it does not cover similar commands and does not change any setting.",
  );
  return lines.join("\n");
}

const NO_RETRY =
  "Do not retry this command and do not rephrase or respell it to get around the check. Tell the user what you were trying to do and ask how they want to proceed.";

export function destroyRejectedMessage(): string {
  return `The user rejected this command, so it was NOT run. ${NO_RETRY}`;
}

export function destroyExpiredMessage(): string {
  return `Nobody approved this command in time, so it was NOT run. ${NO_RETRY}`;
}
