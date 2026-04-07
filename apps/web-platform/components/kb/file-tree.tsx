"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useKb } from "./kb-context";
import type { TreeNode } from "@/server/kb-reader";

export function FileTree() {
  const { tree, expanded, toggleExpanded } = useKb();

  if (!tree?.children?.length) return null;

  return (
    <nav aria-label="Knowledge base file tree">
      <ul className="space-y-0.5">
        {tree.children.map((node) => (
          <TreeItem
            key={node.name}
            node={node}
            depth={0}
            parentPath=""
            expanded={expanded}
            onToggle={toggleExpanded}
          />
        ))}
      </ul>
    </nav>
  );
}

function TreeItem({
  node,
  depth,
  parentPath,
  expanded,
  onToggle,
}: {
  node: TreeNode;
  depth: number;
  parentPath: string;
  expanded: Set<string>;
  onToggle: (path: string) => void;
}) {
  const pathname = usePathname();
  // Cap visual indent at 3 levels
  const indent = Math.min(depth, 3);
  const paddingLeft = `${indent * 12 + 8}px`;

  if (node.type === "directory") {
    const dirKey = parentPath ? `${parentPath}/${node.name}` : node.name;
    const isExpanded = expanded.has(dirKey);

    return (
      <li>
        <button
          onClick={() => onToggle(dirKey)}
          className="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-neutral-300 hover:bg-neutral-800/50"
          style={{ paddingLeft }}
          aria-expanded={isExpanded}
        >
          <svg
            width="12"
            height="12"
            viewBox="0 0 12 12"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.5"
            className={`shrink-0 transition-transform ${isExpanded ? "rotate-90" : ""}`}
          >
            <path d="M4.5 2.5 8 6 4.5 9.5" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          <FolderIcon />
          <span className="truncate font-medium">{node.name}</span>
          {node.modifiedAt && (
            <span className="ml-auto shrink-0 text-xs text-neutral-600">
              {formatRelativeTime(node.modifiedAt)}
            </span>
          )}
        </button>
        {isExpanded && node.children && (
          <ul className="space-y-0.5">
            {node.children.map((child) => (
              <TreeItem
                key={child.name}
                node={child}
                depth={depth + 1}
                parentPath={dirKey}
                expanded={expanded}
                onToggle={onToggle}
              />
            ))}
          </ul>
        )}
      </li>
    );
  }

  // File node
  const filePath = `/dashboard/kb/${node.path}`;
  const isActive = pathname === filePath;

  return (
    <li>
      <Link
        href={filePath}
        className={`flex items-center gap-2 rounded-md px-2 py-1.5 text-sm transition-colors ${
          isActive
            ? "bg-neutral-800 text-amber-400"
            : "text-neutral-400 hover:bg-neutral-800/50 hover:text-neutral-200"
        }`}
        style={{ paddingLeft }}
      >
        <FileIcon />
        <span className="truncate">{node.name}</span>
        {node.modifiedAt && (
          <span className="ml-auto shrink-0 text-xs text-neutral-600">
            {formatRelativeTime(node.modifiedAt)}
          </span>
        )}
      </Link>
    </li>
  );
}

function formatRelativeTime(iso: string): string {
  const now = Date.now();
  const then = new Date(iso).getTime();
  const diffMs = now - then;
  const diffSec = Math.floor(diffMs / 1_000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHr = Math.floor(diffMin / 60);
  const diffDay = Math.floor(diffHr / 24);
  const diffWeek = Math.floor(diffDay / 7);

  if (diffSec < 60) return "just now";
  if (diffMin < 60) return `${diffMin}m ago`;
  if (diffHr < 24) return `${diffHr}h ago`;
  if (diffDay < 7) return `${diffDay}d ago`;
  if (diffWeek < 52) return `${diffWeek}w ago`;
  return `${Math.floor(diffDay / 365)}y ago`;
}

function FolderIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="shrink-0 text-amber-500/70">
      <path d="M2 7.5V19a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 4H4a2 2 0 0 0-2 2Z" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function FileIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="shrink-0 text-neutral-500">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M14 2v6h6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
