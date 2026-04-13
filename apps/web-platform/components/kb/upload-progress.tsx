/**
 * Circular progress indicator for KB file uploads.
 *
 * percent = 0–100  → determinate ring that fills progressively
 * percent = -1     → indeterminate spinning animation (fallback when
 *                    lengthComputable is false)
 */
export function UploadProgress({ percent }: { percent: number }) {
  // Indeterminate mode: reuse the old spinner look
  if (percent < 0) {
    return (
      <svg
        width="12"
        height="12"
        viewBox="0 0 12 12"
        className="shrink-0 animate-spin text-amber-400"
      >
        <circle
          cx="6"
          cy="6"
          r="4.5"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
          opacity="0.3"
        />
        <path
          d="M6 1.5a4.5 4.5 0 0 1 4.5 4.5"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
          strokeLinecap="round"
        />
      </svg>
    );
  }

  const radius = 4.5;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (percent / 100) * circumference;

  return (
    <svg width="12" height="12" viewBox="0 0 12 12" className="shrink-0">
      {/* Background track */}
      <circle
        cx="6"
        cy="6"
        r={radius}
        fill="none"
        stroke="currentColor"
        strokeWidth="1.5"
        className="text-amber-400/30"
      />
      {/* Progress arc */}
      <circle
        cx="6"
        cy="6"
        r={radius}
        fill="none"
        stroke="currentColor"
        strokeWidth="1.5"
        className="text-amber-400 transition-[stroke-dashoffset] duration-300 ease-linear"
        strokeLinecap="round"
        strokeDasharray={circumference}
        strokeDashoffset={offset}
        transform="rotate(-90 6 6)"
      />
    </svg>
  );
}
