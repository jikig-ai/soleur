"use client";

import { TeamSettingsContent } from "@/components/settings/team-settings";
import { TeamNamesProvider } from "@/hooks/use-team-names";

export default function TeamSettingsPage() {
  return (
    <TeamNamesProvider>
      <TeamSettingsContent />
    </TeamNamesProvider>
  );
}
