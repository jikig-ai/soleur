// Chapter routing for the chapter-chunking PDF resolver (#3436 Phase 3).
//
// `selectChapter` runs a small, model-pinned routing turn over a question
// + outline (TOC). It returns one of three discriminated shapes:
//
//   - `selected`     — model returned a numeric chapter index, OR the
//                      reply fuzzy-matched a chapter title within
//                      Levenshtein < 0.3 of length.
//   - `ambiguous`    — model returned the literal "AMBIGUOUS" sentinel,
//                      or numeric+fuzzy parsing both failed. The runner
//                      handles this by replying "I can answer from
//                      chapter X or Y — which would you like?" and does
//                      NOT fire the answer turn.
//   - `cost-cap-hit` — adding the routing-turn cost to
//                      `state.totalCostUsd` would cross `perConvCap`.
//                      The runner emits the existing `cost_ceiling`
//                      directive and does not fire the answer turn.
//
// Per plan §Sharp Edges, the model is PINNED to Sonnet 4.6 / 200K — even
// if the parent runner switches to Opus-1M for KB chats. Routing-turn
// cost is reported via `routingCostUsd` so the runner can charge the
// session cost ledger BEFORE deciding whether to fire the answer turn.
//
// BYOK note: when `getCurrentByokLease()` returns a non-null lease, the
// router invokes `query()` inside the same ALS scope so the SDK picks
// up the user's API key. When null (Soleur-key path), `ANTHROPIC_API_KEY`
// from process env is used by the SDK — same as the other dispatch paths.

