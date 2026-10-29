// The user-facing half of the Claude CLI auth-failure handling (#11086). When the CLI replies that it cannot sign in, the raw
// line ("Not logged in · Please run /login") used to be streamed and persisted as the assistant's answer. This module turns a
// matcher hit into server-authored copy chosen from a CLOSED table keyed by `match_kind` x credential scheme, so no raw CLI
// text ever reaches a user and no tenant is ever shown subscription-token wording.
//
// Ordering contract (pinned by test/agent-auth-friendly-error-wire.test.ts): the matcher in ./agent-auth-match runs on the RAW
// message, the rewrite builds a NEW content array and never mutates the SDK message, and the diagnostic probe/tap observe the
// original object before any consumer sees the friendly text. This module imports neither the diagnostic nor Sentry
// (test/agent-auth-import-boundary.test.ts), so the #11085 removal cannot reach it.
//
// Copy rules: plain text only (the card renders plain text; no backticks), tenant (`api_key`) cells name only the Anthropic API
// key, `oauth_token` cells are for the scheme only the operator can hold (knowledge-base/legal/audits/2026-10-06-clo-9580-
// live-anthropic-terms-subscription-auth.md), and an unknown scheme gets a neutral cell that names neither.

import type { CredentialScheme } from "@/lib/credential-scheme";

import { matchAgentAuthFailure, type AgentAuthMatchKind } from "./agent-auth-match";

/** A matcher kind plus the lease-time kind (a stored credential the CLI is known to drop, refused before any CLI spawn). */
export type AuthFailureKind = AgentAuthMatchKind | "oauth_unusable";

/** The recovery sentence of the neutral cell: used when the credential scheme is unknown, so it names neither credential. */
const NEUTRAL = "check your credentials in Settings and try again";

type CopyCell = { readonly api_key: string; readonly oauth_token: string; readonly neutral: string };

const COPY: Record<Exclude<AuthFailureKind, "oauth_unusable">, CopyCell> & { oauth_unusable: CopyCell } = {
  not_logged_in: {
    api_key:
      "We couldn't sign in to Claude with your Anthropic API key, so nothing ran. Re-enter your API key in Settings and try again.",
    oauth_token:
      "We couldn't sign in to Claude with your saved subscription token, so nothing ran. Generate a new token with claude setup-token, save it in Settings, then try again.",
    neutral: `We couldn't sign in to Claude, so nothing ran. Please ${NEUTRAL}.`,
  },
  invalid_api_key: {
    api_key:
      "Anthropic rejected your API key. Check that it is active and copied in full, then re-enter it in Settings.",
    oauth_token:
      "Anthropic rejected your saved credential. Generate a new token with claude setup-token and save it in Settings.",
    neutral: `Anthropic rejected your credential. Please ${NEUTRAL}.`,
  },
  oauth_token_revoked: {
    // Unreachable for a tenant (an API key has no revocation reply); typed away by mapping to the invalid_api_key cell below.
    api_key:
      "Anthropic rejected your API key. Check that it is active and copied in full, then re-enter it in Settings.",
    oauth_token:
      "Your subscription token has been revoked or has expired. Generate a new one with claude setup-token and save it in Settings.",
    neutral: `Your credential has been revoked or has expired. Please ${NEUTRAL}.`,
  },
  session_expired: {
    api_key:
      "Your Claude session expired before we could finish. Start a new message, and if it happens again, re-enter your API key in Settings.",
    oauth_token:
      "Your Claude session expired before we could finish. Start a new message, and if it happens again, save a fresh token from claude setup-token.",
    neutral: `Your Claude session expired before we could finish. Start a new message, and if it happens again, ${NEUTRAL}.`,
  },
  structured: {
    api_key:
      "Claude couldn't authenticate your request. Re-enter your Anthropic API key in Settings and try again.",
    oauth_token:
      "Claude couldn't authenticate your request. Save a fresh token from claude setup-token in Settings and try again.",
    neutral: `Claude couldn't authenticate your request. Please ${NEUTRAL}.`,
  },
  oauth_unusable: {
    // Only the operator can hold an oauth row, so the tenant and neutral cells are defensive and never name a subscription.
    api_key:
      "We couldn't sign in to Claude with your Anthropic API key, so nothing ran. Re-enter your API key in Settings and try again.",
    oauth_token:
      "We couldn't sign in to Claude with your saved subscription token, so nothing ran. Generate a new token with claude setup-token, save it in Settings, then try again. Nothing was billed to your API key.",
    neutral: `We couldn't sign in to Claude, so nothing ran. Please ${NEUTRAL}.`,
  },
};

