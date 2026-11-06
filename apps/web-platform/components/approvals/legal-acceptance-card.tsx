"use client";

// Founder legal-acceptance card (#12011 PR-C, ADR-319, wireframes 10 to 16). A client component fed PLAIN props by the
// server page: the registry text body and its hash come from the server, the browser hashes nothing and sends no text.
//
// Honesty rules (single-user-incident class):
//   - No choice is pre-selected and Enter alone answers nothing: Yes opens the email check, No asks to confirm, Request
//     changes opens a text box. Only an explicit "Record No", "Save my request" or the dialog's "Confirm and record Yes"
//     sends anything.
//   - Yes stays locked (aria-disabled, reason announced in an aria-live region) until the text is confirmed: a text that
//     fits its viewport unlocks at once, otherwise the reader scrolls to the end AND ticks the box. Before the first
//     measurement the card is locked, so a slow hydration never exposes an unlocked Yes. The reading latches only on a
//     real scroll to the bottom; if the text later stops fitting (resize, reflow) the reading and the tick are reset.
//   - The card changes state only from the server's answer; a failed, lost or unreadable answer is an error, never
//     success. An answer is final: there is no undo here (task 6.10); a new version of the text is the way to change it.

import { useCallback, useEffect, useId, useLayoutEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";
import { deriveLegalCardState } from "@/lib/approval-card-state";
import {
  LEGAL_COPY,
  confirmedWithCodeLine,
  formatLegalDate,
  formatLegalUtc,
  legalTextLabel,
} from "@/lib/legal-acceptance-copy";
import { interpretDecide, postLegalDecide, type LegalRowFacts } from "@/lib/legal-acceptance-client";
import { REQUEST_CHANGES_MAX, codePointLength, truncateCodePoints, type LegalCardStateWire, type LegalChoiceWire } from "@/lib/legal-acceptance-wire";
import { LegalReauthDialog } from "@/components/approvals/legal-reauth-dialog";

export type { LegalRowFacts };

export interface LegalAcceptanceCardProps {
  keyName: string;
  version: string;
  /** The registry text exactly as the server read it. Empty for a replaced card (the older text is no longer in the registry). */
  body: string;
  /** The hash of the registry text, from the server. Sent back with the decision so the server can refuse a changed text. */
  textHash: string;
  /** YYYY-MM-DD or null. */
  validUntil: string | null;
  state: LegalCardStateWire;
  /** The stored row for this card when there is one. */
  row: LegalRowFacts | null;
  /** The `approval-queue` flag. Off: the card is read-only and says answering is not available yet. */
  flagEnabled: boolean;
  /** The signed-in account's email, for the start step of the check. */
  email: string | null;
  /** The registry's current version, for the replaced card. */
  currentVersion: string;
  /** False when the page does not render the current version's card (flag off, no answer yet): a replaced card then links nowhere. Default true. */
  currentVisible?: boolean;
}

const BOX = "rounded-xl border-2 p-4 md:p-6";
const KICKER = "text-xs font-semibold uppercase tracking-wider text-soleur-accent-gold-fg";
const BADGE = "inline-block rounded-md px-2.5 py-1 text-xs font-bold uppercase tracking-wider";

const STATE_STYLE: Record<LegalCardStateWire, { box: string; badge: string }> = {
  pending: { box: "border-soleur-accent-gold-fg bg-soleur-bg-surface-1", badge: "bg-soleur-accent-gold-fg text-soleur-text-on-accent" },
  accepted: { box: "border-green-500/70 bg-green-950/20", badge: "border border-green-500/70 text-green-400" },
  declined: { box: "border-soleur-border-default bg-soleur-bg-surface-1", badge: "bg-soleur-bg-surface-2 text-soleur-text-secondary" },
  changes_requested: { box: "border-soleur-accent-gold-fg bg-soleur-bg-surface-1", badge: "border border-soleur-accent-gold-fg text-soleur-accent-gold-fg" },
  replaced: { box: "border-soleur-border-default bg-soleur-bg-surface-1", badge: "bg-soleur-bg-surface-2 text-soleur-text-secondary" },
  expired: { box: "border-soleur-border-default bg-soleur-bg-surface-1", badge: "bg-soleur-bg-surface-2 text-soleur-text-secondary" },
};

export function LegalAcceptanceCard(props: LegalAcceptanceCardProps) {
  const { keyName, version, body, textHash, validUntil, flagEnabled, email, currentVersion, currentVisible = true } = props;
  const label = legalTextLabel(keyName);

  // The server's last word about this card. After a recorded answer the same pure derivation gives the new state.
  const [local, setLocal] = useState<{ row: LegalRowFacts; already: boolean } | null>(null);
  const row = local?.row ?? props.row;
  const state: LegalCardStateWire = local
    ? deriveLegalCardState({
        cardHash: textHash,
        currentHash: textHash,
        validUntil,
        rows: [{ textHash, choice: local.row.choice }],
        now: new Date(),
      })
    : props.state;

  const onRecorded = useCallback((r: LegalRowFacts, already: boolean) => setLocal({ row: r, already }), []);
  const style = STATE_STYLE[state];

  return (
    <article data-testid="legal-card" data-state={state} aria-label={label} className={`${BOX} ${style.box}`}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className={`${BADGE} ${style.badge}`}>{badgeFor(state)}</span>
        <span className="text-xs text-soleur-text-secondary">{metaFor(state, validUntil, row)}</span>
      </div>

      {state === "pending" ? (
        <PendingBody
          keyName={keyName}
          version={version}
          body={body}
          textHash={textHash}
          label={label}
          flagEnabled={flagEnabled}
          email={email}
          onRecorded={onRecorded}
        />
      ) : (
        <ResolvedBody
          state={state}
          label={label}
          version={version}
          body={body}
          row={row}
          currentVersion={currentVersion}
          currentVisible={currentVisible}
          already={local?.already ?? false}
        />
      )}
    </article>
  );
}

function badgeFor(state: LegalCardStateWire): string {
  switch (state) {
    case "pending":
      return LEGAL_COPY.pending.badge;
    case "accepted":
      return LEGAL_COPY.accepted.badge;
    case "declined":
      return LEGAL_COPY.declined.badge;
    case "changes_requested":
      return LEGAL_COPY.changesRequested.badge;
    case "replaced":
      return LEGAL_COPY.replaced.badge;
    case "expired":
      return LEGAL_COPY.expired.badge;
  }
}

function metaFor(state: LegalCardStateWire, validUntil: string | null, row: LegalRowFacts | null): string {
  switch (state) {
    case "pending":
      return validUntil ? LEGAL_COPY.pending.openUntil(validUntil) : "";
    case "accepted":
    case "declined":
    case "changes_requested": {
      const when = formatLegalUtc(row?.decidedAt);
      return when ? `${when} · by you` : "";
    }
    case "replaced":
      return "";
    case "expired":
      return validUntil ? `Expired ${formatLegalDate(validUntil)}` : "";
  }
}

// ---- resolved states (wireframe 16) ----------------------------------------------------------------------------------

function ResolvedBody({
  state,
  label,
  version,
  body,
  row,
  currentVersion,
  currentVisible,
  already,
}: {
  state: Exclude<LegalCardStateWire, "pending">;
  label: string;
  version: string;
  body: string;
  row: LegalRowFacts | null;
  currentVersion: string;
  currentVisible: boolean;
  already: boolean;
}) {
  let title: string;
  let howGiven: string;
  let closing: string | null = null;
  switch (state) {
    case "accepted":
      title = LEGAL_COPY.accepted.title(label);
      howGiven = confirmedWithCodeLine(row?.reauthAt);
      closing = LEGAL_COPY.accepted.body;
      break;
    case "declined":
      title = LEGAL_COPY.declined.title(label);
      howGiven = LEGAL_COPY.signedInLine;
      closing = LEGAL_COPY.declined.body;
      break;
    case "changes_requested":
      title = LEGAL_COPY.changesRequested.title;
      howGiven = LEGAL_COPY.signedInLine;
      closing = LEGAL_COPY.changesRequested.body;
      break;
    case "replaced":
      title = LEGAL_COPY.replaced.title(version, currentVersion);
      howGiven = row ? LEGAL_COPY.replaced.earlierAnswer(row.choice) : "";
      break;
    case "expired":
      title = LEGAL_COPY.expired.title;
      howGiven = LEGAL_COPY.expired.howGiven;
      closing = LEGAL_COPY.expired.body;
      break;
  }

  return (
    <div className="mt-4 space-y-4">
      <h2 className="text-xl font-medium text-soleur-text-primary">{title}</h2>
      <p className="text-sm text-soleur-text-secondary">{LEGAL_COPY.textMeta(label, version)}</p>

      {state === "changes_requested" && row?.requestedEdit && (
        <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-base p-3">
          <p className={KICKER}>{LEGAL_COPY.changesRequested.noteHeading}</p>
          <p className="mt-1 whitespace-pre-wrap break-words text-sm text-soleur-text-primary">{row.requestedEdit}</p>
        </div>
      )}

      {howGiven && (
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-soleur-text-muted">{LEGAL_COPY.howGivenHeading}</p>
          <p className="mt-1 text-sm text-soleur-text-primary">{howGiven}</p>
        </div>
      )}
      {already && <p className="text-sm text-soleur-text-secondary">{LEGAL_COPY.alreadyAnswered}</p>}
      {closing && <p className="text-sm text-soleur-text-secondary">{closing}</p>}

      {state === "replaced" && currentVisible && (
        <>
          <p className="text-sm text-soleur-text-secondary">{LEGAL_COPY.replaced.needsOwnAnswer(currentVersion)}</p>
          <a href="#current-version" className="inline-block text-sm text-soleur-accent-gold-fg underline">
            {LEGAL_COPY.replaced.open(currentVersion)}
          </a>
        </>
      )}

      {body && state !== "replaced" && (
        <details>
          <summary className="cursor-pointer text-sm text-soleur-accent-gold-fg">{LEGAL_COPY.seeTheText}</summary>
          <pre className="mt-2 max-h-80 overflow-auto whitespace-pre-wrap break-words rounded-lg border border-soleur-border-default bg-soleur-bg-base p-3 font-sans text-sm text-soleur-text-primary">
            {body}
          </pre>
        </details>
      )}
    </div>
  );
}

// ---- pending (wireframes 10, 11, 13, 14) -----------------------------------------------------------------------------

type Mode = null | "decline" | "changes";

function PendingBody({
  keyName,
  version,
  body,
  textHash,
  label,
  flagEnabled,
  email,
  onRecorded,
}: {
  keyName: string;
  version: string;
  body: string;
  textHash: string;
  label: string;
  flagEnabled: boolean;
  email: string | null;
  onRecorded: (row: LegalRowFacts, already: boolean) => void;
}) {
  const uid = useId();
  const regionRef = useRef<HTMLDivElement | null>(null);
  // `measured` stays false until the first layout read: until then the card is locked.
  const [fits, setFits] = useState(false);
  const [atEnd, setAtEnd] = useState(false);
  const [ticked, setTicked] = useState(false);
  const [mode, setMode] = useState<Mode>(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [note, setNote] = useState("");
  const [error, setError] = useState<{ message: string; reload: boolean } | null>(null);
  // Whether the last measurement said the whole text is on screen. A ref, so a measurement can tell "was fitting, now
  // overflows" without a state updater with side effects.
  const fitsRef = useRef(false);

  // Pending state for the No and Request changes submits: one shared flag, errors rendered below (inner flow never throws).
  const { run: runSubmit, pending: busy, error: submitCrash } = usePendingAction(
    async (choice: Exclude<LegalChoiceWire, "accept">, payloadNote?: string) => {
      setError(null);
      const post = await postLegalDecide(keyName, { choice, textHash, ...(payloadNote !== undefined ? { note: payloadNote } : {}) });
      const out = interpretDecide(post, { choice, note: payloadNote, version }, false);
      if (out.kind === "recorded") onRecorded(out.row, out.already);
      else setError({ message: out.message, reload: out.reload });
    },
  );

  // Measures the text viewport. It only ever tracks "does the whole text fit"; it never marks the end as reached.
  const measure = useCallback(() => {
    const el = regionRef.current;
    if (!el) return;
    const fitsNow = el.scrollHeight - el.clientHeight <= 1;
    const wasFitting = fitsRef.current;
    fitsRef.current = fitsNow;
    setFits(fitsNow);
    if (wasFitting && !fitsNow) {
      // The text stopped fitting (a resize or a reflow): any earlier reading is void and must be earned again.
      setAtEnd(false);
      setTicked(false);
    }
  }, []);

  // Scrolling is the only way to reach the end. The reading latches: scrolling back up does not take it away.
  const onScroll = useCallback(() => {
    const el = regionRef.current;
    if (!el) return;
    measure();
    if (el.scrollHeight - el.clientHeight > 1 && el.scrollTop + el.clientHeight >= el.scrollHeight - 2) setAtEnd(true);
  }, [measure]);

  useLayoutEffect(() => {
    if (flagEnabled) measure();
  }, [measure, body, flagEnabled]);
  useEffect(() => {
    if (!flagEnabled) return;
    const el = regionRef.current;
    window.addEventListener("resize", measure);
    const ro = typeof ResizeObserver === "function" && el ? new ResizeObserver(measure) : null;
    if (ro && el) ro.observe(el);
    return () => {
      window.removeEventListener("resize", measure);
      ro?.disconnect();
    };
  }, [measure, flagEnabled]);

  const confirmed = fits || (atEnd && ticked);
  const lockText = confirmed ? LEGAL_COPY.lock.open : atEnd ? LEGAL_COPY.lock.needsTick : LEGAL_COPY.lock.atEnd;
  const lockId = `${uid}-lock`;
  const trimmed = note.trim();

  return (
    <div className="mt-4 space-y-5">
      <div>
        <h2 className="text-xl font-medium text-soleur-text-primary">{LEGAL_COPY.pending.title(label)}</h2>
        <p className="mt-1 text-sm text-soleur-text-secondary">{LEGAL_COPY.versionMeta(version)}</p>
      </div>

      {flagEnabled ? (
        <>
          <div>
            <h3 className={KICKER}>{LEGAL_COPY.whatYourAnswerDoes}</h3>
            <dl className="mt-2 space-y-2 text-sm">
              {[LEGAL_COPY.yesRow, LEGAL_COPY.noRow, LEGAL_COPY.changesRow].map((r, i) => (
                <div key={r.label} className={`rounded-lg border p-3 md:grid md:grid-cols-[10rem_1fr] md:gap-3 ${i === 0 ? "border-soleur-accent-gold-fg" : "border-soleur-border-default"}`}>
                  <dt className="font-semibold text-soleur-text-primary">{r.label}</dt>
                  <dd className="mt-1 text-soleur-text-secondary md:mt-0">{r.body}</dd>
                </div>
              ))}
            </dl>
          </div>
          <p className="text-sm text-soleur-text-secondary">{LEGAL_COPY.pending.howGiven}</p>
        </>
      ) : (
        <p className="text-sm text-soleur-text-primary">{LEGAL_COPY.pending.notAvailable}</p>
      )}

      <div>
        <div className="flex items-baseline justify-between gap-2">
          <h3 id={`${uid}-text`} className={KICKER}>
            {LEGAL_COPY.exactTextHeading}
          </h3>
          <span className="text-xs text-soleur-accent-gold-fg">{LEGAL_COPY.textMeta(label, version)}</span>
        </div>
        <div
          ref={regionRef}
          role="region"
          aria-labelledby={`${uid}-text`}
          tabIndex={0}
          onScroll={flagEnabled ? onScroll : undefined}
          className="mt-2 max-h-80 overflow-y-auto whitespace-pre-wrap break-words rounded-lg border border-soleur-border-default bg-soleur-bg-base p-4 text-sm text-soleur-text-primary"
        >
          {body}
        </div>
        {flagEnabled && (
          <div className="mt-2 space-y-2">
            <p className="text-xs text-soleur-text-secondary">{fits ? LEGAL_COPY.scroll.fits : atEnd ? LEGAL_COPY.scroll.reached : LEGAL_COPY.scroll.keep}</p>
            {!fits && (
              <label className="flex items-start gap-2 text-sm text-soleur-text-primary">
                <input
                  type="checkbox"
                  checked={ticked}
                  aria-disabled={!atEnd}
                  onChange={(e) => {
                    if (atEnd) setTicked(e.target.checked);
                  }}
                  className="mt-0.5 h-4 w-4"
                />
                <span>
                  {LEGAL_COPY.scroll.checkbox}
                  {!atEnd && <span className="text-soleur-text-muted"> {LEGAL_COPY.scroll.checkboxLocked}</span>}
                </span>
              </label>
            )}
          </div>
        )}
      </div>

      {flagEnabled && (
        <div className="space-y-3">
          <p className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 p-3 text-xs text-soleur-text-secondary">{LEGAL_COPY.cardNotice}</p>

          <div>
            <h3 className={KICKER}>{LEGAL_COPY.answerHeading}</h3>
            <p className="mt-1 text-sm text-soleur-text-secondary">{LEGAL_COPY.noDefault}</p>
          </div>

          <div className="grid gap-3 md:grid-cols-3">
            <ChoiceButton
              title={LEGAL_COPY.choices.yes.label}
              hint={LEGAL_COPY.choices.yes.hint}
              locked={!confirmed}
              describedBy={lockId}
              onClick={() => {
                if (!confirmed) return;
                setError(null);
                setMode(null);
                setDialogOpen(true);
              }}
            />
            <ChoiceButton
              title={LEGAL_COPY.choices.no.label}
              hint={LEGAL_COPY.choices.no.hint}
              expanded={mode === "decline"}
              onClick={() => {
                setError(null);
                setMode(mode === "decline" ? null : "decline");
              }}
            />
            <ChoiceButton
              title={LEGAL_COPY.choices.changes.label}
              hint={LEGAL_COPY.choices.changes.hint}
              expanded={mode === "changes"}
              onClick={() => {
                setError(null);
                setMode(mode === "changes" ? null : "changes");
              }}
            />
          </div>

          <p id={lockId} role="status" aria-live="polite" className={`text-sm ${confirmed ? "text-green-400" : "text-soleur-accent-gold-fg"}`}>
            {lockText}
          </p>

          {mode === "decline" && (
            <div className="space-y-3 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 p-3">
              <h3 className="text-sm font-semibold text-soleur-text-primary">{LEGAL_COPY.decline.heading}</h3>
              <p className="text-sm text-soleur-text-secondary">{LEGAL_COPY.decline.body}</p>
              <div className="flex gap-2">
                <Button variant="outlined" loading={busy} loadingLabel="Recording" onClick={() => runSubmit("decline")}>
                  {LEGAL_COPY.decline.confirm}
                </Button>
                <Button variant="ghost" disabled={busy} onClick={() => setMode(null)}>
                  {LEGAL_COPY.decline.cancel}
                </Button>
              </div>
            </div>
          )}

          {mode === "changes" && (
            <div className="space-y-2">
              <p className="text-sm text-soleur-text-primary">{LEGAL_COPY.requestChangesNotice}</p>
              <label htmlFor={`${uid}-note`} className={`block ${KICKER}`}>
                {LEGAL_COPY.changes.label}
              </label>
              <textarea
                id={`${uid}-note`}
                value={note}
                rows={5}
                placeholder={LEGAL_COPY.changes.placeholder}
                aria-describedby={`${uid}-note-count`}
                onChange={(e) => setNote(truncateCodePoints(e.target.value, REQUEST_CHANGES_MAX))}
                className="w-full rounded-lg border border-soleur-accent-gold-fg bg-soleur-bg-base p-3 text-sm text-soleur-text-primary"
              />
              <div className="flex flex-wrap justify-between gap-2 text-xs">
                <span className="text-soleur-accent-gold-fg">{trimmed.length === 0 ? LEGAL_COPY.changes.required : ""}</span>
                <span id={`${uid}-note-count`} className="text-soleur-text-muted">
                  {LEGAL_COPY.changes.counter(codePointLength(note), REQUEST_CHANGES_MAX)}
                </span>
              </div>
              <div className="flex gap-2">
                <Button variant="outlined" disabled={trimmed.length === 0} loading={busy} loadingLabel="Saving" onClick={() => runSubmit("request_changes", trimmed)}>
                  {LEGAL_COPY.changes.send}
                </Button>
                <Button variant="ghost" disabled={busy} onClick={() => setMode(null)}>
                  {LEGAL_COPY.changes.cancel}
                </Button>
              </div>
              <p className="text-xs text-soleur-text-secondary">{LEGAL_COPY.changes.footer}</p>
            </div>
          )}

          {(error || submitCrash) && (
            <div role="alert" className="rounded-lg border border-red-500/60 bg-red-950/30 p-3 text-sm text-soleur-text-primary">
              <p>{error ? error.message : LEGAL_COPY.errors.unknownResult}</p>
              {(error ? error.reload : true) && (
                <Button variant="outlined" className="mt-2 px-3 py-1.5" onClick={() => window.location.reload()}>
                  {LEGAL_COPY.errors.reload}
                </Button>
              )}
            </div>
          )}

          <p className="text-xs text-soleur-text-secondary">{LEGAL_COPY.finalNote}</p>
        </div>
      )}

      {flagEnabled && <p className="text-sm text-soleur-text-secondary">{LEGAL_COPY.pending.nothingAccepted}</p>}

      {dialogOpen && (
        <LegalReauthDialog
          keyName={keyName}
          textHash={textHash}
          label={label}
          version={version}
          email={email}
          onClose={() => setDialogOpen(false)}
          onRecorded={(r, already) => {
            setDialogOpen(false);
            onRecorded(r, already);
          }}
        />
      )}
    </div>
  );
}

function ChoiceButton({
  title,
  hint,
  locked,
  describedBy,
  expanded,
  onClick,
}: {
  title: string;
  hint: string;
  locked?: boolean;
  describedBy?: string;
  expanded?: boolean;
  onClick: () => void;
}) {
  return (
    <Button
      variant="outlined"
      aria-disabled={locked === undefined ? undefined : locked}
      aria-describedby={describedBy}
      aria-expanded={expanded === undefined ? undefined : expanded}
      onClick={onClick}
      className={`h-full flex-col items-start gap-1 p-4 text-left ${locked ? "cursor-not-allowed opacity-60" : ""}`}
    >
      <span className="text-base font-semibold">{title}</span>
      <span className="text-xs font-normal text-soleur-text-secondary">{hint}</span>
    </Button>
  );
}
