export function WorkspaceNotReady() {
  return (
    <div className="flex h-full items-center justify-center p-6">
      <div className="text-center">
        <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-soleur-bg-surface-2">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="animate-pulse text-soleur-accent-gold-fg">
            <path d="M12 6v6l4 2" strokeLinecap="round" strokeLinejoin="round" />
            <circle cx="12" cy="12" r="10" />
          </svg>
        </div>
        <h1 className="mb-2 font-serif text-lg font-medium text-soleur-text-primary">
          Setting Up Your Workspace
        </h1>
        <p className="text-sm text-soleur-text-secondary">
          Your workspace is being prepared. This usually takes a moment.
        </p>
      </div>
    </div>
  );
}
