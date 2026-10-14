"use client";

import { ConversationNamesSettingsContent } from "@/components/settings/conversation-names-settings";
import { TeamNamesProvider } from "@/hooks/use-team-names";

export default function ConversationNamesSettingsPage() {
  return (
    // Team names ARE this page's primary content — fetch at mount, not
    // post-FCP (the outer shell provider still defers its own idle arm; the
    // shared SWR key means this mount feeds it).
    <TeamNamesProvider defer={false}>
      <ConversationNamesSettingsContent />
    </TeamNamesProvider>
  );
}
