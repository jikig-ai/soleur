"use client";

import { createContext, useContext, useState, useEffect, useCallback, useRef, type ReactNode } from "react";
import useSWR from "swr";
import { jsonFetcher, swrKeys } from "@/lib/swr-config";
import { usePostFcp } from "@/hooks/use-post-fcp";
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

interface TeamNamesResponse {
  names: Record<string, string>;
  iconPaths?: Record<string, string>;
  nudgesDismissed: string[];
  namingPromptedAt: string | null;
}

export function TeamNamesProvider({
  children,
  defer = true,
}: {
  children: ReactNode;
  /** #9178 — defer the fetch past first paint (default). Pass `false` where
   *  team names ARE the primary content (the conversation-names settings
   *  page) so they are not idle-gated there. Both providers share the one
   *  SWR key, so a single fetch feeds whichever mounts. */
  defer?: boolean;
}) {
  const [names, setNames] = useState<Record<string, string>>({});
  const [iconPaths, setIconPaths] = useState<Record<string, string>>({});
  const [nudgesDismissed, setNudgesDismissed] = useState<string[]>([]);
  const [namingPromptedAt, setNamingPromptedAt] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // #9178 mount-fetch contract: the GET rides the shared SWR key (the shell
  // provider and the settings-page provider coalesce into one flight) and is
  // deferred past first paint — team names are cosmetic chrome, not the
  // above-fold payload. Mutations below stay raw fetch (non-GET).
  const postFcp = usePostFcp();
  const fetchEnabled = !defer || postFcp;
  const {
    data,
    error: swrError,
    isLoading,
    mutate: revalidate,
  } = useSWR<TeamNamesResponse>(
    fetchEnabled ? swrKeys.teamNames() : null,
    jsonFetcher<TeamNamesResponse>,
    { onError: (err) => console.error("[team-names] fetch error:", err) },
  );

  const refetch = useCallback(() => {
    void revalidate();
  }, [revalidate]);

  // Hydrate the optimistic-overlay state from the shared cache entry; SWR
  // revalidations (focus, mutate) re-seed it with server truth.
  const hydrated = useRef(false);
  useEffect(() => {
    if (!data) return;
    hydrated.current = true;
    setNames(data.names);
    setIconPaths(data.iconPaths ?? {});
    setNudgesDismissed(data.nudgesDismissed);
    setNamingPromptedAt(data.namingPromptedAt);
    setError(null);
  }, [data]);

  useEffect(() => {
    if (swrError) {
      setError(
        swrError instanceof Error ? swrError.message : "Failed to load team names",
      );
    }
  }, [swrError]);

  // `loading` reports "initial read outstanding": false while deferred (the
  // key is gated), false on error. The `!hydrated` arm closes the one-render
  // gap between `data` arriving and this effect's setNames commit — otherwise
  // a consumer's `if (loading) return null` boundary would mount its rows
  // against empty `names` and a `useState(customName)` seed would freeze "".
  const loading =
    fetchEnabled && !swrError && (isLoading || (data !== undefined && !hydrated.current));

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
      const res = await fetch("/api/team-names", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ leaderId, name: trimmed }),
      });
      if (!res.ok) throw new Error(`team-names PUT ${res.status}`);
      // Revalidate the shared SWR key so the shell provider (mounted in the
      // dashboard shell) and any focus revalidation converge on server truth
      // rather than carrying the pre-write entry until the next revalidation.
      void revalidate();
    } catch (err) {
      console.error("[team-names] save error:", err);
      setError(err instanceof Error ? err.message : "Failed to save");
      void revalidate(); // re-seed server truth over the optimistic overlay
    }
  }, [revalidate]);

  const dismissNudge = useCallback(async (leaderId: string) => {
    setNudgesDismissed((prev) =>
      prev.includes(leaderId) ? prev : [...prev, leaderId],
    );

    try {
      const res = await fetch("/api/team-names", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ leaderId }),
      });
      if (!res.ok) throw new Error(`team-names PATCH ${res.status}`);
      void revalidate();
    } catch (err) {
      console.error("[team-names] dismiss error:", err);
      void revalidate();
    }
  }, [revalidate]);

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
      const res = await fetch("/api/team-names", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ leaderId, iconPath: path }),
      });
      if (!res.ok) throw new Error(`team-names icon PUT ${res.status}`);
      void revalidate();
    } catch (err) {
      console.error("[team-names] icon save error:", err);
      setError(err instanceof Error ? err.message : "Failed to save");
      void revalidate();
    }
  }, [revalidate]);

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
