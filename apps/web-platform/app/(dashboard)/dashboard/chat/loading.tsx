// Streaming skeleton for the chat segment. The chat layout resolves
// delegation/invite banners asynchronously; this fallback streams while that
// (and the segment RSC render) resolves. Hand-rolled animate-pulse idiom.
export default function ChatLoading() {
  return (
    <div className="flex h-full min-h-0 flex-1 flex-col items-center justify-center px-4 py-10">
      <div className="w-full max-w-xl space-y-4">
        <div className="h-6 w-40 animate-pulse rounded bg-soleur-bg-surface-2/50" />
        <div className="h-[44px] w-full animate-pulse rounded-xl bg-soleur-bg-surface-2/50" />
      </div>
    </div>
  );
}
