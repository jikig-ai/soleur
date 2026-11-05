"use client";

// In-place email-code check before a Yes is recorded (#12011 PR-C, ADR-319, wireframe 12/15 A, B, C). Email code only:
// the password and provider steps are deferred (#12031) and are deliberately absent.
//
// The dialog opens on top of the SAME card and closes back to it. It holds no persistence: a reload starts the check
// again with nothing recorded. It sends only {step, resend?, code?} and {choice, textHash}: the browser never sends
// the legal text. Every typed server outcome maps to plain wording that never claims more than happened; success is
// shown ONLY when the server's decide answer says `recorded` or `already_recorded` with the choice it recorded.

import { useId, useState } from "react";
import { Button } from "@/components/ui/button";
import { ResponsiveModal } from "@/components/ui/responsive-modal";
import { LEGAL_COPY } from "@/lib/legal-acceptance-copy";
import { PENDING_WATCHDOG_MS } from "@/lib/pending-timing";
import {
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

// ---- network helpers (shared with the card) -------------------------------------------------------------------------

/** `rejected`: our own route answered non-2xx, which means nothing was written. `unknown`: a lost or unreadable reply. */
export type LegalPost<T> = { kind: "ok"; value: T } | { kind: "rejected" } | { kind: "unknown" };

async function postJson(url: string, body: unknown): Promise<LegalPost<unknown>> {
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
  if (!res.ok) return { kind: "rejected" };
  try {
    return { kind: "ok", value: await res.json() };
  } catch {
    return { kind: "unknown" };
  }
}

const SEND_REASONS = ["rate_limited", "already_recorded", "replaced", "unavailable"] as const;
const VERIFY_REASONS = ["wrong_code", "locked", "expired", "replaced", "code_stale", "unavailable"] as const;

function parseSend(v: unknown): LegalReauthSendResult | null {
  if (!v || typeof v !== "object") return null;
  const o = v as { ok?: unknown; state?: unknown; reason?: unknown };
  if (o.ok === true && o.state === "sent") return { ok: true, state: "sent" };
  if (o.ok === false && typeof o.reason === "string" && (SEND_REASONS as readonly string[]).includes(o.reason)) {
    return { ok: false, reason: o.reason as (typeof SEND_REASONS)[number] };
  }
  return null;
}

function parseVerify(v: unknown): LegalReauthVerifyResult | null {
  if (!v || typeof v !== "object") return null;
  const o = v as { ok?: unknown; reason?: unknown };
  if (o.ok === true) return { ok: true };
  if (o.ok === false && typeof o.reason === "string" && (VERIFY_REASONS as readonly string[]).includes(o.reason)) {
    return { ok: false, reason: o.reason as (typeof VERIFY_REASONS)[number] };
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

export type DecideInterpretation = { kind: "recorded"; row: LegalRowFacts; already: boolean } | { kind: "error"; message: string; reload: boolean };

/**
 * Reads the server's decide answer. A row is shown ONLY for `recorded` (the choice we sent unless the server names one)
 * and for `already_recorded` WITH the server's choice. Everything else is an error that records nothing on screen.
 */
export function interpretDecide(
  post: LegalPost<LegalDecideResult>,
  sent: { choice: LegalChoiceWire; note?: string; version: string },
  codePath: boolean,
): DecideInterpretation {
  if (post.kind === "rejected") return { kind: "error", message: LEGAL_COPY.errors.nothingRecorded, reload: false };
  if (post.kind === "unknown") return { kind: "error", message: LEGAL_COPY.errors.unknownResult, reload: true };
  const r = post.value;
  const unknown = { kind: "error", message: LEGAL_COPY.errors.unknownResult, reload: true } as const;
  switch (r.outcome) {
    case "recorded": {
      const choice = r.choice === undefined ? sent.choice : r.choice;
      if (!isLegalChoice(choice)) return unknown;
      return {
        kind: "recorded",
        already: false,
        row: {
          choice,
          version: sent.version,
          decidedAt: typeof r.decidedAt === "string" ? r.decidedAt : null,
          reauthAt: typeof r.reauthAt === "string" ? r.reauthAt : null,
          requestedEdit: choice === "request_changes" && choice === sent.choice && sent.note ? sent.note : null,
        },
      };
    }
    case "already_recorded": {
      // The second tab: what is on screen comes from the server's answer. Without its choice nothing can be shown.
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
      return codePath ? { kind: "error", message: LEGAL_COPY.dialog.decideError.code_expired, reload: false } : unknown;
  }
}

// ---- the dialog --------------------------------------------------------------------------------------------------------

const CODE_RE = /^\d{6,8}$/;

export interface LegalReauthDialogProps {
  keyName: string;
  textHash: string;
  label: string;
  version: string;
  /** The account email shown in the start step; null falls back to wording without an address. */
  email: string | null;
  /** Go back, Escape: nothing was recorded. */
  onClose: () => void;
  /** The server recorded the answer (or says it already was). The card shows the state from `row`. */
  onRecorded: (row: LegalRowFacts, already: boolean) => void;
}

export function LegalReauthDialog({ keyName, textHash, label, version, email, onClose, onRecorded }: LegalReauthDialogProps) {
  const titleId = useId();
  const [step, setStep] = useState<"start" | "code">("start");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState<"send" | "confirm" | null>(null);
  const [verified, setVerified] = useState(false);
  const [error, setError] = useState<{ message: string; help: boolean; reload: boolean } | null>(null);
  const [showHelp, setShowHelp] = useState(false);

  async function send(resend: boolean) {
    if (busy) return;
    setBusy("send");
    setError(null);
    const post = await postJson(`/api/legal-acceptance/${encodeURIComponent(keyName)}/reauth`, resend ? { step: "send", resend: true } : { step: "send" });
    setBusy(null);
    const parsed = post.kind === "ok" ? parseSend(post.value) : null;
    if (parsed?.ok) {
      setVerified(false);
      setCode("");
      setStep("code");
      return;
    }
    const reason = parsed && !parsed.ok ? parsed.reason : "unavailable";
    setError({
      message: LEGAL_COPY.dialog.sendError[reason],
      help: reason === "unavailable",
      reload: reason === "replaced" || reason === "already_recorded",
    });
  }

  async function confirm() {
    if (busy) return;
    if (!verified && !CODE_RE.test(code)) return;
    setBusy("confirm");
    setError(null);
    if (!verified) {
      const post = await postJson(`/api/legal-acceptance/${encodeURIComponent(keyName)}/reauth`, { step: "verify", code });
      const parsed = post.kind === "ok" ? parseVerify(post.value) : null;
      if (!parsed?.ok) {
        const reason = parsed && !parsed.ok ? parsed.reason : "unavailable";
        setBusy(null);
        setError({ message: LEGAL_COPY.dialog.verifyError[reason], help: reason === "unavailable", reload: reason === "replaced" });
        return;
      }
      setVerified(true);
    }
    const post = await postLegalDecide(keyName, { choice: "accept", textHash });
    setBusy(null);
    const out = interpretDecide(post, { choice: "accept", version }, true);
    if (out.kind === "recorded") {
      onRecorded(out.row, out.already);
      return;
    }
    // A confirmation that is too old needs a new code: the next click must verify again.
    if (post.kind === "ok" && post.value.outcome === "code_expired") setVerified(false);
    setError({ message: out.message, help: false, reload: out.reload });
  }

  const codeOk = CODE_RE.test(code);

  return (
    <ResponsiveModal open onClose={onClose} closeOnBackdrop={false} aria-labelledby={titleId} desktopMaxWidth="max-w-lg">
      <div data-testid="legal-reauth-dialog" className="space-y-4">
        <p className="text-xs font-semibold uppercase tracking-wider text-soleur-accent-gold-fg">
          {step === "start" ? LEGAL_COPY.dialog.startKicker : LEGAL_COPY.dialog.codeKicker}
        </p>
        <h2 id={titleId} className="text-lg font-medium text-soleur-text-primary">
          {step === "start" ? LEGAL_COPY.dialog.startTitle : LEGAL_COPY.dialog.codeTitle}
        </h2>

        {step === "start" ? (
          <>
            <p className="text-sm text-soleur-text-secondary">{LEGAL_COPY.dialog.startBody(email)}</p>
            <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 p-3 text-sm">
              <p className="font-medium text-soleur-text-primary">{LEGAL_COPY.dialog.answerSummary}</p>
              <p className="mt-1 text-soleur-text-secondary">{LEGAL_COPY.dialog.answerDetail(label, version)}</p>
            </div>
          </>
        ) : (
          <>
            <p className="text-sm text-soleur-text-secondary">{LEGAL_COPY.dialog.codeBody}</p>
            <p className="text-sm text-soleur-text-secondary">{LEGAL_COPY.dialog.codeSent}</p>
            <div>
              <label htmlFor={`${titleId}-code`} className="block text-sm font-medium text-soleur-text-primary">
                {LEGAL_COPY.dialog.codeLabel}
              </label>
              <input
                id={`${titleId}-code`}
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                maxLength={8}
                value={code}
                readOnly={verified}
                aria-describedby={`${titleId}-code-hint`}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 8))}
                className="mt-1 w-full rounded-lg border border-soleur-border-default bg-soleur-bg-base px-3 py-2 font-mono text-lg tracking-widest text-soleur-text-primary"
              />
              <p id={`${titleId}-code-hint`} className="mt-1 text-xs text-soleur-text-muted">
                {LEGAL_COPY.dialog.codeHint}
              </p>
            </div>
          </>
        )}

        {error && (
          <div role="alert" className="rounded-lg border border-red-500/60 bg-red-950/30 p-3 text-sm text-soleur-text-primary">
            <p>{error.message}</p>
            {error.reload && (
              <Button variant="outlined" className="mt-2 px-3 py-1.5" onClick={() => window.location.reload()}>
                {LEGAL_COPY.errors.reload}
              </Button>
            )}
          </div>
        )}
        {(showHelp || error?.help) && <p className="text-sm text-soleur-text-secondary">{LEGAL_COPY.dialog.help}</p>}

        <div className="flex flex-col gap-2">
          {step === "start" ? (
            <Button variant="gold" loading={busy === "send"} loadingLabel={LEGAL_COPY.dialog.sendingCode} onClick={() => void send(false)}>
              {LEGAL_COPY.dialog.sendCode}
            </Button>
          ) : (
            <>
              <Button
                variant="gold"
                disabled={!verified && !codeOk}
                loading={busy === "confirm"}
                loadingLabel={LEGAL_COPY.dialog.confirming}
                onClick={() => void confirm()}
              >
                {LEGAL_COPY.dialog.confirmAndRecord}
              </Button>
              <Button variant="ghost" loading={busy === "send"} loadingLabel={LEGAL_COPY.dialog.sendingCode} onClick={() => void send(true)}>
                {LEGAL_COPY.dialog.sendNewCode}
              </Button>
              <Button variant="ghost" onClick={() => setShowHelp(true)}>
                {LEGAL_COPY.dialog.cannotGetCode}
              </Button>
            </>
          )}
          <Button variant="outlined" onClick={onClose}>
            {LEGAL_COPY.dialog.goBack}
          </Button>
        </div>
      </div>
    </ResponsiveModal>
  );
}
