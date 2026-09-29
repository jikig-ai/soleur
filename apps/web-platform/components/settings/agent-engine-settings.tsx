"use client";

import { useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";

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
  settingsSelectable?: boolean;
  rolloutEnabled?: boolean;
  qualificationOnly?: boolean;
};

type PendingAuthChange = {
  authMode: string;
  affectedConversationCount: number;
  rollback: { engineId: string; authMode: string };
};

function engineLabel(engineId: string): string {
  if (engineId === DEFAULT_AGENT_ENGINE_ID) return "Claude Code";
  if (engineId === "codex") return "Codex";
  return engineId;
}

export function AgentEngineSettings({ isOwner }: { isOwner: boolean }) {
  const [engines, setEngines] = useState<Engine[]>([]);
  const [selected, setSelected] = useState<string>(DEFAULT_AGENT_ENGINE_ID);
  const [workspaceDefaultEngineId, setWorkspaceDefaultEngineId] = useState<string>(DEFAULT_AGENT_ENGINE_ID);
  const [authMode, setAuthMode] = useState<string>("managed");
  const [claudeAuthMode, setClaudeAuthMode] = useState<string>("managed");
  const [codexAuthMode, setCodexAuthMode] = useState<string>("managed");
  const [status, setStatus] = useState<"loading" | "ready" | "saving" | "error">("loading");
  const [pendingAuthChange, setPendingAuthChange] = useState<PendingAuthChange | null>(null);
  const [statusMessage, setStatusMessage] = useState("");
  const settingsRevision = useRef(0);
  const isEngineSelectable = (engine: Engine): boolean =>
    engine.settingsSelectable === true
      || (
        engine.enabledForNewRuns
        && (engine.qualificationOnly === true
          || (engine.rolloutEnabled ?? engine.id === DEFAULT_AGENT_ENGINE_ID))
      );
  const selectedEngine = engines.find((engine) => engine.id === selected);

  useEffect(() => {
    const revision = settingsRevision.current;
    void fetch("/api/dashboard/settings/agent-engine")
      .then((response) => response.ok ? response.json() : Promise.reject(new Error("settings unavailable")))
      .then((payload: { engines: Engine[]; defaultEngineId: string; defaultAuthMode?: string; codexAuthMode?: string }) => {
        if (settingsRevision.current !== revision) return;
        setEngines(payload.engines);
        setSelected(payload.defaultEngineId);
        setWorkspaceDefaultEngineId(payload.defaultEngineId);
        setAuthMode(payload.defaultAuthMode ?? "managed");
        setClaudeAuthMode(payload.defaultAuthMode ?? "managed");
        setCodexAuthMode(payload.codexAuthMode ?? "managed");
        setStatus("ready");
      })
      .catch(() => {
        if (settingsRevision.current === revision) setStatus("error");
      });
  }, []);

  async function save(
    engineId: string,
    nextAuthMode: string,
    rollback: { engineId: string; authMode: string },
    applyToExistingCodexConversations: boolean,
    expectedAffectedConversationCount?: number,
  ) {
    settingsRevision.current += 1;
    const revision = settingsRevision.current;
    setSelected(engineId);
    setAuthMode(nextAuthMode);
    setStatus("saving");
    setStatusMessage("Saving agent engine settings.");
    try {
      const response = await fetch("/api/dashboard/settings/agent-engine", {
        method: "PUT",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          engineId,
          authMode: nextAuthMode,
          applyToExistingCodexConversations,
          ...(applyToExistingCodexConversations ? { expectedAffectedConversationCount } : {}),
        }),
      });
      if (!response.ok) throw new Error("save failed");
      if (settingsRevision.current !== revision) return;
      setStatus("ready");
      setPendingAuthChange(null);
      if (!applyToExistingCodexConversations) setWorkspaceDefaultEngineId(engineId);
      if (engineId === "codex") setCodexAuthMode(nextAuthMode);
      if (engineId === DEFAULT_AGENT_ENGINE_ID) setClaudeAuthMode(nextAuthMode);
      if (applyToExistingCodexConversations) {
        const result = await response.json().catch(() => ({})) as { affectedConversationCount?: number };
        const count = typeof result.affectedConversationCount === "number"
          ? result.affectedConversationCount
          : undefined;
        setStatusMessage(typeof count === "number"
          ? `Authentication mode changed for ${count} existing Codex conversation${count === 1 ? "" : "s"}.`
          : "Authentication mode changed for existing Codex conversations.");
      } else {
        setStatusMessage("Agent engine settings saved.");
      }
    } catch {
      if (settingsRevision.current !== revision) return;
      setSelected(rollback.engineId);
      setAuthMode(rollback.authMode);
      setPendingAuthChange(null);
      setStatus("error");
      setStatusMessage("Engine settings were not saved. Your previous selection is still active.");
    }
  }

  function chooseEngine(engineId: string) {
    const engine = engines.find((candidate) => candidate.id === engineId);
    if (!engine || !isEngineSelectable(engine)) return;
    const configuredMode = engine.id === "codex" ? codexAuthMode : claudeAuthMode;
    const nextMode = engine.authModes.includes(configuredMode) ? configuredMode : engine.authModes[0] ?? "managed";
    if (engine.settingsSelectable && !engine.enabledForNewRuns) {
      settingsRevision.current += 1;
      setSelected(engine.id);
      setAuthMode(nextMode);
      if (engine.id === "codex") setCodexAuthMode(nextMode);
      setPendingAuthChange(null);
      setStatus("ready");
      setStatusMessage(`Codex settings selected. Workspace default remains ${engineLabel(workspaceDefaultEngineId)} because Codex execution is disabled. Change its mode to update existing Codex conversations.`);
      return;
    }
    const rollback = { engineId: selected, authMode };
    setPendingAuthChange(null);
    void save(engine.id, nextMode, rollback, false);
  }

  async function chooseAuthMode(nextMode: string) {
    if (nextMode === authMode) return;
    const rollback = { engineId: selected, authMode };
    if (selected === "codex") {
      setStatus("saving");
      setStatusMessage("Checking which existing conversations will change.");
      try {
        const response = await fetch(`/api/dashboard/settings/agent-engine?previewAuthMode=${encodeURIComponent(nextMode)}`);
        if (!response.ok) throw new Error("conversation count unavailable");
        const result = await response.json() as { affectedConversationCount?: unknown };
        if (typeof result.affectedConversationCount !== "number"
          || !Number.isInteger(result.affectedConversationCount)
          || result.affectedConversationCount < 0) {
          throw new Error("conversation count unavailable");
        }
        setPendingAuthChange({ authMode: nextMode, affectedConversationCount: result.affectedConversationCount, rollback });
        setStatusMessage("");
        setStatus("ready");
      } catch {
        setStatus("error");
        setStatusMessage("Could not check the conversations to update. No settings were changed.");
      }
      return;
    }
    void save(selected, nextMode, rollback, false);
  }

  return (
    <section data-testid="agent-engine-settings">
      <h2 className="mb-4 text-lg font-semibold text-soleur-text-primary">Agent engine</h2>
      <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
        <p id="agent-engine-help" className="mb-4 text-sm text-soleur-text-secondary">
          Choose the default engine for new conversations and routine runs in this workspace.
          Codex is available only for qualified synthetic testing until rollout approval.
        </p>
        {status === "error" && <p role="alert" className="mb-3 text-sm text-red-400">{statusMessage || "Engine settings are unavailable."}</p>}
        {statusMessage && status !== "error" && <p role="status" aria-live="polite" className="mb-3 text-sm text-soleur-text-secondary">{statusMessage}</p>}
        <label htmlFor="agent-engine-select" className="block text-sm text-soleur-text-primary">
          <span className="mb-2 block font-medium">Agent engine</span>
          <select
            id="agent-engine-select"
            aria-describedby="agent-engine-help"
            value={selected}
            disabled={!isOwner || status === "loading" || status === "saving"}
            onChange={(event) => chooseEngine(event.target.value)}
            className="w-full rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            {engines.map((engine) => {
              const selectable = isEngineSelectable(engine);
              const availability = selectable
                ? engine.settingsSelectable && !engine.enabledForNewRuns
                  ? " · settings only; execution disabled"
                  : engine.qualificationOnly ? " · synthetic qualification only" : ""
                : " · coming soon";
              return (
                <option key={engine.id} value={engine.id} disabled={!selectable}>
                  {engineLabel(engine.id)}{availability}
                </option>
              );
            })}
          </select>
        </label>
        <p className="mt-2 text-xs text-soleur-text-secondary" data-testid="workspace-default-engine">
          Workspace default for new conversations: {engineLabel(workspaceDefaultEngineId)}
        </p>
        {selectedEngine?.authModes.length ? (
          <label className="mt-5 block text-sm text-soleur-text-primary">
            <span className="mb-2 block font-medium">Authentication mode</span>
            <select
              aria-label="Authentication mode"
              value={authMode}
              disabled={!isOwner || status === "loading" || status === "saving" || !isEngineSelectable(selectedEngine)}
              onChange={(event) => chooseAuthMode(event.target.value)}
              className="rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
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
                This uses the API key belonging to the member who resumes a conversation. A Codex mode change applies to existing Codex conversations in this workspace. Each member must acknowledge before their stored history is sent to OpenAI under their own account, which may incur provider charges. Previous Codex session data is cleared. Only submit data you are authorized to share with the provider.
              </p>
            )}
          </label>
        ) : null}
        {pendingAuthChange && (
          <div
            role="alertdialog"
            aria-labelledby="codex-auth-change-title"
            aria-describedby="codex-auth-change-description"
            className="mt-5 rounded-lg border border-amber-600/40 bg-amber-950/20 p-4"
          >
            <h3 id="codex-auth-change-title" className="font-medium">Change mode for existing Codex conversations?</h3>
            <p id="codex-auth-change-description" className="mt-2 text-sm text-soleur-text-secondary">
              This affects all Codex conversations in this workspace, including chats started by other members.
              The current selection will change {pendingAuthChange.affectedConversationCount} existing Codex conversation{pendingAuthChange.affectedConversationCount === 1 ? "" : "s"}.
              Their stored history will be sent under the selected provider account only after each member acknowledges.
              Each member uses their own credential and is responsible for provider charges. Old Codex recovery sessions are cleared.
            </p>
            <div className="mt-4 flex gap-3">
              <Button
                type="button"
                variant="gold"
                modal
                loading={status === "saving"}
                loadingLabel="Applying"
                onClick={() => void save(
                  selected,
                  pendingAuthChange.authMode,
                  pendingAuthChange.rollback,
                  true,
                  pendingAuthChange.affectedConversationCount,
                )}
                className="rounded-md px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                Apply to existing Codex conversations
              </Button>
              <Button
                type="button"
                variant="outlined"
                modal
                disabled={status === "saving"}
                onClick={() => setPendingAuthChange(null)}
                className="rounded-md px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                Cancel
              </Button>
            </div>
          </div>
        )}
        {!isOwner && <p className="mt-4 text-xs text-soleur-text-secondary">Only workspace owners can change this setting.</p>}
      </div>
    </section>
  );
}
