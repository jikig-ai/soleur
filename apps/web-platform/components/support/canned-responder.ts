// feat-support-interface — THE BACKEND SEAM.
//
// This is the ONLY file that produces support replies. Today it is SYNCHRONOUS
// and returns canned copy (no LLM, no network). When the real support backend
// lands, change this to `async`/return a Promise AND update the single caller
// (use-support-chat.ts `send`) to `await` it — that one caller plus this file are
// the entire swap surface; no UI component contains canned copy.

import { SUPPORT_KB_HREF } from "./support-persona";

const COMING_SOON =
  "Live support chat is coming soon. In the meantime, you can browse your knowledge base for guides";

// Keyed answers for the 3 starter chips. Each restates the coming-soon framing
// and points at a real escape hatch so a stuck user is never dead-ended.
const KEYED_REPLIES: Record<string, string> = {
  routines:
    `To create a routine, open **Routines** from the left sidebar and choose "New routine" — ` +
    `you'll pick a schedule and the work it should run. ${COMING_SOON}: ${SUPPORT_KB_HREF}.`,
  "knowledge-base":
    `Your **Knowledge Base** lives in the left sidebar under "Knowledge Base" — it's where your ` +
    `docs, conventions, and learnings are organized. ${COMING_SOON}: ${SUPPORT_KB_HREF}.`,
  workstream:
    `The **Workstream** is your board for tracking work in progress across columns. ` +
    `Open it from the left sidebar to see what's active. ${COMING_SOON}: ${SUPPORT_KB_HREF}.`,
};

const GENERIC_REPLY =
  `Thanks for the question! ${COMING_SOON}: ${SUPPORT_KB_HREF}. ` +
  `A teammate will be able to answer live questions here soon.`;

/**
 * Returns a support reply for the user's message.
 *
 * @param _userMessage the user's (already trimmed, non-empty) message text.
 * @param chipKey optional starter-chip key when the message came from a chip tap.
 * @returns the reply text (synchronous today). See the file header for the
 *   backend-swap contract.
 */
export function getSupportReply(
  _userMessage: string,
  chipKey?: string,
): string {
  if (chipKey && KEYED_REPLIES[chipKey]) {
    return KEYED_REPLIES[chipKey];
  }
  return GENERIC_REPLY;
}
