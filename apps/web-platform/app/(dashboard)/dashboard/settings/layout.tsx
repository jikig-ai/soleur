import { SettingsShell } from "@/components/settings/settings-shell";
import { resolveMembersTab } from "@/server/members-tab";

export default async function SettingsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const membersTab = await resolveMembersTab();
  const activityTab = membersTab
    ? { href: "/dashboard/settings/team-activity", label: "Team Activity" }
    : null;
  return <SettingsShell membersTab={membersTab} activityTab={activityTab}>{children}</SettingsShell>;
}
