"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const SETTINGS_TABS = [
  { href: "/dashboard/settings", label: "General" },
  { href: "/dashboard/settings/team", label: "Team" },
  { href: "/dashboard/settings/services", label: "Integrations" },
] as const;

export function SettingsShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();

  return (
    <div className="flex min-h-full">
      {/* Settings sidebar — hidden on mobile, shown on md+ */}
      <nav className="hidden w-48 shrink-0 border-r border-neutral-800 px-4 py-10 md:block">
        <h2 className="mb-4 text-xs font-medium uppercase tracking-wider text-neutral-500">
          Settings
        </h2>
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
                  className={`block rounded-lg px-3 py-2 text-sm transition-colors ${
                    active
                      ? "bg-neutral-800 text-white font-medium"
                      : "text-neutral-400 hover:bg-neutral-800/50 hover:text-neutral-200"
                  }`}
                >
                  {tab.label}
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>

      {/* Mobile tab bar */}
      <div className="fixed bottom-0 left-0 right-0 z-40 flex border-t border-neutral-800 bg-neutral-900 safe-bottom md:hidden">
        {SETTINGS_TABS.map((tab) => {
          const active =
            tab.href === "/dashboard/settings"
              ? pathname === "/dashboard/settings"
              : pathname.startsWith(tab.href);

          return (
            <Link
              key={tab.href}
              href={tab.href}
              className={`flex-1 py-3 text-center text-xs font-medium transition-colors ${
                active ? "text-white" : "text-neutral-500"
              }`}
            >
              {tab.label}
            </Link>
          );
        })}
      </div>

      {/* Content area */}
      <div className="flex-1 px-4 py-10 pb-20 md:px-10 md:pb-10">
        <div className="mx-auto max-w-2xl">{children}</div>
      </div>
    </div>
  );
}
