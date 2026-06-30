// Same-tab refresh signal for workspace-logo changes (#4916 follow-up).
//
// The logo upload/removal control (WorkspaceLogoSettings) lives on the Settings
// page; the workspace identity is rendered by the single mounted switcher
// (OrgSwitcherContainer) — which now serves BOTH the expanded pill and the
// collapsed-rail icon tile (one instance, never remounted on collapse). It
// fetches /api/workspace/list-memberships once on mount and only re-polls on
// the event below — so without an explicit signal, a same-tab upload never
// updates the switcher until a full reload.
//
// On a successful upload/removal the control dispatches this CustomEvent;
// the switcher listens and re-fetches its memberships.
// Mirrors the in-app CustomEvent pattern already used by kb-sidebar-shell.tsx
// (RAIL_EXPAND_EVENT) — no polling interval, no new data path.
//
// The `detail.workspaceId` lets the identity tile cache-bust its stable proxy
// `src` (which is otherwise browser-cached for max-age=300) so a REPLACE — where
// hasLogo stays true and the src path is unchanged — still refreshes the visible
// logo without a full reload.
export const WORKSPACE_LOGO_CHANGED_EVENT = "soleur:workspace-logo-changed";

export interface WorkspaceLogoChangedDetail {
  workspaceId: string;
}
