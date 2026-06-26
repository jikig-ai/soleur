"use client";

// The Workstream filter bar — four composable filter dimensions (Priority,
// Status, Assignee, Domain) that narrow the already-fetched issue set
// client-side. Priority/Assignee/Domain are multi-select checkbox menus
// (OR-within); Status is a tri-state radio (All/Open/Closed). Options are
// derived from the FULL loaded set by the board (deriveFilterOptions); a
// dimension with zero options is hidden (Status always shows — fixed control).
//
// Chrome matches the existing board (rounded, soleur tokens, gold active state)
// per operator design sign-off 2026-06-26 (mock 04/05) — NOT square corners, so
// the new controls read as one cohesive surface with the rounded columns/cards.

import { useEffect, useRef, useState } from "react";
import {
  priorityLabel,
  type FilterOptions,
  type WorkstreamFilters,
  type WorkstreamPriority,
  type WorkstreamRole,
} from "@/lib/workstream";
import { ChevronDownIcon } from "@/components/icons";

/** Toggle a value in an immutable Set, returning a new Set. */
function toggleInSet<T>(set: Set<T>, value: T): Set<T> {
  const next = new Set(set);
  if (next.has(value)) next.delete(value);
  else next.add(value);
  return next;
}

/** A dropdown wrapper: a labelled trigger button with an optional active-count
 *  badge, opening a popover that closes on outside-click + Escape. */
function Dropdown({
  label,
  activeCount,
  children,
}: {
  label: string;
  activeCount: number;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function onDown(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const active = activeCount > 0;
  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        className={`flex items-center gap-1.5 rounded-lg border px-3 py-2 text-sm font-medium transition-colors ${
          active
            ? "border-soleur-accent-gold-fill/50 bg-soleur-accent-gold-fill/10 text-soleur-text-primary"
            : "border-soleur-border-default bg-soleur-bg-surface-1 text-soleur-text-secondary hover:text-soleur-text-primary"
        }`}
      >
        <span>{label}</span>
        {active ? (
          <span className="flex h-4 min-w-4 items-center justify-center rounded-full bg-soleur-accent-gold-fill/20 px-1 text-[11px] font-semibold text-soleur-accent-gold-text">
            {activeCount}
          </span>
        ) : null}
        <ChevronDownIcon
          className={`h-3.5 w-3.5 transition-transform ${open ? "rotate-180" : ""} ${
            active ? "text-soleur-accent-gold-text" : "text-soleur-text-tertiary"
          }`}
        />
      </button>
      {open ? (
        <div className="absolute left-0 top-full z-20 mt-1 min-w-44 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-1 shadow-lg shadow-black/30">
          {children}
        </div>
      ) : null}
    </div>
  );
}

/** A multi-select checkbox row. */
function CheckRow({
  label,
  checked,
  onToggle,
}: {
  label: string;
  checked: boolean;
  onToggle: () => void;
}) {
  return (
    <label className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary">
      <input
        type="checkbox"
        checked={checked}
        onChange={onToggle}
        className="h-3.5 w-3.5 accent-soleur-accent-gold-fill"
      />
      <span>{label}</span>
    </label>
  );
}

export function FilterBar({
  options,
  filters,
  onChange,
}: {
  options: FilterOptions;
  filters: WorkstreamFilters;
  onChange: (next: WorkstreamFilters) => void;
}) {
  const assigneeActive =
    filters.roles.size + filters.users.size + (filters.unassigned ? 1 : 0);

  return (
    <div className="flex flex-wrap items-center gap-2">
      {/* Priority */}
      {options.priorities.length > 0 ? (
        <Dropdown label="Priority" activeCount={filters.priorities.size}>
          {options.priorities.map((p: WorkstreamPriority) => (
            <CheckRow
              key={p}
              label={priorityLabel(p)}
              checked={filters.priorities.has(p)}
              onToggle={() =>
                onChange({
                  ...filters,
                  priorities: toggleInSet(filters.priorities, p),
                })
              }
            />
          ))}
        </Dropdown>
      ) : null}

      {/* Status — fixed tri-state radio (always shown) */}
      <Dropdown
        label={filters.status === "all" ? "Status" : `Status: ${filters.status === "open" ? "Open" : "Closed"}`}
        activeCount={filters.status === "all" ? 0 : 1}
      >
        <div role="radiogroup" aria-label="Status">
          {(["all", "open", "closed"] as const).map((s) => (
            <label
              key={s}
              className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
            >
              <input
                type="radio"
                name="workstream-status"
                checked={filters.status === s}
                onChange={() => onChange({ ...filters, status: s })}
                className="h-3.5 w-3.5 accent-soleur-accent-gold-fill"
              />
              <span>{s === "all" ? "All" : s === "open" ? "Open" : "Closed"}</span>
            </label>
          ))}
        </div>
      </Dropdown>

      {/* Assignee — roles, then people, then Unassigned (combined-OR) */}
      {options.roles.length > 0 ||
      options.users.length > 0 ||
      options.hasUnassigned ? (
        <Dropdown label="Assignee" activeCount={assigneeActive}>
          {options.roles.map((r: WorkstreamRole) => (
            <CheckRow
              key={`role-${r}`}
              label={r.toUpperCase()}
              checked={filters.roles.has(r)}
              onToggle={() =>
                onChange({ ...filters, roles: toggleInSet(filters.roles, r) })
              }
            />
          ))}
          {options.users.map((u: string) => (
            <CheckRow
              key={`user-${u}`}
              label={u}
              checked={filters.users.has(u)}
              onToggle={() =>
                onChange({ ...filters, users: toggleInSet(filters.users, u) })
              }
            />
          ))}
          {options.hasUnassigned ? (
            <CheckRow
              label="Unassigned"
              checked={filters.unassigned}
              onToggle={() =>
                onChange({ ...filters, unassigned: !filters.unassigned })
              }
            />
          ) : null}
        </Dropdown>
      ) : null}

      {/* Domain */}
      {options.domains.length > 0 ? (
        <Dropdown label="Domain" activeCount={filters.domains.size}>
          {options.domains.map((d: string) => (
            <CheckRow
              key={d}
              label={d.replace(/^domain\//, "")}
              checked={filters.domains.has(d)}
              onToggle={() =>
                onChange({ ...filters, domains: toggleInSet(filters.domains, d) })
              }
            />
          ))}
        </Dropdown>
      ) : null}
    </div>
  );
}
