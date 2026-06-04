import { memo, useState, useEffect } from "react";
import * as Sentry from "@sentry/nextjs";

// Presentational workspace-identity tile (ADR-047 single-mount: imports no
// data-bearing nav component, so it can render at any of the switcher's
// identity sites without re-mounting OrgSwitcherContainer/LiveRepoBadge).
//
// Renders a custom logo when `hasLogo` (via the stable proxy `src`
// /api/workspace/<id>/logo — signature-free, browser-cacheable so focus
// re-polls don't thrash; AC7c, #4916), falling back to a MONOGRAM on the
// no-logo path AND on any img load error (onError, modeled on
// components/leader-avatar.tsx). A set-but-broken logo is a defect → Sentry;
// the no-logo monogram path stays silent.
//
// Two MONOGRAM variants (D4-bolder, #4915 follow-up):
//   - "identity": a BOLD gold-gradient anchor for the active-workspace identity
//     (rail identity panel, collapsed rail, mobile). Supersedes the original FR6
//     "non-gold tile" for the identity surface (founder-approved, frames 25/26/27).
//   - "list" (default): the NEUTRAL non-gold monogram (org-switcher dropdown
//     rows), so the current-row gold-ring distinction still reads (FR6 where it
//     still applies). A custom logo (img) is variant-agnostic — it covers the
//     tile via object-cover regardless of variant.

const SIZE_CLASSES = {
  sm: { container: "h-6 w-6", text: "text-[11px]", rounded: "rounded-md" },
  md: { container: "h-8 w-8", text: "text-sm", rounded: "rounded-md" },
  lg: { container: "h-11 w-11", text: "text-lg", rounded: "rounded-xl" },
} as const;

const VARIANT_CLASSES = {
  identity:
    "bg-gradient-to-br from-soleur-accent-gradient-start to-soleur-accent-gradient-end text-soleur-text-on-accent shadow-md",
  list: "bg-soleur-bg-surface-2 text-soleur-text-secondary",
} as const;

interface WorkspaceIdentityTileProps {
  name: string;
  size: keyof typeof SIZE_CLASSES;
  /** "identity" = bold gold-gradient anchor (active-workspace identity);
   *  "list" (default) = neutral non-gold monogram (dropdown rows). */
  variant?: keyof typeof VARIANT_CLASSES;
  className?: string;
  /** Workspace id — builds the stable proxy logo `src`. Required for the logo branch. */
  workspaceId?: string;
  /** Whether the workspace has a custom logo (resolver `hasLogo`). */
  hasLogo?: boolean;
}

function monogram(name: string): string {
  const ch = name.trim().charAt(0);
  return ch ? ch.toUpperCase() : "?";
}

export const WorkspaceIdentityTile = memo(function WorkspaceIdentityTile({
  name,
  size,
  variant = "list",
  className,
  workspaceId,
  hasLogo,
}: WorkspaceIdentityTileProps) {
  const sizeConfig = SIZE_CLASSES[size];
  const [imgError, setImgError] = useState(false);

  // Reset the error latch when the workspace changes (new mount target / upload).
  useEffect(() => {
    setImgError(false);
  }, [workspaceId]);

  const showLogo = !!hasLogo && !!workspaceId && !imgError;

  return (
    <span
      data-testid="workspace-identity-tile"
      aria-hidden="true"
      className={`flex ${sizeConfig.container} shrink-0 items-center justify-center overflow-hidden ${sizeConfig.rounded} ${VARIANT_CLASSES[variant]} ${sizeConfig.text} font-bold ${className ?? ""}`}
    >
      {showLogo ? (
        <img
          data-testid="workspace-logo-img"
          src={`/api/workspace/${workspaceId}/logo`}
          alt=""
          className="h-full w-full object-cover"
          onError={() => {
            setImgError(true);
            Sentry.captureMessage("workspace logo failed to load", {
              level: "warning",
              tags: { feature: "workspace-logo", op: "render-onerror" },
            });
          }}
        />
      ) : (
        monogram(name)
      )}
    </span>
  );
});
