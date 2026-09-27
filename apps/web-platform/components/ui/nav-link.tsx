"use client";

// feat-ui-action-feedback Layer 2 trigger (a) — `next/link` wrapper. Same
// props; `onNavigate` (SPA same-origin navigations only — modifier-key clicks,
// external URLs, and download links never fire it per the Link contract)
// starts the pending episode unless the target resolves to the current
// document — an active-rail re-click would otherwise strand the bar until the
// stall timeout (kieran #2). A caller-supplied onNavigate still runs.

import Link from "next/link";
import { isSameDocTarget, startNavPending } from "@/lib/nav-pending-store";

export type NavLinkProps = React.ComponentProps<typeof Link>;

export function NavLink({ onNavigate, ...props }: NavLinkProps) {
  return (
    <Link
      {...props}
      onNavigate={(event) => {
        // Consumer runs first AND vetoes count: Next's NavigateEvent exposes
        // only preventDefault() (no defaultPrevented getter), so wrap it —
        // a vetoed nav never commits and must not arm a phantom bar that
        // strands to the 30s stall.
        let vetoed = false;
        onNavigate?.({
          ...event,
          preventDefault() {
            vetoed = true;
            event.preventDefault();
          },
        });
        if (!vetoed && !isSameDocTarget(props.href)) startNavPending("link");
      }}
    />
  );
}
