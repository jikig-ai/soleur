"use client";

// Releases feed surface (#5958; filters/sort/search follow-up). Client component
// rendered inside a <Suspense> by the server page at
// app/(dashboard)/dashboard/releases. Fetches /api/dashboard/releases (web-v*
// GitHub Releases, cleaned server-side, newest first) and renders
// reverse-chronological cards with client-side search, sort, and a release-type
// filter (the full list is already in memory via SWR). State handling mirrors
// inbox-surface (ADR-067): skeleton gates on `!data`, RefreshShimmer on warm
// revalidation, StaleRefreshBar when a background refresh fails while stale data
// is shown, ErrorCard only on the cold (`!data && error`) failure.

import { useCallback, useMemo, useState } from "react";
import useSWR from "swr";
import { ErrorCard } from "@/components/ui/error-card";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { RefreshShimmer } from "@/components/ui/refresh-shimmer";
import { StaleRefreshBar } from "@/components/ui/stale-refresh-bar";
import { swrKeys } from "@/lib/swr-config";
import type { ReleaseBump, ReleaseCard } from "@/server/release-notes";

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

type SortOrder = "newest" | "oldest";
type BumpFilter = "all" | Exclude<ReleaseBump, null>;

const SELECT_CLASS =
  "rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 px-2.5 py-1.5 text-sm text-soleur-text-primary focus:border-amber-400/50 focus:outline-none";

export function ReleasesSurface() {
  const {
    data: releases,
    error,
    isValidating,
    mutate,
  } = useSWR(swrKeys.releasesList(), fetchReleases);

  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<SortOrder>("newest");
  const [bumpFilter, setBumpFilter] = useState<BumpFilter>("all");

  const refetch = useCallback(() => {
    void mutate();
  }, [mutate]);

  // The server returns newest-first, so the true latest is index 0 — pin the
  // "Latest" badge to its tag so it stays correct under any sort/filter.
  const latestTag = releases?.[0]?.tag;

  const visible = useMemo(() => {
    const all = releases ?? [];
    const q = query.trim().toLowerCase();
    const filtered = all.filter((r) => {
      if (bumpFilter !== "all" && r.bump !== bumpFilter) return false;
      if (!q) return true;
      return (
        r.tag.toLowerCase().includes(q) ||
        r.title.toLowerCase().includes(q) ||
        r.bodyMarkdown.toLowerCase().includes(q)
      );
    });
    // Stable sort by publish time; `all` is already newest-first.
    return sort === "newest"
      ? filtered
      : [...filtered].sort(
          (a, b) => Date.parse(a.publishedAt) - Date.parse(b.publishedAt),
        );
  }, [releases, query, sort, bumpFilter]);

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

      {/* Controls: search + release-type filter + sort. */}
      <div className="mb-5 flex flex-wrap items-center gap-2">
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search releases…"
          aria-label="Search releases"
          className="min-w-[12rem] flex-1 rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-1.5 text-sm text-soleur-text-primary placeholder:text-soleur-text-muted focus:border-amber-400/50 focus:outline-none"
        />
        <select
          value={bumpFilter}
          onChange={(e) => setBumpFilter(e.target.value as BumpFilter)}
          aria-label="Filter by release type"
          className={SELECT_CLASS}
        >
          <option value="all">All releases</option>
          <option value="major">Major</option>
          <option value="minor">Minor</option>
          <option value="patch">Patch</option>
        </select>
        <select
          value={sort}
          onChange={(e) => setSort(e.target.value as SortOrder)}
          aria-label="Sort releases"
          className={SELECT_CLASS}
        >
          <option value="newest">Newest first</option>
          <option value="oldest">Oldest first</option>
        </select>
      </div>

      <p className="mb-3 text-xs text-soleur-text-muted">
        {visible.length === releases.length
          ? `${releases.length} release${releases.length === 1 ? "" : "s"}`
          : `${visible.length} of ${releases.length} releases`}
      </p>

      {visible.length === 0 ? (
        <div className="py-8 text-sm text-soleur-text-secondary">
          No releases match your search or filter.{" "}
          <button
            type="button"
            onClick={() => {
              setQuery("");
              setBumpFilter("all");
            }}
            className="text-soleur-text-primary underline underline-offset-2 hover:text-amber-400"
          >
            Clear
          </button>
        </div>
      ) : (
        <ul className="space-y-4">
          {visible.map((r) => (
            <li
              key={r.tag}
              className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-5"
            >
              <div className="mb-2 flex items-baseline justify-between gap-3">
                <div className="flex items-center gap-2">
                  <span className="font-mono text-sm text-soleur-text-primary">
                    {r.tag}
                  </span>
                  {r.tag === latestTag && (
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
      )}
    </div>
  );
}
