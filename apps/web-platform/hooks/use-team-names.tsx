"use client";

import { createContext, useContext, useState, useEffect, useCallback, type ReactNode } from "react";
import { DOMAIN_LEADERS, type DomainLeaderId } from "@/server/domain-leaders";

interface TeamNamesState {
  /** Map of leaderId -> custom name (e.g., { cto: "Alex" }) */
  names: Record<string, string>;
  /** Map of leaderId -> custom icon KB path (e.g., { cto: "settings/team-icons/cto.png" }) */
  iconPaths: Record<string, string>;
  /** Array of leader IDs whose contextual nudge was dismissed */
  nudgesDismissed: string[];
  /** Whether the onboarding naming prompt was already shown */
  namingPromptedAt: string | null;
  /** Whether the initial fetch is still loading */
  loading: boolean;
  /** Error message from the last fetch attempt, or null if successful */
  error: string | null;
  /** Update a leader's custom name. Empty string removes the name. */
  updateName: (leaderId: string, name: string) => Promise<void>;
  /** Update a leader's custom icon path. Null clears it. */
  updateIcon: (leaderId: string, path: string | null) => Promise<void>;
  /** Dismiss the contextual nudge for a leader. */
  dismissNudge: (leaderId: string) => Promise<void>;
  /** Retry fetching team names after a failure. */
  refetch: () => void;
  /** Get the display name: "CustomName (ROLE)" or "ROLE" if no custom name. */
  getDisplayName: (leaderId: DomainLeaderId) => string;
  /** Get just the label for the avatar badge (first 3 chars of custom name, or role acronym). */
  getBadgeLabel: (leaderId: DomainLeaderId) => string;
  /** Get the custom icon KB path, or null if not set. */
  getIconPath: (leaderId: DomainLeaderId) => string | null;
}

const TeamNamesContext = createContext<TeamNamesState | null>(null);

const leaderNameMap = new Map(DOMAIN_LEADERS.map((l) => [l.id, l.name]));

export function TeamNamesProvider({ children }: { children: ReactNode }) {
  const [names, setNames] = useState<Record<string, string>>({});
  const [iconPaths, setIconPaths] = useState<Record<string, string>>({});
  const [nudgesDismissed, setNudgesDismissed] = useState<string[]>([]);
  const [namingPromptedAt, setNamingPromptedAt] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [fetchKey, setFetchKey] = useState(0);

  const refetch = useCallback(() => {
    setFetchKey((k) => k + 1);
  }, []);

  useEffect(() => {
    setLoading(true);
    setError(null);
    fetch("/api/team-names")
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then((data: { names: Record<string, string>; iconPaths?: Record<string, string>; nudgesDismissed: string[]; namingPromptedAt: string | null }) => {
        setNames(data.names);
        setIconPaths(data.iconPaths ?? {});
        setNudgesDismissed(data.nudgesDismissed);
        setNamingPromptedAt(data.namingPromptedAt);
        setError(null);
      })
      .catch((err) => {
        console.error("[team-names] fetch error:", err);
        setError(err instanceof Error ? err.message : "Failed to load team names");
      })
      .finally(() => setLoading(false));
  }, [fetchKey]);

  const updateName = useCallback(async (leaderId: string, name: string) => {
    const trimmed = name.trim();

    // Optimistic update
    setNames((prev) => {
      if (trimmed === "") {
        const next = { ...prev };
        delete next[leaderId];
        return next;
      }
      return { ...prev, [leaderId]: trimmed };
    });

    // Deleting a name deletes the entire row, so clear the icon path too
    if (trimmed === "") {
      setIconPaths((prev) => {
        const next = { ...prev };
        delete next[leaderId];
        return next;
      });
    }

    try {
      await fetch("/api/team-names", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ leaderId, name: trimmed }),
      });
    } catch (err) {
      console.error("[team-names] save error:", err);
    }
  }, []);

  const dismissNudge = useCallback(async (leaderId: string) => {
    setNudgesDismissed((prev) =>
      prev.includes(leaderId) ? prev : [...prev, leaderId],
    );

    try {
      await fetch("/api/team-names", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ leaderId }),
      });
    } catch (err) {
      console.error("[team-names] dismiss error:", err);
    }
  }, []);

  const getDisplayName = useCallback(
    (leaderId: DomainLeaderId): string => {
      const customName = names[leaderId];
      const roleName = leaderNameMap.get(leaderId) ?? leaderId.toUpperCase();
      if (customName) return `${customName} (${roleName})`;
      return roleName;
    },
    [names],
  );

  const getBadgeLabel = useCallback(
    (leaderId: DomainLeaderId): string => {
      const customName = names[leaderId];
      if (customName) return customName.slice(0, 3).toUpperCase();
      return (leaderNameMap.get(leaderId) ?? leaderId.toUpperCase()).slice(0, 3);
    },
    [names],
  );

  const getIconPath = useCallback(
    (leaderId: DomainLeaderId): string | null => {
      return iconPaths[leaderId] ?? null;
    },
    [iconPaths],
  );

  const updateIcon = useCallback(async (leaderId: string, path: string | null) => {
    // Optimistic update
    setIconPaths((prev) => {
      if (path === null) {
        const next = { ...prev };
        delete next[leaderId];
        return next;
      }
      return { ...prev, [leaderId]: path };
    });

    try {
      await fetch("/api/team-names", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ leaderId, iconPath: path }),
      });
    } catch (err) {
      console.error("[team-names] icon save error:", err);
    }
  }, []);

  return (
    <TeamNamesContext.Provider value={{
      names,
      iconPaths,
      nudgesDismissed,
      namingPromptedAt,
      loading,
      error,
      updateName,
      updateIcon,
      dismissNudge,
      refetch,
      getDisplayName,
      getBadgeLabel,
      getIconPath,
    }}>
      {children}
    </TeamNamesContext.Provider>
  );
}

export function useTeamNames(): TeamNamesState {
  const ctx = useContext(TeamNamesContext);
  if (!ctx) {
    throw new Error("useTeamNames must be used within a TeamNamesProvider");
  }
  return ctx;
}
