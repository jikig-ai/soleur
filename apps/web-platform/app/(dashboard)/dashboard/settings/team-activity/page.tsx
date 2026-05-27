import { ActivityFeed } from "@/components/dashboard/activity-feed";

export default function TeamActivityPage() {
  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold text-soleur-text-primary">Team Activity</h2>
        <p className="mt-1 text-sm text-soleur-text-secondary">
          Recent activity across your workspace — member joins, departures, and shared conversations.
        </p>
      </div>
      <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1">
        <ActivityFeed />
      </div>
    </div>
  );
}
