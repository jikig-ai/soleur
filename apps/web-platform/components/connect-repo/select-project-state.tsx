"use client";

import { useState } from "react";

import { ArrowLeftIcon, SearchIcon, SpinnerIcon, ChevronDownIcon, RefreshIcon } from "@/components/icons";
import { Badge } from "@/components/ui/badge";
import { GoldButton } from "@/components/ui/gold-button";
import { relativeTime } from "@/lib/relative-time";
import { serif } from "./fonts";
import type { Repo } from "./types";

interface SelectProjectStateProps {
  repos: Repo[];
  loading: boolean;
  onSelect: (repo: Repo) => void;
  onBack: () => void;
  onRefresh?: () => void;
}

export function SelectProjectState({ repos, loading, onSelect, onBack, onRefresh }: SelectProjectStateProps) {
  const [selected, setSelected] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const [showAccess, setShowAccess] = useState(false);
  const perPage = 8;

  const filtered = repos.filter(
    (r) =>
      r.name.toLowerCase().includes(search.toLowerCase()) ||
      (r.description ?? "").toLowerCase().includes(search.toLowerCase()),
  );
  const totalPages = Math.max(1, Math.ceil(filtered.length / perPage));
  const paginated = filtered.slice((page - 1) * perPage, page * perPage);

  function handleConnect() {
    const repo = repos.find((r) => r.fullName === selected);
    if (repo) onSelect(repo);
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={onBack}
          className="flex h-8 w-8 items-center justify-center rounded-lg border border-soleur-border-default text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
        >
          <ArrowLeftIcon className="h-4 w-4" />
        </button>
        <Badge>CONNECT PROJECT</Badge>
        {onRefresh && (
          <button
            type="button"
            onClick={onRefresh}
            className="flex h-8 w-8 items-center justify-center rounded-lg border border-soleur-border-default text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
            aria-label="Refresh"
          >
            <RefreshIcon className="h-4 w-4" />
          </button>
        )}
      </div>

      <div className="space-y-2">
        <h1 className={`${serif.className} text-3xl font-semibold`}>
          Select a Project
        </h1>
        <p className="text-sm text-soleur-text-secondary">
          Choose which project your AI team should work on. You can change this
          later from Settings.
        </p>
      </div>

      {/* Search */}
      <div className="relative">
        <SearchIcon className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-soleur-text-muted" />
        <input
          type="text"
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setPage(1);
          }}
          placeholder="Search projects..."
          className="w-full rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 py-2.5 pl-10 pr-4 text-sm placeholder:text-soleur-text-muted focus:border-soleur-text-muted focus:outline-none"
        />
      </div>

      {/* Repo list */}
      {loading ? (
        <div className="flex items-center justify-center py-12">
          <SpinnerIcon className="h-6 w-6 text-soleur-accent-gold-fg/70" />
        </div>
      ) : (
        <div className="space-y-1">
          {paginated.map((repo) => (
            <button
              key={repo.fullName}
              type="button"
              onClick={() => setSelected(repo.fullName)}
              className={`flex w-full items-center justify-between rounded-lg border px-4 py-3 text-left transition-colors ${
                selected === repo.fullName
                  ? "border-soleur-border-emphasized/40 bg-soleur-accent-gold-fg/5"
                  : "border-soleur-border-default bg-soleur-bg-surface-1/30 hover:bg-soleur-bg-surface-1/60"
              }`}
            >
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium text-soleur-text-primary">
                    {repo.name}
                  </span>
                  <span
                    className={`rounded px-1.5 py-0.5 text-[10px] font-medium uppercase ${
                      repo.private
                        ? "bg-soleur-bg-surface-2 text-soleur-text-secondary"
                        : "bg-emerald-950 text-emerald-400"
                    }`}
                  >
                    {repo.private ? "Private" : "Public"}
                  </span>
                </div>
                {repo.description && (
                  <p className="mt-0.5 truncate text-xs text-soleur-text-muted">
                    {repo.description}
                  </p>
                )}
              </div>
              <span className="shrink-0 text-xs text-soleur-text-secondary">
                Updated {relativeTime(repo.updatedAt)}
              </span>
            </button>
          ))}
        </div>
      )}

      {/* Pagination */}
      {!loading && totalPages > 1 && (
        <div className="flex items-center justify-between text-xs text-soleur-text-muted">
          <button
            type="button"
            onClick={() => setPage((p) => Math.max(1, p - 1))}
            disabled={page === 1}
            className="rounded px-2 py-1 hover:bg-soleur-bg-surface-2 disabled:opacity-30"
          >
            Previous
          </button>
          <span>
            Page {page} of {totalPages}
          </span>
          <button
            type="button"
            onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
            disabled={page === totalPages}
            className="rounded px-2 py-1 hover:bg-soleur-bg-surface-2 disabled:opacity-30"
          >
            Next
          </button>
        </div>
      )}

      {/* Connect CTA */}
      <div className="flex items-center gap-3">
        <GoldButton onClick={handleConnect} disabled={!selected}>
          Connect This Repository
        </GoldButton>
      </div>

      {/* Expandable: access info */}
      <div className="border-t border-soleur-border-default pt-4">
        <button
          type="button"
          onClick={() => setShowAccess((v) => !v)}
          className="flex items-center gap-2 text-sm text-soleur-text-secondary transition-colors hover:text-soleur-text-primary"
        >
          <ChevronDownIcon
            className={`h-4 w-4 transition-transform ${showAccess ? "rotate-180" : ""}`}
          />
          What can the GitHub App access?
        </button>
        {showAccess && (
          <div className="mt-3 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1/50 p-4 text-xs text-soleur-text-muted">
            <p>
              The Soleur GitHub App can read and write code in repositories you
              explicitly grant access to. It cannot access other repositories,
              your personal settings, billing information, or any other GitHub
              data. You can modify or revoke access at any time from your GitHub
              settings.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
