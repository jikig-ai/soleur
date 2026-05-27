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

  const fetchEvents = useCallback(async (append = false) => {
    if (!append) setLoading(true);
    setError(null);

    try {
      const supabase = createClient();
      const { data: authData } = await supabase.auth.getUser();
      if (!authData.user) {
        setError("Authentication required");
        setLoading(false);
        return;
      }

      if (!workspaceIdRef.current) {
        const { data: memberRow } = await supabase
          .from("workspace_members")
          .select("workspace_id")
          .eq("user_id", authData.user.id)
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
        setError(fetchErr.message);
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
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchEvents();
    const timer = setInterval(() => fetchEvents(), POLL_INTERVAL_MS);
    return () => clearInterval(timer);
  }, [fetchEvents]);

  const loadMore = useCallback(() => {
    if (hasMore && !loading) fetchEvents(true);
  }, [hasMore, loading, fetchEvents]);

  return { events, loading, error, loadMore, hasMore };
}
