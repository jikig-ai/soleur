"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import Link from "next/link";
import type { SearchResult, SearchMatch } from "@/server/kb-reader";

export function SearchOverlay() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(null);

  const search = useCallback(async (q: string) => {
    if (!q.trim()) {
      setResults([]);
      setSearched(false);
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const res = await fetch(`/api/kb/search?q=${encodeURIComponent(q)}`);
      if (res.ok) {
        const data = await res.json();
        setResults(data.results ?? []);
      }
    } catch {
      // Silently fail — search is best-effort
    } finally {
      setLoading(false);
      setSearched(true);
    }
  }, []);

  useEffect(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    if (!query.trim()) {
      setResults([]);
      setSearched(false);
      return;
    }
    debounceRef.current = setTimeout(() => search(query), 300);
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, [query, search]);

  return (
    <div>
      <div className="relative">
        <svg
          width="14"
          height="14"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          className="absolute left-3 top-1/2 -translate-y-1/2 text-neutral-500"
        >
          <circle cx="11" cy="11" r="8" />
          <path d="m21 21-4.3-4.3" strokeLinecap="round" />
        </svg>
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search files..."
          className="w-full rounded-lg border border-neutral-700 bg-neutral-900 py-2 pl-9 pr-3 text-sm text-neutral-200 placeholder-neutral-500 outline-none transition-colors focus:border-amber-500/50"
        />
      </div>

      {/* Search results */}
      {searched && query.trim() && (
        <div className="mt-3">
          <p className="mb-2 text-xs text-neutral-500">
            {results.length} result{results.length !== 1 ? "s" : ""} for &ldquo;{query}&rdquo;
          </p>

          {results.length === 0 ? (
            <p className="py-4 text-center text-sm text-neutral-500">
              No results for &ldquo;{query}&rdquo;
            </p>
          ) : (
            <div className="space-y-2">
              {results.map((result) => (
                <SearchResultCard key={result.path} result={result} />
              ))}
            </div>
          )}
        </div>
      )}

      {loading && query.trim() && (
        <div className="mt-3 flex justify-center py-4">
          <span className="h-4 w-4 animate-spin rounded-full border-2 border-neutral-600 border-t-amber-500" />
        </div>
      )}
    </div>
  );
}

function SearchResultCard({ result }: { result: SearchResult }) {
  const snippets = result.matches.slice(0, 3);

  return (
    <Link
      href={`/dashboard/kb/${result.path}`}
      className="block rounded-lg border border-neutral-800 p-3 transition-colors hover:border-neutral-700 hover:bg-neutral-900/50"
    >
      <div className="mb-1 flex items-center gap-1.5">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="shrink-0 text-amber-500/70">
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z" strokeLinecap="round" strokeLinejoin="round" />
          <path d="M14 2v6h6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        <span className="text-sm font-medium text-amber-400">{result.path}</span>
      </div>
      <div className="space-y-1">
        {snippets.map((match, i) => (
          <SnippetLine key={i} match={match} kind={result.kind} />
        ))}
      </div>
    </Link>
  );
}

function SnippetLine({
  match,
  kind,
}: {
  match: SearchMatch;
  kind: SearchResult["kind"];
}) {
  const [start, end] = match.highlight;
  const before = match.text.substring(0, start);
  const highlighted = match.text.substring(start, end);
  const after = match.text.substring(end);

  return (
    <div className="flex items-start gap-2 text-xs">
      <span className="shrink-0 text-neutral-600">
        {kind === "filename" ? "Filename" : `Line ${match.line}`}
      </span>
      <p className="truncate text-neutral-400">
        {before}
        <mark className="rounded bg-amber-500/20 px-0.5 text-amber-300">{highlighted}</mark>
        {after}
      </p>
    </div>
  );
}
