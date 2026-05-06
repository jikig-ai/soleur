import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..");

// Files that legitimately retain literal Tailwind grays/colors.
// Each entry MUST cite a one-line reason — reviewer reviews each entry.
const ALLOWLIST = new Set<string>([
  "components/chat/leader-colors.ts", // Domain-leader identity palette (cross-theme).
  "components/chat/status-indicator.tsx", // Status semantics (red/orange/green).
]);

// Surfaces that must consume Soleur tokens after the light-theme migration.
// Representative sampling across Group A–F (chat, KB, settings, connect-repo, dashboard, UI primitives).
const SURFACE_GROUPS: readonly string[] = [
  // Group A — Chat
  "components/chat/chat-surface.tsx",
  "components/chat/interactive-prompt-card.tsx",
  "components/chat/message-bubble.tsx",
  "components/chat/chat-input.tsx",
  "components/chat/at-mention-dropdown.tsx",
  "components/chat/workflow-lifecycle-bar.tsx",
  "components/chat/subagent-group.tsx",
  "components/chat/notification-prompt.tsx",
  "components/chat/review-gate-card.tsx",
  "components/chat/pwa-install-banner.tsx",
  "components/chat/attachment-display.tsx",
  "components/chat/welcome-card.tsx",
  "components/chat/naming-nudge.tsx",
  "components/chat/kb-chat-content.tsx",
  "components/chat/tool-use-chip.tsx",
  "components/chat/routed-leaders-strip.tsx",

  // Group B — KB
  "components/kb/file-tree.tsx",
  "components/kb/pdf-preview.tsx",
  "components/kb/share-popover.tsx",
  "components/kb/search-overlay.tsx",
  "components/kb/kb-desktop-layout.tsx",
  "components/kb/text-preview.tsx",
  "components/kb/no-project-state.tsx",
  "components/kb/file-preview.tsx",
  "components/kb/empty-state.tsx",
  "components/kb/download-preview.tsx",
  "components/kb/workspace-not-ready.tsx",
  "components/kb/selection-toolbar.tsx",
  "components/kb/loading-skeleton.tsx",
  "components/kb/kb-content-header.tsx",
  "components/kb/desktop-placeholder.tsx",

  // Group C — Settings
  "components/settings/connected-services-content.tsx",
  "components/settings/settings-content.tsx",
  "components/settings/team-settings.tsx",
  "components/settings/settings-shell.tsx",
  "components/settings/project-setup-card.tsx",
  "components/settings/disconnect-repo-dialog.tsx",
  "components/settings/delete-account-dialog.tsx",

  // Group D — Connect-repo / onboarding
  "components/connect-repo/select-project-state.tsx",
  "components/connect-repo/ready-state.tsx",
  "components/connect-repo/create-project-state.tsx",
  "components/connect-repo/github-redirect-state.tsx",
  "components/connect-repo/choose-state.tsx",
  "components/connect-repo/setting-up-state.tsx",
  "components/connect-repo/github-resolve-state.tsx",
  "components/connect-repo/failed-state.tsx",
  "components/connect-repo/no-projects-state.tsx",
  "components/connect-repo/interrupted-state.tsx",
  "components/onboarding/naming-modal.tsx",

  // Group E — Dashboard / analytics / inbox / share
  "app/(dashboard)/dashboard/page.tsx",
  "components/analytics/analytics-dashboard.tsx",
  "components/inbox/conversation-row.tsx",
  "components/dashboard/foundation-cards.tsx",
  "app/shared/[token]/page.tsx",

  // Group F — UI primitives + global-error
  "components/ui/markdown-renderer.tsx",
  "components/ui/sheet.tsx",
  "components/ui/error-card.tsx",
  "components/ui/outlined-button.tsx",
  "components/ui/card.tsx",
  "components/error-boundary-view.tsx",
  "app/global-error.tsx",
];

// Hardcoded Tailwind gray/text-white classes that should not appear on tokenized surfaces.
// `\b(bg|text|border)-` deliberately scoped so it doesn't false-match `border-l-pink-500`
// (leader-colors palette) or status colors (`bg-red-600`, `text-orange-400`).
const HARDCODED =
  /\b(?:bg|text|border)-(?:zinc|slate|neutral|stone|gray)-\d+|\btext-white\b/;

// Soleur token namespace — at least one occurrence required per migrated file.
const TOKENIZED = /\bsoleur-(?:bg|text|border|accent)-/;

describe("light-theme tokenization regression", () => {
  for (const rel of SURFACE_GROUPS) {
    if (ALLOWLIST.has(rel)) continue;

    it(`${rel} contains no hardcoded gray classes`, () => {
      const src = readFileSync(resolve(ROOT, rel), "utf8");
      expect(src).not.toMatch(HARDCODED);
    });

    it(`${rel} consumes Soleur tokens`, () => {
      const src = readFileSync(resolve(ROOT, rel), "utf8");
      expect(src).toMatch(TOKENIZED);
    });
  }
});
