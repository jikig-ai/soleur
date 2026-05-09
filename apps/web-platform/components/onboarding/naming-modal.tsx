"use client";

import { useState } from "react";
import { ROUTABLE_DOMAIN_LEADERS } from "@/server/domain-leaders";
import { LeaderAvatar } from "@/components/leader-avatar";

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
    <div className="flex min-h-[100dvh] items-center justify-center bg-soleur-bg-base px-4">
      <div className="w-full max-w-lg">
        <div className="mb-2 text-center text-xs font-medium uppercase tracking-wider text-soleur-accent-gold-fg">
          Meet Your Team
        </div>
        <h1 className="mb-2 text-center text-2xl font-semibold text-soleur-text-primary">
          Want to Name Your Leaders?
        </h1>
        <p className="mb-8 text-center text-sm text-soleur-text-secondary">
          Give each domain leader a name that feels right to you. You can always
          change these later in Settings.
        </p>

        <div className="space-y-3">
          {ROUTABLE_DOMAIN_LEADERS.map((leader) => (
            <div key={leader.id} className="flex items-center gap-4">
              <LeaderAvatar leaderId={leader.id} size="lg" />
              <span className="min-w-0 flex-1 text-sm text-soleur-text-secondary">
                {leader.title}
              </span>
              <input
                type="text"
                value={names[leader.id] ?? ""}
                onChange={(e) => handleChange(leader.id, e.target.value)}
                placeholder="Enter a name..."
                maxLength={30}
                className="w-40 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2/50 px-3 py-2 text-sm text-soleur-text-primary placeholder-soleur-text-muted outline-none transition-colors focus:border-soleur-border-emphasized"
              />
            </div>
          ))}
        </div>

        <div className="mt-8 flex items-center justify-center gap-6">
          <button
            onClick={onSkip}
            className="text-sm text-soleur-text-secondary transition-colors hover:text-soleur-text-primary"
          >
            Skip for now
          </button>
          <button
            onClick={handleSave}
            className="rounded-lg bg-soleur-accent-gold-fill px-6 py-2.5 text-sm font-semibold text-soleur-text-on-accent transition-colors hover:bg-soleur-accent-gold-text"
          >
            Save Names
          </button>
        </div>
      </div>
    </div>
  );
}
