"use client";

import { useState } from "react";
import { ROUTABLE_DOMAIN_LEADERS } from "@/server/domain-leaders";
import { LEADER_BG_COLORS } from "@/components/chat/leader-colors";

interface NamingOnboardingModalProps {
  onSave: (leaderId: string, name: string) => Promise<void>;
  onSkip: () => void;
  onComplete: () => void;
}

export function NamingOnboardingModal({
  onSave,
  onSkip,
  onComplete,
}: NamingOnboardingModalProps) {
  const [names, setNames] = useState<Record<string, string>>({});

  function handleChange(leaderId: string, value: string) {
    setNames((prev) => ({ ...prev, [leaderId]: value }));
  }

  async function handleSave() {
    const entries = Object.entries(names).filter(([, v]) => v.trim() !== "");
    await Promise.all(entries.map(([id, name]) => onSave(id, name.trim())));
    onComplete();
  }

  return (
    <div className="flex min-h-[100dvh] items-center justify-center bg-neutral-950 px-4">
      <div className="w-full max-w-lg">
        <div className="mb-2 text-center text-xs font-medium uppercase tracking-wider text-amber-500">
          Meet Your Team
        </div>
        <h1 className="mb-2 text-center text-2xl font-semibold text-white">
          Want to Name Your Leaders?
        </h1>
        <p className="mb-8 text-center text-sm text-neutral-400">
          Give each domain leader a name that feels right to you. You can always
          change these later in Settings.
        </p>

        <div className="space-y-3">
          {ROUTABLE_DOMAIN_LEADERS.map((leader) => (
            <div key={leader.id} className="flex items-center gap-4">
              <span
                className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-xs font-semibold text-white ${LEADER_BG_COLORS[leader.id]}`}
              >
                {leader.name}
              </span>
              <span className="min-w-0 flex-1 text-sm text-neutral-300">
                {leader.title}
              </span>
              <input
                type="text"
                value={names[leader.id] ?? ""}
                onChange={(e) => handleChange(leader.id, e.target.value)}
                placeholder="Enter a name..."
                maxLength={30}
                className="w-40 rounded-lg border border-neutral-700 bg-neutral-800/50 px-3 py-2 text-sm text-white placeholder-neutral-500 outline-none transition-colors focus:border-amber-600"
              />
            </div>
          ))}
        </div>

        <div className="mt-8 flex items-center justify-center gap-6">
          <button
            onClick={onSkip}
            className="text-sm text-neutral-400 transition-colors hover:text-neutral-200"
          >
            Skip for now
          </button>
          <button
            onClick={handleSave}
            className="rounded-lg bg-amber-500 px-6 py-2.5 text-sm font-semibold text-neutral-900 transition-colors hover:bg-amber-400"
          >
            Save Names
          </button>
        </div>
      </div>
    </div>
  );
}
