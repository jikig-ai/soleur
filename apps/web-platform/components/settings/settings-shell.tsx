"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { RailSlotPortal } from "@/components/dashboard/rail-slot";

interface SettingsTab {
  href: string;
  label: string;
}

const STATIC_SETTINGS_TABS: readonly SettingsTab[] = [
  { href: "/dashboard/settings", label: "General" },
  { href: "/dashboard/settings/conversation-names", label: "Conversation names" },
  { href: "/dashboard/settings/services", label: "Integrations" },
  { href: "/dashboard/settings/scope-grants", label: "Scope Grants" },
  { href: "/dashboard/settings/billing", label: "Billing" },
] as const;

// AC-A: when the team-workspace-invite flag is OFF, `membersTab` is null and
// the Members link href is not constructed here. The server layout evaluates
// the flag gate and decides what to pass.
//
// ADR-047: the Settings sub-nav is lifted into the single nav rail's secondary
// slot via a portal — it stays inside this client component's subtree (so it
// keeps the server-resolved membersTab/activityTab props) while its DOM lands
// in the unified rail. The per-shell collapse chrome and the mobile bottom tab
// bar are gone: the unified rail owns collapse (⌘B) and hosts the nav on every
// breakpoint (the drawer on mobile).
export function SettingsShell({
  children,
  membersTab = null,
  activityTab = null,
}: {
  children: React.ReactNode;
  membersTab?: SettingsTab | null;
  activityTab?: SettingsTab | null;
}) {
  const SETTINGS_TABS: readonly SettingsTab[] = [
    ...STATIC_SETTINGS_TABS,
    ...(membersTab ? [membersTab] : []),
    ...(activityTab ? [activityTab] : []),
  ];
  const pathname = usePathname();

  return (
    <div className="flex min-h-full">
      <RailSlotPortal>
        <nav aria-label="Settings" className="px-2 py-2">
          <ul className="space-y-1">
            {SETTINGS_TABS.map((tab) => {
              const active =
                tab.href === "/dashboard/settings"
                  ? pathname === "/dashboard/settings"
                  : pathname.startsWith(tab.href);

              return (
                <li key={tab.href}>
                  <Link
                    href={tab.href}
                    aria-current={active ? "page" : undefined}
                    className={`block rounded-lg px-3 py-2 text-sm transition-colors ${
                      active
                        ? "bg-soleur-bg-surface-2 text-soleur-text-primary font-medium"
                        : "text-soleur-text-secondary hover:bg-soleur-bg-surface-2/50 hover:text-soleur-text-primary"
                    }`}
                  >
                    {tab.label}
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>
      </RailSlotPortal>

      {/* Content area */}
      <div className="relative flex-1 px-4 py-10 md:px-10">
        <div className="mx-auto max-w-2xl">{children}</div>
      </div>
    </div>
  );
}
