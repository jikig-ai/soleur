"use client";

import React, { memo } from "react";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { LEADER_COLORS } from "@/components/chat/leader-colors";
import { LeaderAvatar } from "@/components/leader-avatar";
import { AttachmentDisplay } from "@/components/chat/attachment-display";
import type { AttachmentRef, MessageState } from "@/lib/types";
import { formatAssistantText } from "@/lib/format-assistant-text";
import { reportSilentFallback } from "@/lib/client-observability";

export function ThinkingDots() {
  return (
    <div className="flex items-center gap-1.5 py-1" data-testid="thinking-dots">
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-soleur-text-secondary" style={{ animationDelay: "0ms" }} />
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-soleur-text-secondary" style={{ animationDelay: "150ms" }} />
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-soleur-text-secondary" style={{ animationDelay: "300ms" }} />
    </div>
  );
}

export function ToolStatusChip({ label }: { label: string }) {
  return (
    <div className="flex items-center gap-2 py-0.5" data-testid="tool-status-chip">
      <span className="text-sm text-soleur-text-secondary">{label}</span>
    </div>
  );
}

/**
 * FR5 (#2861): rendered on a `tool_use` bubble that has `retrying: true`.
 * `aria-live="polite"` announces the transition to screen-reader users.
 * The last-known activity label is shown below so the user sees *what* is
 * being retried, not just a generic spinner.
 */
export function RetryingChip({ label }: { label: string | undefined }) {
  return (
    <div
      className="flex flex-col gap-1 py-0.5"
      role="status"
      aria-live="polite"
      data-testid="retrying-chip"
    >
      <div className="flex items-center gap-2">
        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-amber-400" />
        <span className="text-sm font-medium text-amber-400">Retrying…</span>
      </div>
      {label ? (
        <span className="text-xs text-soleur-text-muted">{label}</span>
      ) : null}
    </div>
  );
}

/** #3448 PR2 — abort-marker payload, mirrors the `usage` jsonb persisted on
 *  `messages` rows whose `status === 'aborted'`. The shape is documented in
 *  migration 040 and `lib/types.ts:Message.usage`.
 *
 *  #3603 W4 — fields widened to optional so the cc-narrowed `{ cost_usd }`
 *  shape (cc-router aborted rows under `CC_PERSIST_USAGE=true`) renders as a
 *  cost-only marker without producing `NaN` from `input_tokens +
 *  output_tokens`.
 *
 *  #3640 F6 — `variant` discriminates the two persistence shapes so
 *  readers can switch on `variant` instead of doing `typeof === "number"`
 *  field-presence checks. Optional during the F6 transition (readers
 *  treat `undefined` as `"legacy"`); derived at hydration from
 *  `leader_id === CC_ROUTER_LEADER_ID`. */
export interface AbortMarkerUsage {
  variant?: "legacy" | "cc";
  input_tokens?: number;
  output_tokens?: number;
  cost_usd?: number | null;
  completed_actions?: Array<{
    tool_name: string;
    input_summary: string;
    result_summary: string;
  }>;
}

