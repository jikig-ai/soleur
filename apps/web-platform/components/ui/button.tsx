"use client";

import { Children, isValidElement, useEffect, useState } from "react";
import type { ComponentPropsWithRef, ReactNode } from "react";
import { SpinnerIcon } from "@/components/icons";
import { PENDING_ENTRY_DELAY_MS } from "@/lib/pending-timing";
import { GOLD_GRADIENT } from "./constants";

export type ButtonVariant = "gold" | "outlined" | "ghost" | "danger";

export type ButtonProps = ComponentPropsWithRef<"button"> & {
  variant?: ButtonVariant;
  loading?: boolean;
  loadingLabel?: string;
  modal?: boolean;
};

const VARIANT_CLASSES: Record<ButtonVariant, string> = {
  gold: "text-soleur-text-on-accent hover:opacity-90",
  outlined:
    "border border-soleur-border-default bg-transparent text-soleur-text-primary hover:bg-soleur-bg-surface-2",
  ghost:
    "bg-transparent text-soleur-text-secondary hover:bg-soleur-bg-surface-2",
  danger: "bg-red-600 text-soleur-text-on-accent hover:bg-red-500",
};

const SPINNER_CLASSES: Record<ButtonVariant, string> = {
  gold: "text-soleur-text-on-accent",
  outlined: "text-soleur-accent-gold-fg",
  ghost: "text-soleur-text-muted",
  danger: "text-current",
};

function hasTextChild(children: ReactNode): boolean {
  let found = false;
  Children.forEach(children, (child) => {
    if (found) return;
    if (typeof child === "string") {
      if (child.trim().length > 0) found = true;
    } else if (typeof child === "number") {
      found = true;
    } else if (isValidElement<{ children?: ReactNode }>(child)) {
      if (hasTextChild(child.props.children)) found = true;
    }
  });
  return found;
}

function pendingLabelText(label: string): string {
  return `${label.trim().replace(/[.…]+$/, "").trimEnd()}…`;
}

export function Button({
  variant = "outlined",
  loading = false,
  loadingLabel,
  modal = false,
  disabled,
  className,
  style,
  children,
  "aria-label": ariaLabel,
  "aria-busy": ariaBusy,
  ref,
  ...rest
}: ButtonProps) {
  const [spinnerVisible, setSpinnerVisible] = useState(false);

  useEffect(() => {
    if (!loading) {
      setSpinnerVisible(false);
      return;
    }
    const timer = setTimeout(
      () => setSpinnerVisible(true),
      PENDING_ENTRY_DELAY_MS,
    );
    return () => clearTimeout(timer);
  }, [loading]);

  const showSpinner = loading && spinnerVisible;
  const iconOnly = !hasTextChild(children);
  const pendingOpacity = modal
    ? "disabled:opacity-[0.65]"
    : "disabled:opacity-[0.55]";

  // Base box (`soleur-btn`) and text-button padding (`soleur-btn-pad`) are
  // defined in app/globals.css under `@layer components` so caller utilities
  // always win. The padding literals are therefore not greppable in this file.
  return (
    <button
      ref={ref}
      disabled={disabled || loading}
      aria-busy={loading || ariaBusy || undefined}
      aria-label={ariaLabel}
      className={`soleur-btn ${iconOnly ? "" : "soleur-btn-pad"} transition-[transform,opacity,background-color,border-color,color] duration-[120ms] active:scale-[0.98] active:opacity-90 motion-reduce:active:scale-100 disabled:cursor-not-allowed ${loading ? pendingOpacity : "disabled:opacity-50"} ${VARIANT_CLASSES[variant]} ${className ?? ""}`}
      style={
        variant === "gold"
          ? { background: GOLD_GRADIENT, ...style }
          : style
      }
      {...rest}
    >
      {showSpinner && iconOnly ? (
        <span
          aria-hidden="true"
          className="relative inline-flex items-center justify-center"
        >
          <span className="invisible inline-flex items-center justify-center">
            {children}
          </span>
          <SpinnerIcon
            className={`absolute left-1/2 top-1/2 h-3.5 w-3.5 -translate-x-1/2 -translate-y-1/2 ${SPINNER_CLASSES[variant]}`}
          />
        </span>
      ) : (
        <>
          {showSpinner ? (
            <SpinnerIcon
              className={`h-3.5 w-3.5 shrink-0 ${SPINNER_CLASSES[variant]}`}
            />
          ) : null}
          {loading && loadingLabel ? pendingLabelText(loadingLabel) : children}
        </>
      )}
    </button>
  );
}
