"use client";

// Read-only contact-detail drawer (feat-beta-crm-ui #6172). Reskins
// components/workstream/issue-detail-sheet.tsx: a createPortal right-side
// overlay. Fetches the detail via SWR through GET /api/crm/contacts/[id] (the
// atomic read+audit RPC — opening the drawer IS the Art. 5(2) accountable
// read). States: loading skeleton · notFound (byte-identical neutral copy, no
// oracle) · error (ErrorCard + Retry, never raw server text) · loaded (fields +
// dual-lens note timeline + stage history + read-only hint).

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import Link from "next/link";
import useSWR from "swr";
import { swrKeys } from "@/lib/swr-config";
import { ErrorCard } from "@/components/ui/error-card";
import { LockIcon } from "@/components/icons";
import { STAGE_ACCENT, STAGE_LABEL, type Stage } from "./stage-style";

type Contact = {
  id: string;
  company: string | null;
  name: string | null;
  role: string | null;
  source: string | null;
  stage: string;
  amount: number | null;
  currency: string | null;
  last_contact: string | null;
  created_at: string;
};
type Note = {
  id: string;
  body: string;
  lens: string[];
  occurred_at: string | null;
  created_at: string;
};
type Transition = {
  id: string;
  from_stage: string | null;
  to_stage: string;
  entered_at: string;
};
type Detail = { contact: Contact; notes: Note[]; transitions: Transition[] };

// Fetcher that surfaces the HTTP status so a 404 (notFound, no oracle) is
// distinguishable from a 5xx (loud error + Retry).
async function detailFetcher(key: readonly [string, ...unknown[]]): Promise<Detail> {
  const res = await fetch(key[0]);
  if (!res.ok) {
    const err = new Error(`crm detail ${res.status}`) as Error & { status: number };
    err.status = res.status;
    throw err;
  }
  return (await res.json()) as Detail;
}

function formatDate(str: string | null, dateOnly = false): string {
  if (!str) return "—";
  const d = new Date(dateOnly && str.length === 10 ? `${str}T00:00:00Z` : str);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  });
}

function formatAmount(amount: number | null, currency: string | null): string {
  if (amount == null) return "—";
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: currency ?? "USD",
      maximumFractionDigits: 0,
    }).format(amount);
  } catch {
    return `${amount}${currency ? ` ${currency}` : ""}`;
  }
}

const LENS_LABEL: Record<string, string> = {
  sales: "What they said",
  product: "What it means",
};

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <dt className="text-soleur-text-tertiary">{label}</dt>
      <dd className="text-right text-soleur-text-primary">{children}</dd>
    </div>
  );
}

export function ContactDetailSheet({
  contactId,
  onClose,
}: {
  contactId: string | null;
  onClose: () => void;
}) {
  const open = contactId != null;
  const [mounted, setMounted] = useState(false);
  const closeBtnRef = useRef<HTMLButtonElement>(null);

  const { data, error, isLoading, mutate } = useSWR<Detail>(
    swrKeys.crmContactDetail(contactId),
    detailFetcher,
  );

  useEffect(() => setMounted(true), []);

  // Escape closes; focus the close button on open.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    const t = setTimeout(() => closeBtnRef.current?.focus(), 0);
    return () => {
      window.removeEventListener("keydown", onKey);
      clearTimeout(t);
    };
  }, [open, onClose]);

  if (!open || !mounted) return null;

  const notFound = !!error && (error as { status?: number }).status === 404;
  const loadError = !!error && !notFound;

  return createPortal(
    <div className="fixed inset-0 z-50">
      <div
        className="absolute inset-0 bg-black/40"
        aria-hidden="true"
        onClick={onClose}
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={data ? `${data.contact.company ?? "Contact"} detail` : "Contact detail"}
        className="absolute right-0 top-0 flex h-full w-full max-w-[460px] flex-col border-l border-soleur-border-default bg-soleur-bg-base shadow-2xl"
      >
        <Header
          detail={data}
          closeBtnRef={closeBtnRef}
          onClose={onClose}
          showTitle={!notFound}
        />

        <div className="min-h-0 flex-1 overflow-y-auto p-4">
          {loadError ? (
            <ErrorCard
              title="Couldn't load this contact"
              message="Something went wrong loading the contact detail. Please try again."
              onRetry={() => void mutate()}
            />
          ) : notFound ? (
            <NotFoundBody onClose={onClose} />
          ) : isLoading || !data ? (
            <DetailSkeleton />
          ) : (
            <LoadedBody detail={data} />
          )}
        </div>
      </div>
    </div>,
    document.body,
  );
}