import { query } from "@anthropic-ai/claude-agent-sdk";
import type {
  SDKMessage,
  SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";

import type { ChapterIndex } from "./pdf-text-extract";

const ROUTING_MODEL = "claude-sonnet-4-6";
const AMBIGUOUS_SENTINEL = "AMBIGUOUS";
/**
 * Levenshtein-distance ratio threshold for the title-fuzzy-match
 * fallback. A reply that paraphrases a chapter title within 30% of the
 * title's length is treated as a hit. Tighter than 0.3 misses common
 * casing / punctuation drift; looser risks cross-chapter false matches.
 */
const FUZZY_RATIO = 0.3;

export interface SelectChapterArgs {
  question: string;
  outline: ChapterIndex[];
  userId: string;
  conversationCostState: { totalCostUsd: number; perConvCap: number };
}

export type SelectChapterResult =
  | {
      kind: "selected";
      /** 0-based index into `outline`. The user-visible "chapter <N>"
       *  number is `chapterIndex + 1`. */
      chapterIndex: number;
      alternates: number[];
      routingCostUsd: number;
    }
  | { kind: "ambiguous"; candidates: number[]; routingCostUsd: number }
  | { kind: "cost-cap-hit"; cap: number; totalCostUsd: number };

export async function selectChapter(
  args: SelectChapterArgs,
): Promise<SelectChapterResult> {
  const { question, outline, conversationCostState } = args;

  const systemPrompt = buildRouterSystemPrompt(outline);
  const userMessage = buildRouterUserMessage(question);

  let routingCostUsd = 0;
  let assistantText = "";

  // Drive the SDK turn. The router uses an empty MCP server set + tools
  // disabled (numeric/short reply only) so the routing turn is a single
  // request/response.
  const q = query({
    prompt: routerUserStream(userMessage),
    options: {
      model: ROUTING_MODEL,
      systemPrompt,
      allowedTools: [],
      maxTurns: 1,
    },
  });

  for await (const msg of q as AsyncIterable<SDKMessage>) {
    if (msg.type === "assistant") {
      const content = (msg as { message?: { content?: unknown } }).message
        ?.content;
      if (Array.isArray(content)) {
        for (const block of content) {
          if (
            block &&
            typeof block === "object" &&
            (block as { type?: string }).type === "text" &&
            typeof (block as { text?: unknown }).text === "string"
          ) {
            assistantText += (block as { text: string }).text;
          }
        }
      }
    } else if (msg.type === "result") {
      const cost = (msg as { total_cost_usd?: number }).total_cost_usd;
      if (typeof cost === "number" && cost >= 0) routingCostUsd = cost;
    }
  }

  const projectedTotal = conversationCostState.totalCostUsd + routingCostUsd;
  if (projectedTotal >= conversationCostState.perConvCap) {
    return {
      kind: "cost-cap-hit",
      cap: conversationCostState.perConvCap,
      totalCostUsd: projectedTotal,
    };
  }

  const reply = assistantText.trim();

  if (reply.toUpperCase() === AMBIGUOUS_SENTINEL) {
    return { kind: "ambiguous", candidates: [], routingCostUsd };
  }

  // 1. Numeric parse — strict 1-based, must be in range.
  const numericMatch = reply.match(/^\s*(\d+)\b/);
  if (numericMatch) {
    const oneBased = Number.parseInt(numericMatch[1], 10);
    if (
      Number.isFinite(oneBased) &&
      oneBased >= 1 &&
      oneBased <= outline.length
    ) {
      return {
        kind: "selected",
        chapterIndex: oneBased - 1,
        alternates: [],
        routingCostUsd,
      };
    }
  }

  // 2. Fuzzy match — Levenshtein distance / title length.
  const fuzzyHit = fuzzyMatchTitle(reply, outline);
  if (fuzzyHit !== null) {
    return {
      kind: "selected",
      chapterIndex: fuzzyHit,
      alternates: [],
      routingCostUsd,
    };
  }

  // 3. Both parse strategies failed — ambiguous.
  return { kind: "ambiguous", candidates: [], routingCostUsd };
}

function buildRouterSystemPrompt(outline: ChapterIndex[]): string {
  const tocLines = outline
    .map((c, i) => `${i + 1}. ${c.title} (pages ${c.startPage}-${c.endPage})`)
    .join("\n");
  return [
    "You are a chapter router for a large PDF. The user asked a question.",
    "Below is the table of contents. Pick the SINGLE chapter number (1-N)",
    "that best answers the question, or reply with the literal text",
    `"${AMBIGUOUS_SENTINEL}" if multiple chapters apply about equally.`,
    "Reply with JUST the number (or AMBIGUOUS) — nothing else.",
    "",
    "Table of contents:",
    tocLines,
  ].join("\n");
}

function buildRouterUserMessage(question: string): string {
  return `Question: ${question}\n\nWhich chapter number best answers this?`;
}

async function* routerUserStream(
  text: string,
): AsyncIterable<SDKUserMessage> {
  yield {
    type: "user",
    parent_tool_use_id: null,
    session_id: `chapter-router-${Date.now()}`,
    message: {
      role: "user",
      content: text,
      // biome-ignore lint/suspicious/noExplicitAny: SDK MessageParam accepts string|array
    } as any,
  } as SDKUserMessage;
}

/**
 * Fuzzy-match the assistant reply against chapter titles. Returns the
 * 0-based index of the best match if its Levenshtein distance is less
 * than `FUZZY_RATIO * title.length`; otherwise `null`. Lowercased
 * normalization handles casing drift.
 */
function fuzzyMatchTitle(
  reply: string,
  outline: ChapterIndex[],
): number | null {
  const normReply = reply.toLowerCase().trim();
  if (normReply.length === 0) return null;
  let bestIdx = -1;
  let bestRatio = Number.POSITIVE_INFINITY;
  for (let i = 0; i < outline.length; i++) {
    const title = outline[i].title.toLowerCase();
    const dist = levenshtein(normReply, title);
    const ratio = dist / Math.max(title.length, 1);
    if (ratio < bestRatio) {
      bestRatio = ratio;
      bestIdx = i;
    }
  }
  if (bestIdx >= 0 && bestRatio < FUZZY_RATIO) return bestIdx;
  return null;
}

/** Levenshtein edit distance — iterative two-row DP. */
function levenshtein(a: string, b: string): number {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;
  let prev = new Array<number>(b.length + 1);
  let curr = new Array<number>(b.length + 1);
  for (let j = 0; j <= b.length; j++) prev[j] = j;
  for (let i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      curr[j] = Math.min(
        curr[j - 1] + 1,
        prev[j] + 1,
        prev[j - 1] + cost,
      );
    }
    [prev, curr] = [curr, prev];
  }
  return prev[b.length];
}
