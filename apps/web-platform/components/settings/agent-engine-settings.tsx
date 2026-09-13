"use client";

import { useEffect, useState } from "react";
import { DEFAULT_AGENT_ENGINE_ID } from "@/server/agent-engine-contract";

type Engine = { id: string; version: string; transport: string; authModes: string[]; enabledForNewRuns: boolean };

export function AgentEngineSettings({ isOwner }: { isOwner: boolean }) {
  const [engines, setEngines] = useState<Engine[]>([]);
  const [selected, setSelected] = useState<string>(DEFAULT_AGENT_ENGINE_ID);
  const [status, setStatus] = useState<"loading" | "ready" | "saving" | "error">("loading");

  useEffect(() => {
    void fetch("/api/dashboard/settings/agent-engine")
      .then((response) => response.ok ? response.json() : Promise.reject(new Error("settings unavailable")))
      .then((payload: { engines: Engine[]; defaultEngineId: string }) => {
        setEngines(payload.engines);
        setSelected(payload.defaultEngineId);
        setStatus("ready");
      })
      .catch(() => setStatus("error"));
  }, []);

  async function save(engineId: string) {
    setSelected(engineId);
    setStatus("saving");
    try {
      const response = await fetch("/api/dashboard/settings/agent-engine", {
        method: "PUT",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ engineId }),
      });
      if (!response.ok) throw new Error("save failed");
      setStatus("ready");
    } catch {
      setStatus("error");
    }
  }

  return (
    <section data-testid="agent-engine-settings">
      <h2 className="mb-4 text-lg font-semibold text-soleur-text-primary">Agent engine</h2>
      <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
        <p className="mb-4 text-sm text-soleur-text-secondary">
          Choose the default engine for new conversations and routine runs in this workspace.
        </p>
        {status === "error" && <p role="alert" className="mb-3 text-sm text-red-400">Engine settings are unavailable.</p>}
        <div className="space-y-3">
          {engines.map((engine) => (
            <label key={engine.id} className="flex items-start gap-3 text-sm text-soleur-text-primary">
              <input
                type="radio"
                name="agent-engine"
                value={engine.id}
                checked={selected === engine.id}
                disabled={!isOwner || status === "loading" || status === "saving" || !engine.enabledForNewRuns}
                onChange={() => void save(engine.id)}
              />
              <span>
                <span className="block font-medium">{engine.id === DEFAULT_AGENT_ENGINE_ID ? "Claude Code" : engine.id}</span>
                <span className="block text-xs text-soleur-text-secondary">
                  {engine.enabledForNewRuns ? `${engine.transport} · ${engine.authModes.join(" or ")}` : "Coming soon"}
                </span>
              </span>
            </label>
          ))}
        </div>
        {!isOwner && <p className="mt-4 text-xs text-soleur-text-secondary">Only workspace owners can change this setting.</p>}
      </div>
    </section>
  );
}
