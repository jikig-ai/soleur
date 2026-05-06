"use client";

import { useRef } from "react";
import { useTheme, type Theme } from "./theme-provider";

type Segment = {
  value: Theme;
  label: string;
  ariaLabel: string;
  Icon: (props: { className?: string }) => React.JSX.Element;
};

const SEGMENTS: readonly Segment[] = [
  { value: "dark", label: "Dark", ariaLabel: "Dark theme", Icon: MoonIcon },
  { value: "light", label: "Light", ariaLabel: "Light theme", Icon: SunIcon },
  {
    value: "system",
    label: "System",
    ariaLabel: "Follow system theme",
    Icon: MonitorIcon,
  },
];

export function ThemeToggle({ collapsed }: { collapsed: boolean }) {
  const { theme, setTheme } = useTheme();
  const buttonsRef = useRef<Array<HTMLButtonElement | null>>([]);

  if (collapsed) {
    const currentIndex = SEGMENTS.findIndex((s) => s.value === theme);
    const safeIndex = currentIndex === -1 ? 0 : currentIndex;
    const current = SEGMENTS[safeIndex] ?? SEGMENTS[0]!;
    const nextIndex = (safeIndex + 1) % SEGMENTS.length;
    const next = SEGMENTS[nextIndex] ?? SEGMENTS[0]!;
    return (
      <button
        type="button"
        data-testid="theme-cycle-button"
        onClick={() => setTheme(next.value)}
        aria-label={`Theme: ${current.label}`}
        className={[
          "flex h-9 w-9 items-center justify-center rounded-full",
          "border border-soleur-border-default bg-soleur-bg-surface-2",
          "text-soleur-accent-gold-fg transition-colors",
          "hover:ring-1 hover:ring-inset hover:ring-soleur-border-emphasized",
          "focus-visible:outline focus-visible:outline-2",
          "focus-visible:outline-offset-2 focus-visible:outline-soleur-border-emphasized",
        ].join(" ")}
      >
        <current.Icon className="h-4 w-4" />
      </button>
    );
  }

  function handleKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    const key = event.key;
    if (key !== "ArrowLeft" && key !== "ArrowRight" && key !== "Home" && key !== "End") {
      return;
    }
    event.preventDefault();
    const currentIndex = SEGMENTS.findIndex((s) => s.value === theme);
    const safeIndex = currentIndex === -1 ? 0 : currentIndex;
    let nextIndex = safeIndex;
    if (key === "ArrowLeft") {
      nextIndex = (safeIndex - 1 + SEGMENTS.length) % SEGMENTS.length;
    } else if (key === "ArrowRight") {
      nextIndex = (safeIndex + 1) % SEGMENTS.length;
    } else if (key === "Home") {
      nextIndex = 0;
    } else if (key === "End") {
      nextIndex = SEGMENTS.length - 1;
    }
    const next = SEGMENTS[nextIndex];
    if (!next) return;
    setTheme(next.value);
    buttonsRef.current[nextIndex]?.focus();
  }

  return (
    <div
      role="group"
      aria-label="Theme"
      onKeyDown={handleKeyDown}
      className="flex h-8 w-full items-stretch border border-soleur-border-default"
    >
      {SEGMENTS.map((seg, index) => {
        const active = theme === seg.value;
        return (
          <button
            key={seg.value}
            ref={(el) => {
              buttonsRef.current[index] = el;
            }}
            type="button"
            onClick={() => setTheme(seg.value)}
            aria-pressed={active}
            aria-label={seg.ariaLabel}
            title={seg.label}
            className={[
              "flex flex-1 items-center justify-center transition-colors",
              "border-r border-soleur-border-default last:border-r-0",
              active
                ? "bg-soleur-bg-surface-2 text-soleur-accent-gold-fg ring-1 ring-inset ring-soleur-border-emphasized"
                : "text-soleur-text-muted hover:text-soleur-text-secondary",
            ].join(" ")}
          >
            <seg.Icon className="h-3 w-3" />
          </button>
        );
      })}
    </div>
  );
}

/* Inline SVG icons — matches the codebase pattern (see app/(dashboard)/layout.tsx).
   Stroke 1.5 / 24x24 viewBox, sized via className from the parent. */

function MoonIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
      aria-hidden="true"
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M21.752 15.002A9.718 9.718 0 0 1 18 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 0 0 3 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 0 0 9.002-5.998Z"
      />
    </svg>
  );
}

function SunIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
      aria-hidden="true"
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M12 3v2.25m6.364.386-1.591 1.591M21 12h-2.25m-.386 6.364-1.591-1.591M12 18.75V21m-4.773-4.227-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z"
      />
    </svg>
  );
}

function MonitorIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
      aria-hidden="true"
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25"
      />
    </svg>
  );
}
