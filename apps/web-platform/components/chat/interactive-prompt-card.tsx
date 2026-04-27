"use client";

import React, { useState } from "react";
import type {
  InteractivePromptPayload,
  InteractivePromptResponsePayload,
  TodoItem,
} from "@/lib/types";
import { formatAssistantText } from "@/lib/format-assistant-text";

/**
 * Stage 4 (#2886) — InteractivePromptCard component.
 *
 * Renders all 6 `interactive_prompt.kind` variants at V1 minimal fidelity.
 * The wire payload is a discriminated union (`{ kind, payload }`); the card
 * narrows on `kind` with a `: never` exhaustiveness rail.
 *
 * Test hooks:
 *   - `data-prompt-kind` on the card root
 *   - `data-prompt-id` on the card root
 *
 * Security:
 *   - Three payload fields carry attacker-influenced strings (`bash_approval.
 *     command`, `diff.path`, `notebook_edit.notebookPath`). All are rendered
 *     as standard JSX text nodes (default React escaping). NO escape-hatch
 *     render APIs are used; the sentinel grep `rg "danger|innerHTML|__html"`
 *     in Phase 6 enforces this.
 *
 * V1 → V2 follow-ups tracked as separate GitHub issues (review F23 #2886):
 *   each deferred capability has a `deferred-scope-out` issue milestoned
 *   to "Post-MVP / Later". See PR #2925 review summary for the issue list.
 */

/**
 * Review F14 (#2886): per-kind past-tense verb maps so the rendered
 * "selected" footers don't string-interpolate into ungrammatical results
 * like "Plan iterateed" (double-e from "iterate" + "ed") or "Bash ackd".
 * Discriminated maps are exhaustive at compile time.
 */
const PLAN_PREVIEW_VERB: Record<"accept" | "iterate", string> = {
  accept: "accepted",
  iterate: "iterated",
};
const BASH_APPROVAL_VERB: Record<"approve" | "deny", string> = {
  approve: "approved",
  deny: "denied",
};

interface InteractivePromptCardPropsBase {
  promptId: string;
  conversationId: string;
  resolved?: boolean;
  selectedResponse?: InteractivePromptResponsePayload["response"];
  onRespond: (response: InteractivePromptResponsePayload) => void;
}

// Discriminated props that match `InteractivePromptPayload`'s `{kind,payload}`.
type InteractivePromptCardProps = InteractivePromptCardPropsBase &
  InteractivePromptPayload;

export function InteractivePromptCard(props: InteractivePromptCardProps) {
  const baseClass =
    "rounded-xl border border-neutral-800 bg-neutral-900/60 px-4 py-3";
  const disabled = props.resolved === true;

  switch (props.kind) {
    case "ask_user":
      return (
        <AskUserCard {...props} kind="ask_user" disabled={disabled} baseClass={baseClass} />
      );
    case "plan_preview":
      return (
        <PlanPreviewCard {...props} kind="plan_preview" disabled={disabled} baseClass={baseClass} />
      );
    case "diff":
      return (
        <DiffCard {...props} kind="diff" disabled={disabled} baseClass={baseClass} />
      );
    case "bash_approval":
      return (
        <BashApprovalCard {...props} kind="bash_approval" disabled={disabled} baseClass={baseClass} />
      );
    case "todo_write":
      return (
        <TodoWriteCard {...props} kind="todo_write" disabled={disabled} baseClass={baseClass} />
      );
    case "notebook_edit":
      return (
        <NotebookEditCard {...props} kind="notebook_edit" disabled={disabled} baseClass={baseClass} />
      );
    default: {
      // Compile-time exhaustiveness rail.
      const _exhaustive: never = props;
      void _exhaustive;
      return null;
    }
  }
}

interface VariantProps<K extends InteractivePromptPayload["kind"], P>
  extends InteractivePromptCardPropsBase {
  kind: K;
  payload: P;
  disabled: boolean;
  baseClass: string;
}

function CardShell({
  promptId,
  kind,
  children,
}: {
  promptId: string;
  kind: InteractivePromptPayload["kind"];
  children: React.ReactNode;
}) {
  return (
    <div data-prompt-kind={kind} data-prompt-id={promptId}>
      {children}
    </div>
  );
}

// ---------------------------------------------------------------------------
// ask_user
// ---------------------------------------------------------------------------

