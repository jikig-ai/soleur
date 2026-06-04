import { memo, useState, useEffect } from "react";
import * as Sentry from "@sentry/nextjs";

// Presentational workspace-identity tile (ADR-047 single-mount: imports no
// data-bearing nav component, so it can render at any of the switcher's
// identity sites without re-mounting OrgSwitcherContainer/LiveRepoBadge).
//
// Renders a custom logo when `hasLogo` (via the stable proxy `src`
// /api/workspace/<id>/logo — a signature-free, browser-cacheable path, so
// focus re-polls don't thrash; AC7c), falling back to a monogram (first letter
// of the workspace name) on the no-logo path AND on any img load error
// (onError, modeled on components/leader-avatar.tsx). The monogram sits on a
// NON-gold surface (FR6). A set-but-broken logo is a defect → Sentry; the
// no-logo monogram path stays silent.

const SIZE_CLASSES = {
  sm: { container: "h-6 w-6", text: "text-[11px]" },
  md: { container: "h-8 w-8", text: "text-sm" },
} as const;

interface WorkspaceIdentityTileProps {
  name: string;
  size: keyof typeof SIZE_CLASSES;
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
      className={`flex ${sizeConfig.container} shrink-0 items-center justify-center overflow-hidden rounded-md bg-soleur-bg-surface-2 ${sizeConfig.text} font-bold text-soleur-text-secondary ${className ?? ""}`}
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
