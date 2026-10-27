/**
 * Tool tier classification for platform MCP tools (#1926).
 *
 * Extracted from agent-runner.ts for unit testability (following the
 * tool-path-checker.ts and review-gate.ts extraction pattern).
 *
 * Tiers:
 * - auto-approve: read-only tools, pass through without review gate
 * - gated: write tools, require founder confirmation via review gate
 * - blocked: destructive patterns, rejected unconditionally
 *
 * Invariant (#11303): the Agent SDK approves a bare `allowedTools` entry BEFORE it consults
 * `canUseTool`, so only `auto-approve` platform tools may ever be handed to the SDK as
 * pre-approved. `buildAllowedTools` is the single filter; `canUseTool` is the only approver
 * of every other tier. This module imports only the pure `outbound-compliance` validators
 * (node:crypto and nothing else) so tests and the real-SDK probe can load it without booting
 * the runner.
 */

import {
  extractAddrSpec,
  EMAIL_ADDR_MAX,
  EMAIL_BODY_MAX,
  EMAIL_RAW_ADDR_MAX,
  EMAIL_SUBJECT_MAX,
} from "./email-triage/outbound-compliance";

export type ToolTier = "auto-approve" | "gated" | "blocked";

/**
 * Canonical tier assignments for all platform MCP tools.
 * Tools not in this map default to "gated" in getToolTier()
 * (fail-closed: new tools require explicit tier assignment).
 */
