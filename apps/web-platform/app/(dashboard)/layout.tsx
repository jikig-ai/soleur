"use client";

import { useState, useEffect, useCallback } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { TeamNamesProvider } from "@/hooks/use-team-names";
import { useSidebarCollapse } from "@/hooks/use-sidebar-collapse";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { SignOutConfirmModal } from "@/components/auth/sign-out-confirm-modal";
import { useSignOut } from "@/components/auth/use-sign-out";
import { WorkspaceContextBand } from "@/components/dashboard/workspace-context-band";
import { useActiveWorkspace } from "@/hooks/use-active-workspace";
import { RailSlotProvider, RailCollapsedProvider, RAIL_EXPAND_EVENT } from "@/components/dashboard/rail-slot";
import { RailResizeHandle } from "@/components/dashboard/rail-resize-handle";
import { useRailWidth, railMaxPx, RAIL_MIN_PX } from "@/hooks/use-rail-width";
import { segmentToDrillLevel, isKbDocView } from "@/hooks/segment-to-drill-level";
import { MembershipRevokedScreen } from "@/components/dashboard/membership-revoked-screen";
import { NoApiKeyBanner } from "@/components/dashboard/no-api-key-banner";
import { PendingInviteBannerRecovery } from "@/components/dashboard/pending-invite-banner-recovery";

const BANNER_DISMISS_KEY = "soleur:past_due_banner_dismissed";

/**
 * Past-due payment warning banner with sessionStorage-backed dismiss.
 *
 * Persists dismissal within a tab session so a page refresh does not re-show
 * the banner, while a new tab still surfaces the warning (sessionStorage is
 * tab-scoped).
 *
 * SSR-safe: the `window.sessionStorage` read is gated in a `useEffect` so the
 * initial render (`dismissed = false`) matches the server output and hydrates
 * cleanly; the post-hydration effect may flip state to `true`, which React
 * reconciles as a client-only update.
 */
