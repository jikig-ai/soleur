import { memo } from "react";

// Pure presentational workspace-identity tile (ADR-047 single-mount: imports
// no data-bearing nav component, so it can render at any of the switcher's
// identity sites without re-mounting OrgSwitcherContainer/LiveRepoBadge).
//
// Two variants:
//   - "identity" (D4-bolder, #4915 follow-up): a BOLD gold-gradient anchor for
//     the active-workspace identity (the rail's identity panel, collapsed rail,
//     mobile). This is the sanctioned active-workspace gold use — it supersedes
//     the original FR6 "non-gold tile" decision for the identity surface, by
//     founder-approved design (frames 25/26/27).
//   - "list" (default): the NEUTRAL non-gold monogram, used in the org-switcher
//     dropdown rows so the current-row gold-ring distinction still reads (FR6
//     preserved where it still applies).
//
// TODO(#4916): when the deferred workspace `logo_url` field lands, add an
// `img` branch with an onError→monogram fallback modeled on
// components/leader-avatar.tsx (showCustomIcon + setImgError). Until then every
// workspace is a monogram; the full workspace name lives in the tooltip/selector
// as the authoritative disambiguator for shared-initial monograms.

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
}: WorkspaceIdentityTileProps) {
  const sizeConfig = SIZE_CLASSES[size];
  return (
    <span
      data-testid="workspace-identity-tile"
      aria-hidden="true"
      className={`flex ${sizeConfig.container} shrink-0 items-center justify-center ${sizeConfig.rounded} ${VARIANT_CLASSES[variant]} ${sizeConfig.text} font-bold ${className ?? ""}`}
    >
      {monogram(name)}
    </span>
  );
});
