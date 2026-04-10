"use client";

import { useState, useRef, useCallback } from "react";
import { ROUTABLE_DOMAIN_LEADERS } from "@/server/domain-leaders";
import { LEADER_BG_COLORS } from "@/components/chat/leader-colors";
import { useTeamNames } from "@/hooks/use-team-names";
import { validateCustomName } from "@/server/team-names-validation";

export function TeamSettingsContent() {
  const { names, updateName, loading } = useTeamNames();

  if (loading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <span className="text-sm text-neutral-400">Loading team...</span>
      </div>
    );
  }

  return (
    <div>
      <div className="mb-1 text-xs font-medium uppercase tracking-wider text-amber-500">
        Your Team
      </div>
      <h1 className="mb-2 text-2xl font-semibold text-white">Domain Leaders</h1>
      <p className="mb-8 text-sm text-neutral-400">
        Give your leaders custom names. Names display as &quot;Name (Role)&quot; across conversations and mentions.
      </p>

      <div className="space-y-1">
        {ROUTABLE_DOMAIN_LEADERS.map((leader) => (
          <LeaderRow
            key={leader.id}
            leaderId={leader.id}
            title={leader.title}
            name={leader.name}
            customName={names[leader.id] ?? ""}
            bgColor={LEADER_BG_COLORS[leader.id]}
            onNameChange={updateName}
          />
        ))}
      </div>

      <p className="mt-6 text-xs text-neutral-500">Changes save automatically</p>
    </div>
  );
}

function LeaderRow({
  leaderId,
  title,
  name,
  customName,
  bgColor,
  onNameChange,
}: {
  leaderId: string;
  title: string;
  name: string;
  customName: string;
  bgColor: string;
  onNameChange: (leaderId: string, name: string) => Promise<void>;
}) {
  const [value, setValue] = useState(customName);
  const [error, setError] = useState("");
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(null);

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const newValue = e.target.value;
      setValue(newValue);
      setError("");

      if (debounceRef.current) clearTimeout(debounceRef.current);

      debounceRef.current = setTimeout(() => {
        const trimmed = newValue.trim();
        if (trimmed !== "") {
          const result = validateCustomName(trimmed);
          if (!result.valid) {
            setError(result.error);
            return;
          }
        }
        onNameChange(leaderId, newValue);
      }, 500);
    },
    [leaderId, onNameChange],
  );

  return (
    <div className="flex items-center gap-4 rounded-lg px-2 py-3">
      <span
        className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-xs font-semibold text-white ${bgColor}`}
      >
        {name}
      </span>
      <span className="min-w-0 flex-1 text-sm text-neutral-300">{title}</span>
      <div className="w-48">
        <input
          type="text"
          value={value}
          onChange={handleChange}
          placeholder="Enter a name..."
          maxLength={30}
          className={`w-full rounded-lg border bg-neutral-800/50 px-3 py-2 text-sm text-white placeholder-neutral-500 outline-none transition-colors focus:border-amber-600 ${
            error ? "border-red-500" : "border-neutral-700"
          }`}
        />
        {error && <p className="mt-1 text-xs text-red-400">{error}</p>}
      </div>
    </div>
  );
}