// Wrapped in React.memo so token streaming (10-50 Hz) doesn't re-render every
// bubble in a long thread. `getDisplayName`/`getIconPath` are already
// `useCallback`-stable in `use-team-names.tsx`; other props are primitives or
// references that only change for the active bubble. See #2137.
export const MessageBubble = memo(function MessageBubble({
  role,
  content,
  leaderId,
  showFullTitle = false,
  messageState,
  toolLabel,
  toolsUsed,
  retrying = false,
  getDisplayName,
  getIconPath,
  attachments,
  variant = "full",
  status,
  usage,
}: {
  role: "user" | "assistant";
  content: string;
  leaderId?: DomainLeaderId;
  showFullTitle?: boolean;
  messageState?: MessageState;
  toolLabel?: string;
  toolsUsed?: string[];
  /** FR5 (#2861): when true, show the "Retrying…" chip on tool_use bubbles. */
  retrying?: boolean;
  getDisplayName?: (id: DomainLeaderId) => string;
  getIconPath?: (id: DomainLeaderId) => string | null;
  attachments?: AttachmentRef[];
  variant?: "full" | "sidebar";
  /** #3448 PR2: persistence-tier discriminator for the abort marker.
   *  `"aborted"` swaps the inner content for a marker block (partial text,
   *  `[stopped by user]` chip, token cost, completed-actions chip-list).
   *  `"complete"` / undefined uses the existing render path. */
  status?: "complete" | "aborted";
  /** #3448 PR2: aborted-turn snapshot. Required when `status === "aborted"`;
   *  ignored otherwise. */
  usage?: AbortMarkerUsage | null;
  // Review F5 (#2886): the `parentId` prop, the `ml-6` indentClass, and the
  // `data-parent-id` attribute were removed — they had no production caller.
  // SubagentGroup renders its child rows directly with their own indentation
  // and `data-child-spawn-id` test hooks.
}) {
  const isUser = role === "user";
  const leader = leaderId ? DOMAIN_LEADERS.find((l) => l.id === leaderId) : null;
  const colorClass = leaderId ? (LEADER_COLORS[leaderId] ?? "border-l-neutral-500") : "";
  const displayName = leaderId && getDisplayName ? getDisplayName(leaderId) : leader?.name;
  const customIconPath = leaderId && getIconPath ? getIconPath(leaderId) : null;
  // Bug 2 (#3225): when displayName is contained in leader.title (cc_router
  // "Concierge"/"Soleur Concierge", system "System"/"System Process"),
  // promote the title into the always-rendered first span and suppress the
  // secondary showFullTitle span. Otherwise the header rendered both
  // side-by-side on first bubbles and bare displayName on follow-ups.
  const titleContainsName =
    !!leader && !!displayName && leader.title.includes(displayName);
  const headerPrimary = leader && titleContainsName ? leader.title : displayName;

  const isActive = messageState === "thinking" || messageState === "tool_use" || messageState === "streaming";
  const isError = messageState === "error";
  const isDone = messageState === "done";

  const borderStyle = isError
    ? "border-2 border-red-900/60"
    : isActive
      ? "message-bubble-active border-2 border-amber-600/70"
      : isDone
        ? "border border-soleur-border-default/60"
        : "border border-soleur-border-default";

  return (
    <div
      className={`flex min-w-0 ${isUser ? "justify-end" : "justify-start"}`}
    >
      <div className={`flex min-w-0 max-w-[90%] gap-3 md:max-w-[80%] ${isUser ? "flex-row-reverse" : ""}`}>
        {leader && (
          <LeaderAvatar leaderId={leaderId!} size="md" className="mt-1" customIconPath={customIconPath} />
        )}

        <div
          className={`relative min-w-0 rounded-xl px-4 py-3 text-sm leading-relaxed ${
            isUser
              ? "bg-soleur-bg-surface-2 text-soleur-text-primary"
              : `bg-soleur-bg-surface-1 text-soleur-text-primary ${borderStyle} ${leader && !isActive && !isError ? `border-l-2 ${colorClass}` : ""}`
          }`}
        >
          {(messageState === "tool_use" || messageState === "streaming") && (
            <span className="absolute -top-2.5 right-3 rounded-full border border-amber-700/50 bg-soleur-bg-surface-1 px-2 py-0.5 text-[10px] font-medium text-amber-500">
              {messageState === "tool_use" ? "Working" : "Streaming"}
            </span>
          )}

          {isDone && role === "assistant" && (
            <span
              className="absolute -top-2.5 right-3 flex h-5 w-5 items-center justify-center rounded-full bg-soleur-bg-surface-1 text-amber-600"
              aria-label="Response complete"
            >
              <svg width="12" height="12" viewBox="0 0 12 12" fill="none" aria-hidden="true">
                <path d="M2 6.5L4.5 9L10 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
          )}

          {leader && (
            <div
              className="mb-1 flex items-center gap-2"
              data-testid="message-bubble-header"
            >
              <span className="text-xs font-semibold text-soleur-text-secondary">
                {headerPrimary}
              </span>
              {showFullTitle && !titleContainsName && (
                <span className="text-xs text-soleur-text-muted">{leader.title}</span>
              )}
            </div>
          )}

          {status === "aborted" && role === "assistant"
            ? renderAbortedAssistant({ content, usage, variant })
            : renderBubbleContent({ isUser, messageState, content, toolLabel, toolsUsed, retrying, isDone, variant })}

          {attachments && attachments.length > 0 && (
            <AttachmentDisplay attachments={attachments} />
          )}
        </div>
      </div>
    </div>
  );
});

