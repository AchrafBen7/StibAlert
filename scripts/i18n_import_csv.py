#!/usr/bin/env python3
"""Import reviewed translations into Localizable.xcstrings.

Expected CSV columns:
  locale,key,translation

Rows with an empty translation are ignored.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "StibAlert/Localizable.xcstrings"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv_file", type=Path)
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    parser.add_argument("--state", default="translated")
    parser.add_argument("--create-missing", action="store_true")
    args = parser.parse_args()

    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    strings = catalog.setdefault("strings", {})
    imported = 0
    skipped = 0

    with args.csv_file.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            locale = (row.get("locale") or "").strip()
            key = row.get("key") or ""
            value = (row.get("translation") or "").strip()
            if not locale or not key or not value:
                skipped += 1
                continue
            if key not in strings:
                if not args.create_missing:
                    skipped += 1
                    continue
                strings[key] = {}

            strings[key].setdefault("localizations", {})[locale] = {
                "stringUnit": {
                    "state": args.state,
                    "value": value,
                }
            }
            imported += 1

    args.catalog.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Imported {imported} translations into {args.catalog}")
    print(f"Skipped {skipped} rows")


if __name__ == "__main__":
    main()
