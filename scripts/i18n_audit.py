#!/usr/bin/env python3
"""Audit StibAlert string catalog coverage and hardcoded Swift UI strings.

Usage:
  python3 scripts/i18n_audit.py
  python3 scripts/i18n_audit.py --write-report /tmp/i18n.md
  python3 scripts/i18n_audit.py --export-missing /tmp/i18n-missing.csv
  python3 scripts/i18n_audit.py --export-hardcoded /tmp/i18n-hardcoded.csv
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = ROOT / "StibAlert"
CATALOG = APP_ROOT / "Localizable.xcstrings"

PRIORITY_FILE_PREFIXES = (
    "StibAlert/View/Home/",
    "StibAlert/View/Reports/",
    "StibAlert/View/Report/",
    "StibAlert/View/Signalements/",
    "StibAlert/View/Favorites/",
    "StibAlert/View/Auth/",
    "StibAlert/View/Onboarding/",
    "StibAlert/OnBoardingView.swift",
    "StibAlert/SplashView.swift",
    "StibAlert/Intents/",
)

UI_STRING_PATTERNS = [
    ("Text", re.compile(r'\bText\("((?:[^"\\]|\\.)+)"\)')),
    ("Button", re.compile(r'\bButton\("((?:[^"\\]|\\.)+)"')),
    ("Label", re.compile(r'\bLabel\("((?:[^"\\]|\\.)+)"')),
    ("TextField", re.compile(r'\bTextField\("((?:[^"\\]|\\.)*)"')),
    ("navigationTitle", re.compile(r'\.navigationTitle\("((?:[^"\\]|\\.)+)"\)')),
    ("accessibilityLabel", re.compile(r'\.accessibilityLabel\("((?:[^"\\]|\\.)+)"\)')),
    ("promptText", re.compile(r'prompt:\s*Text\("((?:[^"\\]|\\.)+)"\)')),
    ("StringLocalized", re.compile(r'\bString\(localized:\s*"((?:[^"\\]|\\.)+)"\)')),
    ("titleArg", re.compile(r'\btitle:\s*"((?:[^"\\]|\\.)+)"')),
    ("subtitleArg", re.compile(r'\bsubtitle:\s*"((?:[^"\\]|\\.)+)"')),
    ("messageArg", re.compile(r'\bmessage:\s*"((?:[^"\\]|\\.)+)"')),
]


def load_catalog() -> dict:
    if not CATALOG.exists():
        raise SystemExit(f"Missing string catalog: {CATALOG}")
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def catalog_stats(catalog: dict) -> tuple[list[str], dict[str, dict[str, int]]]:
    strings = catalog.get("strings", {})
    source_language = catalog.get("sourceLanguage")
    locales = sorted(
        {
            locale
            for item in strings.values()
            for locale in item.get("localizations", {}).keys()
        } | ({source_language} if source_language else set())
    )
    stats: dict[str, dict[str, int]] = {}
    for locale in locales:
        translated = 0
        needs_review = 0
        for item in strings.values():
            unit = item.get("localizations", {}).get(locale, {}).get("stringUnit", {})
            value = unit.get("value", "")
            state = unit.get("state", "")
            if value:
                translated += 1
            if state in {"new", "needs_review"}:
                needs_review += 1
        if locale == source_language:
            translated = len(strings)
        stats[locale] = {
            "translated": translated,
            "missing": len(strings) - translated,
            "needs_review": needs_review,
            "total": len(strings),
        }
    return locales, stats


def should_ignore(value: str) -> bool:
    stripped = value.strip()
    if not stripped:
        return True
    if len(stripped) <= 2 and not any(ch.isalpha() for ch in stripped):
        return True
    if re.fullmatch(r"[%@\d\s:./+<>\-–—·|]+", stripped):
        return True
    return False


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def decode_swift_string(value: str) -> str:
    return (
        value
        .replace(r"\"", '"')
        .replace(r"\n", "\n")
        .replace(r"\t", "\t")
        .replace(r"\\", "\\")
    )


def normalized_catalog_key(value: str) -> str:
    return value.strip()


def swift_ui_candidates(catalog_keys: set[str] | None = None) -> list[dict[str, str | int]]:
    candidates: list[dict[str, str | int]] = []
    catalog_keys = catalog_keys or set()
    for path in sorted(APP_ROOT.rglob("*.swift")):
        rel = path.relative_to(ROOT)
        text = path.read_text(encoding="utf-8", errors="ignore")
        for pattern_name, pattern in UI_STRING_PATTERNS:
            for match in pattern.finditer(text):
                value = decode_swift_string(match.group(1))
                if should_ignore(value):
                    continue
                if normalized_catalog_key(value) in catalog_keys:
                    continue
                candidates.append(
                    {
                        "file": str(rel),
                        "line": line_number(text, match.start()),
                        "pattern": pattern_name,
                        "value": value,
                    }
                )
    return candidates


def priority_candidates(candidates: list[dict[str, str | int]]) -> list[dict[str, str | int]]:
    return [
        item
        for item in candidates
        if any(str(item["file"]).startswith(prefix) for prefix in PRIORITY_FILE_PREFIXES)
    ]


def missing_rows(catalog: dict) -> list[dict[str, str]]:
    strings = catalog.get("strings", {})
    source_language = catalog.get("sourceLanguage")
    rows: list[dict[str, str]] = []
    for key in sorted(strings.keys(), key=str.casefold):
        item = strings[key]
        comment = item.get("comment", "")
        for locale in ["nl", "en"]:
            if locale == source_language:
                continue
            unit = item.get("localizations", {}).get(locale, {}).get("stringUnit", {})
            if not unit.get("value"):
                rows.append(
                    {
                        "locale": locale,
                        "key": key,
                        "source_fr": key,
                        "comment": comment,
                        "translation": "",
                    }
                )
    return rows


def write_hardcoded_csv(path: Path, rows: list[dict[str, str | int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["file", "line", "pattern", "value", "recommended_key"],
        )
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    "file": row["file"],
                    "line": row["line"],
                    "pattern": row["pattern"],
                    "value": row["value"],
                    "recommended_key": row["value"],
                }
            )


def write_missing_csv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["locale", "key", "source_fr", "comment", "translation"],
        )
        writer.writeheader()
        writer.writerows(rows)


def build_report(catalog: dict, candidates: list[dict[str, str | int]]) -> str:
    locales, stats = catalog_stats(catalog)
    strings = catalog.get("strings", {})
    by_file = Counter(str(item["file"]) for item in candidates)
    by_pattern = Counter(str(item["pattern"]) for item in candidates)
    missing = missing_rows(catalog)
    missing_by_locale = Counter(row["locale"] for row in missing)
    priority = priority_candidates(candidates)
    priority_by_file = Counter(str(item["file"]) for item in priority)

    lines: list[str] = []
    lines.append("# StibAlert i18n audit")
    lines.append("")
    lines.append(f"- Catalog: `{CATALOG.relative_to(ROOT)}`")
    lines.append(f"- Source language: `{catalog.get('sourceLanguage', 'unknown')}`")
    lines.append(f"- Catalog keys: `{len(strings)}`")
    lines.append(f"- Swift UI hardcoded candidates: `{len(candidates)}`")
    lines.append(f"- Launch-critical hardcoded candidates: `{len(priority)}`")
    lines.append("")
    lines.append("## Catalog coverage")
    lines.append("")
    lines.append("| Locale | Translated | Missing | Needs review |")
    lines.append("| --- | ---: | ---: | ---: |")
    for locale in locales:
        item = stats[locale]
        lines.append(
            f"| `{locale}` | {item['translated']}/{item['total']} | {item['missing']} | {item['needs_review']} |"
        )
    lines.append("")
    lines.append("## Missing translations")
    lines.append("")
    source_language = catalog.get("sourceLanguage", "unknown")
    lines.append(f"- `{source_language}`: source language fallback")
    for locale in ["nl", "en"]:
        lines.append(f"- `{locale}`: {missing_by_locale.get(locale, 0)} missing")
    lines.append("")
    lines.append("## Top files with hardcoded UI candidates")
    lines.append("")
    for file, count in by_file.most_common(20):
        lines.append(f"- `{file}`: {count}")
    lines.append("")
    lines.append("## Top launch-critical files")
    lines.append("")
    for file, count in priority_by_file.most_common(20):
        lines.append(f"- `{file}`: {count}")
    lines.append("")
    lines.append("## Pattern breakdown")
    lines.append("")
    for pattern, count in by_pattern.most_common():
        lines.append(f"- `{pattern}`: {count}")
    lines.append("")
    lines.append("## First 80 candidates")
    lines.append("")
    for item in candidates[:80]:
        value = str(item["value"]).replace("\n", "\\n")
        lines.append(f"- `{item['file']}:{item['line']}` `{item['pattern']}`: {value}")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-report", type=Path)
    parser.add_argument("--export-missing", type=Path)
    parser.add_argument("--export-hardcoded", type=Path)
    parser.add_argument("--priority-only", action="store_true")
    parser.add_argument("--fail-on-hardcoded", action="store_true")
    args = parser.parse_args()

    catalog = load_catalog()
    catalog_keys = {normalized_catalog_key(key) for key in catalog.get("strings", {}).keys()}
    all_candidates = swift_ui_candidates(catalog_keys)
    candidates = priority_candidates(all_candidates) if args.priority_only else all_candidates
    report = build_report(catalog, candidates)

    if args.write_report:
        args.write_report.parent.mkdir(parents=True, exist_ok=True)
        args.write_report.write_text(report, encoding="utf-8")
    if args.export_missing:
        write_missing_csv(args.export_missing, missing_rows(catalog))
    if args.export_hardcoded:
        write_hardcoded_csv(args.export_hardcoded, candidates)

    print(report)
    if args.write_report:
        print(f"\nReport written to {args.write_report}")
    if args.export_missing:
        print(f"Missing translations exported to {args.export_missing}")
    if args.export_hardcoded:
        print(f"Hardcoded strings exported to {args.export_hardcoded}")
    if args.fail_on_hardcoded and candidates:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