/** Render the inner content of a MessageBubble based on its state. Extracted
 *  to collapse the previous 7-branch ternary chain into a readable switch.
 *  User bubbles render through MarkdownRenderer so sent blockquotes render
 *  as blockquotes (not raw `>` text) — spec TR for kb-chat-sidebar. See #2139.
 */
function renderBubbleContent({
  isUser,
  messageState,
  content,
  toolLabel,
  toolsUsed,
  retrying,
  isDone,
  variant,
}: {
  isUser: boolean;
  messageState: MessageState | undefined;
  content: string;
  toolLabel: string | undefined;
  toolsUsed: string[] | undefined;
  retrying: boolean;
  isDone: boolean;
  variant: "full" | "sidebar";
}): React.ReactNode {
  const wrapCode = variant === "sidebar";
  if (isUser) {
    return (
      <div className="min-w-0 [overflow-wrap:anywhere]">
        <MarkdownRenderer content={content} wrapCode={wrapCode} />
      </div>
    );
  }

  // FR3 (#2861): render-time scrub for assistant-role bubbles only. Stored
  // content stays verbatim. `reportFallthrough` mirrors to Sentry when a
  // `/workspaces/` or `/tmp/claude-` shape survives the canonical pattern
  // table — this is the success metric for FR2+FR3.
  const scrubbedContent = formatAssistantText(content, {
    reportFallthrough: (shape) =>
      reportSilentFallback(null, {
        feature: "command-center",
        op: "asstext-scrub-fallthrough",
        extra: { shape },
      }),
  });

  switch (messageState) {
    case "thinking":
      return <ThinkingDots />;
    case "tool_use":
      if (retrying) return <RetryingChip label={toolLabel} />;
      return toolLabel ? <ToolStatusChip label={toolLabel} /> : <ThinkingDots />;
    case "streaming":
      return (
        <p className="min-w-0 whitespace-pre-wrap [overflow-wrap:anywhere]">
          {scrubbedContent}
          <span className="animate-pulse text-amber-500">&#x258C;</span>
        </p>
      );
    case "error":
      // FR5 (#2861): show the last known activity label + File-issue link.
      return (
        <div className="flex flex-col gap-2 text-red-400">
          <div className="flex items-center gap-2">
            <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
              <circle cx="7" cy="7" r="6" stroke="currentColor" strokeWidth="1.2" />
              <path d="M7 4v3.5M7 9.5v.01" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
            </svg>
            <span className="text-sm">
              Agent stopped responding after: {toolLabel ?? "Working"}
            </span>
          </div>
          <a
            href="https://github.com/jikig-ai/soleur/issues/new?labels=type%2Fbug&template=bug_report.md"
            target="_blank"
            rel="noopener noreferrer"
            className="text-xs text-soleur-text-muted underline hover:text-soleur-text-secondary"
            data-testid="file-issue-link"
          >
            File an issue
          </a>
        </div>
      );
    case "done":
      if (content === "" && toolsUsed && toolsUsed.length > 0) {
        return (
          <div className="flex items-center gap-1.5 text-xs text-soleur-text-muted">
            <span>Used:</span>
            {toolsUsed.map((t, i) => (
              <span key={i} className="rounded bg-soleur-bg-surface-2 px-1.5 py-0.5">
                {t}
              </span>
            ))}
          </div>
        );
      }
      return <MarkdownRenderer content={scrubbedContent} wrapCode={wrapCode} />;
    default:
      void isDone;
      return <MarkdownRenderer content={scrubbedContent} wrapCode={wrapCode} />;
  }
}

