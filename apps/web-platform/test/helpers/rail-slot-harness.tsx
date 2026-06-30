import { useState } from "react";
import { SWRConfig } from "swr";
import {
  RailSlotProvider,
  RailCollapsedProvider,
} from "@/components/dashboard/rail-slot";

/**
 * Test harness for components that portal their secondary nav into the single
 * nav rail's slot (ADR-047). In production the slot node is mounted by
 * (dashboard)/layout.tsx; in isolated component tests there is no layout, so
 * this provides a real DOM slot node (wrapped in a testid) that
 * RailSlotPortal can target. Portaled content is queryable via
 * `within(screen.getByTestId("rail-slot-harness"))` or plain `screen.*`.
 *
 * `collapsed` mirrors the layout's `RailCollapsedProvider` so collapsed-state
 * tests can drive each shell's `useRailCollapsed()` render-conditional. Defaults
 * to `false` (expanded) so existing tests are unaffected.
 */
export function RailSlotHarness({
  children,
  collapsed = false,
}: {
  children: React.ReactNode;
  collapsed?: boolean;
}) {
  const [slot, setSlot] = useState<HTMLElement | null>(null);
  return (
    // ADR-067: in production the dashboard layout mounts <SWRConfig>; isolated
    // KB/rail tests render shells without that layout, so provide a FRESH SWR
    // cache per render here (the production default cache is a module singleton
    // and would leak cached trees/thread-info across test cases). dedupingInterval
    // 0 + shouldRetryOnError false keep fetch-count assertions deterministic.
    <SWRConfig
      value={{
        provider: () => new Map(),
        dedupingInterval: 0,
        revalidateOnReconnect: false,
        shouldRetryOnError: false,
      }}
    >
      <RailSlotProvider value={slot}>
        <RailCollapsedProvider value={collapsed}>
          <div data-testid="rail-slot-harness" ref={setSlot} />
          {children}
        </RailCollapsedProvider>
      </RailSlotProvider>
    </SWRConfig>
  );
}
