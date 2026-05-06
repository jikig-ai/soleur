"use client";

import { useState } from "react";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import { LeaderAvatar } from "@/components/leader-avatar";

interface NamingNudgeProps {
  leaderId: DomainLeaderId;
  onSave: (leaderId: string, name: string) => Promise<void>;
  onDismiss: (leaderId: string) => void;
}

export function NamingNudge({
  leaderId,
  onSave,
  onDismiss,
}: NamingNudgeProps) {
  const [name, setName] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const roleName =
    DOMAIN_LEADERS.find((l) => l.id === leaderId)?.name ?? leaderId.toUpperCase();

  async function handleSave() {
    const trimmed = name.trim();
    if (!trimmed || saving) return;
    setSaving(true);
    setError(null);
    try {
      await onSave(leaderId, trimmed);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save name");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="flex items-center gap-3 rounded-xl border border-amber-800/50 bg-amber-950/30 px-4 py-3">
      <LeaderAvatar leaderId={leaderId} size="lg" />
      <div className="min-w-0 flex-1">
        <p className="text-sm font-medium text-amber-200">
          You just worked with your {roleName}.
        </p>
        <p className="text-xs text-soleur-text-secondary">
          Want to give them a name? It will display as &quot;Name ({roleName})&quot; in conversations.
        </p>
        {error && (
          <p role="alert" className="mt-1 text-xs text-amber-300">
            {error}
          </p>
        )}
      </div>
      <input
        type="text"
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder={`Name your ${roleName}...`}
        maxLength={30}
        disabled={saving}
        className="w-32 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2/50 px-3 py-1.5 text-sm text-soleur-text-primary placeholder:text-soleur-text-muted outline-none focus:border-amber-600 disabled:opacity-50"
      />
      <button
        onClick={handleSave}
        disabled={saving}
        className="rounded-lg bg-soleur-accent-gold-fill px-3 py-1.5 text-sm font-semibold text-soleur-text-on-accent transition-colors hover:bg-amber-400 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {saving ? "Saving..." : "Save"}
      </button>
      <button
        onClick={() => onDismiss(leaderId)}
        disabled={saving}
        className="text-sm text-soleur-text-secondary transition-colors hover:text-soleur-text-primary disabled:opacity-50"
      >
        Dismiss
      </button>
    </div>
  );
}
