#!/usr/bin/env python3
"""Tests for scripts/backfill-frontmatter.py — recursion + extract hardening.

Covers Stage 2 invariants for #4163:
- extract_inline_tags rejects bullet-list noise (--<digits>, category-*,
  module-*, >50-char tokens) from the `## Tags` YAML-block branch ONLY.
- The `**Tags:**` inline comma-form path preserves legitimate prefix-tokens
  like `category-design` and `module-level-state`.
- iter_learning_files walks subdirs and skips README.md case-insensitively.
"""

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT_PATH = SCRIPT_DIR / "backfill-frontmatter.py"

spec = importlib.util.spec_from_file_location("backfill_frontmatter", SCRIPT_PATH)
bf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bf)


# Fixture A: synthesized ## Tags structured-kv that includes a value
# matching the reject pattern. The plan applies the filter at BOTH return
# paths inside the `## Tags` branch — this fixture verifies the structured
# path is filtered (real-world structured-kv values like `integration-issues`,
# `medium` don't match the reject prefixes, so without a synthetic value
# the test would pass vacuously regardless of the filter).
FIXTURE_TAGS_BLOCK_KV_WITH_NOISE = """# Body

## Tags

category: ok-value
severity: --synthetic-noise
"""

# Fixture B: **Tags:** inline form — must preserve legitimate prefix-tokens
FIXTURE_INLINE_TAGS_SENTINELS = """# Body

**Tags:** category-design, module-level-state, ui, react
"""

# Fixture C: canonical 82584251 corruption shape — ## Tags block with
# `key: value` rows AND `  - "id"` sub-bullets. Sub-bullets lack ":" so
# the `all(":" in line)` precondition trips and the whole raw block goes
# through normalize_tags() (the fallback path). Without hardening this
# emits ['category-integration-issues', 'module-marketing-aeo', 'prs',
# '--2794', 'closes', '--2707', 'follow-up', '--2799'].
FIXTURE_TAGS_BLOCK_FALLBACK = """# Body

## Tags

category: integration-issues
module: marketing-aeo
prs:
  - "2794"
closes:
  - "2707"
  - "2708"
follow-up:
  - "2799"
"""


class ExtractInlineTagsHardeningTest(unittest.TestCase):
    def test_structured_kv_path_filter_drops_synthesized_noise(self):
        tags = bf.extract_inline_tags(FIXTURE_TAGS_BLOCK_KV_WITH_NOISE)
        # Clean value survives.
        self.assertIn("ok-value", tags)
        # Synthesized noise value is filtered out.
        self.assertNotIn("--synthetic-noise", tags)
        self.assertFalse(
            any(t.startswith("--") for t in tags),
            f"-- leaked from kv path: {tags}",
        )

    def test_inline_form_preserves_legitimate_prefix_tokens(self):
        tags = bf.extract_inline_tags(FIXTURE_INLINE_TAGS_SENTINELS)
        self.assertIn("category-design", tags)
        self.assertIn("module-level-state", tags)

    def test_inline_form_is_not_subject_to_yaml_block_filter(self):
        # Locks the design invariant: _reject_yaml_block_noise is scoped to
        # the `## Tags` branch ONLY. A future refactor that moves the filter
        # call up to normalize_tags would silently strip authored tokens from
        # the inline comma-form. Synthetic --prefix token simulates that
        # regression.
        content = "# Body\n\n**Tags:** category-design, --legit-edge, normal\n"
        tags = bf.extract_inline_tags(content)
        self.assertIn("--legit-edge", tags)
        self.assertIn("category-design", tags)

    def test_block_fallback_path_drops_bullet_noise(self):
        # The canonical 82584251 corruption shape.
        tags = bf.extract_inline_tags(FIXTURE_TAGS_BLOCK_FALLBACK)
        self.assertFalse(
            any(t.startswith("--") for t in tags),
            f"--<digits> leaked: {tags}",
        )
        self.assertFalse(
            any(t.startswith("category-") for t in tags),
            f"category-* leaked: {tags}",
        )
        self.assertFalse(
            any(t.startswith("module-") for t in tags),
            f"module-* leaked: {tags}",
        )
        self.assertFalse(
            any(len(t) > 50 for t in tags),
            f">50-char token leaked: {tags}",
        )


class IterLearningFilesTest(unittest.TestCase):
    def test_walks_subdirs_and_skips_readme(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "top.md").write_text("# top\n")
            sub = Path(tmp) / "sub"
            sub.mkdir()
            (sub / "nested.md").write_text("# nested\n")
            (sub / "README.md").write_text("# readme\n")
            (sub / "readme.md").write_text("# readme lc\n")  # case-insensitive skip
            (sub / "not-md.txt").write_text("ignored\n")
            archive = sub / "archive"
            archive.mkdir()
            (archive / "old.md").write_text("# old\n")

            results = sorted(os.path.basename(fp) for fp in bf.iter_learning_files(tmp))

        self.assertEqual(results, ["nested.md", "old.md", "top.md"])


if __name__ == "__main__":
    unittest.main()
