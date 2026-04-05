"use client";

export function OutlinedButton({
  children,
  onClick,
}: {
  children: React.ReactNode;
  onClick?: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="rounded-lg border border-neutral-700 bg-transparent px-6 py-3 text-sm font-medium text-neutral-200 transition-colors hover:bg-neutral-800"
    >
      {children}
    </button>
  );
}
