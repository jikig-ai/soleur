export function UnknownError() {
  return (
    <div className="flex h-full items-center justify-center p-6">
      <div className="text-center">
        <p className="text-sm text-neutral-400">
          Unable to load your knowledge base. Please try again later.
        </p>
      </div>
    </div>
  );
}