export const TOOL_TIER_MAP: Record<string, ToolTier> = {
  // C4 diagram editing (#3722 follow-up): a WRITE tool but deliberately
  // auto-approve, unlike the gated github/kb-share writes. Justification: the
  // write is hard-scoped to `engineering/architecture/diagrams/` by
  // `isC4DiagramPath` inside `writeC4Diagram`; owner/repo/installation are
  // closed over from the caller's own active workspace (never tool input); it
  // is reversible (git history); and the whole capability is flag-gated to the
  // c4-visualizer dev cohort. The product intent (deferred-c4-concierge-write)
  // is autonomous in-conversation diagram editing, which a per-edit review gate
  // would defeat. Revisit (→ "gated") if the scope guard ever widens.
  "mcp__soleur_platform__edit_c4_diagram": "auto-approve",

  // Phase 2: Read CI status (auto-approve — read-only)
  // cc-router (#2909): Tier 1 candidate (Phase 2 promotion via #3722)
  "mcp__soleur_platform__github_read_ci_status": "auto-approve",
  "mcp__soleur_platform__github_read_workflow_logs": "auto-approve",

  // Issue/PR reads (#2843): all auto-approve — read-only, narrowed responses.
  // cc-router (#2909): Tier 1 candidates (Phase 2 promotion via #3722)
  "mcp__soleur_platform__github_read_issue": "auto-approve",
  "mcp__soleur_platform__github_read_issue_comments": "auto-approve",
  "mcp__soleur_platform__github_read_pr": "auto-approve",
  "mcp__soleur_platform__github_list_pr_comments": "auto-approve",

  // Phase 3: Trigger workflows (gated — write action)
  // cc-router (#2909): Tier 2 candidate (Phase 2 via #3722; review-gate UX integration required)
  "mcp__soleur_platform__github_trigger_workflow": "gated",

  // Phase 4: Push branches and open PRs (gated — write action)
  // cc-router (#2909): Tier 2 candidates (Phase 2 via #3722)
  "mcp__soleur_platform__github_push_branch": "gated",
  "mcp__soleur_platform__create_pull_request": "gated",
  "mcp__soleur_platform__create_issue": "gated",

  // KB share tools (#2309): list is read-only, create/revoke are
  // user-visible side effects (public URL / permanent revocation) → gated.
  // cc-router (#2909): list = Tier 1 candidate; create/revoke = Tier 2 (Phase 2 via #3722)
  "mcp__soleur_platform__kb_share_list": "auto-approve",
  "mcp__soleur_platform__kb_share_create": "gated",
  "mcp__soleur_platform__kb_share_revoke": "gated",
  // Preview (#2322): metadata-only (no bytes, no state change) — same
  // tier as kb_share_list. Gating it would produce consent fatigue without
  // a security benefit.
  // cc-router (#2909): Tier 1 candidate (Phase 2 via #3722)
  "mcp__soleur_platform__kb_share_preview": "auto-approve",

  // Auth revocation status (#4440 follow-up to #4418): read-only RPC
  // (`my_revocation_status()`) — auto-approve. Agents call this on auth
  // errors to discriminate JWT-deny from transient failures. No side
  // effects, no founder-confirmation surface needed.
  "mcp__soleur_platform__auth_revocation_status": "auto-approve",

  // Workspace autonomous-mode toggle (Issue B part 2): read is auto-approve
  // (read-only); SET is gated — flipping an approval-bypass on a code-executing
  // surface MUST require a review-gate even for the agent (owner check is in
  // the RPC; the gate is the second line). Explicit entries (set would also be
  // gated by the default fallback, but the pairing documents intent).
  "mcp__soleur_platform__workspace_get_autonomous": "auto-approve",
  "mcp__soleur_platform__workspace_set_autonomous": "gated",

  // Email triage inbox reads (operator-inbox-delegation AC11): both
  // read-only, owner-scoped via closure userId + RLS → auto-approve (parity
  // with kb_share_list rationale).
  "mcp__soleur_platform__email_triage_list": "auto-approve",
  "mcp__soleur_platform__email_triage_get": "auto-approve",

  // Unified attention inbox (feat-severity-ranked-inbox #6007): read-only,
  // owner-scoped via closure userId + RLS → auto-approve (parity with
  // email_triage_list). No write tool ships (state changes are operator-UI-only).
  "mcp__soleur_platform__inbox_list": "auto-approve",

  // Routines management (#5345): reads auto-approve; run-now is a write →
  // gated. The review gate is the SINGLE confirmation for the agent path
  // (the routine_run tool dispatches confirmed=true post-approval — no
  // double-gate with the in-band 409). buildGateMessage names the routine.
  "mcp__soleur_platform__routines_list": "auto-approve",
  "mcp__soleur_platform__routine_runs_list": "auto-approve",
  "mcp__soleur_platform__routine_run": "gated",

  // Workstream board (feat-workstream-kanban-tab): read-only board feed over
  // the shared accessor → auto-approve (parity with routines_list; non-PII, no
  // side effects). The edit-fields picker-options read is the same tier (labels/
  // assignees/milestones of the connected repo; degrade-safe, no side effects).
  "mcp__soleur_platform__workstream_issues_list": "auto-approve",
  "mcp__soleur_platform__workstream_issue_options": "auto-approve",

  // Workstream WRITE tools (feat-workstream-issue-crud #6304, ADR-109, closes
  // #5677). All `gated` (precedent: create_issue): the host review gate IS the
  // founder-confirmation surface for a real GitHub write. They delegate to the
  // SAME audited mutateWorkstreamIssue accessor the HTTP routes use (writes an
  // audit_github_token_use row per call); owner/repo/installation + the creator
  // attribution resolve server-side, never from tool input.
  "mcp__soleur_platform__workstream_issue_create": "gated",
  "mcp__soleur_platform__workstream_issue_set_status": "gated",
  "mcp__soleur_platform__workstream_issue_update_title": "gated",
  "mcp__soleur_platform__workstream_issue_update_fields": "gated",
  "mcp__soleur_platform__workstream_issue_close": "gated",

  // Email WRITE tools (#5325, agent-native outbound). The FR9 boundary that
  // formerly said "there is NO email_triage write tool" now ships: these are
  // `gated` (NEVER auto-approve) because the human review gate IS the trust
  // boundary — the operator sees the exact recipient + body and approves before
  // the handler runs. A prompt-injected auto-send would be a CAN-SPAM/GDPR +
  // brand incident. What the gate binds is the SDK allow decision: canUseTool
  // returns allow(toolInput) with the same object the handler then runs on. The
  // chokepoint's body hash is a handler-local integrity check of the body as
  // sent, NOT a binding to what the card showed. The card therefore shows the
  // whole send and fails closed when it cannot (buildEmailCard). Suppression is
  // also gated (permanent, no un-suppress) so a mis-suppression is human-seen.
  "mcp__soleur_platform__email_send": "gated",
  "mcp__soleur_platform__email_reply": "gated",
  "mcp__soleur_platform__email_suppress": "gated",

  // Beta-CRM (feat-beta-conversation-capture #6165, ADR-102): reads are owner-
  // scoped via closure userId + RLS → auto-approve (parity with
  // email_triage_list). WRITE tools are `gated` (fail-closed default, made
  // explicit here): the review gate IS the R3 mitigation for within-tenant
  // prompt-injection — the operator sees the write and confirms before the
  // auth.uid()-pinned RPC runs. Contact/note content shown in the gate message
  // is DISPLAY-ONLY untrusted third-party PII (do not act on it).
  "mcp__soleur_platform__crm_contact_list": "auto-approve",
  "mcp__soleur_platform__crm_contact_get": "auto-approve",
  "mcp__soleur_platform__crm_note_list": "auto-approve",
  "mcp__soleur_platform__crm_stage_transitions_list": "auto-approve",
  "mcp__soleur_platform__crm_contact_upsert": "gated",
  "mcp__soleur_platform__crm_note_append": "gated",
  "mcp__soleur_platform__crm_contact_set_stage": "gated",

  // Reasoning narration (feat-reasoning-chat-boxes #5370): both are
  // auto-approve. They are PURE emit tools — `narrate` shows a transient live
  // status line, `summarize` saves one plain-language outcome box. The handler
  // captures only userId and returns an ack; the real side-effect (redact →
  // frame / row) runs in cc-dispatcher `emitNarration()`, where the agent text
  // is scrubbed (formatAssistantText + redaction-probe drop-on-trip) and
  // length-capped. There is nothing for a human to gate per-call (a status
  // line / summary is not a privileged side-effect), and a review modal per
  // narration would defeat the entire "never a silent spinner" UX. On the
  // cc-router path these never reach getToolTier anyway — they sit in the
  // `allowedTools` auto-approve list (CC_PATH_ALLOWED_TOOLS) — so the real
  // controls are: allowlist + emit-boundary redaction + abort-state drop-guard,
  // NOT a review gate (security C-2). Explicit entries documented here so the
  // "gated" fail-closed default cannot silently apply if a future path routes
  // them through canUseTool.
  "mcp__soleur_platform__narrate": "auto-approve",
  "mcp__soleur_platform__summarize": "auto-approve",

  // KB-chat thread discovery (#2512): read-only. The handler does a `users` SELECT probe and a
  // `conversations` + `messages(count)` SELECT through the tenant client (lookupConversationForPath),
  // plus a SELECT in getCurrentRepoUrl; userId is closure-bound and nothing is written. Auto-approve
  // (parity with kb_share_list). Verified read-only at #11303; the registered siblings
  // (conversations_list, conversation_archive, ...) are NOT on the canUseTool allowlist and stay
  // unclassified (denied by canUseTool's deny-default).
  // cc-router (#2909): Tier 1 candidate.
  "mcp__soleur_platform__conversations_lookup": "auto-approve",

  // Explicit `gated` entries (#11303). Behaviour is unchanged (getToolTier already defaulted these to
  // gated); the entries exist so a census can tell "decided" from "defaulted" and a NEW platform tool
  // fails CI until someone decides its tier.
  // Plausible: the user's own stored PLAUSIBLE_API_KEY (serviceTokens), an account-wide key with no per-site scoping.
  "mcp__soleur_platform__plausible_create_site": "gated",
  "mcp__soleur_platform__plausible_add_goal": "gated",
  "mcp__soleur_platform__plausible_get_stats": "gated",
  // Account: export bundles the user's data and files; delete is destructive and permanent.
  "mcp__soleur_platform__account_export_enqueue": "gated",
  "mcp__soleur_platform__account_delete_initiate": "gated",
};

