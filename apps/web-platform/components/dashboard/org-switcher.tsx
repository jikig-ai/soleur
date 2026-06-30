"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { OrgMembershipSummary } from "@/server/org-memberships-resolver";
import { WorkspaceIdentityTile } from "@/components/dashboard/workspace-identity-tile";

// AC-C: when the user belongs to 0 or 1 organizations, this component renders
// nothing — no chip, no dropdown trigger. The dashboard header chrome stays
// SOLEUR-wordmark + avatar for solo users. Multi-org users see the chip in the
// top-center header position per wireframe 04-org-switcher-header.png.
//
// Phase 5.4 wiring: the org switch posts to /api/workspace/set-current-organization,
// which writes user_session_state, then the client calls supabase.auth
// .refreshSession() to force the JWT custom claim (migration 060) to refresh
// across all tabs. Until 5.4 lands, the onSwitch callback is a stub that
// reloads the page after a best-effort POST.

function roleLabel(role: "owner" | "member"): string {
  return role === "owner" ? "Owner" : "Member";
}

export function OrgSwitcher({
  memberships,
  onSwitch,
  repoName,
  collapsed = false,
}: {
  memberships: readonly OrgMembershipSummary[];
  onSwitch?: (organizationId: string) => void;
  /** Active-workspace repo (e.g. "jikig-ai/soleur"), surfaced as a muted
   *  subtitle on the closed pill face. The role label now lives only in the
   *  dropdown (multi-org) — the face shows workspace identity, not role.
   *  The subtitle keeps the `live-repo-badge` testid (inherited from the
   *  retired standalone badge) so existing e2e/unit selectors stay valid. */
  repoName?: string | null;
  /** Collapsed rail (md:w-14) icon-only mode. The SAME mounted OrgSwitcher (and
   *  its parent OrgSwitcherContainer) owns BOTH the full pill and the icon tile,
   *  so a collapse/expand toggle is a prop change on a persistent element — NOT
   *  an element swap. That is the only thing that preserves the membership fetch
   *  + switch-confirm state across the toggle (ADR-047; the band's former
   *  `collapsed` early-return remounted this container and re-fired its fetch). */
  collapsed?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [open]);

  // Close on ESC
  useEffect(() => {
    if (!open) return;
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("keydown", handleKey);
    return () => document.removeEventListener("keydown", handleKey);
  }, [open]);

  const handleSelect = useCallback(
    (orgId: string, isCurrent: boolean) => {
      setOpen(false);
      if (isCurrent) return;
      onSwitch?.(orgId);
    },
    [onSwitch],
  );

  // RQ7: with no memberships there is no workspace to name — render nothing.
  if (memberships.length === 0) return null;

  const current = memberships.find((m) => m.isCurrent) ?? memberships[0];

  // Collapsed rail (md:w-14): render ONLY the icon-only identity tile — no pill
  // chrome, no `▾`, no switch button (there is no horizontal room for them at
  // 56px). Both solo and multi-org collapse to the same icon. The full workspace
  // name rides the `title`/`aria-label` as the authoritative disambiguator for
  // shared-initial monograms (P0-3). Keeps the `workspace-identity-icon` testid +
  // tooltip the band unit suite and nav-states-shell.e2e.ts depend on — they used
  // to be produced by the band's (now-deleted) collapsed early-return.
  if (collapsed) {
    return (
      <span
        data-testid="workspace-identity-icon"
        aria-label={current.organizationName}
        title={current.organizationName}
        className="flex shrink-0"
      >
        <WorkspaceIdentityTile
          name={current.organizationName}
          size="sm"
          variant="identity"
          workspaceId={current.workspaceId}
          hasLogo={current.hasLogo}
        />
      </span>
    );
  }

  // RQ7 / CPO sign-off condition #2: a solo user (exactly one workspace) still
  // sees their workspace NAME in the context band for orientation, but as a
  // VISIBLY NON-INTERACTIVE chip — no dropdown trigger, no `▾` affordance —
  // because there is nothing to switch to. The band's identity display is a
  // distinct concern from the interactive switch.
  if (memberships.length === 1) {
    return (
      <div
        data-testid="workspace-identity-static"
        className="flex w-full min-w-0 items-center gap-3 rounded-xl bg-soleur-bg-surface-2 px-3 py-2.5 text-left shadow-sm"
      >
        <WorkspaceIdentityTile
          name={current.organizationName}
          size="lg"
          variant="identity"
          workspaceId={current.workspaceId}
          hasLogo={current.hasLogo}
        />
        <span className="min-w-0">
          <span className="block truncate text-sm font-bold text-soleur-text-primary">
            {current.organizationName}
          </span>
          {repoName ? (
            <span
              data-testid="live-repo-badge"
              className="block truncate text-xs text-soleur-text-muted"
            >
              {repoName}
            </span>
          ) : null}
        </span>
      </div>
    );
  }

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        aria-label="Switch workspace"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        className="flex w-full min-w-0 items-center gap-3 rounded-xl bg-soleur-bg-surface-2 px-3 py-2.5 text-left shadow-sm transition-shadow hover:shadow-md"
      >
        <WorkspaceIdentityTile
          name={current.organizationName}
          size="lg"
          variant="identity"
          workspaceId={current.workspaceId}
          hasLogo={current.hasLogo}
        />
        <span className="min-w-0">
          <span className="block truncate text-sm font-bold text-soleur-text-primary">
            {current.organizationName}
          </span>
          {repoName ? (
            <span
              data-testid="live-repo-badge"
              className="block truncate text-xs text-soleur-text-muted"
            >
              {repoName}
            </span>
          ) : null}
        </span>
        <span aria-hidden="true" className="ml-1 shrink-0 text-soleur-text-muted">▾</span>
      </button>

      {open && (
        <div
          role="menu"
          className="absolute left-0 top-full z-50 mt-2 w-80 max-w-[calc(100vw-1.5rem)] rounded-md bg-soleur-bg-surface-1 py-2 shadow-xl ring-1 ring-soleur-border-default/40"
        >
          <div className="px-4 pb-2 text-xs font-medium uppercase tracking-wider text-soleur-text-muted">
            Your workspaces
          </div>
          <ul className="max-h-72 overflow-auto">
            {memberships.map((m) => (
              <li key={m.organizationId}>
                <button
                  type="button"
                  role="menuitem"
                  data-testid="org-row"
                  onClick={() => handleSelect(m.organizationId, m.isCurrent)}
                  className={`flex w-full items-center gap-3 px-4 py-2.5 text-left hover:bg-soleur-bg-surface-2 ${
                    m.isCurrent
                      ? "border-l-2 border-soleur-accent-gold-fg bg-soleur-bg-surface-2/40"
                      : ""
                  }`}
                >
                  <WorkspaceIdentityTile
                    name={m.organizationName}
                    size="md"
                    workspaceId={m.workspaceId}
                    hasLogo={m.hasLogo}
                    // Current row keeps a gold ACCENT (ring, not a fill) — the
                    // sanctioned active-workspace-identity gold use (FR6), so the
                    // current vs non-current distinction survives the swatch→tile
                    // swap without reintroducing the gold square fill.
                    className={
                      m.isCurrent
                        ? "ring-2 ring-inset ring-soleur-accent-gold-fg"
                        : undefined
                    }
                  />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-medium text-soleur-text-primary">
                      {m.organizationName}
                    </span>
                    <span className="block text-xs text-soleur-text-muted">
                      {roleLabel(m.role)} · {m.memberCount}{" "}
                      {m.memberCount === 1 ? "member" : "members"}
                    </span>
                  </span>
                  {m.isCurrent && (
                    <span
                      aria-hidden="true"
                      data-testid="current-mark"
                      className="text-soleur-accent-gold-fg"
                    >
                      ✓
                    </span>
                  )}
                </button>
              </li>
            ))}
          </ul>
          <div className="mt-2 border-t border-soleur-border-default px-4 pt-2 text-xs text-soleur-text-muted">
            Switch is read-only — billing and data stay with each workspace.
          </div>
        </div>
      )}
    </div>
  );
}
