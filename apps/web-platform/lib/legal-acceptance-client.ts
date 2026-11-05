// Browser-side helpers shared by the legal-acceptance card and its email-code dialog (#12011 PR-C, ADR-319). Client-safe:
// no server imports. Everything here maps a network answer to wording that never claims more than happened.

import { LEGAL_COPY } from "@/lib/legal-acceptance-copy";
import { PENDING_WATCHDOG_MS } from "@/lib/pending-timing";
import {
  LEGAL_SEND_REASONS,
  LEGAL_VERIFY_REASONS,
  isLegalChoice,
  isLegalDecideResult,
  type LegalChoiceWire,
  type LegalDecideResult,
  type LegalReauthSendResult,
  type LegalReauthVerifyResult,
} from "@/lib/legal-acceptance-wire";

/** What the card needs to show a recorded answer. `decidedAt` is null when the server did not say. */
export interface LegalRowFacts {
  choice: LegalChoiceWire;
  version: string;
  decidedAt: string | null;
  reauthAt: string | null;
  requestedEdit: string | null;
}

/**
 * How a POST ended.
 *   - `ok`: 2xx with a readable body.
 *   - `rejected`: a genuine 4xx (not 429) from our own route. The request was refused, so nothing was written.
 *   - `reverify`: HTTP 403 with `{error:"reverify"}`: the email check no longer counts (decide route, contract 1).
 *   - `unknown`: everything else (5xx, 429, a network error, a timeout, an abort, an unreadable body). A committed row can
 *     sit behind any of these, so the caller must never say "nothing was recorded" for it.
 */
export type LegalPost<T> = { kind: "ok"; value: T } | { kind: "rejected" } | { kind: "reverify" } | { kind: "unknown" };

async function isReverifyBody(res: Response): Promise<boolean> {
  try {
    const b = (await res.json()) as { error?: unknown } | null;
    return !!b && typeof b === "object" && b.error === "reverify";
  } catch {
    return false;
  }
}

export async function postJson(url: string, body: unknown): Promise<LegalPost<unknown>> {
  let res: Response;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
      ...(typeof AbortSignal !== "undefined" && typeof AbortSignal.timeout === "function" ? { signal: AbortSignal.timeout(PENDING_WATCHDOG_MS) } : {}),
    });
  } catch {
    return { kind: "unknown" };
  }
  if (!res.ok) {
    if (res.status === 403 && (await isReverifyBody(res))) return { kind: "reverify" };
    if (res.status >= 400 && res.status < 500 && res.status !== 429) return { kind: "rejected" };
    return { kind: "unknown" };
  }
  try {
    return { kind: "ok", value: await res.json() };
  } catch {
    return { kind: "unknown" };
  }
}

export function parseSend(v: unknown): LegalReauthSendResult | null {
  if (!v || typeof v !== "object") return null;
  const o = v as { ok?: unknown; state?: unknown; reason?: unknown };
  if (o.ok === true && o.state === "sent") return { ok: true, state: "sent" };
  if (o.ok === false && typeof o.reason === "string" && (LEGAL_SEND_REASONS as readonly string[]).includes(o.reason)) {
    return { ok: false, reason: o.reason as (typeof LEGAL_SEND_REASONS)[number] };
  }
  return null;
}

export function parseVerify(v: unknown): LegalReauthVerifyResult | null {
  if (!v || typeof v !== "object") return null;
  const o = v as { ok?: unknown; reason?: unknown };
  if (o.ok === true) return { ok: true };
  if (o.ok === false && typeof o.reason === "string" && (LEGAL_VERIFY_REASONS as readonly string[]).includes(o.reason)) {
    return { ok: false, reason: o.reason as (typeof LEGAL_VERIFY_REASONS)[number] };
  }
  return null;
}

export async function postLegalDecide(
  keyName: string,
  body: { choice: LegalChoiceWire; textHash: string; note?: string },
): Promise<LegalPost<LegalDecideResult>> {
  const r = await postJson(`/api/legal-acceptance/${encodeURIComponent(keyName)}/decide`, body);
  if (r.kind !== "ok") return r;
  return isLegalDecideResult(r.value) ? { kind: "ok", value: r.value } : { kind: "unknown" };
}

/**
 * `recheck` says what the email check needs next: "code" = the confirmation is too old, enter or send a code again from
 * the code step; "start" = the server no longer counts the check, go back to the send step.
 */
export type DecideInterpretation =
  | { kind: "recorded"; row: LegalRowFacts; already: boolean }
  | { kind: "error"; message: string; reload: boolean; recheck?: "code" | "start" };

/**
 * Reads the server's decide answer. A row is shown ONLY for `recorded` (with the choice the server names) and for
 * `already_recorded` WITH the server's choice. Everything else is an error that records nothing on screen.
 */
export function interpretDecide(
  post: LegalPost<LegalDecideResult>,
  sent: { choice: LegalChoiceWire; note?: string; version: string },
  codePath: boolean,
): DecideInterpretation {
  if (post.kind === "rejected") return { kind: "error", message: LEGAL_COPY.errors.nothingRecorded, reload: false };
  if (post.kind === "reverify") {
    return codePath
      ? { kind: "error", message: LEGAL_COPY.dialog.reverify, reload: false, recheck: "start" }
      : { kind: "error", message: LEGAL_COPY.errors.nothingRecorded, reload: false };
  }
  if (post.kind === "unknown") return { kind: "error", message: LEGAL_COPY.errors.unknownResult, reload: true };
  const r = post.value;
  const unknown = { kind: "error", message: LEGAL_COPY.errors.unknownResult, reload: true } as const;
  switch (r.outcome) {
    case "recorded": {
      // The service always names the choice it recorded; an answer without it is unreadable, not a success.
      if (!isLegalChoice(r.choice)) return unknown;
      return {
        kind: "recorded",
        already: false,
        row: {
          choice: r.choice,
          version: sent.version,
          decidedAt: typeof r.decidedAt === "string" ? r.decidedAt : null,
          reauthAt: typeof r.reauthAt === "string" ? r.reauthAt : null,
          requestedEdit: r.choice === "request_changes" && r.choice === sent.choice && sent.note ? sent.note : null,
        },
      };
    }
    case "already_recorded": {
      // The second tab: what is on screen comes from the server's answer. Without its choice nothing can be shown. The
      // note of the other tab's answer is not echoed, so none is shown here (the card says to reload to see it).
      if (!isLegalChoice(r.choice)) return unknown;
      return {
        kind: "recorded",
        already: true,
        row: {
          choice: r.choice,
          version: sent.version,
          decidedAt: typeof r.decidedAt === "string" ? r.decidedAt : null,
          reauthAt: typeof r.reauthAt === "string" ? r.reauthAt : null,
          requestedEdit: null,
        },
      };
    }
    case "replaced":
      return { kind: "error", message: codePath ? LEGAL_COPY.dialog.decideError.replaced : LEGAL_COPY.errors.replaced, reload: true };
    case "expired":
      return { kind: "error", message: codePath ? LEGAL_COPY.dialog.decideError.expired : LEGAL_COPY.errors.expired, reload: false };
    case "code_expired":
      return codePath ? { kind: "error", message: LEGAL_COPY.dialog.decideError.code_expired, reload: false, recheck: "code" } : unknown;
  }
}