/**
 * Permanent Tier 3 denylist for the cc-soleur-go router (#2909).
 *
 * Tools in this set MAY NEVER be promoted to the router's mcpServers via
 * the inline `readCcMcpAllowlist()` helper in `cc-dispatcher.ts`. Enforced
 * fail-closed at factory construction (the helper throws if any short-name
 * resolving to a member of this set appears in `CC_MCP_ALLOWLIST`).
 *
 * Plausible tools (`plausible_create_site/add_goal/get_stats`) run on the
 * user's own stored `PLAUSIBLE_API_KEY`, an account-wide key with no
 * per-site scoping (see `apps/web-platform/server/plausible-tools.ts:52-74`
 * and the `serviceTokens.PLAUSIBLE_API_KEY` read in `agent-runner.ts`).
 * Exposing them via the router would hand an account-wide credential to the
 * autonomous path, regardless of any future demand signal.
 *
 * See brainstorm Key Decision #3:
 *   knowledge-base/project/brainstorms/archive/20261013-014038-2026-05-13-mcp-tier-classify-cc-soleur-go-brainstorm.md
 *
 * NOTE: the legacy `TOOL_TIER_MAP` carries explicit `gated` entries for the Plausible
 * tools (#11303), so the legacy review-gate surfaces them with founder confirmation.
 * This denylist is the cc-router-specific permanent block.
 */
export const CC_ROUTER_TIER3_DENYLIST: ReadonlySet<string> = new Set([
  "mcp__soleur_platform__plausible_create_site",
  "mcp__soleur_platform__plausible_add_goal",
  "mcp__soleur_platform__plausible_get_stats",
]);

/**
 * Look up the tier for a platform MCP tool.
 * Returns "gated" for tools not in the map (fail-closed: new tools
 * require explicit tier assignment before they can auto-approve).
 */
export function getToolTier(toolName: string): ToolTier {
  // hasOwn: a prototype key ("constructor", "__proto__") must resolve to the fail-closed default, not an inherited value.
  return Object.hasOwn(TOOL_TIER_MAP, toolName) ? TOOL_TIER_MAP[toolName] : "gated";
}

/** Plugin MCP server names come from `plugin.json`; only this shape may be interpolated into a wildcard entry. */
const PLUGIN_SERVER_NAME_SOURCE = "[a-z0-9-]+";
const PLUGIN_SERVER_NAME_RE = new RegExp(`^${PLUGIN_SERVER_NAME_SOURCE}$`);
/** The tool-name prefix every plugin MCP tool carries: `mcp__plugin_soleur_<server>__`. */
export function pluginToolPrefix(server: string): string {
  return `mcp__plugin_soleur_${server}__`;
}
/** The SDK `allowedTools` wildcard entry for one plugin MCP server: `mcp__plugin_soleur_<server>__*`. */
export function pluginWildcard(server: string): string {
  return `${pluginToolPrefix(server)}*`;
}
const PLUGIN_WILDCARD_RE = new RegExp(`^mcp__plugin_soleur_(${PLUGIN_SERVER_NAME_SOURCE})__\\*$`);
/** The server name inside a valid plugin wildcard entry, or null when the entry is not exactly that shape. */
export function parsePluginWildcard(entry: string): string | null {
  const m = PLUGIN_WILDCARD_RE.exec(entry);
  return m === null ? null : m[1];
}

/**
 * The ONE keep-rule for SDK pre-approval (#11303): a platform tool may be handed to the SDK as pre-approved only when its
 * effective tier is `auto-approve` (fail-closed: `gated`, `blocked` and unclassified names are all not pre-approvable).
 * `buildAllowedTools` filters with it and `assertAllowedToolsPreApprovalSafe` re-checks with it.
 */
export function isPreApprovable(fqn: string): boolean {
  return getToolTier(fqn) === "auto-approve";
}

/**
 * The SDK `allowedTools` pre-approval list for the legacy runner (#11303).
 *
 * The SDK auto-approves a bare `allowedTools` entry BEFORE it consults `canUseTool`, so any `gated` platform tool listed
 * there runs with no review card. This keeps a platform name only when `isPreApprovable` holds, and appends
 * `pluginWildcard(server)` for each validly-named plugin MCP server (third-party plugin servers are allowed by design, as
 * `canUseTool` also allows them). Pure; never mutates its inputs; always returns an array (the call site omits the key
 * when it is empty). `createCanUseTool` must keep receiving the UNFILTERED platform list.
 */