/**
 * #3448 PR2 — abort-marker render path.
 *
 * Honest disclosure (G2 in the abort plan): partial text the user paid for,
 * the `[stopped by user]` chip, the token cost, and the chip-list of
 * tool calls that completed before Stop landed. The ToolUseChip component
 * narrows `leaderId` to the routing leaders (`cc_router`/`system`), so we
 * render the per-action chips inline rather than misusing that component
 * with a different leader contract.
 */
function renderAbortedAssistant({
  content,
  usage,
  variant,
}: {
  content: string;
  usage: AbortMarkerUsage | null | undefined;
  variant: "full" | "sidebar";
}): React.ReactNode {
  const wrapCode = variant === "sidebar";
  // #3640 F6 — switch on `usage.variant` per the `AbortMarkerUsage`
  // doc-comment above and the `Message.usage` doc-comment in
  // `lib/types.ts`. The cc-router path persists only
  // `cost_usd` (Art. 5(1)(c) data minimization); the legacy
  // `agent-runner` path persists the full `UsageSnapshot` (input_tokens +
  // output_tokens + cost_usd + completed_actions). `undefined` variant
  // defaults to `"legacy"` for fixture-stable backward-compat with the
  // pre-#3640 corpus. The cc branch skips the token sum so a cc-router
  // aborted-row reload renders cost-only (no `NaN tokens`).
  const usageVariant = usage?.variant ?? "legacy";
  const totalTokens =
    usage && usageVariant === "legacy" &&
    usage.input_tokens !== undefined &&
    usage.output_tokens !== undefined
      ? usage.input_tokens + usage.output_tokens
      : null;
  // Review #3670 — guard against non-numeric `cost_usd` values that could
  // leak from the `messages.usage` jsonb column (legacy rows, partial
  // backfills). `typeof === "number" && Number.isFinite` mirrors the
  // pre-#3640 behavior — a malformed cell renders "included in your plan"
  // rather than crashing the bubble (`.toFixed` on a string) or rendering
  // "$NaN" / "$Infinity" to the user.
  const costUsd = usage?.cost_usd;
  const costLabel =
    typeof costUsd === "number" && Number.isFinite(costUsd)
      ? `$${costUsd.toFixed(4)}`
      : "included in your plan";
  const actions = usage?.completed_actions ?? [];

  return (
    <div className="min-w-0" data-testid="abort-marker">
      {content.length > 0 && (
        <div className="min-w-0">
          <MarkdownRenderer content={content} wrapCode={wrapCode} />
        </div>
      )}
      <div className="mt-2 flex flex-wrap items-center gap-2 text-xs">
        <span
          className="inline-flex items-center rounded-full border border-amber-700/60 bg-soleur-bg-surface-2 px-2 py-0.5 text-amber-400"
          data-testid="abort-marker-chip"
        >
          [stopped by user]
        </span>
        {totalTokens !== null && (
          <span
            className="inline-flex items-center gap-1 text-soleur-text-muted"
            data-testid="abort-marker-cost"
          >
            <span className="tabular-nums">{totalTokens}</span>
            <span>tokens · {costLabel}</span>
          </span>
        )}
      </div>
      {actions.length > 0 && (
        <div
          className="mt-2 flex flex-wrap gap-1.5"
          data-testid="abort-marker-actions"
        >
          {actions.map((a, i) => (
            <span
              key={`${a.tool_name}-${i}`}
              title={a.result_summary || a.input_summary}
              className="inline-flex items-center rounded bg-soleur-bg-surface-2 px-1.5 py-0.5 text-xs text-soleur-text-secondary"
            >
              {a.tool_name}
              {a.input_summary ? (
                <span className="ml-1 max-w-[180px] truncate text-soleur-text-muted">
                  · {a.input_summary}
                </span>
              ) : null}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}