function Header({
  detail,
  closeBtnRef,
  onClose,
  showTitle,
}: {
  detail: Detail | undefined;
  closeBtnRef: React.RefObject<HTMLButtonElement | null>;
  onClose: () => void;
  showTitle: boolean;
}) {
  const c = detail?.contact;
  const eyebrow = c ? [c.name, c.role].filter(Boolean).join(" · ") : "";
  return (
    <div className="flex items-start justify-between gap-3 border-b border-soleur-border-default p-4">
      <div className="min-w-0">
        {eyebrow ? (
          <p className="text-[11px] font-medium uppercase tracking-wider text-soleur-text-tertiary">
            {eyebrow}
          </p>
        ) : null}
        {showTitle ? (
          <h2 className="mt-1 truncate text-base font-medium text-soleur-text-primary">
            {c?.company ?? "Contact"}
          </h2>
        ) : null}
      </div>
      <div className="flex shrink-0 items-center gap-2">
        {c ? <StagePill stage={c.stage} /> : null}
        <button
          ref={closeBtnRef}
          type="button"
          onClick={onClose}
          aria-label="Close"
          className="rounded p-1 text-soleur-text-muted hover:text-soleur-text-primary"
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round">
            <line x1="6" y1="6" x2="18" y2="18" />
            <line x1="18" y1="6" x2="6" y2="18" />
          </svg>
        </button>
      </div>
    </div>
  );
}

function StagePill({ stage }: { stage: string }) {
  const s = stage as Stage;
  const accent = STAGE_ACCENT[s] ?? "#888";
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full border px-2 py-0.5 text-[11px] font-medium"
      style={{ borderColor: `${accent}80`, color: accent }}
    >
      <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: accent }} aria-hidden />
      {STAGE_LABEL[s] ?? stage}
    </span>
  );
}

function LoadedBody({ detail }: { detail: Detail }) {
  const { contact: c, notes, transitions } = detail;
  return (
    <div className="space-y-6">
      <dl className="space-y-3 text-sm">
        <Row label="Company">{c.company ?? "—"}</Row>
        <Row label="Contact">{c.name ?? "—"}</Row>
        <Row label="Role">{c.role ?? "—"}</Row>
        <Row label="Deal value">
          <span className="text-soleur-accent-gold-fg">
            {formatAmount(c.amount, c.currency)}
          </span>
        </Row>
        <Row label="Captured via">{c.source ?? "agent conversation"}</Row>
        <Row label="Last activity">{formatDate(c.last_contact, true)}</Row>
      </dl>

      <NoteTimeline notes={notes} />
      <StageHistory contact={c} transitions={transitions} />

      <div className="flex items-start gap-2 border-t border-soleur-border-default pt-4 text-xs text-soleur-text-tertiary">
        <LockIcon className="mt-0.5 h-3.5 w-3.5 shrink-0" />
        <p>
          Read-only. Update this contact by mentioning it in a chat with your{" "}
          <Link href="/dashboard/chat" className="text-soleur-accent-gold-fg hover:underline">
            CRO or CPO agent
          </Link>
          .
        </p>
      </div>
    </div>
  );
}

