function isIosSafari(): boolean {
  if (typeof navigator === "undefined") return false;
  const ua = navigator.userAgent;
  const isIos = /iPhone|iPad|iPod/.test(ua);
  const isNotChromeOrFirefox = !/CriOS|FxiOS|OPiOS|EdgiOS/.test(ua);
  const isSafari = /Safari/.test(ua);
  return isIos && isNotChromeOrFirefox && isSafari;
}

interface PwaInstallBannerProps {
  dismissed: boolean;
  onDismiss: () => void;
}

export function PwaInstallBanner({ dismissed, onDismiss }: PwaInstallBannerProps) {
  if (dismissed || !isIosSafari()) return null;

  return (
    <div className="mb-4 flex w-full items-start gap-3 rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/80 p-4">
      <span className="mt-0.5 text-lg text-soleur-text-secondary">
        <ShareIcon />
      </span>
      <div className="flex-1">
        <p className="text-sm font-semibold text-soleur-text-primary">
          Add Soleur to Your Home Screen
        </p>
        <p className="mt-1 text-sm text-soleur-text-secondary">
          Open on any device, no app store needed. Tap the Share icon, then
          &ldquo;Add to Home Screen.&rdquo;
        </p>
      </div>
      <button
        type="button"
        onClick={onDismiss}
        className="shrink-0 rounded p-1 text-soleur-text-muted transition-colors hover:text-soleur-text-secondary"
        aria-label="Dismiss PWA install banner"
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <line x1="18" y1="6" x2="6" y2="18" />
          <line x1="6" y1="6" x2="18" y2="18" />
        </svg>
      </button>
    </div>
  );
}

function ShareIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8" />
      <polyline points="16 6 12 2 8 6" />
      <line x1="12" y1="2" x2="12" y2="15" />
    </svg>
  );
}
