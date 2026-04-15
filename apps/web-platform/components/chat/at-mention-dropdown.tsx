"use client";

import { useState, useEffect, useCallback, useMemo } from "react";
import { ROUTABLE_DOMAIN_LEADERS } from "@/server/domain-leaders";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { LeaderAvatar } from "@/components/leader-avatar";

interface AtMentionDropdownProps {
  query: string;
  visible: boolean;
  onSelect: (leaderId: DomainLeaderId) => void;
  onDismiss: () => void;
  /** Custom names map from TeamNamesProvider (e.g., { cto: "Alex" }) */
  customNames?: Record<string, string>;
  /** Whether custom names are still loading from the API */
  loading?: boolean;
}

export function AtMentionDropdown({
  query,
  visible,
  onSelect,
  onDismiss,
  customNames = {},
  loading = false,
}: AtMentionDropdownProps) {
  const [activeIndex, setActiveIndex] = useState(0);

  const filtered = useMemo(() =>
    ROUTABLE_DOMAIN_LEADERS.filter((leader) => {
      if (!query) return true;
      const q = query.toLowerCase();
      const custom = customNames[leader.id]?.toLowerCase() ?? "";
      return (
        leader.id.includes(q) ||
        leader.name.toLowerCase().includes(q) ||
        leader.title.toLowerCase().includes(q) ||
        custom.includes(q)
      );
    }), [query, customNames]);

  // Reset active index when query or visibility changes
  useEffect(() => {
    setActiveIndex(0);
  }, [query, visible]);

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (!visible || filtered.length === 0) return;

      switch (e.key) {
        case "ArrowDown":
          e.preventDefault();
          setActiveIndex((prev) => (prev + 1) % filtered.length);
          break;
        case "ArrowUp":
          e.preventDefault();
          setActiveIndex((prev) => (prev - 1 + filtered.length) % filtered.length);
          break;
        case "Enter":
          e.preventDefault();
          onSelect(filtered[activeIndex].id);
          break;
        case "Escape":
          e.preventDefault();
          onDismiss();
          break;
      }
    },
    [visible, filtered, activeIndex, onSelect, onDismiss],
  );

  useEffect(() => {
    if (visible) {
      document.addEventListener("keydown", handleKeyDown);
      return () => document.removeEventListener("keydown", handleKeyDown);
    }
  }, [visible, handleKeyDown]);

  if (!visible) return null;

  return (
    <div
      role="listbox"
      aria-label="Leaders"
      className="absolute bottom-full left-0 z-50 mb-2 w-full max-w-md rounded-xl border border-neutral-700 bg-neutral-900 shadow-xl"
    >
      <div className="px-3 py-2 text-xs font-medium uppercase tracking-wider text-neutral-500">
        Leaders
      </div>
      {filtered.length === 0 ? (
        <div className="px-3 py-3 text-sm text-neutral-500">
          {loading && query ? "Loading team..." : "No matches"}
        </div>
      ) : (
        <ul className="max-h-64 overflow-y-auto pb-1">
          {filtered.map((leader, index) => (
            <li
              key={leader.id}
              role="option"
              aria-selected={index === activeIndex}
              onClick={() => onSelect(leader.id)}
              onMouseEnter={() => setActiveIndex(index)}
              className={`flex cursor-pointer items-center gap-3 px-3 py-2.5 transition-colors ${
                index === activeIndex ? "bg-neutral-800" : ""
              }`}
            >
              <LeaderAvatar leaderId={leader.id} size="md" />
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-semibold text-white">
                    {customNames[leader.id]
                      ? `${customNames[leader.id]} (${leader.name})`
                      : leader.name}
                  </span>
                </div>
                <p className="truncate text-xs text-neutral-400">
                  {leader.title} &mdash; {leader.description.split(",").slice(0, 3).join(",")}
                </p>
              </div>
            </li>
          ))}
        </ul>
      )}
      <div className="flex items-center gap-3 border-t border-neutral-800 px-3 py-1.5 text-xs text-neutral-400">
        <span>{filtered.length} {filtered.length === 1 ? "match" : "matches"}</span>
        <span className="ml-auto flex items-center gap-1">
          <kbd className="rounded border border-neutral-700 px-1">↑</kbd>
          <kbd className="rounded border border-neutral-700 px-1">↓</kbd>
          to navigate
        </span>
      </div>
    </div>
  );
}
