"use client";

import { useState } from "react";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { LEADER_BG_COLORS } from "./leader-colors";

interface NamingNudgeProps {
  leaderId: DomainLeaderId;
  leaderTitle: string;
  onSave: (leaderId: string, name: string) => Promise<void>;
  onDismiss: (leaderId: string) => void;
}

export function NamingNudge({
  leaderId,
  leaderTitle,
  onSave,
  onDismiss,
}: NamingNudgeProps) {
  const [name, setName] = useState("");
  const roleName = leaderId.toUpperCase();

  async function handleSave() {
    const trimmed = name.trim();
    if (!trimmed) return;
    await onSave(leaderId, trimmed);
  }

  return (
    <div className="flex items-center gap-3 rounded-xl border border-amber-800/50 bg-amber-950/30 px-4 py-3">
      <span
        className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-xs font-semibold text-white ${LEADER_BG_COLORS[leaderId]}`}
      >
        {roleName}
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-sm font-medium text-amber-200">
          You just worked with your {roleName}.
        </p>
        <p className="text-xs text-neutral-400">
          Want to give them a name? It will display as &quot;Name ({roleName})&quot; in conversations.
        </p>
      </div>
      <input
        type="text"
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder={`Name your ${roleName}...`}
        maxLength={30}
        className="w-32 rounded-lg border border-neutral-700 bg-neutral-800/50 px-3 py-1.5 text-sm text-white placeholder-neutral-500 outline-none focus:border-amber-600"
      />
      <button
        onClick={handleSave}
        className="rounded-lg bg-amber-500 px-3 py-1.5 text-sm font-semibold text-neutral-900 transition-colors hover:bg-amber-400"
      >
        Save
      </button>
      <button
        onClick={() => onDismiss(leaderId)}
        className="text-sm text-neutral-400 transition-colors hover:text-neutral-200"
      >
        Dismiss
      </button>
    </div>
  );
}
