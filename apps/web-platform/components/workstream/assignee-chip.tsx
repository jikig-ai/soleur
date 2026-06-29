// Small initials chips for the Workstream board.
//
// AssigneeChip = the PRIMARY role assignee (CTO/COO/…) — colored per the
// self-contained role palette in lib/workstream.ts.
// UserAvatar = the SECONDARY person (Addendum item 5) — a quiet gray avatar,
// always subordinate to the role chip.

import {
  assigneeInitials,
  roleColorClass,
  roleTitle,
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
