"use client";

import { TeamSettingsContent } from "@/components/settings/team-settings";
import { TeamNamesProvider } from "@/hooks/use-team-names";
import { SettingsShell } from "@/components/settings/settings-shell";

export default function TeamSettingsPage() {
  return (
    <TeamNamesProvider>
      <SettingsShell>
        <TeamSettingsContent />
      </SettingsShell>
    </TeamNamesProvider>
  );
}
