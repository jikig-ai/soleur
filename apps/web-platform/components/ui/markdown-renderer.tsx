"use client";

import { useMemo } from "react";
import Markdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeHighlight from "rehype-highlight";
import type { Components } from "react-markdown";

// Per-render component builder. We used to share a module-level
// `DEFAULT_COMPONENTS` with two mutable `let` flags (`linkRel`, `preWrap`);
// that races across co-mounted MarkdownRenderer instances because the
// components closure captured the `let` bindings, so the last renderer
// wrote always won. See review finding #2380.
interface BuildOptions {
  linkRel: string;
  preWrap: boolean;
}

function buildComponents({ linkRel, preWrap }: BuildOptions): Components {
  return {
    h1: ({ children }) => (
      <h1 className="mb-3 mt-4 text-lg font-semibold text-soleur-text-primary">{children}</h1>
    ),
    h2: ({ children }) => (
      <h2 className="mb-2 mt-3 text-base font-semibold text-soleur-text-primary">{children}</h2>
    ),
    h3: ({ children }) => (
      <h3 className="mb-2 mt-3 text-sm font-semibold text-soleur-text-primary">{children}</h3>
    ),
    p: ({ children }) => (
      <p className="mb-2 leading-relaxed">{children}</p>
    ),
    ul: ({ children }) => (
      <ul className="mb-2 ml-4 list-disc space-y-1">{children}</ul>
    ),
    ol: ({ children }) => (
      <ol className="mb-2 ml-4 list-decimal space-y-1">{children}</ol>
    ),
    li: ({ children }) => (
      <li className="text-soleur-text-secondary">{children}</li>
    ),
    table: ({ children }) => (
      <div className="mb-3 overflow-x-auto">
        <table className="w-auto border-collapse text-sm">{children}</table>
      </div>
    ),
    th: ({ children }) => (
      <th className="whitespace-nowrap border border-soleur-border-default bg-soleur-bg-surface-2/50 px-3 py-1.5 text-left font-semibold text-soleur-text-primary">
        {children}
      </th>
    ),
    // 8ch keeps single-token / empty cells visible; 40ch caps prose cells to a
    // readable line so a single long-paragraph cell doesn't blow out the table.
    // Header may exceed 40ch (whitespace-nowrap on th wins) by design.
    td: ({ children }) => (
      <td className="min-w-[8ch] max-w-[40ch] border border-soleur-border-default px-3 py-1.5 align-top text-soleur-text-secondary">{children}</td>
    ),
    pre: ({ children }) => (
      <pre
        className={
          preWrap
            ? "mb-3 min-w-0 whitespace-pre-wrap break-words rounded-lg bg-soleur-bg-base p-3 text-xs text-soleur-text-secondary [overflow-wrap:anywhere]"
            : "mb-3 overflow-x-auto rounded-lg bg-soleur-bg-base p-3 text-xs text-soleur-text-secondary"
        }
      >
        {children}
      </pre>
    ),
    code: ({ className, children }) => {
      const isBlock = /language-|hljs/.test(className || "");
      return isBlock ? (
        <code className={className}>{children}</code>
      ) : (
        <code className="rounded bg-soleur-bg-surface-2 px-1.5 py-0.5 text-xs text-soleur-accent-gold-fg">{children}</code>
      );
    },
    strong: ({ children }) => (
      <strong className="font-semibold text-soleur-text-primary">{children}</strong>
    ),
    a: ({ href, children }) => (
      <a href={href} target="_blank" rel={linkRel}
        className="text-soleur-accent-gold-fg underline hover:text-soleur-accent-gold-text">{children}</a>
    ),
    blockquote: ({ children }) => (
      <blockquote className="mb-2 border-l-2 border-soleur-border-default pl-3 italic text-soleur-text-muted">
        {children}
      </blockquote>
    ),
  };
}

const REMARK_PLUGINS = [remarkGfm];
const DISALLOWED_ELEMENTS = ["script", "iframe", "form", "object", "embed", "style", "link"];
const REHYPE_PLUGINS = [rehypeHighlight];

interface MarkdownRendererProps {
  content: string;
  /** Add rel="nofollow" to all links (used for public shared documents). */
  nofollow?: boolean;
  /** When true, fenced code blocks wrap instead of scrolling horizontally.
   *  Set by sidebar-variant callers where the 380px column makes horizontal
   *  scroll unreadable. Plan Phase 3.1 / AC10. */
  wrapCode?: boolean;
}

export function MarkdownRenderer({ content, nofollow, wrapCode }: MarkdownRendererProps) {
  const components = useMemo(
    () =>
      buildComponents({
        linkRel: nofollow ? "nofollow noopener noreferrer" : "noopener noreferrer",
        preWrap: !!wrapCode,
      }),
    [nofollow, wrapCode],
  );

  return (
    <div
      className="min-w-0 [overflow-wrap:anywhere]"
      data-narrow-wrap={wrapCode ? "true" : undefined}
    >
      <Markdown
        remarkPlugins={REMARK_PLUGINS}
        rehypePlugins={REHYPE_PLUGINS}
        components={components}
        disallowedElements={DISALLOWED_ELEMENTS}
        unwrapDisallowed
      >
        {content}
      </Markdown>
    </div>
  );
}
