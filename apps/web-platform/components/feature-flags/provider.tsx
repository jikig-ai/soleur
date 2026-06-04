"use client";

import { createContext, useContext } from "react";
import type { FlagName } from "@/lib/feature-flags/server";

type FlagMap = Record<FlagName, boolean>;

const FeatureFlagContext = createContext<FlagMap | null>(null);

export function FeatureFlagProvider({
  flags,
  children,
}: {
  flags: FlagMap;
  children: React.ReactNode;
}) {
  return (
    <FeatureFlagContext.Provider value={flags}>
      {children}
    </FeatureFlagContext.Provider>
  );
}

export function useFeatureFlag(name: FlagName): boolean {
  const ctx = useContext(FeatureFlagContext);
  if (!ctx) {
    throw new Error(
      "useFeatureFlag must be used inside <FeatureFlagProvider> (wired in app/layout.tsx)",
    );
  }
  return ctx[name];
}

/**
 * Non-throwing variant: returns `false` when no provider is mounted instead of
 * throwing. For components that legitimately render outside the provider (e.g.
 * the KB content page in provider-less test surfaces) and treat "no flag info"
 * as off.
 */
export function useOptionalFeatureFlag(name: FlagName): boolean {
  const ctx = useContext(FeatureFlagContext);
  return ctx ? ctx[name] : false;
}
