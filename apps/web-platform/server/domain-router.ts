import { ROUTABLE_DOMAIN_LEADERS, type DomainLeaderId } from "./domain-leaders";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";

const log = createChildLogger("domain");

// Assessment questions ported from brainstorm-domain-config.md
// Only routable leaders are included — internal leaders (e.g. "system") are excluded.
const DOMAIN_ASSESSMENT: Partial<Record<DomainLeaderId, string>> = {
  cmo: "Does this involve content, brand, SEO, pricing, or marketing?",
  cto: "Does this require architectural decisions, code review, or technical assessment?",
  cfo: "Does this involve budgeting, revenue, or financial planning?",
  cpo: "Does this involve product strategy, specs, UX, or competitive analysis?",
  cro: "Does this involve sales, pipeline, outbound, or deal negotiation?",
  coo: "Does this involve operations, vendors, tools, or expense tracking?",
  clo: "Does this involve legal documents, compliance, or privacy?",
  cco: "Does this involve support, community, or customer engagement?",
};

const MAX_LEADERS_PER_MESSAGE = 3;

// Structured-output schema (#5186): the model returns leader IDs wrapped in an
// object (structured-output roots are objects, not top-level arrays).
// `additionalProperties: false` is REQUIRED; the validIds filter + MAX cap stay
// post-parse (the schema only guarantees a well-formed string array).
const LEADERS_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["leaders"],
  properties: {
    leaders: { type: "array", items: { type: "string" } },
  },
} as const;

export interface RouteResult {
  leaders: DomainLeaderId[];
  source: "auto" | "mention";
}

/**
 * Parse @-mentions from a message. Case-insensitive matching against
 * leader IDs and names (e.g., @CMO, @cmo, @CTO).
 * Returns only valid leader IDs; invalid mentions are ignored.
 */
export function parseAtMentions(
  message: string,
  customNames?: Record<string, string>,
): DomainLeaderId[] {
  // Build reverse lookup: custom name (lowercase) -> leader ID
  const customNameMap = new Map<string, DomainLeaderId>();
  if (customNames) {
    for (const [leaderId, name] of Object.entries(customNames)) {
      if (name) {
        // Map the full custom name and its first word (for multi-word names)
        customNameMap.set(name.toLowerCase(), leaderId as DomainLeaderId);
        const firstWord = name.split(/\s+/)[0];
        if (firstWord) customNameMap.set(firstWord.toLowerCase(), leaderId as DomainLeaderId);
      }
    }
  }

  const mentionPattern = /@(\w+)/g;
  const mentions: DomainLeaderId[] = [];
  const seen = new Set<DomainLeaderId>();

  let match: RegExpExecArray | null;
  while ((match = mentionPattern.exec(message)) !== null) {
    const tag = match[1].toLowerCase();

    // Check role ID and role name first
    let leader = ROUTABLE_DOMAIN_LEADERS.find(
      (l) => l.id === tag || l.name.toLowerCase() === tag,
    );

    // Fall back to custom name lookup
    if (!leader) {
      const customId = customNameMap.get(tag);
      if (customId) {
        leader = ROUTABLE_DOMAIN_LEADERS.find((l) => l.id === customId);
      }
    }

    if (leader && !seen.has(leader.id)) {
      seen.add(leader.id);
      mentions.push(leader.id);
    }
  }

  return mentions;
}

/**
 * Route a user message to 1-N domain leaders via auto-detection or @-mention override.
 *
 * If @-mentions are present, only mentioned leaders respond (override mode).
 * Otherwise, uses Claude API to classify which domains are relevant.
 * Falls back to CPO as general advisor if no domains match.
 */
export async function routeMessage(
  message: string,
  apiKey: string,
  context?: { path?: string; type?: string; content?: string },
  customNames?: Record<string, string>,
): Promise<RouteResult> {
  // Check for explicit @-mentions first (override mode)
  const mentions = parseAtMentions(message, customNames);
  if (mentions.length > 0) {
    return { leaders: mentions.slice(0, MAX_LEADERS_PER_MESSAGE), source: "mention" };
  }

  // Auto-detect via Claude API classification
  const leaders = await classifyMessage(message, apiKey, context);
  return { leaders, source: "auto" };
}

/**
 * Use Claude API to classify which domain leaders should respond to a message.
 * Returns a ranked list of leader IDs, capped at MAX_LEADERS_PER_MESSAGE.
 */
