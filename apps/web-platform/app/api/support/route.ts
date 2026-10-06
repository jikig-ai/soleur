// POST /api/support — the in-app support chat's streaming transport
// (feat-wire-concierge-support-chat, ADR-113 / CTO Option D).
//
// This route is DELIBERATELY decoupled from the Command Center WebSocket
// (server/ws-handler.ts): the WS is single-per-user (supersedeExistingUserSocket)
// and support is a concurrent conversation, so support streams over its OWN HTTP
// Server-Sent-Events response instead of the shared WS. It reuses the finished
// support execution verbatim: `dispatchSoleurGo` takes `sendToClient` as an
// injected sink, so we hand it an SSE-writing adapter and pass `persona:"support"`.
//
// It imports NEITHER ws-handler's `sendToClient` NOR the `sessions` map — that
// isolation is what mechanically guarantees a support turn cannot disturb a
// Command Center session (asserted by test/support-route-isolation.test.ts).

import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { resolveIdentity } from "@/lib/feature-flags/identity";
import { getRuntimeFlag } from "@/lib/feature-flags/server";
import { dispatchSoleurGo } from "@/server/cc-dispatcher";
import { resolveOrCreateSupportConversation } from "@/server/support-conversation";
import {
  formatSupportSseFrame,
  supportTerminalPrefixFrames,
  SUPPORT_TERMINAL_FRAME_TYPES,
} from "@/lib/support-sse";
import {
  consumeSupportEscalation,
  clearSupportEscalation,
} from "@/server/support-escalation";
import { truncateSupportHandoffTask } from "@/lib/support-handoff";
import { sanitizeErrorForClient } from "@/server/error-sanitizer";
import { reportSilentFallback } from "@/server/observability";
import { verifiedUserId } from "@/server/request-auth";
import { createChildLogger } from "@/server/logger";
import type { WSMessage } from "@/lib/types";

const log = createChildLogger("support-route");

// #9539 — one in-flight support turn per conversation, enforced at the
// transport boundary. `resolveOrCreateSupportConversation` is STICKY (every
// non-forceNew POST resolves the same row), and the runner warm-reuses the
// conversation's Query — a second POST rebinds `state.events` to the new
// request's sink, so the older stream starves (pre-existing frame-hijack)
// and the per-conversation escalation flag can cross-attribute a deny to an
// innocent turn. The support client already aborts prior turns before
// sending, so a 409 here only greets cross-tab/double-send races — a much
// better answer than silently consuming the wrong turn's frames.
const SUPPORT_TURNS_IN_FLIGHT = new Set<string>();

// Hard cap on how long the SSE response is held open waiting for the turn to
// finish. A well-behaved turn ends with a `stream_end`/`session_ended` frame far
// sooner; this only backstops a turn that crashes mid-stream or is reaped without
// a terminal frame (the client also has its own 30s idle watchdog).
const SUPPORT_TURN_MAX_MS = 120_000;