export function buildAllowedTools(
  platformToolNames: readonly string[],
  pluginMcpServerNames: readonly string[],
): string[] {
  const out = new Set<string>();
  for (const name of platformToolNames) {
    if (isPreApprovable(name)) out.add(name);
  }
  for (const server of pluginMcpServerNames) {
    if (PLUGIN_SERVER_NAME_RE.test(server)) out.add(pluginWildcard(server));
  }
  return [...out];
}

/**
 * Outbound-email tool inputs carry a third party's address and a message body,
 * and the published privacy notice scopes where those may be stored (#8532).
 * For those tools, returns a summary naming only which fields were supplied;
 * for any other tool, returns null so the caller summarises as usual.
 */
export function summarizeOutboundEmailInput(toolName: string, input: unknown): string | null {
  if (!/(^|__)email_(send|reply|suppress)$/.test(toolName)) return null;
  const keys = input !== null && typeof input === "object" ? Object.keys(input).sort() : [];
  return `[outbound email: ${keys.join(", ") || "no fields"} — values withheld]`;
}

/**
 * Card-field helpers (#11303). Once the gate is reachable, the review card is the only control, and its text is built
 * from model-controlled tool input. Every scalar interpolated into a card goes through `cardField`: control, bidi and
 * zero-width characters are stripped, newlines and markdown emphasis/link/html characters are removed, the value is
 * length-capped (with a visible ellipsis), and a non-scalar becomes the literal word `unknown` (never an object).
 * The outbound-email tools do NOT use `cardField` for the fields that decide who receives what: see `buildEmailCard`.
 */
const CARD_FIELD_MAX = 120;
// ONE source class for every invisible/format character a card must neutralise (cardField strips them; the email card makes
// them visible). DEL and C1, the combining grapheme joiner, soft hyphen, Arabic letter mark, Hangul fillers, Khmer inherent
// vowels, the Mongolian vowel separator, zero-width and bidi marks, line and paragraph separators, bidi embeddings/overrides/
// isolates, word joiner, the invisible math operators and deprecated format characters (U+2060-206F), the Braille blank, the
// Hangul filler, variation selectors, the BOM, the halfwidth Hangul filler, the Unicode tag characters and the variation
// selectors supplement. Escapes only: no literal separators (cq-regex-unicode-separators-escape-only). Written as `\\u` text
// in a string and compiled with the `u` flag, so the astral ranges use the `\u{...}` form.
const HIDDEN_COMMON_CLASS =
  "\\u007F-\\u009F\\u00AD\\u034F\\u061C\\u115F\\u1160\\u17B4\\u17B5\\u180E\\u200B-\\u200F\\u2028-\\u202E\\u2060-\\u206F" +
  "\\u2800\\u3164\\uFE00-\\uFE0F\\uFEFF\\uFFA0\\u{E0000}-\\u{E007F}\\u{E0100}-\\u{E01EF}";
// C0 controls: all of them for a single-line field; the body variant leaves tab and newline (ordinary body text) alone.
const HIDDEN_LINE_CONTROLS = "\\u0000-\\u001F";
const HIDDEN_BODY_CONTROLS = "\\u0000-\\u0008\\u000B-\\u001F";
// cardField folds newline, tab and the separators to a space first, then strips this set.
const CARD_STRIP_RE = new RegExp(`[${HIDDEN_LINE_CONTROLS}${HIDDEN_COMMON_CLASS}]`, "gu");
// Markdown emphasis, code, link and html characters.
const CARD_MARKDOWN_RE = /[*`[\]<>\\~|]/g;
const CARD_MARKDOWN_CHAR_RE = /[*`[\]<>\\~|]/;

function cardScalar(v: unknown): string | null {
  if (typeof v === "string") return v;
  if (typeof v === "number" || typeof v === "boolean" || typeof v === "bigint") return String(v);
  return null;
}

function cleanForCard(raw: string): string {
  return raw
    .replace(/[\r\n\t\u2028\u2029]+/g, " ")
    .replace(CARD_STRIP_RE, "")
    .replace(CARD_MARKDOWN_RE, "")
    .replace(/\s+/g, " ")
    .trim();
}

function cardField(v: unknown, fallback = "unknown", max = CARD_FIELD_MAX): string {
  const raw = cardScalar(v);
  if (raw === null) return fallback;
  // Perf: model input is unbounded; never clean more than one character past the cap.
  const clipped = raw.length > max + 1;
  const cleaned = cleanForCard(clipped ? raw.slice(0, max + 1) : raw);
  if (cleaned === "") return fallback;
  return clipped || cleaned.length > max ? `${cleaned.slice(0, max)}…` : cleaned;
}

const CARD_LIST_MAX = 10;
/** A short list of scalars (labels, assignees, lens); a non-array is the word `unknown`; a longer list says how many more. */
function cardList(v: unknown, sep = ", "): string {
  if (!Array.isArray(v)) return "unknown";
  const shown = v.slice(0, CARD_LIST_MAX).map((x) => cardField(x, "?", 40)).join(sep);
  return v.length > CARD_LIST_MAX ? `${shown}${sep}… +${v.length - CARD_LIST_MAX} more` : shown;
}