/** Kinds after which the chat cannot continue without a credential change; `session_expired` is bubble-only. */
const TERMINAL: Record<AuthFailureKind, boolean> = {
  not_logged_in: true,
  invalid_api_key: true,
  oauth_token_revoked: true,
  structured: true,
  oauth_unusable: true,
  session_expired: false,
};

/** The credential scheme a cell is chosen for, or undefined for the neutral cell. Anything else is treated as unknown. */
function knownScheme(scheme: unknown): CredentialScheme | undefined {
  return scheme === "api_key" || scheme === "oauth_token" ? scheme : undefined;
}

/** The copy for one (kind, scheme). Total: every kind has a cell and an unknown scheme falls to the neutral one. */
export function authFailureCopy(kind: AuthFailureKind, scheme: unknown): string {
  const cell = COPY[kind];
  const known = knownScheme(scheme);
  if (known === undefined) return cell.neutral;
  // A tenant API key has no revocation reply: map the unreachable cell to the invalid-key copy at lookup, not by dead data.
  if (kind === "oauth_token_revoked" && known === "api_key") return COPY.invalid_api_key.api_key;
  return cell[known];
}

export function isTerminalAuthFailure(kind: AuthFailureKind): boolean {
  return TERMINAL[kind];
}

/** The `error` frame for a credential the user has to fix. `credentialScheme` is present only for a known scheme. */
export interface AuthFailureFrame {
  type: "error";
  message: string;
  errorCode: "key_invalid";
  credentialScheme?: CredentialScheme;
}

/**
 * The lease refused a stored subscription credential of a class the CLI drops (`ByokLeaseError` cause `oauth_unusable`).
 * Duck-typed on purpose: this module must not import byok-lease (its static graph is heavy and partial test mocks of it would
 * undefine the class), and `name` + `cause` are the class's own contract.
 */
export function isOauthUnusableLeaseError(err: unknown): boolean {
  return err instanceof Error && err.name === "ByokLeaseError" && (err as { cause?: unknown }).cause === "oauth_unusable";
}

/** The recovery frame for a lease refusal of an unusable stored credential, or null for any other error. */
export function authFailureFrameFromLeaseError(err: unknown): AuthFailureFrame | null {
  return isOauthUnusableLeaseError(err) ? buildAuthFailureFrame("oauth_unusable", "oauth_token") : null;
}

/** The ONE producer of this frame, used at every site that can emit it (both runners, the lease catch, the ws-handler catch). */
export function buildAuthFailureFrame(kind: AuthFailureKind, scheme: unknown): AuthFailureFrame {
  const known = knownScheme(scheme);
  return {
    type: "error",
    message: authFailureCopy(kind, known),
    errorCode: "key_invalid",
    ...(known !== undefined ? { credentialScheme: known } : {}),
  };
}

export interface AgentAuthRewrite {
  kind: AgentAuthMatchKind;
  /** A NEW content array holding the friendly text; the SDK message is never mutated. */
  content: [{ type: "text"; text: string }];
  terminal: boolean;
  /** The frame to send once the bubble is finalized; only meaningful when `terminal`. */
  frame: AuthFailureFrame;
}

/**
 * Match the RAW message with the shared matcher and, on a hit, return the friendly replacement. Rewrites ONLY an assistant
 * message whose content is exactly one text block: a multi-block or tool-bearing `authentication_failed` message is left raw
 * (and is still observed by the probe). Never throws: the matcher swallows its own faults and returns null, which means "the
 * raw message passes through"; the rest is a table lookup and an array build.
 */
export function rewriteAgentAuthFailure(rawMessage: unknown, scheme: unknown): AgentAuthRewrite | null {
  const kind = matchAgentAuthFailure(rawMessage);
  if (kind === null) return null;
  if (!hasSingleTextBlock(rawMessage)) return null;
  return {
    kind,
    content: [{ type: "text", text: authFailureCopy(kind, scheme) }],
    terminal: isTerminalAuthFailure(kind),
    frame: buildAuthFailureFrame(kind, scheme),
  };
}

function hasSingleTextBlock(message: unknown): boolean {
  try {
    if (typeof message !== "object" || message === null) return false;
    const m = message as { type?: unknown; message?: unknown };
    if (m.type !== "assistant") return false;
    const inner = m.message as { content?: unknown } | null | undefined;
    const content = inner?.content;
    if (!Array.isArray(content) || content.length !== 1) return false;
    const block = content[0] as { type?: unknown } | null;
    return typeof block === "object" && block !== null && block.type === "text";
  } catch {
    return false;
  }
}