export function PaymentWarningBanner({
  subscriptionStatus,
}: {
  subscriptionStatus: string | null;
}) {
  const [dismissed, setDismissed] = useState(false);

  // Hydrate dismiss state from sessionStorage (client-only).
  useEffect(() => {
    try {
      if (sessionStorage.getItem(BANNER_DISMISS_KEY) === "1") {
        setDismissed(true);
      }
    } catch {
      // sessionStorage unavailable (private mode, etc.) — keep default false.
    }
  }, []);

  function dismissBanner() {
    setDismissed(true);
    try {
      sessionStorage.setItem(BANNER_DISMISS_KEY, "1");
    } catch {
      // Persistence failed (quota, private mode) — in-memory state still hides
      // the banner for the current mount, which is acceptable degradation.
    }
  }

  if (subscriptionStatus !== "past_due" || dismissed) {
    return null;
  }

  return (
    <div className="border-b border-orange-800/50 bg-orange-950/30 px-4 py-3">
      <div className="mx-auto flex max-w-4xl items-center justify-between gap-3">
        <p className="text-sm text-soleur-text-primary">
          <span className="font-medium text-orange-400">Your last payment failed.</span>{" "}
          Update your payment method to avoid service interruption.
        </p>
        <div className="flex shrink-0 items-center gap-2">
          <a
            href="/dashboard/settings"
            className="rounded-lg bg-orange-600 px-3 py-1.5 text-xs font-medium text-soleur-text-on-accent hover:bg-orange-500"
          >
            Update Payment
          </a>
          <button
            onClick={dismissBanner}
            aria-label="Dismiss payment warning"
            className="rounded p-1 text-soleur-text-secondary hover:text-soleur-text-primary"
          >
            <XIcon className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}

const NAV_ITEMS = [
  { href: "/dashboard", label: "Dashboard", icon: GridIcon },
  { href: "/dashboard/kb", label: "Knowledge Base", icon: BookIcon },
  { href: "/dashboard/routines", label: "Routines", icon: RepeatIcon },
];

const ADMIN_NAV_ITEMS = [
  { href: "/dashboard/admin/analytics", label: "Analytics", icon: ChartIcon },
];

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [isAdmin, setIsAdmin] = useState(false);
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [subscriptionStatus, setSubscriptionStatus] = useState<string | null>(null);
  const [collapsed, toggleCollapsed] = useSidebarCollapse("soleur:sidebar.main.collapsed");
  // Widenable KB rail (amendment): persisted width applied to the `aside` ONLY
  // when drilled into KB and expanded (collapse takes precedence; KB-only) and
  // only at the md+ breakpoint (the mobile drawer keeps its `w-64` width). The
  // value rides the `--kb-rail-w` CSS var + a `data-kb-rail-width` attribute,
  // consumed by an md+ rule in globals.css — deterministic, no JS media-query
  // state (which did not flip reliably under SSR hydration here).
  const [railWidth, setRailWidth] = useRailWidth();
  const [signOutModalOpen, setSignOutModalOpen] = useState(false);
  const { handleSignOut, isSigningOut } = useSignOut();
  // Secondary-nav slot node — drilled sections portal their nav here (ADR-047).
  // A useState ref-callback so the provider value updates once the slot mounts.
  const [railSlotEl, setRailSlotEl] = useState<HTMLElement | null>(null);
  // Active workspace name for the COLLAPSED rail band's monogram tooltip — the
  // collapsed band does not mount OrgSwitcherContainer, so the name is threaded
  // in here (P0-3, #4915). Gated on `collapsed`: the expanded rail + mobile band
  // already surface the name via OrgSwitcherContainer, so the fetch only fires
  // for the one state that lacks it (avoids a redundant cold-mount GET + a
  // net-new focus poll in the common expanded case).
  const activeWorkspace = useActiveWorkspace(collapsed);
  const activeWorkspaceName = activeWorkspace.name;

  // Check admin status on mount
  useEffect(() => {
    fetch("/api/admin/check")
      .then((res) => res.json())
      .then((data: { isAdmin: boolean }) => setIsAdmin(data.isAdmin))
      .catch(() => {});
  }, []);

  useEffect(() => {
    const supabase = createClient();
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUserEmail(session?.user?.email ?? null);
      if (session?.user?.id) {
        supabase
          .from("users")
          .select("subscription_status")
          .eq("id", session.user.id)
          .single()
          .then(({ data }) => {
            setSubscriptionStatus(data?.subscription_status ?? null);
          });
      }
    });
  }, []);

  const navItems = isAdmin ? [...NAV_ITEMS, ...ADMIN_NAV_ITEMS] : NAV_ITEMS;
  // segmentToDrillLevel is the SOLE drill-state authority (AC4c) — no raw
  // pathname.startsWith("/dashboard/(kb|settings|chat)") literal lives here.
  const drill = segmentToDrillLevel(pathname);
  const settingsActive = drill === "settings";
  // The widen affordance is KB-only AND subordinate to collapse: the inline
  // width + handle apply solely in this branch, so collapsed (md:w-14) and
  // Settings/Chat (md:w-56) widths are structurally untouched (AC12/AC13).
  const kbExpanded = drill === "kb" && !collapsed;
  // Phase 3 (#4915): one back per state. In the mobile KB DOC VIEW the
  // kb-content-header owns the only back ("Back to file tree", md:hidden), so the
  // mobile band's "Back to menu" is suppressed to stop the two co-rendering. This
  // is path EXTRACTION ("a KB doc is open" — trailing-slash form), explicitly
  // distinct from drill detection (which stays sole to segmentToDrillLevel,
  // AC4c): the band itself never reads pathname for this — the layout owns it.
  // The KB page-body header (kb/layout.tsx) keys its own back on the SAME
  // predicate, so exactly one "Back to menu" renders per state.
  const inKbDocView = isKbDocView(pathname);

  // Auto-close drawer on route change
  useEffect(() => {
    setDrawerOpen(false);
  }, [pathname]);

  // Close drawer on ESC key (register once — setDrawerOpen(false) is a no-op when already closed)
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") setDrawerOpen(false);
    }
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, []);

  // Cmd/Ctrl+B toggles THE single nav rail (AC5). This is now the sole ⌘B
  // owner across every section — the per-route handlers that previously lived
  // in SettingsShell, useKbLayoutState, and ConversationsRail are removed, so
  // there is exactly one keydown handler and exactly one rail it toggles.
  useEffect(() => {
    function handleToggleShortcut(e: KeyboardEvent) {
      if (!(e.metaKey || e.ctrlKey) || e.key !== "b") return;
      // Skip when typing in form elements
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      if ((e.target as HTMLElement)?.isContentEditable) return;
      e.preventDefault();
      toggleCollapsed();
    }
    document.addEventListener("keydown", handleToggleShortcut);
    return () => document.removeEventListener("keydown", handleToggleShortcut);
  }, [toggleCollapsed]);

  // Sidebar-UX follow-up Issue 6: a collapsed-rail child (the KB shell's
  // "Browse files" affordance) cannot reach the collapse state directly (it only
  // reads RailCollapsedProvider). It requests an EXPAND via a window event so the
  // layout — the sole collapse owner (ADR-047) — can flip it. Expand-only (never
  // collapses), so a stray dispatch while expanded is a no-op.
  useEffect(() => {
    function handleExpandRequest() {
      if (collapsed) toggleCollapsed();
    }
    window.addEventListener(RAIL_EXPAND_EVENT, handleExpandRequest);
    return () =>
      window.removeEventListener(RAIL_EXPAND_EVENT, handleExpandRequest);
  }, [collapsed, toggleCollapsed]);

  // Body scroll lock when drawer is open
  useEffect(() => {
    if (drawerOpen) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }
    return () => {
      document.body.style.overflow = "";
    };
  }, [drawerOpen]);

  // Auto-close drawer when viewport crosses md breakpoint (orientation change)
  useEffect(() => {
    const mediaQuery = window.matchMedia("(min-width: 768px)");
    const handler = () => {
      if (mediaQuery.matches) setDrawerOpen(false);
    };
    mediaQuery.addEventListener("change", handler);
    return () => mediaQuery.removeEventListener("change", handler);
  }, []);

  return (
    <TeamNamesProvider>
    <RailSlotProvider value={railSlotEl}>
    <RailCollapsedProvider value={collapsed}>
    <div className="flex h-dvh flex-col md:flex-row">
      {/* Mobile top bar — only visible below md breakpoint. RQ1: the context
          band replaces the bare "Soleur" label so workspace identity is shown
          in EVERY mobile state, OUTSIDE the hamburger drawer. */}
      <div className="flex min-h-14 shrink-0 items-center gap-1 border-b border-soleur-border-default bg-soleur-bg-surface-1 px-2 safe-top md:hidden">
        <button
          onClick={() => setDrawerOpen(true)}
          aria-label="Open navigation"
          aria-expanded={drawerOpen}
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg text-soleur-text-muted hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
        >
          <MenuIcon className="h-5 w-5" />
        </button>
        {/* Mobile band — placed via CSS (this bar is `md:hidden`), NOT a JS
            viewport gate, so workspace identity + the back chevron paint on the
            FIRST frame (no SSR/hydration tick where identity is absent). */}
        <WorkspaceContextBand
          pathname={pathname}
          variant="mobile"
          suppressBack={inKbDocView}
          // KB owns its "Knowledge Base" title in the page body on mobile
          // (kb/layout fullWidth header), so the mobile band drops the duplicate
          // section title. Settings/Chat keep theirs (KB-scoped).
          suppressSectionTitle={drill === "kb"}
        />
      </div>

      {/* Overlay backdrop — always rendered for fade transition */}
      <div
        className={`fixed inset-0 z-40 bg-black/50 transition-opacity duration-200 md:hidden ${
          drawerOpen ? "opacity-100" : "pointer-events-none opacity-0"
        }`}
        aria-hidden="true"
        onClick={() => setDrawerOpen(false)}
      />

      {/* Sidebar / mobile drawer — always rendered for CSS transitions.
          `inert` while the sign-out modal is open removes the sidebar
          Sign out button from the a11y tree so agent-driven selectors
          (and screen readers) target only the modal's confirm button. */}
      <aside
        inert={signOutModalOpen || undefined}
        // The KB-expanded branch drives the md+ width from a CSS variable so the
        // inline value is scoped to the desktop rail; the mobile `w-64` drawer
        // is left to the base class. (Inline `style.width` would otherwise win
        // at every breakpoint and resize the mobile drawer too — Sharp Edge.)
        data-kb-rail-width={kbExpanded ? "" : undefined}
        style={
          kbExpanded
            ? ({ "--kb-rail-w": `${railWidth}px` } as React.CSSProperties)
            : undefined
        }
        className={`
          fixed inset-y-0 left-0 z-50 flex w-64 flex-col border-r border-soleur-border-default bg-soleur-bg-surface-1
          transition-transform duration-200 ease-out
          ${drawerOpen ? "translate-x-0" : "-translate-x-full"}
          md:relative md:z-30 md:translate-x-0
          md:transition-[width] md:duration-200 md:ease-out
          ${/* md:w-56 = 14rem = 224px = RAIL_DEFAULT_PX (use-rail-width.ts); the KB
               rail starts at that same default. When kbExpanded, the
               data-kb-rail-width rule in globals.css overrides this at md+ with
               the persisted --kb-rail-w. */ ""}
          ${collapsed ? "md:w-14" : "md:w-56"}
        `}
      >
        {/* Mobile-only close row. The desktop collapse toggle was lifted OUT of
            this row and FLOATED (see the button below) so the workspace context
            band rises to the very top of the desktop rail. The "Soleur" wordmark
            was removed in #4915 Phase 2, leaving this row near-empty on desktop and
            wasting ~45px (the row + its pt-3/pb-2 + the band's pt-2 stacked above
            the workspace pill). The row is now md:hidden and holds only the mobile
            drawer-close button; it keeps `safe-top` for the notch inset (desktop
            has no safe-area inset, so dropping it from the desktop path is correct). */}
        <div className="flex items-center safe-top px-3 pt-3 pb-2 md:hidden">
          <button
            onClick={() => setDrawerOpen(false)}
            aria-label="Close navigation"
            className="flex h-10 w-10 items-center justify-center rounded-lg text-soleur-text-muted hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
          >
            <XIcon className="h-5 w-5" />
          </button>
        </div>

        {/* Desktop collapse toggle — FLOATED in the rail's top-right so it costs
            ZERO vertical space (the workspace band now owns the sidebar top).
            Absolutely positioned against the <aside> (its md:relative containing
            block), NOT in the flex-col flow. EXPANDED: `right-3` pins it to the rail's
            top-right, the corner of the workspace pill. COLLAPSED: `left-1/2
            -translate-x-1/2` centers it on the same vertical axis as the monogram tile
            and the icon-only nav column below, so the collapsed rail reads as one clean
            centered column (the right-3 corner control sat off-axis above the logo).
            Vertical: EXPANDED `top-10` (40px) vertically CENTERS the h-6 (24px) button
            on the workspace pill row's center. COLLAPSED `top-3` pins it HIGH near the
            rail top — there is no pill to center on, and at top-10 the button's bottom
            edge (64px) landed flush with the monogram tile (pt-16 → 64px) and read as
            crowding the logo; top-3 lifts it clear. The toggle is positioned against the <aside>,
            but the band (and its pill) sits ~12px BELOW the aside top (the reclaimed-
            space offset — VRT-measured, asserted ≤12). The pill leads the band at pt-2
            (8px) and is 64px tall (lg h-11 tile + py-2.5), so its center sits at
            12+8+32 = 52px from the aside top; the toggle's center at 40+12 = 52px.
            (VRT-derived: top-7 left a 12px residual = the band offset.) This follows the repo's
            CENTER-against-an-adjacent-element convention (components/kb/file-tree.tsx,
            components/kb/search-overlay.tsx) rather than the fixed top-right CORNER
            convention (components/ui/error-card.tsx) — the toggle aligns to a card's
            center, not a card's corner, so the corner `top-3` it originally mirrored
            (PR #4997) read ~28px high. z-10 lifts it above the band's static content;
            the multi-workspace switcher dropdown opens DOWNWARD (`top-full`) in a
            disjoint vertical band and a separate stacking context, so there is no
            cross-context z race. The expanded pill row (md:pr) and the collapsed
            icon column (pt) reserve clearance so this never overlaps the workspace
            card, its dropdown chevron, or the collapsed monogram tile. In the
            collapsed rail (md:w-14 = 56px) it stays fully inside the rail and is the
            only non-keyboard expand affordance — its aria-label/title/⌘B semantics
            are preserved verbatim. */}
        <button
          onClick={toggleCollapsed}
          aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
          title={collapsed ? "Expand sidebar (⌘B)" : "Collapse sidebar (⌘B)"}
          className={`absolute ${collapsed ? "left-1/2 -translate-x-1/2 top-3" : "right-3 top-10"} z-10 hidden h-6 w-6 items-center justify-center rounded text-soleur-text-muted hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary md:flex`}
        >
          <PanelToggleIcon className="h-4 w-4" />
        </button>

        {/* Persistent workspace context band (ADR-047). Mounted OUTSIDE the
            rail swap region and NEVER gated on `collapsed` — this fixes the
            live bug where OrgSwitcherContainer + LiveRepoBadge unmounted on
            collapse, leaving the active workspace ambiguous during a
            tenant-sensitive action. The band is the SOLE render site for both
            components (AC4b single-mount); it also carries the back chevron +
            section title in drilled states. Placed via CSS (`hidden md:block`)
            so it paints on the first frame on desktop; on mobile the band lives
            in the top bar (RQ1). Each band manages its own data fetch — the two
            CSS-exclusive placements never show identity twice (AC4b: the band
            is still the single importer of OrgSwitcherContainer/LiveRepoBadge). */}
        <div className="hidden md:block">
          <WorkspaceContextBand
            pathname={pathname}
            collapsed={collapsed}
            activeWorkspaceName={activeWorkspaceName ?? undefined}
            activeWorkspaceId={activeWorkspace.workspaceId ?? undefined}
            activeWorkspaceHasLogo={activeWorkspace.hasLogo}
          />
        </div>

        {/* Rail swap region (ADR-047): the section's secondary nav REPLACES
            the primary nav + footer in the same rail when drilled. A true
            conditional swap (not CSS hide) — exactly one nav surface mounts at
            a time. The drilled section portals its nav into the slot below. */}
        {drill === null ? (
          <>
            {/* Navigation */}
            <nav className={`flex-1 space-y-1 pt-3 ${collapsed ? "px-1" : "px-3"}`}>
              {navItems.map((item) => {
                const active =
                  item.href === "/dashboard"
                    ? pathname === "/dashboard" || drill === "chat"
                    : pathname.startsWith(item.href);

                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    title={collapsed ? item.label : undefined}
                    aria-current={active ? "page" : undefined}
                    className={`relative flex min-h-[44px] items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors ${
                      active
                        ? "bg-soleur-accent-gold-fill/10 text-soleur-accent-gold-text"
                        : "text-soleur-text-muted hover:bg-soleur-bg-surface-2/60 hover:text-soleur-text-secondary"
                    } ${collapsed ? "md:justify-center md:gap-0 md:px-0" : ""}`}
                  >
                    {/* D4-bolder active treatment: a flush left-edge gold bar
                        OVERLAY (left-0, in the px-3 gutter) so the icon/label
                        column is NOT indented vs inactive items. Hidden on the
                        collapsed rail where there is no left gutter. */}
                    {active && (
                      <span
                        aria-hidden="true"
                        className={`absolute inset-y-1.5 left-0 w-[3px] rounded-full bg-soleur-accent-gold-fill ${collapsed ? "md:hidden" : ""}`}
                      />
                    )}
                    <item.icon className="h-4 w-4 shrink-0" />
                    <span className={`overflow-hidden whitespace-nowrap ${collapsed ? "md:hidden" : ""}`}>
                      {item.label}
                    </span>
                  </Link>
                );
              })}
            </nav>

            {/* Footer links */}
            <div className={`border-t border-soleur-border-default safe-bottom ${collapsed ? "p-1" : "p-3"}`}>
              {userEmail && !collapsed && (
                <p
                  className="truncate px-3 py-1 text-xs text-soleur-text-muted"
                  title={userEmail}
                >
                  {userEmail}
                </p>
              )}
              <a
                href="https://soleur-ai.betteruptime.com/"
                target="_blank"
                rel="noopener noreferrer"
                title={collapsed ? "Status" : undefined}
                className={`flex min-h-[44px] w-full items-center gap-3 rounded-lg px-3 py-2 text-sm text-soleur-text-muted transition-colors hover:bg-soleur-bg-surface-2/60 hover:text-soleur-text-secondary ${collapsed ? "md:justify-center md:gap-0 md:px-0" : ""}`}
              >
                <StatusIcon className="h-4 w-4 shrink-0" />
                <span className={`overflow-hidden whitespace-nowrap ${collapsed ? "md:hidden" : ""}`}>Status</span>
              </a>
              <Link
                href="/dashboard/settings"
                title={collapsed ? "Settings" : undefined}
                aria-current={settingsActive ? "page" : undefined}
                className={`flex min-h-[44px] w-full items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors ${
                  settingsActive
                    ? "bg-soleur-bg-surface-2 text-soleur-text-primary"
                    : "text-soleur-text-muted hover:bg-soleur-bg-surface-2/60 hover:text-soleur-text-secondary"
                } ${collapsed ? "md:justify-center md:gap-0 md:px-0" : ""}`}
              >
                <SettingsIcon className="h-4 w-4 shrink-0" />
                <span className={`overflow-hidden whitespace-nowrap ${collapsed ? "md:hidden" : ""}`}>Settings</span>
              </Link>
              <button
                onClick={() => setSignOutModalOpen(true)}
                title={collapsed ? "Sign out" : undefined}
                className={`flex min-h-[44px] w-full items-center gap-3 rounded-lg px-3 py-2 text-sm text-soleur-text-muted transition-colors hover:bg-soleur-bg-surface-2/60 hover:text-soleur-text-secondary ${collapsed ? "md:justify-center md:gap-0 md:px-0" : ""}`}
              >
                <LogOutIcon className="h-4 w-4 shrink-0" />
                <span className={`overflow-hidden whitespace-nowrap ${collapsed ? "md:hidden" : ""}`}>Sign out</span>
              </button>
              {/* Theme toggle — the quiet, lowest-priority affordance sits at the
                  very bottom of the rail, BELOW Sign out (matches the D4 wireframe
                  frames 16/23). Stays top-level chrome, render-conditional via the
                  `drill === null` branch this footer lives in. */}
              <div className={collapsed ? "pt-2" : "px-1 pt-2"}>
                <ThemeToggle collapsed={collapsed} />
              </div>
            </div>
          </>
        ) : (
          <div
            ref={setRailSlotEl}
            data-testid="rail-secondary-slot"
            className="flex min-h-0 flex-1 flex-col overflow-y-auto"
          />
        )}

        {/* Widenable KB rail (amendment): a right-edge drag handle, rendered
            ONLY when drilled into KB and expanded. It drives the `aside`'s
            --kb-rail-w via the persisted useRailWidth hook (transient on drag,
            commit on pointerup). Collapsed / Settings / Chat never render it
            (collapse precedence + KB-only). `hidden md:block` keeps it off the
            mobile drawer. */}
        {kbExpanded && (
          <RailResizeHandle
            width={railWidth}
            min={RAIL_MIN_PX}
            max={railMaxPx()}
            onWidthChange={(px) => setRailWidth(px, false)}
            onCommit={(px) => setRailWidth(px, true)}
          />
        )}
      </aside>

      {/* Main content — inert when drawer is open for focus trapping */}
      <main
        className="flex-1 overflow-y-auto bg-soleur-bg-base"
        inert={drawerOpen || undefined}
      >
        {/* Payment banners */}
        {subscriptionStatus === "unpaid" && (
          <div className="border-b border-red-800/50 bg-red-950/30 px-4 py-3">
            <div className="mx-auto flex max-w-4xl items-center justify-between gap-3">
              <p className="text-sm text-soleur-text-primary">
                <span className="font-medium text-red-400">Your subscription is unpaid.</span>{" "}
                Your account is in read-only mode.
              </p>
              <a
                href="/dashboard/settings"
                className="shrink-0 rounded-lg bg-red-600 px-3 py-1.5 text-xs font-medium text-soleur-text-on-accent hover:bg-red-500"
              >
                Resolve Payment
              </a>
            </div>
          </div>
        )}
        <PaymentWarningBanner subscriptionStatus={subscriptionStatus} />
        {/* Recovery banner (#4715): an invitee who abandoned at /invite reaches
            /dashboard with the accept RPC never called. Self-gates via
            /api/workspace/pending-invites and backs off on chat routes (which
            already mount the banner server-side). */}
        <PendingInviteBannerRecovery />
        {/* Keyless / delegated-but-keyless degraded-state banner (#4642).
            Self-gates via /api/byok/effective-status — renders nothing for
            users with a usable key. */}
        <NoApiKeyBanner />
        {children}
      </main>

      <SignOutConfirmModal
        open={signOutModalOpen}
        onClose={() => setSignOutModalOpen(false)}
        onConfirm={handleSignOut}
        isSigningOut={isSigningOut}
      />

      {/* AC-FLOW2: terminal overlay rendered when ws.close(4012) fires. Mount
          once at the dashboard root so it survives across route changes. */}
      <MembershipRevokedScreen />
    </div>
    </RailCollapsedProvider>
    </RailSlotProvider>
    </TeamNamesProvider>
  );
}

