"use client";

import { useEffect, useState } from "react";

export function ReviewGateCard({
  gateId,
  question,
  options,
  header,
  descriptions,
  stepProgress,
  resolved,
  selectedOption,
  gateError,
  onSelect,
}: {
  gateId: string;
  question: string;
  options: string[];
  header?: string;
  descriptions?: Record<string, string | undefined>;
  stepProgress?: { current: number; total: number };
  resolved?: boolean;
  selectedOption?: string;
  gateError?: string;
  onSelect: (gateId: string, selection: string) => void;
}) {
  const [pending, setPending] = useState<string | null>(null);

  function handleSelect(option: string) {
    if (pending || resolved) return;
    setPending(option);
    onSelect(gateId, option);
  }

  useEffect(() => {
    if (gateError) setPending(null);
  }, [gateError]);

  if (resolved && selectedOption) {
    return (
      <div className="flex items-center gap-2 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1/50 px-4 py-2 text-sm text-soleur-text-secondary transition-all duration-300">
        <svg className="h-4 w-4 text-green-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <polyline points="20 6 9 17 4 12" />
        </svg>
        <span>Selected: <strong className="text-soleur-text-primary">{selectedOption}</strong></span>
      </div>
    );
  }

  return (
    <div role="group" aria-label={question} aria-busy={pending !== null} className="rounded-xl border border-amber-800/50 bg-amber-950/30 p-5">
      {stepProgress && stepProgress.total > 0 && (() => {
        const pct = Math.round((stepProgress.current / stepProgress.total) * 100);
        return (
          <div className="mb-3">
            <div className="mb-1 flex items-center justify-between text-xs text-amber-300">
              <span>Step {stepProgress.current} of {stepProgress.total}</span>
              <span className="text-amber-400/60">{pct}%</span>
            </div>
            <div className="h-1.5 overflow-hidden rounded-full bg-amber-900/40">
              <div
                className="h-full rounded-full bg-amber-500 transition-all duration-500"
                style={{ width: `${pct}%` }}
              />
            </div>
          </div>
        );
      })()}
      {header && (
        <span className="mb-2 inline-block rounded-md bg-amber-900/50 px-2 py-0.5 text-xs font-medium text-amber-300">
          {header}
        </span>
      )}
      <div className="mb-1 flex items-start gap-2">
        <svg className="mt-0.5 h-4 w-4 shrink-0 text-amber-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="10" />
          <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3" />
          <line x1="12" y1="17" x2="12.01" y2="17" />
        </svg>
        <p className="text-base font-medium text-amber-200">{question}</p>
      </div>
      <div className="mt-3 flex flex-wrap gap-2">
        {options.map((option) => (
          <button
            key={option}
            onClick={() => handleSelect(option)}
            disabled={pending !== null}
            className={`flex flex-col items-start rounded-lg border px-4 py-2 text-sm transition-colors ${
              pending === option
                ? "border-amber-500 bg-amber-900/50 text-amber-100"
                : pending !== null
                  ? "border-soleur-border-default text-soleur-text-muted opacity-50"
                  : "border-soleur-border-default text-soleur-text-secondary hover:border-amber-600 hover:text-amber-200"
            }`}
          >
            <span>{option}</span>
            {descriptions?.[option] && (
              <span className="mt-0.5 text-xs text-soleur-text-secondary">{descriptions[option]}</span>
            )}
          </button>
        ))}
      </div>
      {gateError && (
        <p role="alert" className="mt-2 text-sm text-red-400">{gateError}</p>
      )}
    </div>
  );
}
