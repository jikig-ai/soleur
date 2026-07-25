"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { RailSlotPortal, useRailCollapsed } from "@/components/dashboard/rail-slot";

interface SettingsTab {
  href: string;
  label: string;
}

const STATIC_SETTINGS_TABS: readonly SettingsTab[] = [
  { href: "/dashboard/settings", label: "General" },
  { href: "/dashboard/settings/conversation-names", label: "Domain Leaders" },
  { href: "/dashboard/settings/services", label: "Integrations" },
  { href: "/dashboard/settings/scope-grants", label: "Scope Grants" },
  { href: "/dashboard/settings/billing", label: "Billing" },
] as const;

// D4-bolder (#4915): the settings sub-nav gets leading icons (mock 27). Keyed by
// href so the server-provided dynamic tabs (Members/Activity under
// `.../team*`) resolve without threading an icon prop through the layout; an
// href prefix-match + a fallback covers tabs not listed explicitly.
type SettingsIconComponent = (props: { className?: string }) => React.JSX.Element;

const TAB_ICONS: Record<string, SettingsIconComponent> = {
  "/dashboard/settings": GearIcon,
  "/dashboard/settings/conversation-names": ChatIcon,
  "/dashboard/settings/services": PlugIcon,
  "/dashboard/settings/scope-grants": KeyIcon,
  "/dashboard/settings/billing": CardIcon,
};

function iconForHref(href: string): SettingsIconComponent {
  if (TAB_ICONS[href]) return TAB_ICONS[href];
  if (href.includes("/team")) return PeopleIcon; // Members / Team activity
  return DotIcon;
}

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
  // ADR-047 collapse fix (revised by Sidebar-UX follow-up Issue 4): the Settings
  // sub-nav is a FLAT list of single-glyph tabs, so when the unified rail is
  // collapsed it renders an icon-only column (one icon button per tab) instead of
  // DOM-removing the whole nav — the old behaviour left the collapsed rail empty.
  // The icon-only buttons fit the 56px rail by construction (proven by the
  // primary nav already doing this), so there is no horizontal clip. The stable
  // `settings-rail-nav` wrapper always renders so present/absent assertions
  // target exactly one node; the collapse-aware WorkspaceContextBand keeps
  // workspace identity legible.
  const collapsed = useRailCollapsed();

  return (
    <div className="flex min-h-full">
      <RailSlotPortal>
        <div data-testid="settings-rail-nav">
          <nav
            aria-label="Settings"
            data-testid={collapsed ? "settings-rail-icons" : undefined}
            className={collapsed ? "px-1 py-2" : "px-2 py-2"}
          >
            <ul className="space-y-1">
              {SETTINGS_TABS.map((tab) => {
                const active =
                  tab.href === "/dashboard/settings"
                    ? pathname === "/dashboard/settings"
                    : pathname.startsWith(tab.href);
                const Icon = iconForHref(tab.href);

                return (
                  <li key={tab.href}>
                    <Link
                      href={tab.href}
                      // Collapsed: the Link has no text label, so the tab name is
                      // the accessible name (aria-label) + hover tooltip (title),
                      // mirroring the primary nav's collapsed pattern
                      // (layout.tsx). Expanded: the visible text supplies the name.
                      aria-label={collapsed ? tab.label : undefined}
                      title={collapsed ? tab.label : undefined}
                      aria-current={active ? "page" : undefined}
                      className={`relative flex min-h-[44px] items-center rounded-lg text-sm transition-colors ${
                        collapsed
                          ? "justify-center px-0 py-2"
                          : "gap-3 px-3 py-2"
                      } ${
                        active
                          ? "bg-soleur-accent-gold-fill/10 text-soleur-accent-gold-text font-medium"
                          : "text-soleur-text-secondary hover:bg-soleur-bg-surface-2/50 hover:text-soleur-text-primary"
                      }`}
                    >
                      {/* D4-bolder active treatment — gold left-edge bar overlay,
                          consistent with the primary nav + KB tree. Hidden when
                          collapsed (no left gutter to anchor it), matching the
                          primary nav's collapsed treatment. */}
                      {active && (
                        <span
                          aria-hidden="true"
                          className={`absolute inset-y-1.5 left-0 w-[3px] rounded-full bg-soleur-accent-gold-fill ${
                            collapsed ? "hidden" : ""
                          }`}
                        />
                      )}
                      <Icon className="h-4 w-4 shrink-0" />
                      {!collapsed && <span className="truncate">{tab.label}</span>}
                    </Link>
                  </li>
                );
              })}
            </ul>
          </nav>
        </div>
      </RailSlotPortal>

      {/* Content area */}
      <div className="relative min-w-0 flex-1 overflow-x-hidden px-4 py-10 md:px-10">
        <div className="mx-auto max-w-2xl">{children}</div>
      </div>
    </div>
  );
}

