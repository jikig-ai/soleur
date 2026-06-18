// Streaming skeleton for an individual conversation route. Renders an
// alternating message-bubble transcript + a composer bar while the segment
// resolves, so the chat shell paints immediately. Hand-rolled animate-pulse.
export default function ConversationLoading() {
  return (
    <div className="flex h-full min-h-0 flex-1 flex-col">
      <div className="flex-1 space-y-4 overflow-hidden px-4 py-6">
        {Array.from({ length: 5 }).map((_, i) => (
          <div key={i} className={i % 2 === 0 ? "flex justify-start" : "flex justify-end"}>
            <div
              className={`h-16 animate-pulse rounded-2xl bg-soleur-bg-surface-2/50 ${
                i % 2 === 0 ? "w-2/3" : "w-1/2"
              }`}
            />
          </div>
        ))}
      </div>
      <div className="shrink-0 px-4 py-4">
        <div className="h-[44px] w-full animate-pulse rounded-xl bg-soleur-bg-surface-2/50" />
      </div>
    </div>
  );
}
