import { memo } from "react";

// Pure presentational workspace-identity tile (ADR-047 single-mount: imports
// no data-bearing nav component, so it can render at any of the switcher's
// identity sites without re-mounting OrgSwitcherContainer/LiveRepoBadge).
//
// Renders a monogram (first letter of the workspace name) on a NON-gold
// surface — FR6: explicitly not the old gold square swatch. The gold token is
// reserved for active-workspace identity accents + the single primary action.
//
// TODO(#4916): when the deferred workspace `logo_url` field lands, add an
// `img` branch with an onError→monogram fallback modeled on
// components/leader-avatar.tsx (showCustomIcon + setImgError). Until then every
// workspace is a monogram; the full workspace name lives in the tooltip/selector
// as the authoritative disambiguator for shared-initial monograms.

const SIZE_CLASSES = {
  sm: { container: "h-6 w-6", text: "text-[11px]" },
  md: { container: "h-8 w-8", text: "text-sm" },
} as const;

interface WorkspaceIdentityTileProps {
  name: string;
  size: keyof typeof SIZE_CLASSES;
  className?: string;
}

function monogram(name: string): string {
  const ch = name.trim().charAt(0);
  return ch ? ch.toUpperCase() : "?";
}

export const WorkspaceIdentityTile = memo(function WorkspaceIdentityTile({
  name,
  size,
  className,
}: WorkspaceIdentityTileProps) {
  const sizeConfig = SIZE_CLASSES[size];
  return (
    <span
      data-testid="workspace-identity-tile"
      aria-hidden="true"
      className={`flex ${sizeConfig.container} shrink-0 items-center justify-center rounded-md bg-soleur-bg-surface-2 ${sizeConfig.text} font-bold text-soleur-text-secondary ${className ?? ""}`}
    >
      {monogram(name)}
    </span>
  );
});
