"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { OrgMembershipSummary } from "@/server/org-memberships-resolver";

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
}: {
  memberships: readonly OrgMembershipSummary[];
  onSwitch?: (organizationId: string) => void;
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

  // AC-C: hide entirely on solo / empty membership.
  if (memberships.length <= 1) return null;

  const current = memberships.find((m) => m.isCurrent) ?? memberships[0];

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        aria-label="Switch workspace"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-2 rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-1.5 text-left hover:bg-soleur-bg-surface-2"
      >
        <span
          aria-hidden="true"
          className="h-6 w-6 shrink-0 rounded-sm bg-soleur-accent-gold-fg/60"
        />
        <span className="min-w-0">
          <span className="block truncate text-sm font-medium text-soleur-text-primary">
            {current.organizationName}
          </span>
          <span className="block text-xs text-soleur-accent-gold-fg">
            {roleLabel(current.role)}
          </span>
        </span>
        <span aria-hidden="true" className="ml-1 text-soleur-text-muted">▾</span>
      </button>

      {open && (
        <div
          role="menu"
          className="absolute left-1/2 top-12 z-50 w-80 -translate-x-1/2 rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 py-2 shadow-xl"
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
                  <span
                    aria-hidden="true"
                    className={`h-8 w-8 shrink-0 rounded-sm ${
                      m.isCurrent
                        ? "bg-soleur-accent-gold-fg/60"
                        : "bg-soleur-bg-surface-2"
                    }`}
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
