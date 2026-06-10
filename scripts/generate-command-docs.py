#!/usr/bin/env python3
"""Generate docs/COMMANDS.md from live `relato --help` output."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = REPO_ROOT / "docs" / "COMMANDS.md"


def run_help_text() -> str:
    proc = subprocess.run(
        ["swift", "run", "relato", "--help"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return proc.stdout or proc.stderr


def parse_commands(help_text: str) -> list[str]:
    commands: list[str] = []
    in_commands = False
    for line in help_text.splitlines():
        stripped = line.strip()
        if stripped == "Commands:":
            in_commands = True
            continue
        if in_commands and stripped.startswith("relato "):
            commands.append(stripped)
    return commands


def render(commands: list[str]) -> str:
    lines = [
        "# Command Reference",
        "",
        "This file is generated from live CLI help output.",
        "",
        "Authoritative help:",
        "",
        "```sh",
        "relato --help",
        "```",
        "",
        "To regenerate:",
        "",
        "```sh",
        "make generate-command-docs",
        "```",
        "",
        "## Commands",
        "",
    ]
    for command in commands:
        lines.append(f"- `{command}`")
    lines.extend(
        [
            "",
            "## Scripting Tips",
            "",
            "- Use `relato submit --dry-run` before `--confirm` to preview the native handoff plan.",
            "- Use `relato open ROUTE --print-only` when you only need the Feedback Assistant URL.",
            "- Use `relato store summary` and `relato store list` for local verification after native submission.",
            "- Treat local store verification as local evidence, not an Apple server receipt.",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate docs/COMMANDS.md from live CLI help")
    parser.add_argument("--check", action="store_true", help="Fail if docs/COMMANDS.md is out of date")
    args = parser.parse_args()

    generated = render(parse_commands(run_help_text()))

    if args.check:
        current = OUTPUT_PATH.read_text() if OUTPUT_PATH.exists() else ""
        if current != generated:
            print("docs/COMMANDS.md is out of date.")
            print("Run: make generate-command-docs")
            return 1
        print("docs/COMMANDS.md is up to date.")
        return 0

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(generated)
    print(f"Generated {OUTPUT_PATH.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
