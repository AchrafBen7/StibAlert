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


# --- Fuites « String gelé » -----------------------------------------------------
# Classe de bug DIFFÉRENTE des littéraux hardcodés ci-dessus. En SwiftUI,
# `Text("littéral")` devient une LocalizedStringKey (donc traduite), mais
# `Text(uneVariableString)` ne l'est jamais. Un littéral français qui transite par
# un `String` est donc GELÉ en français, même quand le catalogue est complet à 100 %.
# C'est ce qui affichait « Chercher une ligne » en plein écran néerlandais.
FREEZING_PARAMS = ("label", "text", "title", "placeholder", "subtitle", "message", "caption", "hint")
_PARAMS_RE = "|".join(FREEZING_PARAMS)
# Paramètre DÉJÀ correct : les littéraux qu'on lui passe sont traduits.
RE_LOCALIZED_SIG = re.compile(rf"\b({_PARAMS_RE})\s*:\s*LocalizedStringKey\b")
# Autre forme correcte : le helper localise lui-même son paramètre, p. ex.
# `Text(AppLocalizer.string(label))`. Les littéraux des appelants sont donc traduits.
RE_LOCALIZED_VIA_HELPER = re.compile(rf"AppLocalizer\.string\(\s*({_PARAMS_RE})\s*\)")
RE_FROZEN_ARG = re.compile(rf'\b({_PARAMS_RE})\s*:\s*"([^"]{{2,}})"')
RE_FROZEN_RETURN = re.compile(r'\breturn\s+"([^"]{2,})"')
RE_ALREADY_LOCALIZED = re.compile(r"AppLocalizer\.string|String\(localized:|\bL10n\.")
# Déclaration qui RENVOIE une LocalizedStringKey : les `return "…"` de son corps sont
# traduits — ce ne sont pas des fuites. Sans ça, l'audit ne peut jamais atteindre 0.
RE_LOCALIZED_RETURN_DECL = re.compile(r":\s*LocalizedStringKey\s*\{|->\s*LocalizedStringKey\b")
# AppIntents (Siri) : `DisplayRepresentation(title:)` et `@Parameter(title:)` prennent
# une `LocalizedStringResource` — les littéraux y sont extraits et traduits par Xcode.
RE_APPINTENTS = re.compile(r"DisplayRepresentation\(|@Parameter\(|TypeDisplayRepresentation\(")
# Opt-out explicite. Certaines chaînes françaises sont VOLONTAIREMENT non traduites :
# des valeurs canoniques servant à la logique (couleur, icône, sévérité, comparaison,
# envoi au backend) — ex. `canonicalTypeProbleme` dans DTOs.swift. Les traduire
# casserait le matching. On les marque `// i18n:ignore` sur la déclaration (var/func),
# ce qui exclut tout son corps, ou en fin de ligne pour un cas isolé.
RE_IGNORE = re.compile(r"//\s*i18n:ignore\b")
# `var`/`func` seulement : un `let` local vit DANS un corps et refermerait la portée.
RE_DECL = re.compile(r"^\s*(?:@\w+\s+)*(?:public|internal|private|fileprivate)?\s*(?:static\s+)?(?:var|func)\s")

FRENCH_DIACRITICS = set("àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ")
FRENCH_WORDS = {
    "le", "la", "les", "un", "une", "des", "du", "de", "au", "aux", "et", "ou",
    "pour", "dans", "sur", "avec", "sans", "aucun", "aucune", "tout", "toute",
    "chercher", "ligne", "lignes", "arret", "arrets", "reseau", "prochain",
    "passage", "passages", "voir", "plus", "moins", "est", "sont", "pas", "cette",
}


def looks_french(value: str) -> bool:
    if should_ignore(value):
        return False
    if any(ch in FRENCH_DIACRITICS for ch in value):
        return True
    words = re.findall(r"[A-Za-zÀ-ÿ']+", value.lower())
    return sum(1 for word in words if word in FRENCH_WORDS) >= 2


