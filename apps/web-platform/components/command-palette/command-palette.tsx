"use client";

// feat-web-app-shortcuts — the ⌘K command palette (FR1–FR3, FR6). Renders from
// the central registry (buildCommands) for static groups and lazily fetches the
// dense async groups (KB doc search + routines) on first open. cmdk's
// Command.Dialog composes Radix Dialog, so focus trap / restoration / background
// inert are free for the base case (no hand-rolled activeElement capture). The
// one explicit nested-focus case is the 409 confirm modal layered above the
// palette (Phase 3). Routine "Run" is intentionally STRICTER than
// routines-surface.tsx: it surfaces non-409 failures inline + to Sentry.

import { Command } from "cmdk";
import { useCallback, useEffect, useRef, useState } from "react";
import { useShortcuts, buildCommands, type Command as Cmd } from "./use-shortcuts";
import { reportSilentFallback } from "@/lib/client-observability";

// Mirrors the routines route payload (routines-surface.tsx). Only the fields the
// palette disambiguates on (FR3): domain + scheduleLabel + lastRun + the
// protected gate.
interface RunSummary {
  status: string;
  started_at: string;
}
interface RoutineItem {
  fnId: string;
  description: string;
  domain: string;
  ownerRole: string;
  scheduleLabel: string;
  manualTrigger: "allowed" | "confirm";
  lastRun: RunSummary | null;
}

// Mirrors server/kb-reader.ts TreeNode.
interface TreeNode {
  name: string;
  type: "directory" | "file";
  path?: string;
  children?: TreeNode[];
}
interface KbDoc {
  path: string;
  name: string;
}

function humanizeFnId(fnId: string): string {
  const s = fnId.replace(/^cron-/, "").replace(/-/g, " ");
  return s.charAt(0).toUpperCase() + s.slice(1);
}

// Flatten the KB tree to navigable file leaves (depth-first). Directories carry
// no `path`; only files do — and only files are navigable to /dashboard/kb/<path>.
function flattenDocs(nodes: TreeNode[] | undefined, out: KbDoc[] = []): KbDoc[] {
  for (const n of nodes ?? []) {
    if (n.type === "file" && n.path) out.push({ path: n.path, name: n.name });
    if (n.children) flattenDocs(n.children, out);
  }
  return out;
}

type AsyncState =
  | { phase: "idle" }
  | { phase: "loading" }
  | { phase: "ready" }
  | { phase: "error" }
  | { phase: "needsReconnect" };

