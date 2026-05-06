export function WelcomeCard() {
  return (
    <div className="mb-4 flex items-start gap-3 rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/80 p-4">
      <span
        data-testid="welcome-icon"
        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-amber-600 text-sm font-bold text-soleur-text-on-accent"
      >
        S
      </span>
      <div>
        <p className="text-sm font-semibold text-soleur-text-primary">
          Your Organization Is Ready
        </p>
        <p className="mt-1 text-sm text-soleur-text-secondary">
          Eight department leaders are standing by. Type @ to put one to work.
        </p>
      </div>
    </div>
  );
}
