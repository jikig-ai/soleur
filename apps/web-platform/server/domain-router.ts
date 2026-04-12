import { ROUTABLE_DOMAIN_LEADERS, type DomainLeaderId } from "./domain-leaders";
import { createChildLogger } from "./logger";

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

  try {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 200,
        messages: [
          {
            role: "user",
            content: `Classify this user message into the most relevant domain leader(s). Return ONLY a JSON array of leader IDs, ranked by relevance. Return at most ${MAX_LEADERS_PER_MESSAGE} leaders. If no domain clearly matches, return ["cpo"].

Domain leaders:
${assessmentList}
${contextSection}

User message: "${message}"

Respond with ONLY a JSON array like ["cmo","clo"]. No explanation.`,
          },
        ],
      }),
    });

    if (!response.ok) {
      throw new Error(`Anthropic API error: ${response.status}`);
    }

    const data = (await response.json()) as {
      content: Array<{ type: string; text?: string }>;
    };
    const text = data.content[0]?.type === "text" ? (data.content[0].text ?? "") : "";
    const parsed = JSON.parse(text.trim()) as string[];

    // Validate that returned IDs are actual leaders
    const validIds = new Set<string>(ROUTABLE_DOMAIN_LEADERS.map((l) => l.id));
    const validated = parsed.filter((id): id is DomainLeaderId =>
      validIds.has(id),
    );

    if (validated.length === 0) {
      return ["cpo"]; // Fallback to CPO as general advisor
    }

    return validated.slice(0, MAX_LEADERS_PER_MESSAGE);
  } catch (err) {
    log.error({ err }, "Classification failed, falling back to CPO");
    return ["cpo"]; // Fallback on any error
  }
}
