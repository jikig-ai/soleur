"use client";

// Releases feed surface (#5958). Client component rendered inside a <Suspense>
// by the server page at app/(dashboard)/dashboard/releases. Fetches
// /api/dashboard/releases (web-v* GitHub Releases, cleaned server-side, newest
// first) and renders reverse-chronological cards. State handling mirrors
// inbox-surface (ADR-067): skeleton gates on `!data`, RefreshShimmer on warm
// revalidation, StaleRefreshBar when a background refresh fails while stale data
// is shown, ErrorCard only on the cold (`!data && error`) failure.

import { useCallback } from "react";
import useSWR from "swr";
import { ErrorCard } from "@/components/ui/error-card";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { RefreshShimmer } from "@/components/ui/refresh-shimmer";
import { StaleRefreshBar } from "@/components/ui/stale-refresh-bar";
import { swrKeys } from "@/lib/swr-config";
import type { ReleaseCard } from "@/server/release-notes";

export async function fetchReleases(): Promise<ReleaseCard[]> {
  const res = await fetch("/api/dashboard/releases");
  if (!res.ok) throw new Error(`releases ${res.status}`);
  const body = (await res.json()) as { releases: ReleaseCard[] };
  return body.releases ?? [];
}

function formatDate(iso: string): string {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return iso;
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  }).format(new Date(t));
}

export function ReleasesSurface() {
  const {
    data: releases,
    error,
    isValidating,
    mutate,
  } = useSWR(swrKeys.releasesList(), fetchReleases);

  const refetch = useCallback(() => {
    void mutate();
  }, [mutate]);

  // Cold failure (no data yet) — full error surface.
  if (error && releases === undefined) {
    return (
      <ErrorCard
        title="Couldn't load releases"
        message="We're on it — please try again in a moment."
        onRetry={refetch}
      />
    );
  }

  // First load — skeleton (never re-shown on background revalidation).
  if (releases === undefined) {
    return (
      <div data-testid="releases-skeleton" className="space-y-4">
        {[0, 1, 2].map((i) => (
          <div
            key={i}
            className="animate-pulse rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-5"
          >
            <div className="mb-3 h-4 w-40 rounded bg-soleur-bg-surface-2" />
            <div className="mb-2 h-3 w-full rounded bg-soleur-bg-surface-2" />
            <div className="h-3 w-2/3 rounded bg-soleur-bg-surface-2" />
          </div>
        ))}
      </div>
    );
  }

  if (releases.length === 0) {
    return (
      <p className="py-8 text-sm text-soleur-text-secondary">
        No releases yet — when we ship an update to Soleur, it&apos;ll show up here.
      </p>
    );
  }

  return (
    <div>
      {/* Ambient shimmer while revalidating a warm cache hit (past the
          `releases === undefined` skeleton return, so data is always defined). */}
      <RefreshShimmer active={isValidating} />
      {/* Stale-failure affordance: a background refresh failed but we still have
          the last good feed — keep it, offer a retry (spec-flow Gap 2). */}
      {error && <StaleRefreshBar onRetry={refetch} />}

      <ul className="space-y-4">
        {releases.map((r, i) => (
          <li
            key={r.tag}
            className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-5"
          >
            <div className="mb-2 flex items-baseline justify-between gap-3">
              <div className="flex items-center gap-2">
                <span className="font-mono text-sm text-soleur-text-primary">
                  {r.tag}
                </span>
                {i === 0 && (
                  <span className="rounded-full bg-amber-400/15 px-2 py-0.5 text-xs font-medium text-amber-400">
                    Latest
                  </span>
                )}
              </div>
              <time
                dateTime={r.publishedAt}
                className="shrink-0 text-xs text-soleur-text-secondary"
              >
                {formatDate(r.publishedAt)}
              </time>
            </div>
            {r.title && r.title !== r.tag && (
              <h2 className="mb-2 text-base font-medium text-soleur-text-primary">
                {r.title}
              </h2>
            )}
            <div className="text-sm text-soleur-text-secondary">
              <MarkdownRenderer content={r.bodyMarkdown} />
            </div>
            {r.htmlUrl && (
              <a
                href={r.htmlUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="mt-3 inline-block text-xs text-soleur-text-secondary underline-offset-2 hover:text-soleur-text-primary hover:underline"
              >
                View on GitHub
              </a>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
