#!/usr/bin/env python3
"""Ensure every documented provider adapter appears in the site catalog."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "docs" / "providers.md"
LINK_PATTERN = re.compile(
    r"https://github\.com/ulises-jeremias/langchainv/blob/main/"
    r"((?:llms|embeddings|vectorstores)/[^)\s]+/README\.md)"
)
ADAPTER_GROUPS = ("llms", "embeddings", "vectorstores")


def main() -> int:
    catalog = CATALOG.read_text(encoding="utf-8")
    linked = set(LINK_PATTERN.findall(catalog))
    expected = {
        readme.relative_to(ROOT).as_posix()
        for group in ADAPTER_GROUPS
        for readme in (ROOT / group).glob("*/README.md")
    }
    missing = sorted(expected - linked)
    stale = sorted(linked - expected)

    if missing or stale:
        print("Provider catalog check failed:")
        for path in missing:
            print(f"- missing catalog entry for {path}")
        for path in stale:
            print(f"- catalog entry has no matching adapter guide: {path}")
        return 1

    print(f"Catalog covers all {len(expected)} model, embedding, and vector store guides.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
