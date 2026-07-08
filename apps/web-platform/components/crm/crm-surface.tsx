"use client";

// Read-only beta-CRM surface host (feat-beta-crm-ui #6172). Owns the
// Board|Funnel toggle, the contacts SWR, the ?contact=<id> deep-link drawer
// state, and the board's loading/error/empty states. Reskins the interaction
// model of components/workstream/workstream-board.tsx (pushState open /
// replaceState close / popstate sync) into a read-only CRM board. Editing stays
// conversational via the agent — the "edit via your CRO/CPO agent" escape hatch
// is present on board + funnel here (and inside the drawer).

import { useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import Link from "next/link";
import useSWR from "swr";
import { jsonFetcher, swrKeys } from "@/lib/swr-config";
import { ErrorCard } from "@/components/ui/error-card";
import { LockIcon } from "@/components/icons";
import { PipelineColumn, type CrmContact } from "./pipeline-column";
import { ContactDetailSheet } from "./contact-detail-sheet";
import { FunnelView } from "./funnel-view";
import { FUNNEL_STAGES } from "./stage-style";

type ContactsResponse = { contacts: CrmContact[] };
type View = "board" | "funnel";

export function CrmSurface() {
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const [view, setView] = useState<View>("board");
  const [activeId, setActiveId] = useState<string | null>(() =>
    searchParams.get("contact"),
  );

  const { data, error, mutate } = useSWR<ContactsResponse>(
    swrKeys.crmContacts(),
    jsonFetcher,
  );
  const contacts = data?.contacts;

  // Reconcile the drawer with the URL on Back/Forward + cold deep-link.
  useEffect(() => {
    function onPopState() {
      setActiveId(new URLSearchParams(window.location.search).get("contact"));
    }
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  }, []);

  const openContact = useCallback(
    (id: string) => {
      setActiveId(id);
      try {
        window.history.pushState({}, "", `${pathname}?contact=${encodeURIComponent(id)}`);
      } catch {
        /* history unavailable — local state still drives the drawer */
      }
    },
    [pathname],
  );

  const closeContact = useCallback(() => {
    setActiveId(null);
    try {
      window.history.replaceState({}, "", pathname);
    } catch {
      /* history unavailable */
    }
  }, [pathname]);

  // Toggling to Funnel closes the drawer (funnel has no card context, AC8).
  const switchView = useCallback(
    (next: View) => {
      if (next === "funnel" && activeId) closeContact();
      setView(next);
    },
    [activeId, closeContact],
  );

  const byStage = useMemo(() => {
    const m = new Map<string, CrmContact[]>();
    for (const c of contacts ?? []) {
      const list = m.get(c.stage);
      if (list) list.push(c);
      else m.set(c.stage, [c]);
    }
    return m;
  }, [contacts]);

  return (
    <div>
      <Header view={view} onSwitch={switchView} />

      {view === "funnel" ? (
        <FunnelView />
      ) : error && !data ? (
        <ErrorCard
          title="Failed to load the board"
          message="Something went wrong loading your CRM pipeline. Please try again."
          onRetry={() => void mutate()}
        />
      ) : !data ? (
        <BoardSkeleton />
      ) : contacts && contacts.length === 0 ? (
        <EmptyState />
      ) : (
        <div className="flex gap-3 overflow-x-auto pb-4">
          {FUNNEL_STAGES.map((stage) => (
            <PipelineColumn
              key={stage}
              stage={stage}
              contacts={byStage.get(stage) ?? []}
              onOpen={openContact}
            />
          ))}
          <PipelineColumn
            stage="closed_lost"
            contacts={byStage.get("closed_lost") ?? []}
            onOpen={openContact}
            rail
          />
        </div>
      )}

      <ContactDetailSheet contactId={view === "board" ? activeId : null} onClose={closeContact} />
    </div>
  );
}

function Header({ view, onSwitch }: { view: View; onSwitch: (v: View) => void }) {
  return (
    <div className="mb-6 flex items-start justify-between gap-4">
      <div>
        <div className="flex items-center gap-2">
          <h1 className="text-2xl font-semibold text-soleur-text-primary">CRM</h1>
          <span className="rounded-full border border-soleur-accent-gold-fg/50 px-2 py-0.5 text-[11px] font-medium uppercase tracking-wide text-soleur-accent-gold-fg">
            Read-only
          </span>
        </div>
        <p className="mt-1 max-w-2xl text-sm text-soleur-text-secondary">
          {view === "funnel"
            ? "Conversion funnel · counts reflect contacts that have reached each stage, captured from your agent conversations."
            : "Beta pipeline · contacts are captured from your agent conversations. "}
          {view === "board" ? (
            <>
              Editing happens in a{" "}
              <Link href="/dashboard/chat" className="text-soleur-accent-gold-fg hover:underline">
                chat with your CRO or CPO agent
              </Link>
              .
            </>
          ) : null}
        </p>
      </div>
      <ViewToggle view={view} onSwitch={onSwitch} />
    </div>
  );
}

function ViewToggle({ view, onSwitch }: { view: View; onSwitch: (v: View) => void }) {
  return (
    <div
      className="flex shrink-0 items-center rounded-lg border border-soleur-border-default p-0.5"
      role="tablist"
      aria-label="CRM view"
    >
      {(["board", "funnel"] as const).map((v) => (
        <button
          key={v}
          type="button"
          role="tab"
          aria-selected={view === v}
          onClick={() => onSwitch(v)}
          className={`rounded-md px-3 py-1 text-sm font-medium capitalize transition-colors ${
            view === v
              ? "bg-soleur-bg-surface-2 text-soleur-accent-gold-fg"
              : "text-soleur-text-tertiary hover:text-soleur-text-primary"
          }`}
        >
          {v}
        </button>
      ))}
    </div>
  );
}

function EmptyState() {
  return (
    <div className="mx-auto mt-12 max-w-md rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/40 p-8 text-center">
      <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-soleur-accent-gold-fg/10">
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5} className="text-soleur-accent-gold-fg" strokeLinecap="round" strokeLinejoin="round">
          <path d="M7.5 8.25h9m-9 3.75h6m-8.25 6 3-3h6.75a2.25 2.25 0 0 0 2.25-2.25V6a2.25 2.25 0 0 0-2.25-2.25H5.25A2.25 2.25 0 0 0 3 6v9a2.25 2.25 0 0 0 2.25 2.25H6v3Z" />
        </svg>
      </div>
      <h2 className="text-lg font-medium text-soleur-text-primary">No contacts yet</h2>
      <p className="mx-auto mt-2 max-w-sm text-sm text-soleur-text-secondary">
        Your pipeline fills as you talk to beta testers. Mention a prospect in a
        chat with your CRO or CPO agent and it appears here automatically —
        there&apos;s nothing to enter by hand.
      </p>
      <p className="mt-4 flex items-center justify-center gap-1.5 text-xs text-soleur-text-muted">
        <LockIcon className="h-3.5 w-3.5" />
        This board is read-only
      </p>
    </div>
  );
}

function BoardSkeleton() {
  return (
    <div className="flex gap-3 overflow-x-auto pb-4" aria-label="Loading">
      {[0, 1, 2, 3, 4, 5].map((i) => (
        <div
          key={i}
          className="h-48 w-72 shrink-0 animate-pulse rounded-xl border border-soleur-border-default/60 bg-soleur-bg-surface-1/40"
        />
      ))}
    </div>
  );
}
