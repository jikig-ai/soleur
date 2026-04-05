"use client";

import { GOLD_GRADIENT } from "./constants";

export function GoldButton({
  children,
  onClick,
  disabled,
  type = "button",
}: {
  children: React.ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  type?: "button" | "submit";
}) {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className="rounded-lg px-6 py-3 text-sm font-medium text-black transition-opacity hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed"
      style={{ background: GOLD_GRADIENT }}
    >
      {children}
    </button>
  );
}
