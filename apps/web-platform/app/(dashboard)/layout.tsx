"use client";

import { useState, useEffect, useRef } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { SWRConfig } from "swr";
import { createClient } from "@/lib/supabase/client";
import { swrConfig } from "@/lib/swr-config";
import { TeamNamesProvider } from "@/hooks/use-team-names";
import { useSidebarCollapse } from "@/hooks/use-sidebar-collapse";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { SignOutConfirmModal } from "@/components/auth/sign-out-confirm-modal";
import { useSignOut } from "@/components/auth/use-sign-out";
import { WorkspaceContextBand } from "@/components/dashboard/workspace-context-band";
import { RailSlotProvider, RailCollapsedProvider, RAIL_EXPAND_EVENT } from "@/components/dashboard/rail-slot";
import { RailResizeHandle } from "@/components/dashboard/rail-resize-handle";
import { useRailWidth, railMaxPx, RAIL_MIN_PX } from "@/hooks/use-rail-width";
import { segmentToDrillLevel, isKbDocView } from "@/hooks/segment-to-drill-level";
import { useNavResume } from "@/hooks/use-nav-resume";
import { MembershipRevokedScreen } from "@/components/dashboard/membership-revoked-screen";
import { NoApiKeyBanner } from "@/components/dashboard/no-api-key-banner";
import { PendingInviteBannerRecovery } from "@/components/dashboard/pending-invite-banner-recovery";
import { PwaControls } from "@/components/pwa/pwa-controls";
import { NAV_ITEMS, ADMIN_NAV_ITEMS } from "@/components/command-palette/nav-items";
import { InboxNavBadge } from "@/components/dashboard/inbox-nav-badge";
import { ConversationsNavBadge } from "@/components/dashboard/conversations-nav-badge";
import { WorkstreamNavBadge } from "@/components/dashboard/workstream-nav-badge";
import { ReleasesNavBadge } from "@/components/dashboard/releases-nav-badge";
import { ShortcutsProvider } from "@/components/command-palette/use-shortcuts";
import {
  isApplePlatform as detectApplePlatform,
  modChord,
} from "@/components/command-palette/platform";
import { CommandPalette } from "@/components/command-palette/command-palette";
import { HelpOverlay } from "@/components/command-palette/help-overlay";
import { MobilePaletteTrigger } from "@/components/command-palette/mobile-palette-trigger";
import { SupportLauncher } from "@/components/support/support-launcher";
import { TourProvider } from "@/components/tour/tour-provider";
import { useOptionalFeatureFlag } from "@/components/feature-flags/provider";

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