/** A card clause for an input the tool accepts but the card does not print: it says so, with the size, instead of staying silent. */
function notShown(label: string, v: unknown): string {
  if (typeof v === "string") return v === "" ? "" : ` (${label} of ${v.length} characters is not shown here)`;
  if (v === undefined || v === null) return "";
  return ` (${label} is not shown here)`;
}

/** The workflow_dispatch inputs: the names are shown, the values are not. */
function workflowInputs(v: unknown): string {
  if (v === undefined || v === null) return "";
  if (typeof v !== "object" || Array.isArray(v)) return " (with inputs that are not shown here)";
  const names = Object.keys(v);
  return names.length ? ` with inputs [${cardList(names)}] (input values are not shown here)` : "";
}

/**
 * Outbound-email card (#5325, #11303). The card is the only control between a prompt-injected agent and a real cold email,
 * so it shows every field that decides who receives what: the FULL parsed recipient address (the display name separately,
 * capped with a visible ellipsis), the reply-to, the subject and the ENTIRE body. When the input cannot be shown in full
 * the tool is DENIED before any card exists (fail closed): nothing is truncated into an Approve card.
 */
const EMAIL_DISPLAY_NAME_MAX = 60;
const EMAIL_MESSAGE_ID_MAX = 64;
const ASCII_HINT = "Use the ASCII form of the address (punycode for international domains).";
export const EMAIL_DENY_RECIPIENT =
  `The recipient could not be shown in full for review, so the email was not sent. Fix the recipient and try again. ${ASCII_HINT}`;
export const EMAIL_DENY_REPLY_TO =
  `The reply-to address could not be shown in full for review, so the email was not sent. Fix the reply-to and try again. ${ASCII_HINT}`;
export const EMAIL_DENY_DISPLAY_NAME = "Remove the comma from the display name, or send to the bare address, and try again.";
export const EMAIL_DENY_BODY = `Shorten the body to ${EMAIL_BODY_MAX.toLocaleString("en-US")} characters or fewer and try again. Tell the user the limit was hit; do not silently truncate the email.`;
export const EMAIL_DENY_SUBJECT = `Shorten the subject to ${EMAIL_SUBJECT_MAX} characters or fewer and try again. Tell the user the limit was hit; do not silently truncate the email.`;
export const EMAIL_DENY_FIELDS =
  "The email could not be shown in full for review, so it was not sent. Fix the email fields and try again.";
export const EMAIL_DENY_SUPPRESS =
  `The recipient could not be shown in full for review, so the suppression was not applied. Fix the recipient and try again. ${ASCII_HINT}`;

