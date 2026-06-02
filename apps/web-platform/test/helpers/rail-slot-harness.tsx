import { useState } from "react";
import { RailSlotProvider } from "@/components/dashboard/rail-slot";

/**
 * Test harness for components that portal their secondary nav into the single
 * nav rail's slot (ADR-047). In production the slot node is mounted by
 * (dashboard)/layout.tsx; in isolated component tests there is no layout, so
 * this provides a real DOM slot node (wrapped in a testid) that
 * RailSlotPortal can target. Portaled content is queryable via
 * `within(screen.getByTestId("rail-slot-harness"))` or plain `screen.*`.
 */
export function RailSlotHarness({ children }: { children: React.ReactNode }) {
  const [slot, setSlot] = useState<HTMLElement | null>(null);
  return (
    <RailSlotProvider value={slot}>
      <div data-testid="rail-slot-harness" ref={setSlot} />
      {children}
    </RailSlotProvider>
  );
}
