"use client";

// feat-ui-action-feedback (implementation-brief §1 desktop / §2 mobile PWA) —
// the ONE mount of the route-pending bar, mounted bare in root
// `app/layout.tsx` (never also in (dashboard)/layout.tsx — spec-flow C2).
// The useSearchParams consumer is Suspense-wrapped here internally, so the
// mount site needs no wrapper.
//
// §2: the fixed bar pins to `env(safe-area-inset-top, 0px)` so it renders
// below the iOS notch/status strip; on non-notch contexts it resolves 0 —
// one rule covers both frames, no breakpoint branching.

import { Suspense, useEffect, useSyncExternalStore } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import {
  getNavLastLocation,
  getNavPendingServerSnapshot,
  getNavPendingSnapshot,
  noteNavLocation,
  startNavPending,
  stopNavPending,
  subscribeNavPending,
} from "@/lib/nav-pending-store";

function NavPendingBar() {
  const { visible } = useSyncExternalStore(
    subscribeNavPending,
    getNavPendingSnapshot,
    getNavPendingServerSnapshot,
  );
  return (
    <>
      {/* §6: "Loading" is announced only when the bar becomes visible — never
          at start(), or warm-cache navs spam a status with no visible feedback
          (ux #5). The region persists; only its text toggles. */}
      <div role="status" className="sr-only">
        {visible ? "Loading" : null}
      </div>
      {visible ? (
        <div
          aria-hidden="true"
          data-testid="nav-pending-bar"
          className="pointer-events-none fixed inset-x-0 top-[env(safe-area-inset-top,0px)] z-50 h-[2px] overflow-hidden"
        >
          <div className="h-full w-1/3 animate-[refresh-shimmer_1.1s_ease-in-out_infinite] bg-soleur-accent-gold-fg/80" />
        </div>
      ) : null}
    </>
  );
}

function NavPendingLocationWatcher() {
  const pathname = usePathname();
  const searchParams = useSearchParams();

  // Completion watcher (§1 step 4): a pathname OR searchParams delta commits
  // the episode — same-path query navs like `workstream?issue=` count. Also
  // keeps the store's last-location current for the popstate gate below.
  useEffect(() => {
    noteNavLocation();
    stopNavPending();
  }, [pathname, searchParams]);

  // History Back/Forward (§1 popstate edge): fire only when the post-pop
  // location's pathname+search differs from the last committed one — the
  // browser updates location before popstate, so the ref still holds the old
  // doc. Hash-only history entries (`#main-content` skip link) never fire.
  useEffect(() => {
    const onPopState = () => {
      const current = window.location.pathname + window.location.search;
      if (current !== getNavLastLocation()) startNavPending("popstate");
    };
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  }, []);

  return null;
}

export function NavPendingIsland() {
  return (
    <>
      <NavPendingBar />
      <Suspense fallback={null}>
        <NavPendingLocationWatcher />
      </Suspense>
    </>
  );
}