function NoteTimeline({ notes }: { notes: Note[] }) {
  return (
    <section>
      <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-soleur-text-tertiary">
        Note timeline
      </h3>
      {notes.length === 0 ? (
        <p className="text-sm text-soleur-text-muted">
          No conversation notes captured yet.
        </p>
      ) : (
        <ol className="space-y-4">
          {notes.map((n, i) => {
            const dateStr = formatDate(n.occurred_at ?? n.created_at, true);
            const prevDate =
              i > 0 ? formatDate(notes[i - 1].occurred_at ?? notes[i - 1].created_at, true) : null;
            const showDate = dateStr !== prevDate;
            const isSales = n.lens.includes("sales");
            const lensLabel =
              n.lens.map((l) => LENS_LABEL[l] ?? l).join(" · ") || "Note";
            return (
              <li key={n.id}>
                {showDate ? (
                  <p className="mb-1 text-[11px] text-soleur-text-muted">{dateStr}</p>
                ) : null}
                <p className="text-[11px] font-semibold uppercase tracking-wide text-soleur-accent-gold-fg">
                  {lensLabel}
                </p>
                <p
                  className={
                    isSales
                      ? "mt-0.5 border-l-2 border-soleur-accent-gold-fg/40 pl-2 text-sm italic text-soleur-text-primary"
                      : "mt-0.5 text-sm text-soleur-text-secondary"
                  }
                >
                  {n.body}
                </p>
              </li>
            );
          })}
        </ol>
      )}
    </section>
  );
}

function StageHistory({
  contact,
  transitions,
}: {
  contact: Contact;
  transitions: Transition[];
}) {
  // 'new' is the implicit start (insert-at-default emits no transition), so seed
  // the history with it at created_at, then append each transition's to_stage.
  const history: { stage: string; at: string }[] = [
    { stage: "new", at: contact.created_at },
    ...transitions.map((t) => ({ stage: t.to_stage, at: t.entered_at })),
  ];
  const currentIdx = history.length - 1;
  return (
    <section>
      <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-soleur-text-tertiary">
        Stage history
      </h3>
      {transitions.length === 0 && contact.stage === "new" ? (
        <p className="text-sm text-soleur-text-muted">Still at the first stage.</p>
      ) : (
        <ol className="space-y-2">
          {history.map((h, i) => {
            const s = h.stage as Stage;
            const accent = STAGE_ACCENT[s] ?? "#888";
            const isCurrent = i === currentIdx;
            return (
              <li key={`${h.stage}-${h.at}-${i}`} className="flex items-center gap-2 text-sm">
                <span className="h-2 w-2 rounded-full" style={{ backgroundColor: accent }} aria-hidden />
                <span className="text-soleur-text-primary">
                  {STAGE_LABEL[s] ?? h.stage}
                  {isCurrent ? (
                    <span className="text-soleur-text-tertiary"> · current</span>
                  ) : null}
                </span>
                <span className="ml-auto text-xs tabular-nums text-soleur-text-muted">
                  {formatDate(h.at, h.at.length === 10)}
                </span>
              </li>
            );
          })}
        </ol>
      )}
    </section>
  );
}

function NotFoundBody({ onClose }: { onClose: () => void }) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-4 text-center">
      <p className="text-sm text-soleur-text-secondary">This contact isn&apos;t available.</p>
      <button
        type="button"
        onClick={onClose}
        className="rounded-lg border border-soleur-border-default px-3 py-1.5 text-sm text-soleur-text-primary hover:bg-soleur-bg-surface-2/40"
      >
        Back to board
      </button>
    </div>
  );
}

function DetailSkeleton() {
  return (
    <div className="space-y-3" aria-label="Loading contact">
      {[0, 1, 2, 3, 4].map((i) => (
        <div
          key={i}
          className="h-6 w-full animate-pulse rounded-lg bg-soleur-bg-surface-1/40"
        />
      ))}
    </div>
  );
}