export function CommandPalette() {
  const { enabled, paletteOpen, closePalette, isAdmin, runEffect } =
    useShortcuts();

  const [query, setQuery] = useState("");
  const [docs, setDocs] = useState<KbDoc[]>([]);
  const [kbState, setKbState] = useState<AsyncState>({ phase: "idle" });
  const [routines, setRoutines] = useState<RoutineItem[]>([]);
  const [routinesState, setRoutinesState] = useState<AsyncState>({
    phase: "idle",
  });
  // Routine run feedback, keyed by fnId.
  const [busyFnId, setBusyFnId] = useState<string | null>(null);
  const [confirming, setConfirming] = useState<RoutineItem | null>(null);
  const [runError, setRunError] = useState<{ fnId: string; msg: string } | null>(
    null,
  );

  const mountedRef = useRef(true);
  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  // Lazy fetch on first open (not prefetched). Static groups render immediately
  // regardless; a KB/routines failure never breaks Navigation/Ask-an-agent.
  useEffect(() => {
    if (!paletteOpen) return;
    if (kbState.phase === "idle") {
      setKbState({ phase: "loading" });
      void (async () => {
        try {
          const res = await fetch("/api/kb/tree");
          if (!res.ok) {
            if (mountedRef.current) setKbState({ phase: "error" });
            return;
          }
          const json = (await res.json()) as {
            tree?: TreeNode;
            needsReconnect?: boolean;
          };
          if (!mountedRef.current) return;
          if (json.needsReconnect) {
            setKbState({ phase: "needsReconnect" });
            return;
          }
          setDocs(flattenDocs(json.tree?.children));
          setKbState({ phase: "ready" });
        } catch {
          if (mountedRef.current) setKbState({ phase: "error" });
        }
      })();
    }
    if (routinesState.phase === "idle") {
      setRoutinesState({ phase: "loading" });
      void (async () => {
        try {
          const res = await fetch("/api/dashboard/routines");
          if (!res.ok) {
            if (mountedRef.current) setRoutinesState({ phase: "error" });
            return;
          }
          const json = (await res.json()) as { routines: RoutineItem[] };
          if (!mountedRef.current) return;
          setRoutines(json.routines ?? []);
          setRoutinesState({ phase: "ready" });
        } catch {
          if (mountedRef.current) setRoutinesState({ phase: "error" });
        }
      })();
    }
  }, [paletteOpen, kbState.phase, routinesState.phase]);

  const runRoutine = useCallback(
    async (item: RoutineItem, confirmed: boolean) => {
      setBusyFnId(item.fnId);
      setRunError(null);
      try {
        const res = await fetch("/api/dashboard/routines/run", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ fnId: item.fnId, confirmed }),
        });
        if (res.status === 409) {
          setConfirming(item); // protected — confirm modal layered above palette
          return;
        }
        if (res.status === 202) {
          setConfirming(null);
          setRunError(null);
          return;
        }
        // Any other status (400/502/…) — surface inline AND to Sentry. This is
        // the deliberate strictness vs routines-surface.tsx (which swallows
        // non-409). The route already mirrors 502 server-side; this captures the
        // CLIENT-observed failure with the fnId tag.
        let code = `HTTP ${res.status}`;
        try {
          const body = (await res.json()) as { error?: string };
          if (body.error) code = body.error;
        } catch {
          /* non-JSON error body — keep the status code */
        }
        reportSilentFallback(new Error(`routine dispatch failed: ${code}`), {
          feature: "command-palette.run-routine",
          extra: { fnId: item.fnId, status: res.status },
        });
        if (mountedRef.current)
          setRunError({ fnId: item.fnId, msg: "Failed to run routine" });
      } catch (err) {
        reportSilentFallback(err, {
          feature: "command-palette.run-routine",
          extra: { fnId: item.fnId },
        });
        if (mountedRef.current)
          setRunError({ fnId: item.fnId, msg: "Failed to run routine" });
      } finally {
        if (mountedRef.current) setBusyFnId(null);
      }
    },
    [],
  );

  if (!enabled) return null;

  const statics = buildCommands({ isAdmin });
  const navCmds = statics.filter((c) => c.group === "Navigation");
  const askCmd = statics.find((c) => c.id === "ask-agent");
  const generalCmds = statics.filter((c) => c.group === "General");
  const trimmed = query.trim();

  function onSelectCommand(cmd: Cmd) {
    runEffect(cmd.run());
  }

  return (
    <>
      <Command.Dialog
        open={paletteOpen}
        onOpenChange={(open) => {
          if (!open) {
            closePalette();
            setQuery("");
            setRunError(null);
            // Let a transient KB/routines failure retry on the next open while
            // keeping a successful fetch cached (don't re-hit the API needlessly).
            setKbState((s) =>
              s.phase === "error" || s.phase === "needsReconnect"
                ? { phase: "idle" }
                : s,
            );
            setRoutinesState((s) =>
              s.phase === "error" ? { phase: "idle" } : s,
            );
          }
        }}
        label="Command palette"
        // cmdk's built-in fuzzy filter across every item's value (FR2).
        loop
      >
        <Command.Input
          placeholder="Search commands, docs, routines…"
          value={query}
          onValueChange={setQuery}
          aria-label="Command palette search"
        />
        <Command.List>
          <Command.Empty>
            <div className="cmdk-empty">
              No results for “{trimmed}”
            </div>
          </Command.Empty>

          {/* Ask an agent — the hero verb. Always present as a fallback so a
              dead-end query becomes the differentiating action (FR6/AC5). */}
          {askCmd && (
            <Command.Group heading="Ask an agent">
              <Command.Item
                value={trimmed ? `ask agent ${trimmed}` : "ask an agent"}
                onSelect={() =>
                  runEffect({
                    kind: "openChat",
                    query: trimmed || undefined,
                  })
                }
                data-testid="cmd-ask-agent"
              >
                {trimmed ? `Ask an agent about “${trimmed}”` : askCmd.label}
              </Command.Item>
            </Command.Group>
          )}

          <Command.Group heading="Navigation">
            {navCmds.map((cmd) => (
              <Command.Item
                key={cmd.id}
                value={cmd.label}
                onSelect={() => onSelectCommand(cmd)}
              >
                {cmd.label}
              </Command.Item>
            ))}
          </Command.Group>

          <Command.Group heading="Knowledge Base">
            {kbState.phase === "loading" && (
              <Command.Loading>Searching…</Command.Loading>
            )}
            {kbState.phase === "needsReconnect" && (
              <Command.Item
                value="reconnect knowledge base"
                onSelect={() => runEffect({ kind: "navigate", href: "/dashboard/settings/services" })}
                data-testid="cmd-kb-reconnect"
              >
                Reconnect KB to search docs
              </Command.Item>
            )}
            {kbState.phase === "error" && (
              <Command.Item value="kb unavailable" disabled data-testid="cmd-kb-error">
                KB search temporarily unavailable
              </Command.Item>
            )}
            {kbState.phase === "ready" &&
              docs.map((doc) => (
                <Command.Item
                  key={doc.path}
                  value={`${doc.name} ${doc.path}`}
                  onSelect={() =>
                    runEffect({ kind: "navigate", href: `/dashboard/kb/${doc.path}` })
                  }
                >
                  {doc.name}
                </Command.Item>
              ))}
          </Command.Group>

          <Command.Group heading="Workflows">
            {routinesState.phase === "loading" && (
              <Command.Loading>Searching…</Command.Loading>
            )}
            {routinesState.phase === "error" && (
              <Command.Item value="routines unavailable" disabled data-testid="cmd-routines-error">
                Workflows temporarily unavailable
              </Command.Item>
            )}
            {routinesState.phase === "ready" &&
              routines.map((item) => (
                <Command.Item
                  key={item.fnId}
                  // Disambiguating context lives in the value so cmdk filters on
                  // it AND it reads in the row (FR3 misfire-resistance).
                  value={`run routine ${humanizeFnId(item.fnId)} ${item.domain} ${item.scheduleLabel}`}
                  onSelect={() => void runRoutine(item, false)}
                  data-testid={`cmd-run-${item.fnId}`}
                >
                  <span className="cmdk-routine-row">
                    <span>Run routine: {humanizeFnId(item.fnId)}</span>
                    <span className="cmdk-routine-meta">
                      {item.domain} · {item.scheduleLabel}
                      {item.lastRun ? ` · last ${item.lastRun.status}` : " · never run"}
                      {item.manualTrigger === "confirm" ? " · ⚠ protected" : ""}
                    </span>
                  </span>
                  {busyFnId === item.fnId && (
                    <span className="cmdk-routine-busy"> running…</span>
                  )}
                  {runError?.fnId === item.fnId && (
                    <span
                      className="cmdk-routine-error"
                      role="alert"
                      data-testid={`cmd-run-error-${item.fnId}`}
                    >
                      {" "}
                      {runError.msg}
                    </span>
                  )}
                </Command.Item>
              ))}
          </Command.Group>

          <Command.Group heading="General">
            {generalCmds.map((cmd) => (
              <Command.Item
                key={cmd.id}
                value={`${cmd.label} ${cmd.keys ?? ""}`}
                onSelect={() => onSelectCommand(cmd)}
              >
                {cmd.label}
                {cmd.keys && <span className="cmdk-keys"> {cmd.keys}</span>}
              </Command.Item>
            ))}
          </Command.Group>
        </Command.List>
      </Command.Dialog>

      {/* 409 confirm modal — layered ABOVE the open palette (Phase 3). A plain
          fixed overlay; the confirm button auto-focuses so keyboard confirm
          works and the nested-focus AC is satisfiable. */}
      {confirming && (
        <ConfirmRunModal
          item={confirming}
          busy={busyFnId === confirming.fnId}
          onCancel={() => setConfirming(null)}
          onConfirm={() => void runRoutine(confirming, true)}
        />
      )}
    </>
  );
}