function AskUserCard({
  promptId,
  payload,
  disabled,
  baseClass,
  onRespond,
  selectedResponse,
}: VariantProps<"ask_user", { question: string; options: string[]; multiSelect: boolean }>) {
  // Review F17 (#2886): hydrate `picked` from `selectedResponse` so a
  // resolved multi-select prompt renders with the previously-selected
  // checkboxes ticked. Otherwise checkboxes appear unchecked while the
  // "Selected: …" footer shows the real values — split-brain UI.
  const [picked, setPicked] = useState<string[]>(() =>
    Array.isArray(selectedResponse) ? selectedResponse : [],
  );

  if (payload.multiSelect) {
    const toggle = (opt: string) =>
      setPicked((prev) =>
        prev.includes(opt) ? prev.filter((o) => o !== opt) : [...prev, opt],
      );
    return (
      <CardShell promptId={promptId} kind="ask_user">
        <div className={baseClass}>
          <p className="mb-2 text-sm text-neutral-200">{payload.question}</p>
          <div className="flex flex-col gap-1.5">
            {payload.options.map((opt) => (
              <label key={opt} className="flex items-center gap-2 text-sm text-neutral-300">
                <input
                  type="checkbox"
                  aria-label={opt}
                  checked={picked.includes(opt)}
                  disabled={disabled}
                  onChange={() => toggle(opt)}
                />
                <span>{opt}</span>
              </label>
            ))}
          </div>
          <button
            type="button"
            disabled={disabled}
            onClick={() =>
              onRespond({ kind: "ask_user", response: picked })
            }
            className="mt-3 rounded-md bg-amber-600 px-3 py-1 text-sm text-white disabled:opacity-50"
          >
            Submit
          </button>
          {disabled && selectedResponse !== undefined ? (
            <p className="mt-2 text-xs text-neutral-500">
              Selected: {Array.isArray(selectedResponse) ? selectedResponse.join(", ") : String(selectedResponse)}
            </p>
          ) : null}
        </div>
      </CardShell>
    );
  }

  // Single-select chip selector.
  return (
    <CardShell promptId={promptId} kind="ask_user">
      <div className={baseClass}>
        <p className="mb-2 text-sm text-neutral-200">{payload.question}</p>
        <div className="flex flex-wrap gap-2">
          {payload.options.map((opt) => (
            <button
              key={opt}
              type="button"
              disabled={disabled}
              onClick={() => onRespond({ kind: "ask_user", response: opt })}
              className="rounded-full border border-neutral-700 px-3 py-1 text-xs text-neutral-200 hover:border-amber-500 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {opt}
            </button>
          ))}
        </div>
        {disabled && selectedResponse !== undefined ? (
          <p className="mt-2 text-xs text-neutral-500">Selected: {String(selectedResponse)}</p>
        ) : null}
      </div>
    </CardShell>
  );
}

// ---------------------------------------------------------------------------
// plan_preview
// ---------------------------------------------------------------------------

function PlanPreviewCard({
  promptId,
  payload,
  disabled,
  baseClass,
  onRespond,
  selectedResponse,
}: VariantProps<"plan_preview", { markdown: string }>) {
  // V1 falls back to formatAssistantText (preserves code fences + line breaks).
  // Full markdown rendering is V2.
  const text = formatAssistantText(payload.markdown);
  return (
    <CardShell promptId={promptId} kind="plan_preview">
      <div className={baseClass}>
        <pre className="mb-3 max-h-64 overflow-auto whitespace-pre-wrap text-sm text-neutral-200">
          {text}
        </pre>
        <div className="flex gap-2">
          <button
            type="button"
            disabled={disabled}
            onClick={() => onRespond({ kind: "plan_preview", response: "accept" })}
            className="rounded-md bg-amber-600 px-3 py-1 text-sm text-white disabled:opacity-50"
          >
            Accept
          </button>
          <button
            type="button"
            disabled={disabled}
            onClick={() => onRespond({ kind: "plan_preview", response: "iterate" })}
            className="rounded-md border border-neutral-700 px-3 py-1 text-sm text-neutral-200 disabled:opacity-50"
          >
            Iterate
          </button>
        </div>
        {disabled && selectedResponse !== undefined ? (
          <p className="mt-2 text-xs text-neutral-500">
            {(() => {
              const sel = selectedResponse as "accept" | "iterate";
              return `Plan ${PLAN_PREVIEW_VERB[sel] ?? String(sel)}`;
            })()}
          </p>
        ) : null}
      </div>
    </CardShell>
  );
}

// ---------------------------------------------------------------------------
// diff
// ---------------------------------------------------------------------------

function DiffCard({
  promptId,
  payload,
  disabled,
  baseClass,
  onRespond,
  selectedResponse,
}: VariantProps<"diff", { path: string; additions: number; deletions: number }>) {
  return (
    <CardShell promptId={promptId} kind="diff">
      <div className={baseClass}>
        <p className="mb-2 text-sm text-neutral-200">
          Edited file <code className="rounded bg-neutral-800 px-1 py-0.5 text-xs">{payload.path}</code>{" "}
          <span className="text-emerald-400">+{payload.additions}</span>{" "}
          <span className="text-red-400">-{payload.deletions}</span>
        </p>
        <button
          type="button"
          disabled={disabled}
          onClick={() => onRespond({ kind: "diff", response: "ack" })}
          className="rounded-md border border-neutral-700 px-3 py-1 text-sm text-neutral-200 disabled:opacity-50"
        >
          Acknowledge
        </button>
        {disabled && selectedResponse !== undefined ? (
          <p className="mt-2 text-xs text-neutral-500">Acknowledged</p>
        ) : null}
      </div>
    </CardShell>
  );
}

