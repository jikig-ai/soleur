"use client";

import { useEffect, useState } from "react";
import { DEFAULT_AGENT_ENGINE_ID, type EngineSettingsMetadata } from "@/server/agent-engine-contract";

type Engine = EngineSettingsMetadata;

export function AgentEngineSettings({ isOwner }: { isOwner: boolean }) {
  const [engines, setEngines] = useState<Engine[]>([]);
  const [selected, setSelected] = useState<string>(DEFAULT_AGENT_ENGINE_ID);
  const [authMode, setAuthMode] = useState<string>("managed");
  const [status, setStatus] = useState<"loading" | "ready" | "saving" | "error">("loading");
  const isEngineSelectable = (engine: Engine): boolean =>
    engine.enabledForNewRuns && engine.rolloutEnabled;
  const selectedEngine = engines.find((engine) => engine.id === selected);

  useEffect(() => {
    void fetch("/api/dashboard/settings/agent-engine")
      .then((response) => response.ok ? response.json() : Promise.reject(new Error("settings unavailable")))
      .then((payload: { engines: Engine[]; defaultEngineId: string; defaultAuthMode?: string }) => {
        setEngines(payload.engines);
        setSelected(payload.defaultEngineId);
        setAuthMode(payload.defaultAuthMode ?? "managed");
        setStatus("ready");
      })
      .catch(() => setStatus("error"));
  }, []);

  async function save(engineId: string, nextAuthMode = authMode) {
    setSelected(engineId);
    setStatus("saving");
    try {
      const response = await fetch("/api/dashboard/settings/agent-engine", {
        method: "PUT",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ engineId, authMode: nextAuthMode }),
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
          {engines.map((engine) => {
            const selectable = isEngineSelectable(engine);
            return (
            <label key={engine.id} className="flex items-start gap-3 text-sm text-soleur-text-primary">
              <input
                type="radio"
                name="agent-engine"
                value={engine.id}
                checked={selected === engine.id}
                disabled={!isOwner || status === "loading" || status === "saving" || !selectable}
                onChange={() => {
                  const nextMode = engine.authModes.includes(authMode) ? authMode : engine.authModes[0] ?? "managed";
                  setAuthMode(nextMode);
                  void save(engine.id, nextMode);
                }}
              />
              <span>
                <span className="block font-medium">{engine.id === DEFAULT_AGENT_ENGINE_ID ? "Claude Code" : engine.id}</span>
                <span className="block text-xs text-soleur-text-secondary">
                  {selectable ? `${engine.transport} · ${engine.authModes.join(" or ")}` : "Coming soon"}
                </span>
              </span>
            </label>
            );
          })}
        </div>
        {selectedEngine?.authModes.length ? (
          <label className="mt-5 block text-sm text-soleur-text-primary">
            <span className="mb-2 block font-medium">Authentication mode</span>
            <select
              aria-label="Authentication mode"
              value={authMode}
              disabled={!isOwner || status === "loading" || status === "saving" || !isEngineSelectable(selectedEngine)}
              onChange={(event) => {
                const nextMode = event.target.value;
                setAuthMode(nextMode);
                void save(selected, nextMode);
              }}
              className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-2"
            >
              {selectedEngine.authModes.map((mode) => (
                <option key={mode} value={mode}>{mode}</option>
              ))}
            </select>
          </label>
        ) : null}
        {!isOwner && <p className="mt-4 text-xs text-soleur-text-secondary">Only workspace owners can change this setting.</p>}
      </div>
    </section>
  );
}
