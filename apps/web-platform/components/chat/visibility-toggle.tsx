"use client";

import { useState, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";

interface VisibilityToggleProps {
  conversationId: string;
  currentVisibility: "private" | "workspace";
  isOwner: boolean;
  onToggle?: (newVisibility: "private" | "workspace") => void;
}

export function VisibilityToggle({
  conversationId,
  currentVisibility,
  isOwner,
  onToggle,
}: VisibilityToggleProps) {
  const [visibility, setVisibility] = useState(currentVisibility);
  const [loading, setLoading] = useState(false);

  const toggle = useCallback(async () => {
    if (!isOwner || loading) return;
    const next = visibility === "private" ? "workspace" : "private";
    setLoading(true);
    try {
      const supabase = createClient();
      const { error } = await supabase.rpc("set_conversation_visibility", {
        p_conversation_id: conversationId,
        p_visibility: next,
      });
      if (error) throw error;
      setVisibility(next);
      onToggle?.(next);
    } finally {
      setLoading(false);
    }
  }, [conversationId, visibility, isOwner, loading, onToggle]);

  if (!isOwner) return null;

  return (
    <button
      onClick={toggle}
      disabled={loading}
      className="inline-flex items-center gap-1.5 rounded px-2 py-1 text-xs font-medium transition-colors"
      style={{
        backgroundColor:
          visibility === "workspace"
            ? "rgba(201, 169, 98, 0.15)"
            : "rgba(255, 255, 255, 0.06)",
        color: visibility === "workspace" ? "#C9A962" : "#888",
        border: `1px solid ${visibility === "workspace" ? "rgba(201, 169, 98, 0.3)" : "rgba(255, 255, 255, 0.1)"}`,
      }}
      title={
        visibility === "private"
          ? "Share with workspace members"
          : "Make private"
      }
    >
      {visibility === "workspace" ? (
        <svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor">
          <path d="M15 14s1 0 1-1-1-4-5-4-5 3-5 4 1 1 1 1h8zm-7.978-1A.261.261 0 017 12.996c.001-.264.167-1.03.76-1.72C8.312 10.629 9.282 10 11 10c1.717 0 2.687.63 3.24 1.276.593.69.758 1.457.76 1.72l-.008.002a.274.274 0 01-.014.002H7.022zM11 7a2 2 0 100-4 2 2 0 000 4zm3-2a3 3 0 11-6 0 3 3 0 016 0zM6.936 9.28a5.88 5.88 0 00-1.23-.247A7.35 7.35 0 005 9c-4 0-5 3-5 4 0 .667.333 1 1 1h4.216A2.238 2.238 0 015 13c0-.344.091-.773.327-1.264a4.837 4.837 0 011.609-1.456zM4.5 8a2.5 2.5 0 100-5 2.5 2.5 0 000 5z" />
        </svg>
      ) : (
        <svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor">
          <path d="M8 1a2 2 0 012 2v4H6V3a2 2 0 012-2zm3 6V3a3 3 0 00-6 0v4a2 2 0 00-2 2v5a2 2 0 002 2h6a2 2 0 002-2V9a2 2 0 00-2-2z" />
        </svg>
      )}
      {visibility === "workspace" ? "Shared" : "Private"}
    </button>
  );
}
