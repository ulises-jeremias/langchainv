#!/usr/bin/env python3
"""Check local links and fragments in a generated static site."""

from __future__ import annotations

import argparse
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit


class SiteParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links: list[str] = []
        self.anchors: set[str] = set()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        for key in ("id", "name"):
            if values.get(key):
                self.anchors.add(values[key] or "")
        for key in ("href", "src"):
            value = values.get(key)
            if value:
                self.links.append(value)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("site", type=Path, help="generated site directory")
    parser.add_argument("--baseurl", default="/langchainv", help="site base path")
    args = parser.parse_args()
    site = args.site.resolve()
    errors: list[str] = []
    pages: dict[Path, SiteParser] = {}

    for html_file in site.rglob("*.html"):
        page_parser = SiteParser()
        page_parser.feed(html_file.read_text(encoding="utf-8"))
        pages[html_file.resolve()] = page_parser

    base = args.baseurl.rstrip("/")
    for current, page_parser in list(pages.items()):
        current_url = (
            "https://site.invalid"
            + base
            + "/"
            + current.relative_to(site).as_posix()
        )
        for link in page_parser.links:
            target = urlsplit(urljoin(current_url, link))
            if target.scheme not in ("http", "https") or target.netloc != "site.invalid":
                continue
            path = unquote(target.path)
            if base and (path == base or path.startswith(base + "/")):
                path = path[len(base) :] or "/"
            relative = Path(path.lstrip("/"))
            destination = (site / relative).resolve()
            if not destination.is_relative_to(site):
                errors.append(f"{current.relative_to(site)}: target escapes site root {link}")
                continue
            if destination.is_dir() or path.endswith("/"):
                destination = destination / "index.html"
            if not destination.exists():
                errors.append(f"{current.relative_to(site)}: missing local target {link}")
                continue
            if target.fragment and destination.suffix == ".html":
                target_parser = pages.get(destination)
                if target_parser is None:
                    target_parser = SiteParser()
                    target_parser.feed(destination.read_text(encoding="utf-8"))
                    pages[destination] = target_parser
                fragment = unquote(target.fragment)
                if fragment not in target_parser.anchors:
                    errors.append(f"{current.relative_to(site)}: missing fragment {link}")

    if errors:
        print("Generated site link check failed:")
        print("\n".join(f"- {error}" for error in errors))
        return 1
    print(f"Checked local links in {len(pages)} generated HTML pages.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
