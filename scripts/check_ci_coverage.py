#!/usr/bin/env python3
"""Keep CI package test coverage aligned with V test files and forbid local wrappers."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
PACKAGE_LINE = re.compile(r"^\s+packages:\s+'([^']*)'\s*$", re.MULTILINE)


def main() -> int:
    errors: list[str] = []
    covered: set[str] = set()
    forbidden = "systemd" + "-run"

    for workflow in sorted(WORKFLOWS.rglob("*")):
        if not workflow.is_file() or workflow.suffix not in (".yml", ".yaml"):
            continue
        contents = workflow.read_text(encoding="utf-8")
        if forbidden in contents:
            errors.append(
                f"{workflow.relative_to(ROOT)}: CI must run commands directly; "
                f"{forbidden} is reserved for local workstation limits"
            )
        for package_list in PACKAGE_LINE.findall(contents):
            for package in package_list.split():
                covered.add(package.removeprefix("./").rstrip("/"))

    tested = {
        test_file.parent.relative_to(ROOT).as_posix()
        for test_file in ROOT.rglob("*_test.v")
        if ".git" not in test_file.parts
    }
    for package in sorted(tested - covered):
        errors.append(f"{package}: has V tests but is missing from the CI package matrix")

    for package in sorted(covered - tested):
        errors.append(f"{package}: appears in the CI package matrix but has no direct V test files")

    if errors:
        print("CI package coverage check failed:")
        print("\n".join(f"- {error}" for error in errors))
        return 1

    print(f"CI matrix covers all {len(tested)} V test packages; no workstation wrappers found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