// Icons live here (local SVGs), keyed by href, so the nav DATA can live in the
// shared `command-palette/nav-items.ts` module (imported by the rail AND the
// ⌘K palette registry) without dragging this "use client" tree into the palette.
const NAV_ICONS: Record<string, (props: { className?: string }) => React.JSX.Element> = {
  "/dashboard": GridIcon,
  "/dashboard/inbox": InboxIcon,
  "/dashboard/workstream": KanbanIcon,
  "/dashboard/crm": ContactsIcon,
  "/dashboard/kb": BookIcon,
  "/dashboard/routines": RepeatIcon,
  "/dashboard/admin/analytics": ChartIcon,
};

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  // #4826 — sticky KB (and chat) section-root hrefs from sessionStorage.
  // Bookmarks to bare `/dashboard/kb` still mean landing; only the main-nav
  // Link href is rewritten so re-entry restores last-open path.
  const { getKbEntryHref } = useNavResume();
  const kbEntryHref = getKbEntryHref();
  const [drawerOpen, setDrawerOpen] = useState(false);
  // Skip-to-content target: the skip link moves focus here explicitly (Safari
  // does not move focus on a bare href="#id" + tabIndex={-1} fragment jump).
  const mainRef = useRef<HTMLElement>(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [subscriptionStatus, setSubscriptionStatus] = useState<string | null>(null);
  const [collapsed, toggleCollapsed] = useSidebarCollapse("soleur:sidebar.main.collapsed");
  // Widenable rail: ONE persisted width applied to the `aside` whenever it is
  // expanded, in EVERY drill state (collapse still takes precedence) and only at
  // the md+ breakpoint (the mobile drawer keeps its `w-64` width). The value
  // rides `--kb-rail-w` + `data-kb-rail-width` on the KB rail and `--main-rail-w`
  // + `data-main-rail-width` elsewhere (one shared useRailWidth instance), each
  // consumed by an md+ rule in globals.css — deterministic, no JS media-query
  // state (which did not flip reliably under SSR hydration here).
  const [railWidth, setRailWidth] = useRailWidth();
  const [signOutModalOpen, setSignOutModalOpen] = useState(false);
  const { handleSignOut, isSigningOut } = useSignOut();
  // feat-web-app-shortcuts — gates the ⌘K palette + ? overlay command layer.
  // Optional (non-throwing) so a provider-less render degrades to "off".
  const commandPaletteEnabled = useOptionalFeatureFlag("command-palette");
  // Secondary-nav slot node — drilled sections portal their nav here (ADR-047).
  // A useState ref-callback so the provider value updates once the slot mounts.
  const [railSlotEl, setRailSlotEl] = useState<HTMLElement | null>(null);
  // SSR-safe: init non-Apple (→ `Ctrl` glyph) then read the real platform on
  // mount, so the ⌘B tooltip shows `Ctrl+B` on Windows/Linux (FR2).
  const [isApplePlatform, setIsApplePlatform] = useState(false);

  // Check admin status on mount
  useEffect(() => {
    fetch("/api/admin/check")
      .then((res) => res.json())
      .then((data: { isAdmin: boolean }) => setIsAdmin(data.isAdmin))
      .catch(() => {});
  }, []);

  // Read the platform once post-hydration for the ⌘/Ctrl tooltip glyph.
  useEffect(() => {
    setIsApplePlatform(detectApplePlatform());
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
  // Releases is a read-only info feed rendered in the footer info/settings
  // group (alongside Status/Settings), NOT the primary action-tab loop. It
  // stays in NAV_ITEMS (the ⌘K palette / `g l` / help-overlay source of
  // truth) and is filtered out of the primary render below. RELEASES_HREF
  // pins the single route literal shared by the filter, the footer <Link>,
  // and releasesActive. Releases is not a drill segment (DrillLevel is only
  // "kb" | "settings" | "chat"), so its active state is a direct pathname
  // check — `drill === "releases"` would be a TS error.
  const RELEASES_HREF = "/dashboard/releases";
  const releasesActive = pathname.startsWith(RELEASES_HREF);
  // The widen affordance applies to ANY expanded rail (every drill state),
  // subordinate to collapse. `kbExpanded` and `mainExpanded` are a structural
  // PARTITION of "expanded" (drill === "kb" XOR drill !== "kb"), so at most one
  // is ever true — the two `data-*-rail-width` attributes can never co-apply and
  // the single grip mount (below) is never duplicated. Both rails share ONE
  // persisted width (useRailWidth, key soleur:sidebar.kb.width); KB drives
  // `--kb-rail-w`, the rest drive `--main-rail-w` (separate vars keep the
  // existing KB CSS rule untouched). Collapsed (md:w-14) applies neither.
  const kbExpanded = drill === "kb" && !collapsed;
  const mainExpanded = drill !== "kb" && !collapsed;
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

  // ⌘B (sidebar toggle), the drawer Escape, and ⌘K/⌘//? are ALL served by the
  // single global keydown listener inside ShortcutsProvider (FR5/TR2) — there is
  // no standalone document keydown handler here anymore. The provider dispatches
  // ⌘B to `toggleCollapsed` and Esc-with-no-overlay-open to `setDrawerOpen(false)`.

  // Sidebar-UX follow-up Issue 6: a collapsed-rail child (the KB shell's
  // "Browse files" affordance) cannot reach the collapse state directly (it only
  // reads RailCollapsedProvider). It requests an EXPAND via a window event so the
  // layout — the sole collapse owner (ADR-047) — can flip it. Expand-only (never
  // collapses), so a stray dispatch while expanded is a no-op.
  useEffect(() => {
    function handleExpandRequest() {
      // An "expand request" must always yield a VISIBLE (expanded) rail. The only
      // dispatcher today is the KB "Browse files" button; this keeps any future
      // out-of-aside dispatcher (command palette, deep link) working too.
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
    // ADR-067: the dashboard client-data cache. Mounted at a structurally
    // stable position (cf. #5632 provider-tree stability) so a view's cached
    // content survives navigation between sibling routes. In-memory only (no
    // persistent provider — CPO C1); cleared on sign-out + workspace switch.
    <SWRConfig value={swrConfig}>
    <TeamNamesProvider>
    <RailSlotProvider value={railSlotEl}>
    <RailCollapsedProvider value={collapsed}>
    <ShortcutsProvider
      enabled={commandPaletteEnabled}
      isAdmin={isAdmin}
      onToggleSidebar={toggleCollapsed}
      onEscape={() => setDrawerOpen(false)}
    >
    <div className="flex h-dvh flex-col md:flex-row">
      {/* Skip-to-content — first focusable child, scoped to the dashboard layout
          (the #main-content target only exists here, not on /login or marketing
          routes). Hidden while the drawer is open because <main> is `inert` then
          and moving focus into an inert element fails silently. The onClick moves
          focus explicitly because Safari won't on a bare fragment jump. */}
      {!drawerOpen && (
        <a
          href="#main-content"
          onClick={() => mainRef.current?.focus()}
          className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-[100] focus:rounded-lg focus:bg-soleur-bg-surface-1 focus:px-4 focus:py-2 focus:text-soleur-text-primary focus:shadow-lg"
        >
          Skip to content
        </a>
      )}
      {/* Mobile top bar — only visible below md breakpoint. RQ1: the context
          band replaces the bare "Soleur" label so workspace identity is shown
          in EVERY mobile state, OUTSIDE the hamburger drawer. */}
      <div className="flex min-h-14 shrink-0 items-center gap-1 border-b border-soleur-border-default bg-soleur-bg-surface-1 px-2 safe-top md:hidden">
        <button
          onClick={() => setDrawerOpen(true)}
          aria-label="Open navigation"
          aria-expanded={drawerOpen}
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg text-soleur-text-muted hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
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
        {/* The only non-keyboard way to open the command palette. `ml-auto`
            pins it to the trailing edge; self-hides when the flag is off. */}
        <MobilePaletteTrigger />
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
        // Whichever rail is expanded drives the md+ width from a CSS variable so
        // the inline value is scoped to the desktop rail; the mobile `w-64` drawer
        // is left to the base class. (Inline `style.width` would otherwise win
        // at every breakpoint and resize the mobile drawer too — Sharp Edge.)
        data-kb-rail-width={kbExpanded ? "" : undefined}
        data-main-rail-width={mainExpanded ? "" : undefined}
        style={
          kbExpanded
            ? ({ "--kb-rail-w": `${railWidth}px` } as React.CSSProperties)
            : mainExpanded
              ? ({ "--main-rail-w": `${railWidth}px` } as React.CSSProperties)
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
               the persisted --kb-rail-w. Collapsed → md:w-14 icon rail; the
               existing md:transition-[width] animates the 224 ↔ 56 glide. */ ""}
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
            className="flex h-11 w-11 items-center justify-center rounded-lg text-soleur-text-muted hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
          >
            <XIcon className="h-5 w-5" />
          </button>
        </div>

        {/* Collapse/expand toggle — the floated « chevron. Collapses the rail to
            the icon rail (md:w-14) and expands it back; the glyph ROTATES 180° when
            collapsed (« → ») so it reads as an "expand" affordance. The resize
            slider also toggles collapse (double-click) and resizes width, so this
            button and the slider are the two collapse/expand affordances; ⌘B is the
            keyboard equivalent. (The full-hide 0px state was removed — it was a
            no-preview duplicate of this collapse.)
            EXPANDED: `right-3 top-10` (the corner of the workspace pill row).
            COLLAPSED: centered on the icon column at `top-3`, in the band's pt-16
            clearance above the monogram. Always mounted (no exclusive unmount), so
            no focus-swap handling is needed. */}
        <button
          onClick={toggleCollapsed}
          aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
          title={
            collapsed
              ? `Expand sidebar (${modChord("B", isApplePlatform)})`
              : `Collapse sidebar (${modChord("B", isApplePlatform)})`
          }
          className={`absolute ${collapsed ? "left-1/2 -translate-x-1/2 top-3" : "right-3 top-10"} z-10 hidden h-6 w-6 items-center justify-center rounded text-soleur-text-muted hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary md:flex`}
        >
          <RailToggleIcon
            className={`h-4 w-4 transition-transform duration-200 ${collapsed ? "rotate-180" : ""}`}
          />
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
          <WorkspaceContextBand pathname={pathname} collapsed={collapsed} />
        </div>

        {/* Rail swap region (ADR-047): the section's secondary nav REPLACES
            the primary nav + footer in the same rail when drilled. A true
            conditional swap (not CSS hide) — exactly one nav surface mounts at
            a time. The drilled section portals its nav into the slot below. */}
        {drill === null ? (
          <>
            {/* Navigation */}
            <nav className={`flex-1 space-y-1 pt-3 ${collapsed ? "px-1" : "px-3"}`}>
              {navItems.filter((item) => item.href !== RELEASES_HREF).map((item) => {
                // Sticky resume only rewrites the Knowledge Base main-nav href
                // (#4826 AC2). Active-state still keys on the canonical
                // section-root href so deep docs keep the gold treatment.
                const href =
                  item.href === "/dashboard/kb" ? kbEntryHref : item.href;
                const active =
                  item.href === "/dashboard"
                    ? pathname === "/dashboard" || drill === "chat"
                    : pathname.startsWith(item.href);
                const Icon = NAV_ICONS[item.href] ?? GridIcon;

                return (
                  <Link
                    key={item.href}
                    href={href}
                    data-tour-id={item.href}
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
                    <Icon className="h-4 w-4 shrink-0" />
                    <span className={`overflow-hidden whitespace-nowrap ${collapsed ? "md:hidden" : ""}`}>
                      {item.label}
                    </span>
                    {/* Nav attention-count badges, special-cased by href (matching
                        the `/dashboard` active-check above) to keep nav-items.ts
                        as pure route/label data. Mounted here — inside this
                        layout's <SWRConfig> (ADR-067) — so each fetch dedups with
                        its surface's list under the shared key. Inbox counts the
                        active email feed; Dashboard counts conversations needing a
                        decision; Workstream counts items needing attention. */}
                    {item.href === "/dashboard/inbox" && (
                      <InboxNavBadge collapsed={collapsed} />
                    )}
                    {item.href === "/dashboard" && (
                      <ConversationsNavBadge collapsed={collapsed} />
                    )}
                    {item.href === "/dashboard/workstream" && (
                      <WorkstreamNavBadge collapsed={collapsed} />
                    )}
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
              {/* Releases — read-only release-notes feed, grouped with the
                  info/settings chrome. Icon referenced directly (not via
                  NAV_ICONS, which is consumed only inside the primary loop);
                  neutral active treatment mirrors Settings so it reads as part
                  of this group, driven by the direct pathname check. */}
              <Link
                href={RELEASES_HREF}
                data-tour-id={RELEASES_HREF}
                title={collapsed ? "Releases" : undefined}
                aria-current={releasesActive ? "page" : undefined}
                className={`relative flex min-h-[44px] w-full items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors ${
                  releasesActive
                    ? "bg-soleur-bg-surface-2 text-soleur-text-primary"
                    : "text-soleur-text-muted hover:bg-soleur-bg-surface-2/60 hover:text-soleur-text-secondary"
                } ${collapsed ? "md:justify-center md:gap-0 md:px-0" : ""}`}
              >
                <RocketIcon className="h-4 w-4 shrink-0" />
                <span className={`overflow-hidden whitespace-nowrap ${collapsed ? "md:hidden" : ""}`}>Releases</span>
                {/* "New version published" cue — a calm gold dot when a web-v*
                    release newer than this device's last-seen tag has shipped
                    (feat-releases-nav-badge). Mounted inside the layout's
                    <SWRConfig> so its fetch dedups with the Releases surface. */}
                <ReleasesNavBadge collapsed={collapsed} />
              </Link>
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
                data-tour-id="/dashboard/settings"
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

        {/* Widenable rail: a right-edge drag handle rendered in EVERY state —
            expanded in any drill (Dashboard / Analytics / Settings / Chat / KB)
            AND collapsed (md:w-14). Alongside the floated « toggle, it is the
            second collapse/expand affordance and also resizes width. Drives the
            `aside` width via the persisted useRailWidth hook (transient on drag,
            commit on pointerup) — KB through --kb-rail-w, the rest through
            --main-rail-w. A SINGLE mount; the width override only applies while
            expanded (kbExpanded XOR mainExpanded = !collapsed), so a collapsed
            rail stays md:w-14 until the user acts on the handle. COLLAPSED
            interaction: `onResizeStart` un-collapses on the first real drag move
            (so the width override engages and the drag widens the rail), and a
            double-click toggles collapse via `onCollapse` (expands when collapsed,
            collapses when expanded). `hidden md:block` keeps it off the mobile
            drawer. A direct child of <aside> (sibling of the secondary slot) so
            the slot's overflow never clips it. */}
        <RailResizeHandle
          width={railWidth}
          min={RAIL_MIN_PX}
          max={railMaxPx()}
          onResizeStart={() => {
            // First genuine drag move while collapsed: un-collapse so the width
            // override (data-*-rail-width + --*-rail-w) engages and the drag
            // actually widens the rail. No-op once already expanded. Fires once
            // per drag (handle-internal latch), so no toggle thrash.
            if (collapsed) toggleCollapsed();
          }}
          onWidthChange={(px) => setRailWidth(px, false)}
          onCommit={(px) => setRailWidth(px, true)}
          onCollapse={toggleCollapsed}
          ariaLabel={drill === "kb" ? "Resize knowledge base sidebar" : "Resize sidebar"}
        />
      </aside>

      {/* (The full-hide 0px state and its floating reveal hamburger + left-edge
          gold strip were removed — that minimized state had no nav preview and
          duplicated the icon-rail collapse, which is now the only minimized
          state.) */}

      {/* Main content — inert when drawer is open for focus trapping */}
      <main
        id="main-content"
        tabIndex={-1}
        ref={mainRef}
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

      {/* PWA progressive-enhancement chrome: update pill / install button / iOS
          A2HS card. Renders null when standalone or when nothing is offerable. */}
      <PwaControls />
    </div>
    {/* Command layer (feat-web-app-shortcuts) — portal-rendered (Radix), so
        placement inside the provider is positional only. Both no-op when the
        command-palette flag is off (enabled=false). feat-guided-tour: TourProvider
        wraps the launch surfaces (support panel + ? overlay) + auto-first-run; no-op
        when the guided-tour flag is off. */}
    <TourProvider>
      <CommandPalette />
      <HelpOverlay />
      {/* feat-support-interface — flag-gated floating support launcher + slide-over.
          No-op when the `support` flag is off (renders null internally). */}
      <SupportLauncher />
    </TourProvider>
    </ShortcutsProvider>
    </RailCollapsedProvider>
    </RailSlotProvider>
    </TeamNamesProvider>
    </SWRConfig>
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

function InboxIcon({ className }: { className?: string }) {
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
        d="M2.25 13.5h3.86a2.25 2.25 0 0 1 2.012 1.244l.256.512a2.25 2.25 0 0 0 2.013 1.244h3.218a2.25 2.25 0 0 0 2.013-1.244l.256-.512a2.25 2.25 0 0 1 2.013-1.244h3.86m-19.5.338V18a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18v-4.162c0-.224-.034-.447-.1-.661L19.24 5.338a2.25 2.25 0 0 0-2.15-1.588H6.911a2.25 2.25 0 0 0-2.15 1.588L2.35 13.177a2.25 2.25 0 0 0-.1.661Z"
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

// Collapse/expand toggle glyph: a double chevron pointing left («), reading
// "fold the rail to the icon column". The caller rotates it 180° when collapsed
// (« → ») so the same glyph reads as "expand" in the collapsed state.
function RailToggleIcon({ className }: { className?: string }) {
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
        d="M18.75 19.5 11.25 12l7.5-7.5m-6 15L5.25 12l7.5-7.5"
      />
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

function KanbanIcon({ className }: { className?: string }) {
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
        d="M3.75 5.25h4.5v13.5h-4.5V5.25Zm6 0h4.5v9h-4.5v-9Zm6 0h4.5v6h-4.5v-6Z"
      />
    </svg>
  );
}

// CRM nav glyph (#6172): people/contacts — the beta-CRM pipeline of prospects.
function ContactsIcon({ className }: { className?: string }) {
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
        d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z"
      />
    </svg>
  );
}

// Releases nav glyph (#5958): a rocket — "what we've shipped".
function RocketIcon({ className }: { className?: string }) {
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
        d="M15.59 14.37a6 6 0 0 1-5.84 7.38v-4.8m5.84-2.58a14.98 14.98 0 0 0 6.16-12.12A14.98 14.98 0 0 0 9.63 8.41m5.96 5.96a14.926 14.926 0 0 1-5.84 2.58m0 0a6.003 6.003 0 0 0-7.38-5.84 6 6 0 0 1 7.38 5.84Zm-2.58-5.96a3 3 0 1 0-4.24-4.24 3 3 0 0 0 4.24 4.24Z"
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
