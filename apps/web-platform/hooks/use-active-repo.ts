"use client";

import useSWR from "swr";
import { jsonFetcher, swrKeys } from "@/lib/swr-config";

// ADR-044 (#4543): the active-workspace repo, kept truthful by run-time
// revalidation (mount + window focus + the while-`cloning` poll), NOT a
// realtime subscription. The active-repo endpoint reads workspaces-only (never
// users.repo_url) and self-heals J5 (access revocation) by resetting the claim
// to the personal workspace; consumers surface that via the `fellBackToSolo`
// signal.
//
// Extracted from live-repo-badge.tsx so BOTH the workspace pill (via
// OrgSwitcherContainer, which renders the repo as a subtitle) AND LiveRepoBadge
// (which owns the J5 revocation interstitial) can read the same active-repo
// state WITHOUT a second component mount — the single-mount invariant
// (nav-single-mount.test.ts) tracks component imports, and a hook is outside
// its scope.
//
// #9178 mount-fetch contract (ADR-067 amendment): this rides the SHARED SWR
// key `swrKeys.workspaceActiveRepo()` — the same key useConversations,
// dashboard/page.tsx and conversations-nav-badge read — so SWR's per-key
// in-flight coalescing + dedupingInterval own dedup across EVERY consumer. The
// former module-level `inFlight` latch only joined raw-fetch callers and was
// blind to the SWR channel, so the same endpoint fired x3-4 per mount.
//
// Semantics preserved from the raw-fetch implementation:
// - keep-last-known on transient failure: jsonFetcher THROWS on non-2xx, so
//   SWR retains the last `data` and routes the failure to `error` (ignored
//   here — callers read `data` only).
// - mount fetch + focus revalidation: revalidateOnMount + the global
//   `revalidateOnFocus` in swrConfig replace the explicit focus listener.
// - #5394 cloning poll: `refreshInterval` re-evaluates on every data write, so
//   it polls every 2 s while repoStatus === "cloning" and self-stops on
//   ready/error/not_connected.

export interface ActiveRepo {
  workspaceId: string;
  repoUrl: string | null;
  repoName: string | null;
  repoStatus: string;
  fellBackToSolo: boolean;
}

export function useActiveRepo(): { data: ActiveRepo | null } {
  const { data } = useSWR<ActiveRepo>(
    swrKeys.workspaceActiveRepo(),
    jsonFetcher<ActiveRepo>,
    {
      refreshInterval: (latest) =>
        latest?.repoStatus === "cloning" ? 2_000 : 0,
    },
  );
  return { data: data ?? null };
}
