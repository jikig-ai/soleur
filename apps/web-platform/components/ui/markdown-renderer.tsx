"use client";

import Markdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeHighlight from "rehype-highlight";
import type { Components } from "react-markdown";

// Module-level variable set before creating components — avoids threading
// a prop through every component definition.
let linkRel = "noopener noreferrer";

function buildComponents(): Components {
  return {
  h1: ({ children }) => (
    <h1 className="mb-3 mt-4 text-lg font-semibold text-white">{children}</h1>
  ),
  h2: ({ children }) => (
    <h2 className="mb-2 mt-3 text-base font-semibold text-white">{children}</h2>
  ),
  h3: ({ children }) => (
    <h3 className="mb-2 mt-3 text-sm font-semibold text-neutral-200">{children}</h3>
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
    <li className="text-neutral-200">{children}</li>
  ),
  table: ({ children }) => (
    <div className="mb-3 overflow-x-auto">
      <table className="w-full border-collapse text-sm">{children}</table>
    </div>
  ),
  th: ({ children }) => (
    <th className="border border-neutral-700 bg-neutral-800/50 px-3 py-1.5 text-left font-semibold text-neutral-200">
      {children}
    </th>
  ),
  td: ({ children }) => (
    <td className="border border-neutral-700 px-3 py-1.5 text-neutral-300">{children}</td>
  ),
  pre: ({ children }) => (
    <pre className="mb-3 overflow-x-auto rounded-lg bg-neutral-950 p-3 text-xs text-neutral-300">
      {children}
    </pre>
  ),
  code: ({ className, children }) => {
    // Block code: has a language class from rehype-highlight or fenced blocks
    const isBlock = /language-|hljs/.test(className || "");
    return isBlock ? (
      <code className={className}>{children}</code>
    ) : (
      <code className="rounded bg-neutral-800 px-1.5 py-0.5 text-xs text-amber-300">{children}</code>
    );
  },
  strong: ({ children }) => (
    <strong className="font-semibold text-white">{children}</strong>
  ),
  a: ({ href, children }) => (
    <a href={href} target="_blank" rel={linkRel}
      className="text-amber-400 underline hover:text-amber-300">{children}</a>
  ),
  blockquote: ({ children }) => (
    <blockquote className="mb-2 border-l-2 border-neutral-600 pl-3 italic text-neutral-400">
      {children}
    </blockquote>
  ),
  };
}

const REMARK_PLUGINS = [remarkGfm];
const DISALLOWED_ELEMENTS = ["script", "iframe", "form", "object", "embed", "style", "link"];

const REHYPE_PLUGINS = [rehypeHighlight];

const DEFAULT_COMPONENTS = buildComponents();

interface MarkdownRendererProps {
  content: string;
  /** Add rel="nofollow" to all links (used for public shared documents). */
  nofollow?: boolean;
}

export function MarkdownRenderer({ content, nofollow }: MarkdownRendererProps) {
  // Update module-level linkRel before rendering.
  linkRel = nofollow
    ? "nofollow noopener noreferrer"
    : "noopener noreferrer";

  return (
    <Markdown
      remarkPlugins={REMARK_PLUGINS}
      rehypePlugins={REHYPE_PLUGINS}
      components={DEFAULT_COMPONENTS}
      disallowedElements={DISALLOWED_ELEMENTS}
      unwrapDisallowed
    >
      {content}
    </Markdown>
  );
}
