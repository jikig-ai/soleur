// Small initials chips for the Workstream board.
//
// AssigneeChip = the PRIMARY role assignee (CTO/COO/…) — colored per the
// self-contained role palette in lib/workstream.ts.
// UserAvatar = the SECONDARY person (Addendum item 5) — a quiet gray avatar,
// always subordinate to the role chip.

import {
  assigneeInitials,
  creatorLabel,
  roleColorClass,
  roleTitle,
  type WorkstreamCreator,
  type WorkstreamRole,
  type WorkstreamUser,
} from "@/lib/workstream";

export function AssigneeChip({
  role,
  className,
}: {
  role: WorkstreamRole | null;
  className?: string;
}) {
  return (
    <span
      title={roleTitle(role)}
      aria-label={roleTitle(role)}
      className={`inline-flex h-5 min-w-[20px] items-center justify-center rounded px-1 text-[10px] font-semibold text-white ${roleColorClass(
        role,
      )} ${className ?? ""}`}
    >
      {assigneeInitials(role)}
    </span>
  );
}

export function UserAvatar({
  user,
  className,
}: {
  user: WorkstreamUser;
  className?: string;
}) {
  return (
    <span
      title={user.name}
      aria-label={user.name}
      className={`inline-flex h-5 min-w-[20px] items-center justify-center rounded bg-soleur-bg-surface-2 px-1 text-[10px] font-semibold text-soleur-text-secondary ${
        className ?? ""
      }`}
    >
      {user.initials}
    </span>
  );
}

// CreatorChip = WHO CREATED the issue (GitHub author). A quiet gray initials chip
// like UserAvatar, but disambiguated from the assignee by (a) a leading glyph
// (🤖 Soleur bot / 👤 human), (b) reduced opacity, and (c) a "Created by …"
// tooltip. Never conflated with the assignee `user`.
export function CreatorChip({
  creator,
  className,
}: {
  creator: WorkstreamCreator;
  className?: string;
}) {
  const label = creatorLabel(creator);
  const glyph = creator.isSoleur ? "🤖" : "👤";
  // Bot with no human initiator → show the word "Soleur" (single-sourced from
  // deriveCreator's display.name); otherwise the display initials.
  const text =
    creator.isSoleur && !creator.initiatorLogin
      ? creator.display.name
      : creator.display.initials;
  return (
    <span
      title={`Created by ${label}`}
      aria-label={`Created by ${label}`}
      className={`inline-flex h-5 min-w-[20px] items-center gap-0.5 rounded bg-soleur-bg-surface-2 px-1 text-[10px] font-semibold text-soleur-text-secondary opacity-70 ${
        className ?? ""
      }`}
    >
      <span aria-hidden="true">{glyph}</span>
      {text}
    </span>
  );
}