/* Inline SVG icon components — avoids external dependency */

function MenuIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"
      />
    </svg>
  );
}

function XIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M6 18 18 6M6 6l12 12"
      />
    </svg>
  );
}

function GridIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M3.75 6A2.25 2.25 0 0 1 6 3.75h2.25A2.25 2.25 0 0 1 10.5 6v2.25a2.25 2.25 0 0 1-2.25 2.25H6a2.25 2.25 0 0 1-2.25-2.25V6ZM3.75 15.75A2.25 2.25 0 0 1 6 13.5h2.25a2.25 2.25 0 0 1 2.25 2.25V18a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18v-2.25ZM13.5 6a2.25 2.25 0 0 1 2.25-2.25H18A2.25 2.25 0 0 1 20.25 6v2.25A2.25 2.25 0 0 1 18 10.5h-2.25a2.25 2.25 0 0 1-2.25-2.25V6ZM13.5 15.75a2.25 2.25 0 0 1 2.25-2.25H18a2.25 2.25 0 0 1 2.25 2.25V18A2.25 2.25 0 0 1 18 20.25h-2.25a2.25 2.25 0 0 1-2.25-2.25v-2.25Z"
      />
    </svg>
  );
}

function BookIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M12 6.042A8.967 8.967 0 0 0 6 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 0 1 6 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 0 1 6-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0 0 18 18a8.967 8.967 0 0 0-6 2.292m0-14.25v14.25"
      />
    </svg>
  );
}

function SettingsIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.212-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z"
      />
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z"
      />
    </svg>
  );
}

function StatusIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
      />
    </svg>
  );
}

function LogOutIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6a2.25 2.25 0 0 0-2.25 2.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15m3 0 3-3m0 0-3-3m3 3H9"
      />
    </svg>
  );
}

// Sidebar-UX follow-up Issue 2: non-directional sidebar/panel-toggle glyph for
// the rail collapse control. Replaces the old left/right ChevronLeftIcon/
// ChevronRightIcon, which read like a "back" arrow on drilled secondary menus
// (Settings / Knowledge Base) where the workspace band already shows a
// BackArrowIcon "Back to menu". A rounded panel rectangle with a left divider
// reads as "toggle the sidebar", not "go back". Used in BOTH toggle states —
// the aria-label/title carry the Expand vs Collapse semantics.
function PanelToggleIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M3.75 6.75A2.25 2.25 0 0 1 6 4.5h12a2.25 2.25 0 0 1 2.25 2.25v10.5A2.25 2.25 0 0 1 18 19.5H6a2.25 2.25 0 0 1-2.25-2.25V6.75Z"
      />
      <path strokeLinecap="round" strokeLinejoin="round" d="M9.75 4.5v15" />
    </svg>
  );
}

function ChartIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 0 1 3 19.875v-6.75ZM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V8.625ZM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V4.125Z"
      />
    </svg>
  );
}

function RepeatIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M16.023 9.348h4.992V4.356M3.985 19.644v-4.992h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.183m0-4.991v4.99"
      />
    </svg>
  );
}