/* Settings sub-nav glyphs (D4-bolder, mock 27). Stroke style matches the
   dashboard primary-nav icons (fill=none, 24-viewbox, currentColor, 1.5). */
function svgProps(className?: string) {
  return {
    className,
    fill: "none" as const,
    viewBox: "0 0 24 24",
    stroke: "currentColor",
    strokeWidth: 1.5,
    // The glyphs are decorative in BOTH states — the nav Link owns the accessible
    // name (visible text when expanded, aria-label when collapsed, Issue 4). Hide
    // the SVG from the a11y tree so it is never announced as a stray graphic (WIG;
    // fixes the prior inconsistency where the active-bar span was aria-hidden but
    // the leading glyph was not).
    "aria-hidden": true,
  };
}

function GearIcon({ className }: { className?: string }) {
  return (
    <svg {...svgProps(className)}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.24-.438.613-.43.991a6.93 6.93 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.98 6.98 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z" />
      <path strokeLinecap="round" strokeLinejoin="round" d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" />
    </svg>
  );
}

function ChatIcon({ className }: { className?: string }) {
  return (
    <svg {...svgProps(className)}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M7.5 8.25h9m-9 3H12m-9.75 1.51c0 1.6 1.123 2.994 2.707 3.227 1.129.166 2.27.293 3.423.379.35.026.67.21.865.501L12 21l2.755-4.133a1.14 1.14 0 0 1 .865-.501 48.17 48.17 0 0 0 3.423-.379c1.584-.233 2.707-1.626 2.707-3.228V6.741c0-1.602-1.123-2.995-2.707-3.228A48.39 48.39 0 0 0 12 3c-2.392 0-4.744.175-7.043.513C3.373 3.746 2.25 5.14 2.25 6.741v6.018Z" />
    </svg>
  );
}

function PlugIcon({ className }: { className?: string }) {
  return (
    <svg {...svgProps(className)}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M14.25 6.087c0-.355.186-.676.401-.959.221-.29.349-.634.349-1.003 0-1.036-1.007-1.875-2.25-1.875s-2.25.84-2.25 1.875c0 .369.128.713.349 1.003.215.283.401.604.401.959v0a.64.64 0 0 1-.657.643 48.4 48.4 0 0 1-4.163-.3c.186 1.613.293 3.25.315 4.907a.656.656 0 0 1-.658.663v0c-.355 0-.676-.186-.959-.401a1.647 1.647 0 0 0-1.003-.349c-1.036 0-1.875 1.007-1.875 2.25s.84 2.25 1.875 2.25c.369 0 .713-.128 1.003-.349.283-.215.604-.401.959-.401v0c.31 0 .555.26.532.57a48.04 48.04 0 0 1-.642 5.056c1.518.19 3.058.309 4.616.354a.64.64 0 0 0 .657-.643v0c0-.355-.186-.676-.401-.959a1.647 1.647 0 0 1-.349-1.003c0-1.035 1.008-1.875 2.25-1.875 1.243 0 2.25.84 2.25 1.875 0 .37-.128.713-.349 1.003-.215.283-.4.604-.4.96v0c0 .333.277.599.61.58a48.1 48.1 0 0 0 5.427-.63 48.05 48.05 0 0 0 .582-4.717.532.532 0 0 0-.533-.57v0c-.355 0-.676.186-.959.401-.29.221-.634.349-1.003.349-1.035 0-1.875-1.007-1.875-2.25s.84-2.25 1.875-2.25c.37 0 .713.128 1.003.349.283.215.604.401.96.401v0a.656.656 0 0 0 .658-.663 48.42 48.42 0 0 0-.37-5.36c-1.676.193-3.374.293-5.09.293a.658.658 0 0 1-.657-.663v0Z" />
    </svg>
  );
}

function KeyIcon({ className }: { className?: string }) {
  return (
    <svg {...svgProps(className)}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 5.25a3 3 0 0 1 3 3m3 0a6 6 0 0 1-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1 1 21.75 8.25Z" />
    </svg>
  );
}

function CardIcon({ className }: { className?: string }) {
  return (
    <svg {...svgProps(className)}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 0 0 2.25-2.25V6.75A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25v10.5A2.25 2.25 0 0 0 4.5 19.5Z" />
    </svg>
  );
}

function PeopleIcon({ className }: { className?: string }) {
  return (
    <svg {...svgProps(className)}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.32 12.32 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z" />
    </svg>
  );
}

function DotIcon({ className }: { className?: string }) {
  return (
    <svg {...svgProps(className)}>
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}