// Characters that are invisible or control in a card are made VISIBLE as [U+XXXX], never deleted. Newline and tab are ordinary
// body text and pass through in the body variant. A LITERAL "[U+" in the original text is escaped in the same pass (as
// "[U+005B]U+"), so text can never forge a real marker. Both regexes compile the one shared source class above.
const CARD_HIDDEN_RE = new RegExp(`\\[U\\+|[${HIDDEN_BODY_CONTROLS}${HIDDEN_COMMON_CLASS}]`, "gu");
const CARD_HIDDEN_LINE_RE = new RegExp(`\\[U\\+|[${HIDDEN_LINE_CONTROLS}${HIDDEN_COMMON_CLASS}]`, "gu");
// A bare ASCII address: printable ASCII only (U+0021-U+007E). International domains must arrive as punycode (xn--).
const CARD_ADDR_ASCII_RE = /^[\x21-\x7E]+$/;
// A bare address: one addr-spec, no whitespace, comma, semicolon, quote, angle bracket or '@' beyond the single separator.
const CARD_ADDR_RE = /^[^\s@<>",;]+@[^\s@<>",;]+\.[^\s@<>",;]+$/;

type Revealed = { text: string; revealed: number };

/**
 * Make hidden characters visible. Returns the escaped text and how many characters were revealed or escaped (0 = verbatim).
 * A marker is `[U+` plus at least four hex digits and `]`: BMP characters print four (`[U+202E]`), the Unicode tag
 * characters and variation selectors supplement print five (`[U+E0041]`). A literal `[U+` in the input is rewritten to
 * `[U+005B]U+`, which no real marker can look like (a real marker has its hex digits right after the `+`).
 */
function revealHidden(raw: string, singleLineField = false): Revealed {
  let revealed = 0;
  const text = (singleLineField ? raw : raw.replace(/\r\n/g, "\n"))
    .replace(singleLineField ? CARD_HIDDEN_LINE_RE : CARD_HIDDEN_RE, (ch) => {
      revealed += 1;
      if (ch === "[U+") return "[U+005B]U+";
      return `[U+${ch.codePointAt(0)!.toString(16).toUpperCase().padStart(4, "0")}]`;
    });
  return { text, revealed };
}

type ParsedAddress = { addr: string; name: string };
type AddressFailure = { fail: "address" | "name" };

/**
 * A bare address or a single `Name <addr>`; anything else is a failure. The card and the tool handler evaluate the SAME
 * string: a value with leading or trailing whitespace is refused (never trimmed), so the handler sends exactly the string
 * this function parsed. The address is shown in full and verbatim: one that is too long, empty, malformed, non-ASCII (v1
 * fails closed: punycode `xn--` is allowed) or that contains a hidden/control/markup character is refused rather than cleaned.
 */
function parseCardAddress(raw: unknown): ParsedAddress | AddressFailure {
  if (typeof raw !== "string" || raw.length > EMAIL_RAW_ADDR_MAX || raw !== raw.trim()) return { fail: "address" };
  const opens = raw.split("<").length - 1;
  const closes = raw.split(">").length - 1;
  let name = "";
  if (opens === 0 && closes === 0) {
    // bare form
  } else if (opens === 1 && closes === 1 && raw.endsWith(">") && raw.indexOf("<") < raw.indexOf(">")) {
    name = raw.slice(0, raw.indexOf("<")).trim();
    // A display name that carries an '@', a comma or a semicolon can pass for a second address or recipient list.
    if (/[@,;]/.test(name)) return { fail: "name" };
  } else {
    return { fail: "address" };
  }
  const addr = extractAddrSpec(raw);
  if (addr === "" || addr.length > EMAIL_ADDR_MAX || !CARD_ADDR_RE.test(addr) || !CARD_ADDR_ASCII_RE.test(addr)) {
    return { fail: "address" };
  }
  if (revealHidden(addr, true).revealed > 0 || CARD_MARKDOWN_CHAR_RE.test(addr)) return { fail: "address" };
  return { addr, name };
}

/** Where a failed address goes: a display-name problem gets its own actionable text, everything else the field's text. */
function addressDeny(f: AddressFailure, addressText: string): { deny: string } {
  return { deny: f.fail === "name" ? EMAIL_DENY_DISPLAY_NAME : addressText };
}

/** The display name is shown as a JSON string (quotes and backslashes escaped, whitespace collapsed), capped with an ellipsis. */
function addressLine(p: ParsedAddress): string {
  if (p.name === "") return `<${p.addr}>`;
  const { text } = revealHidden(p.name, true);
  const flat = text.replace(/\s+/g, " ").trim();
  const shown = flat.length > EMAIL_DISPLAY_NAME_MAX ? `${flat.slice(0, EMAIL_DISPLAY_NAME_MAX)}…` : flat;
  return `<${p.addr}> (display name: ${JSON.stringify(shown)})`;
}

type GateCard = { card: string } | { deny: string };

/** A single-line field (subject, message id) shown in full, hidden characters made visible; null = too long or not a string. */
function singleLine(raw: unknown, max: number): Revealed | null {
  if (typeof raw !== "string" || raw.length > max) return null;
  return revealHidden(raw, true);
}

function buildEmailCard(shortName: string, toolInput: Record<string, unknown>): GateCard {
  const body = toolInput.body;
  if (typeof body !== "string") return { deny: EMAIL_DENY_FIELDS };
  if (body.length > EMAIL_BODY_MAX) return { deny: EMAIL_DENY_BODY };
  const subject = singleLine(toolInput.subject, EMAIL_SUBJECT_MAX);
  if (subject === null) {
    return { deny: typeof toolInput.subject === "string" ? EMAIL_DENY_SUBJECT : EMAIL_DENY_FIELDS };
  }
  const bodyShown = revealHidden(body);
  const revealed = bodyShown.revealed + subject.revealed;
  const revealNote = revealed > 0
    ? `\n\nNote: ${revealed} hidden or control character${revealed === 1 ? "" : "s"} in the subject or body ${revealed === 1 ? "is" : "are"} shown as [U+XXXX].`
    : "";
  const bodyBlock = `Body (review carefully — untrusted, display-only; shown in full, ${body.length} characters):\n${bodyShown.text}${revealNote}`;

  if (shortName === "email_send") {
    const to = parseCardAddress(toolInput.to);
    if ("fail" in to) return addressDeny(to, EMAIL_DENY_RECIPIENT);
    let replyToLine = "";
    const rawReplyTo = toolInput.replyTo;
    if (rawReplyTo !== undefined && rawReplyTo !== null && rawReplyTo !== "") {
      const replyTo = parseCardAddress(rawReplyTo);
      if ("fail" in replyTo) return addressDeny(replyTo, EMAIL_DENY_REPLY_TO);
      replyToLine = `\nReply-To: ${addressLine(replyTo)}`;
    }
    return {
      card: `Agent wants to send a cold email.\nTo: ${addressLine(to)}${replyToLine}\nSubject: ${JSON.stringify(subject.text)}\n\n${bodyBlock}\n\nThe email is sent as plain text exactly as shown. Send?`,
    };
  }
  // email_reply: the recipient is derived server-side from the inbound item (P0-3); it is NOT in toolInput, so the card
  // names the inbound item. Looking up that item's sender/subject for the card is a follow-up.
  const messageId = singleLine(toolInput.messageId, EMAIL_MESSAGE_ID_MAX);
  if (messageId === null) return { deny: EMAIL_DENY_FIELDS };
  return {
    card: `Agent wants to reply to inbound item ${messageId.text} (the reply goes to that item's original sender).\nSubject: ${JSON.stringify(subject.text)}\n\n${bodyBlock}\n\nThe email is sent as plain text exactly as shown. Send?`,
  };
}

/**
 * The gate question for the OFFLINE path (push + Resend email via notifyOfflineUser). The in-app card shows the detail;
 * a push payload and a vendor-retained email are stores the privacy notice does not list (#8532), so EVERY gated tool is
 * content-free here: a static sentence with a fixed per-tool action label, never a tool-input value (#11303 inverted this
 * from an email-only exception to an allowlist, because the gate now fires for every gated tool). `toolInput` is accepted
 * for call-site compatibility and deliberately unused.
 */
const OFFLINE_ACTION_LABELS: Record<string, string> = {
  email_send: "an outbound email action",
  email_reply: "an outbound email action",
  email_suppress: "an outbound email action",
  github_push_branch: "a GitHub push",
  create_pull_request: "a GitHub pull request",
  create_issue: "a GitHub issue",
  github_trigger_workflow: "a GitHub workflow run",
  kb_share_create: "a public document share",
  kb_share_revoke: "a share link revocation",
  routine_run: "a routine run",
  workspace_set_autonomous: "a workspace autonomy change",
  account_delete_initiate: "an account deletion",
  account_export_enqueue: "an account data export",
  plausible_create_site: "an analytics site change",
  plausible_add_goal: "an analytics goal change",
  plausible_get_stats: "an analytics stats request",
  crm_contact_upsert: "a CRM record change",
  crm_note_append: "a CRM record change",
  crm_contact_set_stage: "a CRM record change",
  workstream_issue_create: "a GitHub issue change",
  workstream_issue_set_status: "a GitHub issue change",
  workstream_issue_update_title: "a GitHub issue change",
  workstream_issue_update_fields: "a GitHub issue change",
  workstream_issue_close: "a GitHub issue change",
};

export function buildOfflineGateMessage(
  toolName: string,
  _toolInput: Record<string, unknown>,
): string {
  const shortName = toolName.replace("mcp__soleur_platform__", "");
  const label = Object.hasOwn(OFFLINE_ACTION_LABELS, shortName) ? OFFLINE_ACTION_LABELS[shortName] : "an action";
  return `An agent is waiting for your approval on ${label}. Open the conversation to review it.`;
}

/**
 * Build the review card for a gated tool invocation, or a static deny reason when the input cannot be shown in full (#11303).
 * The caller (`createCanUseTool`) MUST deny on `{ deny }` before any card, status write or notification exists. The card
 * should clearly describe what the agent wants to do so the founder can make an informed approval decision, and every
 * accepted tool input that changes the outcome is either printed or named as not shown. Every interpolated tool-input
 * value goes through the card-field helpers above (bounded and neutralised).
 */
export function buildGateCard(
  toolName: string,
  toolInput: Record<string, unknown>,
): GateCard {
  const shortName = toolName.replace("mcp__soleur_platform__", "");
  if (shortName === "email_send" || shortName === "email_reply") return buildEmailCard(shortName, toolInput);
  if (shortName === "email_suppress") {
    const target = parseCardAddress(toolInput.recipient);
    if ("fail" in target) return addressDeny(target, EMAIL_DENY_SUPPRESS);
    return {
      card: `Agent wants to PERMANENTLY suppress ${addressLine(target)} (reason: ${cardField(toolInput.reason)}) so no future cold email can reach them. There is no un-suppress. Allow?`,
    };
  }
  return { card: buildPlainGateMessage(shortName, toolInput) };
}

/**
 * The card text as a plain string (the fail-closed reason when there is no card). Display and test helper only: the
 * permission callback uses `buildGateCard` and never shows a deny reason in an Approve card.
 */
export function buildGateMessage(
  toolName: string,
  toolInput: Record<string, unknown>,
): string {
  const r = buildGateCard(toolName, toolInput);
  return "card" in r ? r.card : r.deny;
}

function buildPlainGateMessage(
  shortName: string,
  toolInput: Record<string, unknown>,
): string {
  switch (shortName) {
    case "github_trigger_workflow":
      return `Agent wants to trigger workflow **${cardField(toolInput.workflow_id)}** on branch **${cardField(toolInput.ref)}**${workflowInputs(toolInput.inputs)}. Allow?`;
    case "github_push_branch":
      return `Agent wants to push to branch **${cardField(toolInput.branch)}**${toolInput.force === true ? " (a force-push was requested; the push tool rejects force-pushes)" : ""}. Allow?`;
    case "create_pull_request":
      return `Agent wants to open PR: **${cardField(toolInput.title, "untitled")}** (${cardField(toolInput.base, "main")} ← ${cardField(toolInput.head)})${notShown("description", toolInput.body)}. Allow?`;
    case "create_issue":
      return `Agent wants to file an issue: **${cardField(toolInput.title, "untitled")}**${Array.isArray(toolInput.labels) && toolInput.labels.length ? ` with labels [${cardList(toolInput.labels)}]` : ""}${notShown("description", toolInput.body)}. Allow?`;
    case "kb_share_create":
      return `Agent wants to create a public share link for **${cardField(toolInput.documentPath)}**. Allow?`;
    case "kb_share_revoke": {
      const preview = cardField(toolInput.token, "unknown", 12);
      return `Agent wants to revoke share token **${preview}**. This is permanent. Allow?`;
    }
    case "routine_run":
      return `Agent wants to run routine **${cardField(toolInput.fnId)}** now, off-schedule. This fires real production work. Allow?`;
    // Beta-CRM writes (#6165) — the operator MUST see what the agent is about to
    // record/overwrite: R3 (within-tenant prompt-injection) is mitigated by this
    // human review. The gate string can egress to the operator's push/email when
    // they are offline (permission-callback → notifyOfflineUser), so it names the
    // DECISION-relevant fields (stage, amount, dates incl. last_contact, WHICH
    // fields change) but deliberately does NOT echo the verbatim third-party PII
    // values (contact name/company text, the note body) — those stay in the DB;
    // the operator opens the record in-app to review the exact text. (user-impact
    // F1: don't widen the third-party-PII egress surface beyond PA-30 recipients.)
    case "crm_contact_upsert": {
      const isNew = toolInput.contactId == null;
      const target = isNew ? "a NEW contact" : `contact **${cardField(toolInput.contactId)}**`;
      const parts: string[] = [];
      if (toolInput.stage != null) parts.push(`stage→${cardField(toolInput.stage)}`);
      if (toolInput.amount != null)
        parts.push(`amount→${cardField(toolInput.amount)}${toolInput.currency ? ` ${cardField(toolInput.currency)}` : ""}`);
      if (toolInput.lastContact != null) parts.push(`last_contact→${cardField(toolInput.lastContact)}`);
      if (toolInput.nextActionDate != null) parts.push(`next_action_date→${cardField(toolInput.nextActionDate)}`);
      if (toolInput.expectedCloseDate != null) parts.push(`expected_close→${cardField(toolInput.expectedCloseDate)}`);
      const textFields = ["name", "company", "role", "source", "nextAction", "amountBasis"].filter(
        (f) => toolInput[f] != null,
      );
      if (textFields.length) parts.push(`sets ${textFields.join(", ")}`);
      const detail = parts.length ? ` — ${parts.join("; ")}` : "";
      return `Agent wants to save ${target}${detail}. Open the record in-app to review the exact text before approving. Allow?`;
    }
    case "crm_note_append": {
      const lens = Array.isArray(toolInput.lens) ? cardList(toolInput.lens, "+") : cardField(toolInput.lens, "");
      const when = toolInput.occurredAt ? ` dated ${cardField(toolInput.occurredAt)}` : "";
      // The verbatim note body is third-party conversation PII — do NOT include it
      // (it would egress via offline push/email). Review the note text in-app.
      return `Agent wants to append a ${lens} note${when} to contact **${cardField(toolInput.contactId)}**. Open the record in-app to review the note text before approving. Allow?`;
    }
    case "crm_contact_set_stage":
      return `Agent wants to move contact **${cardField(toolInput.contactId)}** to stage **${cardField(toolInput.toStage)}**. Allow?`;
    // Workstream writes (#6304) — name the DECISION-relevant fields so the
    // founder can approve informed (the write hits a real GitHub issue).
    case "workstream_issue_create":
      return `Agent wants to create a GitHub issue: **${cardField(toolInput.title, "untitled")}**${toolInput.status ? ` (→ ${cardField(toolInput.status)})` : ""}${notShown("description", toolInput.body)}. Allow?`;
    case "workstream_issue_set_status":
      return `Agent wants to move issue **#${cardField(toolInput.number, "?")}** to **${cardField(toolInput.status)}**${toolInput.state_reason ? ` (${cardField(toolInput.state_reason)})` : ""}. Allow?`;
    case "workstream_issue_update_title":
      return `Agent wants to rename issue **#${cardField(toolInput.number, "?")}** to **${cardField(toolInput.title, "untitled")}**. Allow?`;
    case "workstream_issue_update_fields": {
      const parts: string[] = [];
      if (toolInput.body !== undefined) parts.push("body");
      if (Array.isArray(toolInput.labels)) parts.push(`labels→[${cardList(toolInput.labels)}]`);
      if (Array.isArray(toolInput.assignees)) parts.push(`assignees→[${cardList(toolInput.assignees)}]`);
      if (toolInput.milestone !== undefined)
        parts.push(`milestone→${toolInput.milestone === null ? "none" : cardField(toolInput.milestone)}`);
      const detail = parts.length ? ` — ${parts.join("; ")}` : "";
      return `Agent wants to edit issue **#${cardField(toolInput.number, "?")}**${detail}. Allow?`;
    }
    case "workstream_issue_close":
      return toolInput.reopen
        ? `Agent wants to REOPEN issue **#${cardField(toolInput.number, "?")}**. Allow?`
        : `Agent wants to close issue **#${cardField(toolInput.number, "?")}** (${cardField(toolInput.reason, "completed")}). Allow?`;
    // Tools whose gate became reachable with #11303 (previously default-gated and pre-approved around the gate): the card
    // must say what is being approved. None of these echo tool input beyond the named fields, and none puts a secret or
    // a confirmation email in the text (the offline path is content-free regardless).
    case "workspace_set_autonomous":
      return toolInput.value === true
        ? "Agent wants to turn autonomous mode ON for this workspace. While it is ON, the agent can run shell commands in the workspace without asking you first. Allow?"
        : toolInput.value === false
          ? "Agent wants to turn autonomous mode OFF for this workspace. The agent will ask before running shell commands. Allow?"
          : "Agent wants to change the autonomous-mode setting for this workspace. When it is ON, the agent runs shell commands without asking you first. Allow?";
    case "account_delete_initiate":
      return "Agent wants to start PERMANENT deletion of your account and all of its data. This cannot be undone. Allow?";
    case "account_export_enqueue":
      return "Agent wants to request a full export of your account data. Allow?";
    case "plausible_create_site":
      return `Agent wants to create the Plausible Analytics site **${cardField(toolInput.domain)}** (timezone ${cardField(toolInput.timezone, "UTC")}). Allow?`;
    case "plausible_add_goal":
      return `Agent wants to add a Plausible Analytics **${cardField(toolInput.goal_type)}** goal **${cardField(toolInput.value)}** to site **${cardField(toolInput.site_id)}**. Allow?`;
    case "plausible_get_stats":
      return `Agent wants to read Plausible Analytics stats for site **${cardField(toolInput.site_id)}** over **${cardField(toolInput.period, "30d")}**. Allow?`;
    default:
      return `Agent wants to use **${shortName}**. Allow?`;
  }
}
