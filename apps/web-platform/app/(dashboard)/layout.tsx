"use client";

import { useState, useEffect, useCallback } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { TeamNamesProvider } from "@/hooks/use-team-names";
import { useSidebarCollapse } from "@/hooks/use-sidebar-collapse";
import { ConversationsRail } from "@/components/chat/conversations-rail";

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
        <p className="text-sm text-neutral-200">
          <span className="font-medium text-orange-400">Your last payment failed.</span>{" "}
          Update your payment method to avoid service interruption.
        </p>
        <div className="flex shrink-0 items-center gap-2">
          <a
            href="/dashboard/settings"
            className="rounded-lg bg-orange-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-orange-500"
          >
            Update Payment
          </a>
          <button
            onClick={dismissBanner}
            aria-label="Dismiss payment warning"
            className="rounded p-1 text-neutral-400 hover:text-neutral-200"
          >
            <XIcon className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}

const NAV_ITEMS = [
  { href: "/dashboard", label: "Command Center", icon: GridIcon },
  { href: "/dashboard/kb", label: "Knowledge Base", icon: BookIcon },
  { href: "/dashboard/settings", label: "Settings", icon: SettingsIcon },
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
  const router = useRouter();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [isAdmin, setIsAdmin] = useState(false);
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [subscriptionStatus, setSubscriptionStatus] = useState<string | null>(null);
  const [collapsed, toggleCollapsed] = useSidebarCollapse("soleur:sidebar.main.collapsed");

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

  // Cmd/Ctrl+B toggles sidebar on non-KB, non-Settings routes
  useEffect(() => {
    function handleToggleShortcut(e: KeyboardEvent) {
      if (!(e.metaKey || e.ctrlKey) || e.key !== "b") return;
      // Skip when typing in form elements
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      if ((e.target as HTMLElement)?.isContentEditable) return;
      // Only fire on routes that are NOT KB, Settings, or chat. On chat
      // pages the ConversationsRail owns Cmd/Ctrl+B for its own collapse.
      if (
        pathname.startsWith("/dashboard/kb") ||
        pathname.startsWith("/dashboard/settings") ||
        pathname.startsWith("/dashboard/chat")
      )
        return;
      e.preventDefault();
      toggleCollapsed();
    }
    document.addEventListener("keydown", handleToggleShortcut);
    return () => document.removeEventListener("keydown", handleToggleShortcut);
  }, [pathname, toggleCollapsed]);

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

  async function handleSignOut() {
    const supabase = createClient();
    // Sign-out tears down ALL channels by design — do not introduce
    // long-lived channels that must survive sign-out. supabase-js v2
    // exposes removeAllChannels() as a single Promise<('ok'|'timed
    // out'|'error')[]>, not an array of promises (the plan's pre-impl
    // sketch said Promise.all(supabase.removeAllChannels()), which the
    // TS overload rejects). Await the promise directly so phx_leave
    // sends while the JWT is still valid before signOut().
    await supabase.removeAllChannels();
    await supabase.auth.signOut();
    router.push("/login");
  }

  return (
    <TeamNamesProvider>
    <div className="flex h-dvh flex-col md:flex-row">
      {/* Mobile top bar — only visible below md breakpoint */}
      <div className="flex h-14 shrink-0 items-center border-b border-neutral-800 bg-neutral-900 px-4 safe-top md:hidden">
        <button
          onClick={() => setDrawerOpen(true)}
          aria-label="Open navigation"
          aria-expanded={drawerOpen}
          className="flex h-10 w-10 items-center justify-center rounded-lg text-neutral-400 hover:bg-neutral-800 hover:text-white"
        >
          <MenuIcon className="h-5 w-5" />
        </button>
        <span className="ml-3 text-lg font-semibold tracking-tight text-white">
          Soleur
        </span>
      </div>

      {/* Overlay backdrop — always rendered for fade transition */}
      <div
        className={`fixed inset-0 z-40 bg-black/50 transition-opacity duration-200 md:hidden ${
          drawerOpen ? "opacity-100" : "pointer-events-none opacity-0"
        }`}
        aria-hidden="true"
        onClick={() => setDrawerOpen(false)}
      />

      {/* Sidebar / mobile drawer — always rendered for CSS transitions */}
      <aside
        className={`
          fixed inset-y-0 left-0 z-50 flex w-64 flex-col border-r border-neutral-800 bg-neutral-900
          transition-transform duration-200 ease-out
          ${drawerOpen ? "translate-x-0" : "-translate-x-full"}
          md:relative md:z-auto md:translate-x-0
          md:transition-[width] md:duration-200 md:ease-out
          ${collapsed ? "md:w-14" : "md:w-56"}
        `}
      >
        {/* Brand + close/collapse buttons */}
        <div className={`flex items-center justify-between safe-top ${collapsed ? "px-2 py-5" : "px-5 py-5"}`}>
          <span className={`text-lg font-semibold tracking-tight text-white overflow-hidden whitespace-nowrap ${collapsed ? "md:hidden" : ""}`}>
            Soleur
          </span>
          <button
            onClick={() => setDrawerOpen(false)}
            aria-label="Close navigation"
            className="flex h-10 w-10 items-center justify-center rounded-lg text-neutral-400 hover:bg-neutral-800 hover:text-white md:hidden"
          >
            <XIcon className="h-5 w-5" />
          </button>
          {/* Collapse toggle — hidden on mobile, visible on md+ */}
          <button
            onClick={toggleCollapsed}
            aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
            title={collapsed ? "Expand sidebar (⌘B)" : "Collapse sidebar (⌘B)"}
            className="hidden md:flex h-6 w-6 items-center justify-center rounded text-neutral-400 hover:bg-neutral-800 hover:text-white"
          >
            {collapsed ? (
              <ChevronRightIcon className="h-4 w-4" />
            ) : (
              <ChevronLeftIcon className="h-4 w-4" />
            )}
          </button>
        </div>

        {/* Navigation */}
        <nav className={`flex-1 space-y-1 ${collapsed ? "px-1" : "px-3"}`}>
          {navItems.map((item) => {
            const active =
              item.href === "/dashboard"
                ? pathname === "/dashboard" || pathname.startsWith("/dashboard/chat")
                : pathname.startsWith(item.href);

            return (
              <Link
                key={item.href}
                href={item.href}
                title={collapsed ? item.label : undefined}
                className={`flex min-h-[44px] items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors ${
                  active
                    ? "bg-neutral-800 text-white"
                    : "text-neutral-400 hover:bg-neutral-800/50 hover:text-neutral-200"
                } ${collapsed ? "md:justify-center md:gap-0 md:px-0" : ""}`}
              >
                <item.icon className="h-4 w-4 shrink-0" />
                <span className={`overflow-hidden whitespace-nowrap ${collapsed ? "md:hidden" : ""}`}>
                  {item.label}
                </span>
              </Link>
            );
          })}
        </nav>

        {/* Recent conversations — mobile drawer only. The chat segment
            layout already renders the rail on md+; here we surface the same
            row markup inside the drawer so phone users can switch threads
            without leaving the drawer. */}
        <div
          data-testid="conversations-rail-drawer"
          className="flex min-h-0 flex-1 flex-col border-t border-neutral-800 md:hidden"
        >
          <ConversationsRail />
        </div>

        {/* Footer links */}
        <div className={`border-t border-neutral-800 safe-bottom ${collapsed ? "p-1" : "p-3"}`}>
          {userEmail && !collapsed && (
            <p
              className="truncate px-3 py-1 text-xs text-neutral-500"
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
            className={`flex min-h-[44px] w-full items-center gap-3 rounded-lg px-3 py-2 text-sm text-neutral-400 transition-colors hover:bg-neutral-800/50 hover:text-neutral-200 ${collapsed ? "md:justify-center md:gap-0 md:px-0" : ""}`}
          >
            <StatusIcon className="h-4 w-4 shrink-0" />
            <span className={`overflow-hidden whitespace-nowrap ${collapsed ? "md:hidden" : ""}`}>Status</span>
          </a>
          <button
            onClick={handleSignOut}
            title={collapsed ? "Sign out" : undefined}
            className={`flex min-h-[44px] w-full items-center gap-3 rounded-lg px-3 py-2 text-sm text-neutral-400 transition-colors hover:bg-neutral-800/50 hover:text-neutral-200 ${collapsed ? "md:justify-center md:gap-0 md:px-0" : ""}`}
          >
            <LogOutIcon className="h-4 w-4 shrink-0" />
            <span className={`overflow-hidden whitespace-nowrap ${collapsed ? "md:hidden" : ""}`}>Sign out</span>
          </button>
        </div>
      </aside>

      {/* Main content — inert when drawer is open for focus trapping */}
      <main
        className="flex-1 overflow-y-auto bg-neutral-950"
        inert={drawerOpen || undefined}
      >
        {/* Payment banners */}
        {subscriptionStatus === "unpaid" && (
          <div className="border-b border-red-800/50 bg-red-950/30 px-4 py-3">
            <div className="mx-auto flex max-w-4xl items-center justify-between gap-3">
              <p className="text-sm text-neutral-200">
                <span className="font-medium text-red-400">Your subscription is unpaid.</span>{" "}
                Your account is in read-only mode.
              </p>
              <a
                href="/dashboard/settings"
                className="shrink-0 rounded-lg bg-red-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-red-500"
              >
                Resolve Payment
              </a>
            </div>
          </div>
        )}
        <PaymentWarningBanner subscriptionStatus={subscriptionStatus} />
        {children}
      </main>
    </div>
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

function ChevronLeftIcon({ className }: { className?: string }) {
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
        d="M15.75 19.5 8.25 12l7.5-7.5"
      />
    </svg>
  );
}

function ChevronRightIcon({ className }: { className?: string }) {
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
        d="m8.25 4.5 7.5 7.5-7.5 7.5"
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