function ConfirmRunModal({
  item,
  busy,
  onCancel,
  onConfirm,
}: {
  item: RoutineItem;
  busy: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const confirmRef = useRef<HTMLButtonElement | null>(null);
  useEffect(() => {
    confirmRef.current?.focus();
  }, []);
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Run protected routine"
      data-testid="cmd-confirm-modal"
      className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 p-4"
      onKeyDown={(e) => {
        if (e.key === "Escape") {
          e.stopPropagation();
          onCancel();
        }
      }}
    >
      <div className="w-full max-w-md rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-5">
        <h3 className="flex items-center gap-2 text-sm font-medium text-soleur-text-primary">
          <span className="text-amber-400">⚠</span> Run protected routine now?
        </h3>
        <p className="mt-1 text-xs text-soleur-text-secondary">
          {humanizeFnId(item.fnId)} is protected. Off-schedule manual runs
          require confirmation. This runs REAL production work and is logged to
          the audit ledger under your operator identity.
        </p>
        <div className="mt-4 flex justify-end gap-2">
          <button
            onClick={onCancel}
            className="rounded border border-soleur-border-default px-3 py-1.5 text-xs text-soleur-text-secondary hover:bg-soleur-bg-surface-2"
          >
            Cancel
          </button>
          <button
            ref={confirmRef}
            onClick={onConfirm}
            disabled={busy}
            data-testid="cmd-confirm-run"
            className="rounded bg-amber-500 px-3 py-1.5 text-xs font-medium text-black hover:bg-amber-400 disabled:opacity-50"
          >
            {busy ? "Running…" : "▷ Run now"}
          </button>
        </div>
      </div>
    </div>
  );
}
