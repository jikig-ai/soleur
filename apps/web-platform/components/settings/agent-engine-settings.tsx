"use client";

import { useEffect, useRef, useState } from "react";

// Keep the settings projection client-local: importing the server contract (even
// for a constant plus a type) pulls the server-only dependency tree into the
// browser bundle. The API response is validated by the server route; this
// structural projection contains no secrets or provider internals.
const DEFAULT_AGENT_ENGINE_ID = "claude-code";
type Engine = {
  id: string;
  version: string;
  transport: "local" | "remote";
  authModes: string[];
  enabledForNewRuns: boolean;
  rolloutEnabled?: boolean;
};

export function AgentEngineSettings({ isOwner }: { isOwner: boolean }) {
  const [engines, setEngines] = useState<Engine[]>([]);
  const [selected, setSelected] = useState<string>(DEFAULT_AGENT_ENGINE_ID);
  const [authMode, setAuthMode] = useState<string>("managed");
  const [status, setStatus] = useState<"loading" | "ready" | "saving" | "error">("loading");
  const settingsRevision = useRef(0);
  const isEngineSelectable = (engine: Engine): boolean =>
    engine.enabledForNewRuns && (engine.rolloutEnabled ?? engine.id === DEFAULT_AGENT_ENGINE_ID);
  const selectedEngine = engines.find((engine) => engine.id === selected);

  useEffect(() => {
    const revision = settingsRevision.current;
    void fetch("/api/dashboard/settings/agent-engine")
      .then((response) => response.ok ? response.json() : Promise.reject(new Error("settings unavailable")))
      .then((payload: { engines: Engine[]; defaultEngineId: string; defaultAuthMode?: string }) => {
        if (settingsRevision.current !== revision) return;
        setEngines(payload.engines);
        setSelected(payload.defaultEngineId);
        setAuthMode(payload.defaultAuthMode ?? "managed");
        setStatus("ready");
      })
      .catch(() => setStatus("error"));
  }, []);

  async function save(
    engineId: string,
    nextAuthMode = authMode,
    rollback: { engineId: string; authMode: string } = { engineId: selected, authMode },
  ) {
    settingsRevision.current += 1;
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
      setSelected(rollback.engineId);
      setAuthMode(rollback.authMode);
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
                  const rollback = { engineId: selected, authMode };
                  setAuthMode(nextMode);
                  void save(engine.id, nextMode, rollback);
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
                const rollback = { engineId: selected, authMode };
                setAuthMode(nextMode);
                void save(selected, nextMode, rollback);
              }}
              className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-2"
            >
              {selectedEngine.authModes.map((mode) => (
                <option key={mode} value={mode}>{mode}</option>
              ))}
            </select>
            {authMode === "api-key" && (
              <p
                className="mt-3 rounded-lg border border-amber-600/40 bg-amber-950/20 p-3 text-xs leading-5 text-amber-100"
                role="note"
                data-testid="user-provider-disclosure"
              >
                This uses your own provider account. Prompts, files, and outputs sent through this
                engine are subject to that provider&apos;s retention, region, and account terms.
                Soleur-managed provider access remains restricted. Only submit data you are
                authorized to share with the provider.
              </p>
            )}
          </label>
        ) : null}
        {!isOwner && <p className="mt-4 text-xs text-soleur-text-secondary">Only workspace owners can change this setting.</p>}
      </div>
    </section>
  );
}
