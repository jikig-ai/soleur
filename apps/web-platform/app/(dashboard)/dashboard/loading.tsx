// Streaming skeleton for the dashboard home segment. Renders during the
// App-Router segment-navigation RSC fetch/render window so the route paints
// immediately instead of a blank screen. Mirrors the hand-rolled animate-pulse
// idiom used across the app (admin/analytics/loading.tsx, kb skeletons) —
// the repo has no Mantine Skeleton convention.
export default function DashboardLoading() {
  return (
    <div className="mx-auto flex min-h-[calc(100dvh-4rem)] max-w-3xl flex-col px-4 py-10">
      {/* Composer / banner strip */}
      <div className="h-[44px] w-full max-w-xl animate-pulse self-center rounded-xl bg-soleur-bg-surface-2/50" />
      {/* Conversation rows */}
      <div className="mt-10 w-full space-y-3">
        {Array.from({ length: 6 }).map((_, i) => (
          <div
            key={i}
            className="h-16 w-full animate-pulse rounded-xl border border-soleur-border-default bg-soleur-bg-surface-2/50"
          />
        ))}
      </div>
    </div>
  );
}