// ---------------------------------------------------------------------------
// bash_approval
// ---------------------------------------------------------------------------

function BashApprovalCard({
  promptId,
  payload,
  disabled,
  baseClass,
  onRespond,
  selectedResponse,
}: VariantProps<"bash_approval", { command: string; cwd: string; gated: boolean }>) {
  return (
    <CardShell promptId={promptId} kind="bash_approval">
      <div className={baseClass}>
        <pre className="mb-2 overflow-auto rounded bg-neutral-950 p-2 text-xs text-neutral-200">
          {/* Default React text-node escaping handles HTML-special chars in
              attacker-influenced `payload.command`. NO escape-hatch render APIs. */}
          {payload.command}
        </pre>
        <p className="mb-3 text-xs text-neutral-500">cwd: {payload.cwd}</p>
        {payload.gated ? (
          <div className="flex gap-2">
            <button
              type="button"
              disabled={disabled}
              onClick={() => onRespond({ kind: "bash_approval", response: "approve" })}
              className="rounded-md bg-amber-600 px-3 py-1 text-sm text-white disabled:opacity-50"
            >
              Approve
            </button>
            <button
              type="button"
              disabled={disabled}
              onClick={() => onRespond({ kind: "bash_approval", response: "deny" })}
              className="rounded-md border border-red-600/60 px-3 py-1 text-sm text-red-400 disabled:opacity-50"
            >
              Deny
            </button>
          </div>
        ) : null}
        {disabled && selectedResponse !== undefined ? (
          <p className="mt-2 text-xs text-neutral-500">
            {(() => {
              const sel = selectedResponse as "approve" | "deny";
              return BASH_APPROVAL_VERB[sel] ?? String(sel);
            })()}
          </p>
        ) : null}
      </div>
    </CardShell>
  );
}

// ---------------------------------------------------------------------------
// todo_write
// ---------------------------------------------------------------------------

function TodoWriteCard({
  promptId,
  payload,
  disabled,
  baseClass,
  onRespond,
  selectedResponse,
}: VariantProps<"todo_write", { items: TodoItem[] }>) {
  return (
    <CardShell promptId={promptId} kind="todo_write">
      <div className={baseClass}>
        <p className="mb-2 text-sm text-neutral-200">{payload.items.length} todos</p>
        <ul className="mb-3 space-y-1">
          {payload.items.map((it) => (
            <li key={it.id} className="flex items-center gap-2 text-xs text-neutral-300">
              <span className="rounded bg-neutral-800 px-1.5 py-0.5 text-[10px] text-neutral-400">
                {it.status}
              </span>
              <span className="truncate">{it.content}</span>
            </li>
          ))}
        </ul>
        <button
          type="button"
          disabled={disabled}
          onClick={() => onRespond({ kind: "todo_write", response: "ack" })}
          className="rounded-md border border-neutral-700 px-3 py-1 text-sm text-neutral-200 disabled:opacity-50"
        >
          Acknowledge
        </button>
        {disabled && selectedResponse !== undefined ? (
          <p className="mt-2 text-xs text-neutral-500">Acknowledged</p>
        ) : null}
      </div>
    </CardShell>
  );
}

// ---------------------------------------------------------------------------
// notebook_edit
// ---------------------------------------------------------------------------

function NotebookEditCard({
  promptId,
  payload,
  disabled,
  baseClass,
  onRespond,
  selectedResponse,
}: VariantProps<"notebook_edit", { notebookPath: string; cellIds: string[] }>) {
  return (
    <CardShell promptId={promptId} kind="notebook_edit">
      <div className={baseClass}>
        <p className="mb-2 text-sm text-neutral-200">
          {payload.cellIds.length} cells in <code className="rounded bg-neutral-800 px-1 py-0.5 text-xs">{payload.notebookPath}</code>
        </p>
        <div className="mb-3 flex flex-wrap gap-1">
          {payload.cellIds.map((cid) => (
            <span key={cid} className="rounded-full bg-neutral-800 px-2 py-0.5 text-[10px] text-neutral-300">
              {cid}
            </span>
          ))}
        </div>
        <button
          type="button"
          disabled={disabled}
          onClick={() => onRespond({ kind: "notebook_edit", response: "ack" })}
          className="rounded-md border border-neutral-700 px-3 py-1 text-sm text-neutral-200 disabled:opacity-50"
        >
          Acknowledge
        </button>
        {disabled && selectedResponse !== undefined ? (
          <p className="mt-2 text-xs text-neutral-500">Acknowledged</p>
        ) : null}
      </div>
    </CardShell>
  );
}