def frozen_string_leaks() -> list[dict[str, str | int]]:
    """Littéraux français réellement gelés dans un `String` (donc jamais traduits)."""
    leaks: list[dict[str, str | int]] = []
    for path in sorted(APP_ROOT.rglob("*.swift")):
        rel = path.relative_to(ROOT)
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError as exc:  # fichier évincé par iCloud → on le signale, on ne l'ignore pas
            leaks.append({"file": str(rel), "line": 0, "kind": "unreadable", "snippet": str(exc)})
            continue
        lines = text.splitlines()
        localized_params = {m.group(1) for line in lines for m in RE_LOCALIZED_SIG.finditer(line)}
        localized_params |= {m.group(1) for line in lines for m in RE_LOCALIZED_VIA_HELPER.finditer(line)}
        # `// i18n:ignore` sur une déclaration exclut TOUT son corps. On borne la
        # portée par l'indentation : on saute tant que les lignes sont plus indentées
        # que la déclaration marquée.
        ignore_indent: int | None = None
        for number, line in enumerate(lines, 1):
            stripped = line.strip()
            if ignore_indent is not None:
                if stripped and (len(line) - len(line.lstrip())) <= ignore_indent:
                    ignore_indent = None  # on est sorti du corps
                else:
                    continue
            if RE_IGNORE.search(line):
                if RE_DECL.match(line):
                    ignore_indent = len(line) - len(line.lstrip())
                continue  # ligne isolée marquée
            # `var x: LocalizedStringKey { … }` : tout son corps est déjà traduit.
            if RE_DECL.match(line) and RE_LOCALIZED_RETURN_DECL.search(line):
                ignore_indent = len(line) - len(line.lstrip())
                continue
            if stripped.startswith("//") or RE_ALREADY_LOCALIZED.search(line):
                continue
            if RE_APPINTENTS.search(line):
                continue  # LocalizedStringResource → déjà traduisible
            for match in RE_FROZEN_ARG.finditer(line):
                if match.group(1) in localized_params:
                    continue  # LocalizedStringKey → littéral bien traduit
                if looks_french(decode_swift_string(match.group(2))):
                    leaks.append({"file": str(rel), "line": number, "kind": "frozen-arg",
                                  "snippet": f'{match.group(1)}: "{match.group(2)}"'})
            for match in RE_FROZEN_RETURN.finditer(line):
                if looks_french(decode_swift_string(match.group(1))):
                    leaks.append({"file": str(rel), "line": number, "kind": "frozen-return",
                                  "snippet": f'return "{match.group(1)}"'})
    return leaks


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
    parser.add_argument("--fail-on-frozen", action="store_true",
                        help="échoue s'il reste des littéraux français gelés dans un String")
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

    leaks = frozen_string_leaks()
    unreadable = [leak for leak in leaks if leak["kind"] == "unreadable"]
    frozen = [leak for leak in leaks if leak["kind"] != "unreadable"]
    print("\n## Frozen French strings (typed `String`, never translatable)\n")
    counts = Counter(str(leak["kind"]) for leak in frozen)
    for kind in sorted(counts):
        print(f"- {kind}: {counts[kind]}")
    print(f"- TOTAL: {len(frozen)}")
    if unreadable:
        # Un fichier illisible afficherait « 0 fuite » : on refuse de mentir sur le score.
        print(f"\n⚠️  {len(unreadable)} fichiers illisibles (iCloud dataless ?) — total non fiable.")

    if args.write_report:
        print(f"\nReport written to {args.write_report}")
    if args.export_missing:
        print(f"Missing translations exported to {args.export_missing}")
    if args.export_hardcoded:
        print(f"Hardcoded strings exported to {args.export_hardcoded}")
    if args.fail_on_hardcoded and candidates:
        raise SystemExit(1)
    if args.fail_on_frozen and (frozen or unreadable):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
