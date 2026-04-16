"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect } from "react";
import { useSidebarCollapse } from "@/hooks/use-sidebar-collapse";

const SETTINGS_TABS = [
  { href: "/dashboard/settings", label: "General" },
  { href: "/dashboard/settings/team", label: "Team" },
  { href: "/dashboard/settings/services", label: "Integrations" },
  { href: "/dashboard/settings/billing", label: "Billing" },
] as const;

export function SettingsShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const [settingsCollapsed, toggleSettingsCollapsed] = useSidebarCollapse("soleur:sidebar.settings.collapsed");

  useEffect(() => {
    function handleToggleShortcut(e: KeyboardEvent) {
      if (!(e.metaKey || e.ctrlKey) || e.key !== "b") return;
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      if ((e.target as HTMLElement)?.isContentEditable) return;
      if (!pathname.startsWith("/dashboard/settings")) return;
      e.preventDefault();
      toggleSettingsCollapsed();
    }
    document.addEventListener("keydown", handleToggleShortcut);
    return () => document.removeEventListener("keydown", handleToggleShortcut);
  }, [pathname, toggleSettingsCollapsed]);

  return (
    <div className="flex min-h-full">
      {/* Settings sidebar — hidden on mobile, shown on md+ */}
      <nav className={`hidden shrink-0 border-r border-neutral-800 md:block
        md:transition-[width] md:duration-200 md:ease-out
        ${settingsCollapsed ? "md:w-0 md:overflow-hidden md:border-r-0" : "w-48 px-4 py-10"}`}>
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
        <button
          onClick={toggleSettingsCollapsed}
          aria-label="Collapse settings nav"
          className="mt-6 flex w-full items-center gap-2 rounded-lg px-3 py-2 text-xs text-neutral-500 transition-colors hover:bg-neutral-800/50 hover:text-neutral-200"
        >
          <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
          </svg>
          Collapse
        </button>
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
        {settingsCollapsed && (
          <button
            onClick={toggleSettingsCollapsed}
            aria-label="Expand settings nav"
            className="hidden md:flex mb-4 h-8 w-8 items-center justify-center rounded-lg border border-neutral-800 text-neutral-400 hover:bg-neutral-800 hover:text-white"
          >
            <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
              <path strokeLinecap="round" strokeLinejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
            </svg>
          </button>
        )}
        <div className="mx-auto max-w-2xl">{children}</div>
      </div>
    </div>
  );
}
