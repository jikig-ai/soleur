"use client";

import type { FlagName } from "@/lib/feature-flags/server";
import { __useFlagContext } from "./provider";

export function useFeatureFlag(name: FlagName): boolean {
  return __useFlagContext()[name];
}
