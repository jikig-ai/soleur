"use client";

import { ConversationNamesSettingsContent } from "@/components/settings/conversation-names-settings";
import { TeamNamesProvider } from "@/hooks/use-team-names";

export default function ConversationNamesSettingsPage() {
  return (
    <TeamNamesProvider>
      <ConversationNamesSettingsContent />
    </TeamNamesProvider>
  );
}