async function classifyMessage(
  message: string,
  apiKey: string,
  context?: { path?: string; type?: string; content?: string },
): Promise<DomainLeaderId[]> {
  const assessmentList = Object.entries(DOMAIN_ASSESSMENT)
    .map(([id, question]) => {
      const leader = ROUTABLE_DOMAIN_LEADERS.find((l) => l.id === id);
      return `- ${id} (${leader?.title ?? id}): ${question}`;
    })
    .join("\n");

  const contextSection = context?.path
    ? `\nThe user is viewing: ${context.path} (${context.type ?? "unknown"})`
    : "";

  // Hoisted so the catch below can say HOW the turn ended: an end_turn with
  // unparseable JSON and a truncated or refused turn are different defects.
  let stopReason = "no-response";

  try {
    // NOTE: this inline Anthropic Messages request mirrors the shared
    // `postAnthropicMessage` helper in `inngest/functions/_cron-shared.ts`.
    // It is kept inline (not routed through the helper) on purpose:
    // `_cron-shared.ts` statically imports octokit/github-app, and this module
    // is on the interactive request path and must stay leaf-light. Mirror any
    // change to EITHER contract in BOTH places — the request side (header
    // version, output_config shape, new required field) AND the RESPONSE-PARSE
    // side. Both are pinned mechanically by the selection-predicate parity test
    // in `apps/web-platform/test/anthropic-text-block-parity.test.ts`; this NOTE
    // is the pointer, not the enforcement.
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        // Literal on purpose (this module stays leaf-light); domain-router.test.ts pins
        // it equal to HAIKU_MODEL, the tier SSOT the pricing table keys on.
        model: "claude-haiku-5-5",
        max_tokens: 200,
        messages: [
          {
            role: "user",
            content: `Classify this user message into the most relevant domain leader(s). Return the leader IDs ranked by relevance, at most ${MAX_LEADERS_PER_MESSAGE} leaders. If no domain clearly matches, return ["cpo"].

Domain leaders:
${assessmentList}
${contextSection}

User message: "${message}"

Respond with ONLY a JSON object like {"leaders":["cmo","clo"]}. No explanation.`,
          },
        ],
        // Structured output (#5186): guarantees a schema-valid {leaders:[...]}
        // object so the response needs no fence-stripping.
        //
        // effort "low" (Haiku 5.5): the model runs adaptive thinking by default and
        // thinking tokens count against max_tokens. At 200 tokens a default-effort
        // request was seen (2026-10-08 probe) emitting `thinking` + text at up to 148
        // output tokens; at effort low it emitted text only, 17-21 tokens. The probe also
        // showed effort and json_schema are accepted together. Do NOT add
        // `thinking: {type: "disabled"}` (capability flag unresolved), a `fallbacks`
        // field (Haiku has no server-side fallback), or assistant prefill (400).
        output_config: {
          effort: "low",
          format: { type: "json_schema", schema: LEADERS_OUTPUT_SCHEMA },
        },
      }),
    });

    if (!response.ok) {
      throw new Error(`Anthropic API error: ${response.status}`);
    }

    const data = (await response.json()) as {
      content: Array<{ type: string; text?: string }>;
      stop_reason?: string;
      stop_details?: { category?: string };
    };
    // First TEXT block, not a fixed position: a thinking-by-default model puts a
    // thinking block first (#8392). Selection is an ALLOWLIST of `text` — a
    // `!== "thinking"` denylist returns undefined on tool_use / redacted_thinking
    // and reopens the same silent-empty class. Byte-mirrors the helper copy,
    // Array.isArray included: `.find` on a non-array `content` (a degraded 200,
    // a proxy error body) would THROW where the old read returned "".
    const text = Array.isArray(data.content)
      ? (data.content.find((b) => b.type === "text")?.text ?? "")
      : "";
    // Make the silent ["cpo"] fallback visible (cq-silent-fallback-must-mirror-to-sentry).
    // No usable text means the budget was spent on thinking, the turn was cut at
    // max_tokens, or the model refused. Message path with err = null: an Error argument
    // is captured by the pino mirror first and the tagged Sentry event is deduplicated
    // away (#8629). `extra` is a closed set of enum-like values; the user's message, the
    // context and the key never ride along.
    stopReason = typeof data.stop_reason === "string" ? data.stop_reason : "unknown";
    if (text === "" || stopReason === "max_tokens" || stopReason === "refusal") {
      const category = data.stop_details?.category;
      reportSilentFallback(null, {
        feature: "domain-router",
        op: "no-text-block",
        message: "domain router got no usable text block from the classifier — falling back to cpo",
        extra: {
          stop_reason: stopReason,
          ...(typeof category === "string" ? { category } : {}),
          model: "claude-haiku-5-5",
        },
      });
    }
    // Structured output guarantees schema-valid JSON — parse directly, no fence strip.
    const parsed = JSON.parse(text) as { leaders?: unknown };
    const leaders = Array.isArray(parsed.leaders) ? parsed.leaders : [];

    // Validate that returned IDs are actual leaders
    const validIds = new Set<string>(ROUTABLE_DOMAIN_LEADERS.map((l) => l.id));
    const validated = leaders.filter((id): id is DomainLeaderId =>
      typeof id === "string" && validIds.has(id),
    );

    if (validated.length === 0) {
      return ["cpo"]; // Fallback to CPO as general advisor
    }

    return validated.slice(0, MAX_LEADERS_PER_MESSAGE);
  } catch (err) {
    log.error({ err, stop_reason: stopReason }, "Classification failed, falling back to CPO");
    return ["cpo"]; // Fallback on any error
  }
}
