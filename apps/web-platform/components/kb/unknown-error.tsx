export function UnknownError() {
  return (
    <div className="flex h-full items-center justify-center p-6">
      <div className="text-center">
        <p className="text-sm text-soleur-text-secondary">
          Unable to load your knowledge base. Please try again later.
        </p>
      </div>
    </div>
  );
}