export async function POST(request: Request): Promise<Response> {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/support", origin);

  const supabase = await createClient();
  const userId = await verifiedUserId(request);
  if (!userId) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  // SECURITY BOUNDARY (ADR-113 "Live rollout gate"): the live Concierge backend
  // is gated behind `support-live`, default OFF. The front-end only calls this
  // route when the flag is ON, but the endpoint is authenticated-reachable on
  // its own, so it MUST re-check server-side — otherwise a direct POST would
  // invoke the support Concierge (and its kb-search read surface) while the
  // feature is meant to be dark. `resolveIdentity` fails CLOSED (env mirror
  // FLAG_SUPPORT_LIVE=0), so a Flagsmith outage can only ever DENY. While OFF the
  // route is invisible (404) — the client shows its canned interface-preview.
  const identity = await resolveIdentity(supabase);
  if (!(await getRuntimeFlag("support-live", identity))) {
    return new Response(JSON.stringify({ error: "Not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

  const body = (await request.json().catch(() => null)) as
    | { message?: unknown; newConversation?: unknown }
    | null;
  const message = typeof body?.message === "string" ? body.message.trim() : "";
  // "Start a new conversation" — the client sets this on the first send after
  // the user taps the panel's new-thread button (or after a cost-cap error).
  const forceNew = body?.newConversation === true;
  if (message.length === 0) {
    return new Response(JSON.stringify({ error: "Missing message" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Resolve-or-create the repo-less kind='support' conversation BEFORE opening the
  // stream so a failure returns a clean 500 (the client then shows its canned
  // fallback) rather than a half-open stream. dispatchSoleurGo requires a
  // persisted row (ownership probe / workspace_id / messages FK).
  let conversationId: string;
  try {
    conversationId = await resolveOrCreateSupportConversation(userId, { forceNew });
  } catch (err) {
    reportSilentFallback(err, { feature: "support", op: "support-route.resolveConversation", extra: { userId } });
    return new Response(JSON.stringify({ error: "Support is unavailable right now." }), {
      status: 503,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Synchronous check-then-open: between this and `start()`'s `add` there is
  // no await, so two concurrent POSTs cannot both slip the guard.
  if (SUPPORT_TURNS_IN_FLIGHT.has(conversationId)) {
    log.info({ sec: true, conversationId }, "support-turn-busy");
    return new Response(
      JSON.stringify({ error: "A support turn is already in flight." }),
      {
        status: 409,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      let closed = false;

      SUPPORT_TURNS_IN_FLIGHT.add(conversationId);
      // The `delete` lives in `finally` — a future edit that throws inside
      // this setup would otherwise strand the key and 409 the conversation
      // until process restart (both fix-round seats flagged the shape).
      try {
      // #9539 — drop any escalation flag left by a PRIOR turn on this reused
      // support conversation (`resolveOrCreateSupportConversation` is sticky
      // and the stream has no `cancel` handler, so a zombie dispatch can
      // record a deny after its own teardown). Clearing at stream OPEN, not
      // only at teardown, narrows the record→consume window to this turn —
      // without it the next innocent turn's terminal frame would consume the
      // stale flag and render a handoff for a deny that never happened. A
      // flag recorded by a zombie turn DURING this turn's window is the
      // accepted residual (the busy-guard above blocks the concurrent-POST
      // form of it).
      clearSupportEscalation(conversationId);
      const handoffTask = truncateSupportHandoffTask(message);

      // CRITICAL: `dispatchSoleurGo` resolves as soon as the turn's SDK query is
      // *started* — the runner consumes it on a fire-and-forget background task
      // (`void consumeStream` in soleur-go-runner.ts), so `onText`/`stream` frames
      // arrive AFTER the dispatch promise settles. The Command Center gets away
      // with this because its WebSocket sink is process-lived, but our per-request
      // SSE stream would close before the first token if we closed on the dispatch
      // promise. So we hold the response open until a TERMINAL frame arrives
      // (stream_end / session_ended / error), or a hard cap fires.
      let settleTurn!: () => void;
      const turnComplete = new Promise<void>((resolve) => {
        settleTurn = resolve;
      });
      let settled = false;
      const finishTurn = () => {
        if (!settled) {
          settled = true;
          settleTurn();
        }
      };

      const enqueue = (msg: WSMessage): boolean => {
        if (closed) return false;
        // #9539 — at the terminal boundary, if a deny path recorded an
        // escalation this turn, emit the `support_handoff` frame BEFORE the
        // terminal frame (the stream closes on terminal, so ordering is
        // load-bearing; a `stream` frame's replace-text semantics is the
        // other reason the emit is terminal-adjacent). Consume-on-read makes
        // this fire exactly once per recorded deny, never unconditionally.
        const consumed = SUPPORT_TERMINAL_FRAME_TYPES.has(msg.type)
          ? consumeSupportEscalation(conversationId)
          : null;
        try {
          for (const frame of supportTerminalPrefixFrames(
            msg,
            consumed === null
              ? null
              : {
                  type: "support_handoff",
                  task: handoffTask,
                  conversationId,
                  // #9556 — undefined drops the key at JSON.stringify, keeping
                  // the frame additive-safe for dep-unwired emitters.
                  repoConnected: consumed.repoConnected,
                },
          )) {
            controller.enqueue(encoder.encode(formatSupportSseFrame(frame)));
          }
        } catch {
          // A consumed flag with a dead stream is neither `emitted` nor
          // `cleared-unconsumed` — mark it so the deny→emit join still reads.
          // The stream is already dead; the turn must not wait out the cap.
          if (consumed !== null) {
            log.warn(
              { sec: true, conversationId, source: consumed.source },
              "support-handoff-emit-failed",
            );
          }
          if (SUPPORT_TERMINAL_FRAME_TYPES.has(msg.type)) finishTurn();
          return false;
        }
        if (consumed !== null) {
          log.info(
            {
              sec: true,
              conversationId,
              source: consumed.source,
              // #9556 — which copy arm the user saw is derivable per turn.
              repoConnected: consumed.repoConnected,
            },
            "support-handoff-emitted",
          );
        }
        if (SUPPORT_TERMINAL_FRAME_TYPES.has(msg.type)) finishTurn();
        return true;
      };

      const capTimer = setTimeout(finishTurn, SUPPORT_TURN_MAX_MS);

      // Fire the dispatch but do NOT await it for turn completion (it settles
      // early). We forward every frame to the SSE sink; a setup-time rejection
      // becomes an honest error frame the client renders, then closes the turn.
      void dispatchSoleurGo({
        userId,
        conversationId,
        userMessage: message,
        currentRouting: { kind: "soleur_go_pending" },
        sendToClient: (_uid: string, msg: WSMessage) => enqueue(msg),
        // Support has no sticky workflow (persona short-circuits routing).
        persistActiveWorkflow: async () => {},
        persona: "support",
      }).catch((err) => {
        reportSilentFallback(err, { feature: "support", op: "support-route.dispatch", extra: { userId, conversationId } });
        enqueue({ type: "error", message: sanitizeErrorForClient(err) } as WSMessage);
        finishTurn();
      });

      await turnComplete;
      clearTimeout(capTimer);
      closed = true;
      // Teardown flag hygiene: a deny recorded by a turn that died without a
      // terminal frame (cap timer, client abort, crash) must not bleed into
      // the next send on this reused conversation. The
      // `support-handoff-cleared-unconsumed` marker distinguishes "flag
      // orphaned" from "never recorded" in the deny→emit observability join.
      if (clearSupportEscalation(conversationId)) {
        log.info({ sec: true, conversationId }, "support-handoff-cleared-unconsumed");
      }
      } finally {
        SUPPORT_TURNS_IN_FLIGHT.delete(conversationId);
        try {
          controller.close();
        } catch {
          // already closed
        }
      }
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    },
  });
}
