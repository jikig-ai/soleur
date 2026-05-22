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

// Internal — exposed for the hook in a sibling file.
export function __useFlagContext(): FlagMap {
  const ctx = useContext(FeatureFlagContext);
  if (!ctx) {
    throw new Error(
      "useFeatureFlag must be used inside <FeatureFlagProvider> (wired in app/layout.tsx)",
    );
  }
  return ctx;
}
