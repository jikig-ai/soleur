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
      className="rounded-lg border border-soleur-border-default bg-transparent px-6 py-3 text-sm font-medium text-soleur-text-primary transition-colors hover:bg-soleur-bg-surface-2"
    >
      {children}
    </button>
  );
}
