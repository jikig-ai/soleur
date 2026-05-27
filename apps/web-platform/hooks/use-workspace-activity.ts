"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { createClient } from "@/lib/supabase/client";

export interface ActivityEvent {
  id: string;
  workspace_id: string;
  actor_user_id: string | null;
  event_type: string;
  metadata: Record<string, unknown>;
  created_at: string;
}

interface UseWorkspaceActivityResult {
  events: ActivityEvent[];
  loading: boolean;
  error: string | null;
  loadMore: () => void;
  hasMore: boolean;
}

const PAGE_SIZE = 20;
const POLL_INTERVAL_MS = 60_000;

export function useWorkspaceActivity(): UseWorkspaceActivityResult {
  const [events, setEvents] = useState<ActivityEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const offsetRef = useRef(0);
  const workspaceIdRef = useRef<string | null>(null);
  const userIdRef = useRef<string | null>(null);
  const fetchingRef = useRef(false);

  const fetchEvents = useCallback(async (append = false) => {
    if (fetchingRef.current) return;
    fetchingRef.current = true;
    if (!append) setLoading(true);
    setError(null);

    try {
      const supabase = createClient();

      if (!userIdRef.current) {
        const { data: authData } = await supabase.auth.getUser();
        if (!authData.user) {
          setError("Authentication required");
          setLoading(false);
          return;
        }
        userIdRef.current = authData.user.id;
      }

      if (!workspaceIdRef.current) {
        const { data: memberRow } = await supabase
          .from("workspace_members")
          .select("workspace_id")
          .eq("user_id", userIdRef.current)
          .maybeSingle();
        workspaceIdRef.current = (memberRow?.workspace_id as string) ?? null;
      }

      if (!workspaceIdRef.current) {
        setEvents([]);
        setLoading(false);
        return;
      }

      const offset = append ? offsetRef.current : 0;
      const { data, error: fetchErr } = await supabase
        .from("workspace_activity")
        .select("*")
        .eq("workspace_id", workspaceIdRef.current)
        .order("created_at", { ascending: false })
        .range(offset, offset + PAGE_SIZE - 1);

      if (fetchErr) {
        setError("Failed to load activity");
        setLoading(false);
        return;
      }

      const rows = (data ?? []) as ActivityEvent[];
      setHasMore(rows.length === PAGE_SIZE);

      if (append) {
        setEvents((prev) => [...prev, ...rows]);
        offsetRef.current += rows.length;
      } else {
        setEvents(rows);
        offsetRef.current = rows.length;
      }
    } finally {
      fetchingRef.current = false;
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchEvents();

    let timer: ReturnType<typeof setTimeout>;
    const scheduleNext = () => {
      timer = setTimeout(() => {
        if (document.visibilityState === "visible") {
          fetchEvents().then(scheduleNext);
        } else {
          scheduleNext();
        }
      }, POLL_INTERVAL_MS);
    };
    scheduleNext();

    return () => clearTimeout(timer);
  }, [fetchEvents]);

  const loadMore = useCallback(() => {
    if (hasMore && !loading) fetchEvents(true);
  }, [hasMore, loading, fetchEvents]);

  return { events, loading, error, loadMore, hasMore };
}
