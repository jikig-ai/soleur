"use client";

// Releases left-nav "new version" badge (feat-releases-nav-badge). The Releases
// feed is Soleur's own web-v* GitHub releases (user-independent), so there is no
// per-account read state — "new version published" is a per-DEVICE signal: the
// newest tag differs from the last one this browser looked at (see
// lib/releases-seen). Reuses the Releases surface's shared SWR key + fetcher so
// the badge and the list are fed by ONE request (free dedup, ADR-067) and can
// never disagree about what "latest" is.
//
// Honesty contract (mirrors inbox-nav-badge): a loading/errored fetch NEVER
// renders a false signal — COLD (undefined data) omits entirely. States:
//   - no local record yet → SEED silently to latest, no dot (first-load contract)
//   - latest tag !== last seen → a calm gold dot ("New version published")
//   - else → omit
// A calm dot (no number) matches the read-only informational nature of the tab;
// releases are FYI, never an action count.

import { useEffect } from "react";
import useSWR from "swr";
import { fetchReleases } from "@/components/releases/releases-surface";
import { swrKeys } from "@/lib/swr-config";
import { warnSilentFallback } from "@/lib/client-observability";
import { NavDotBadge } from "@/components/dashboard/nav-count-badge";
import {
  isNewerReleaseTag,
  seedReleasesSeenIfEmpty,
  useLastSeenReleaseTag,
} from "@/lib/releases-seen";
import type { ReleaseCard } from "@/server/release-notes";

export function ReleasesNavBadge({ collapsed }: { collapsed: boolean }) {
  const { data } = useSWR<ReleaseCard[]>(
    swrKeys.releasesList(),
    fetchReleases,
    {
      onError: (err) =>
        warnSilentFallback(err, {
          feature: "releases-nav-badge",
          op: "count-fetch",
        }),
    },
  );
  const lastSeen = useLastSeenReleaseTag();

  // The server returns newest-first, so index 0 is the true latest.
  const latestTag = data?.[0]?.tag;

  // First-load contract: no record on this device → seed silently to the current
  // latest so the dot only ever fires on a version published AFTER now. Runs as
  // an effect (not during render); the write-time-guarded seed can never clobber
  // an existing record, so a transient null snapshot can't suppress a real dot.
  useEffect(() => {
    if (latestTag && lastSeen === null) seedReleasesSeenIfEmpty(latestTag);
  }, [latestTag, lastSeen]);

  // COLD (undefined data, incl. a hard-failed first load): omit — never a false dot.
  // No local record yet: seeding above suppresses the dot until the next publish.
  if (!latestTag || lastSeen === null) return null;

  // Only a STRICTLY newer version paints the dot — inequality alone would fire on
  // a rollback (a yanked release regressing the newest tag), which isn't "new".
  if (!isNewerReleaseTag(latestTag, lastSeen)) return null;

  // A newer version shipped → a calm gold dot (no number), reusing the shared
  // NavDotBadge so it reads identically to the inbox FYI dot.
  return (
    <NavDotBadge
      collapsed={collapsed}
      testId="releases-nav-badge-dot"
      label="New version published"
    />
  );
}
