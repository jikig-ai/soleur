"use client";

// In-place email-code check before a Yes is recorded (#12011 PR-C, ADR-319, wireframe 12/15 A, B, C). Email code only:
// the password and provider steps are deferred (#12031) and are deliberately absent.
//
// The dialog opens on top of the SAME card and closes back to it. It holds no persistence: a reload starts the check
// again with nothing recorded. It sends only {step, resend?, code?} and {choice, textHash}: the browser never sends
// the legal text. Every typed server outcome maps to plain wording that never claims more than happened; success is
// shown ONLY when the server's decide answer says `recorded` or `already_recorded` with the choice it recorded.

import { useEffect, useId, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { ResponsiveModal } from "@/components/ui/responsive-modal";
import { OTP_RESEND_COOLDOWN_MS } from "@/lib/auth/constants";
import { LEGAL_COPY } from "@/lib/legal-acceptance-copy";
import { interpretDecide, parseSend, parseVerify, postJson, postLegalDecide, type LegalRowFacts } from "@/lib/legal-acceptance-client";
import { LEGAL_CODE_MAX_DIGITS, isLegalCode } from "@/lib/legal-acceptance-wire";

// `LegalRowFacts`, `postLegalDecide` and `interpretDecide` live in `lib/legal-acceptance-client.ts` (client-safe, shared with the card).
export type { LegalRowFacts };

// ---- the dialog --------------------------------------------------------------------------------------------------------

export interface LegalReauthDialogProps {
  keyName: string;
  textHash: string;
  version: string;
  /** The sentence that says what the Yes is for, resolved by the card from the text's declared kind (the dialog does no kind lookup). */
  answerDetail: string;
  /** The account email shown in the start step; null falls back to wording without an address. */
  email: string | null;
  /** Go back, Escape: nothing was recorded. Never called while a request is in flight. */
  onClose: () => void;
  /** The server recorded the answer (or says it already was). The card shows the state from `row`. */
  onRecorded: (row: LegalRowFacts, already: boolean) => void;
}

export function LegalReauthDialog({ keyName, textHash, version, answerDetail, email, onClose, onRecorded }: LegalReauthDialogProps) {
  const titleId = useId();
  const [step, setStep] = useState<"start" | "code">("start");
  const [code, setCode] = useState("");
  // Hand-rolled pending state, exempt from `usePendingAction` (components/ui/README.md, "Deliberate non-adoptions"): one
  // flag is shared by THREE coupled controls (send, resend, confirm) and `confirm` is a two-request flow (verify, then
  // decide) that must hold the dialog open across both. Every request is bounded by `AbortSignal.timeout(PENDING_WATCHDOG_MS)`
  // in `postJson`, so the flag cannot stay set forever, and every outcome ends in an announced `error` or `onRecorded`.
  const [busy, setBusy] = useState<"send" | "confirm" | null>(null);
  const busyRef = useRef<"send" | "confirm" | null>(null);
  const [verified, setVerified] = useState(false);
  const [error, setError] = useState<{ message: string; help: boolean; reload: boolean } | null>(null);
  const [showHelp, setShowHelp] = useState(false);
  // Client cooldown on "Send me a new code": the auth service accepts one code per address per minute.
  const [cooling, setCooling] = useState(false);
  const coolTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  // True after a send that ended in an error or `rate_limited`, cleared by a success. The server skips the mail for a
  // plain send on a live intent ("the earlier code is still valid"); after a failed send no code exists, so every send
  // that follows one is asked for as a resend, and "sent" is never told for a mail that was not attempted.
  const lastSendFailed = useRef(false);

  useEffect(
    () => () => {
      if (coolTimer.current !== null) clearTimeout(coolTimer.current);
    },
    [],
  );

  function startCooldown() {
    if (coolTimer.current !== null) clearTimeout(coolTimer.current);
    setCooling(true);
    coolTimer.current = setTimeout(() => {
      coolTimer.current = null;
      setCooling(false);
    }, OTP_RESEND_COOLDOWN_MS);
  }

  function begin(kind: "send" | "confirm"): boolean {
    if (busyRef.current) return false;
    busyRef.current = kind;
    setBusy(kind);
    setError(null);
    return true;
  }
  function end() {
    busyRef.current = null;
    setBusy(null);
  }

  /** Go back and Escape: ignored while a request is in flight, so an answer that may be recorded is never discarded unseen. */
  function closeIfIdle() {
    if (busyRef.current) return;
    onClose();
  }

  async function send(resend: boolean) {
    // A failed or rate-limited send turns the next attempt into a resend, which opens a new intent and spends the
    // 3-per-15-minutes budget, so no send (start step or resend) goes out while the cooldown runs.
    if (cooling) return;
    if (!begin("send")) return;
    const asResend = resend || lastSendFailed.current;
    const post = await postJson(`/api/legal-acceptance/${encodeURIComponent(keyName)}/reauth`, asResend ? { step: "send", resend: true } : { step: "send" });
    end();
    const parsed = post.kind === "ok" ? parseSend(post.value) : null;
    lastSendFailed.current = !parsed?.ok;
    if (parsed?.ok) {
      setVerified(false);
      setCode("");
      setStep("code");
      startCooldown();
      return;
    }
    const reason = parsed && !parsed.ok ? parsed.reason : "unavailable";
    if (reason === "rate_limited") startCooldown();
    setError({
      message: LEGAL_COPY.dialog.sendError[reason],
      help: reason === "unavailable",
      reload: reason === "replaced" || reason === "already_recorded",
    });
  }

  async function confirm() {
    if (!verified && !isLegalCode(code)) return;
    if (!begin("confirm")) return;
    if (!verified) {
      const post = await postJson(`/api/legal-acceptance/${encodeURIComponent(keyName)}/reauth`, { step: "verify", code });
      const parsed = post.kind === "ok" ? parseVerify(post.value) : null;
      if (!parsed?.ok) {
        const reason = parsed && !parsed.ok ? parsed.reason : "unavailable";
        end();
        setError({ message: LEGAL_COPY.dialog.verifyError[reason], help: reason === "unavailable", reload: reason === "replaced" });
        return;
      }
      setVerified(true);
    }
    const post = await postLegalDecide(keyName, { choice: "accept", textHash });
    end();
    const out = interpretDecide(post, { choice: "accept", version }, true);
    if (out.kind === "recorded") {
      onRecorded(out.row, out.already);
      return;
    }
    // A confirmation that is too old, or one the server no longer counts, needs a new check: the next click must verify
    // again (from the send step when the server says the check no longer counts).
    if (out.recheck) {
      setVerified(false);
      setCode("");
      if (out.recheck === "start") {
        // The server says the check no longer counts: the founder must be able to ask for a new code now, not after the
        // cooldown of the earlier send. The 3-per-15-minutes intent budget on the server is the bound.
        if (coolTimer.current !== null) clearTimeout(coolTimer.current);
        coolTimer.current = null;
        setCooling(false);
        setStep("start");
      }
    }
    setError({ message: out.message, help: false, reload: out.reload });
  }

  const codeOk = isLegalCode(code);

  return (
    <ResponsiveModal open onClose={closeIfIdle} closeOnBackdrop={false} aria-labelledby={titleId} desktopMaxWidth="max-w-lg">
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
              <p className="mt-1 text-soleur-text-secondary">{answerDetail}</p>
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
                maxLength={LEGAL_CODE_MAX_DIGITS}
                value={code}
                readOnly={verified}
                aria-describedby={`${titleId}-code-hint`}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, LEGAL_CODE_MAX_DIGITS))}
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
            <>
              <Button
                variant="gold"
                loading={busy === "send"}
                loadingLabel={LEGAL_COPY.dialog.sendingCode}
                disabled={cooling}
                onClick={() => void send(false)}
              >
                {LEGAL_COPY.dialog.sendCode}
              </Button>
              {cooling && <p className="text-xs text-soleur-text-muted">{LEGAL_COPY.dialog.resendWait}</p>}
            </>
          ) : (
            <>
              <Button
                variant="gold"
                disabled={(!verified && !codeOk) || busy === "send"}
                loading={busy === "confirm"}
                loadingLabel={LEGAL_COPY.dialog.confirming}
                onClick={() => void confirm()}
              >
                {LEGAL_COPY.dialog.confirmAndRecord}
              </Button>
              <Button
                variant="ghost"
                disabled={cooling || busy !== null}
                loading={busy === "send"}
                loadingLabel={LEGAL_COPY.dialog.sendingCode}
                onClick={() => void send(true)}
              >
                {LEGAL_COPY.dialog.sendNewCode}
              </Button>
              {cooling && <p className="text-xs text-soleur-text-muted">{LEGAL_COPY.dialog.resendWait}</p>}
              <Button variant="ghost" onClick={() => setShowHelp(true)}>
                {LEGAL_COPY.dialog.cannotGetCode}
              </Button>
            </>
          )}
          <Button variant="outlined" disabled={busy !== null} onClick={closeIfIdle}>
            {LEGAL_COPY.dialog.goBack}
          </Button>
        </div>
      </div>
    </ResponsiveModal>
  );
}
