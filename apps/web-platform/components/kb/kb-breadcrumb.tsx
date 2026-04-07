"use client";

import Link from "next/link";

export function KbBreadcrumb({ path }: { path: string }) {
  const segments = path.split("/");

  return (
    <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-neutral-500">
      {segments.map((segment, i) => {
        const isLast = i === segments.length - 1;
        const href = `/dashboard/kb/${segments.slice(0, i + 1).join("/")}`;

        return (
          <span key={i} className="flex items-center gap-1">
            {i > 0 && <span>/</span>}
            {isLast ? (
              <span className="text-neutral-300">{segment}</span>
            ) : (
              <Link
                href={href}
                className="hover:text-neutral-300 transition-colors"
              >
                {segment}
              </Link>
            )}
          </span>
        );
      })}
    </nav>
  );
}
