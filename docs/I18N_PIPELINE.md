# StibAlert i18n pipeline

Source language: French (`fr`).

## Current baseline

Run:

```bash
python3 scripts/i18n_audit.py \
  --write-report /tmp/stibalert-i18n-audit.md \
  --export-missing /tmp/stibalert-i18n-missing.csv \
  --export-hardcoded /tmp/stibalert-i18n-hardcoded.csv
```

Current audit result:

- `Localizable.xcstrings`: 513 keys.
- French coverage: 513/513 via source-language fallback.
- Dutch coverage: 44/513, 469 missing.
- English coverage: 63/513, 450 missing.
- Swift UI hardcoded candidates still outside the catalog: 348 total, 222 launch-critical.
- Launch-critical hardcoded candidates: run `--priority-only` to isolate Home, Reports, report flow, auth, onboarding, favorites, line detail and Siri intents.

## Fast launch workflow

1. Export missing NL/EN strings with `scripts/i18n_audit.py`.
2. Fill `/tmp/stibalert-i18n-missing.csv` with machine translation as a bootstrap.
3. Send only visible product strings to native review, prioritizing Dutch.
4. Import reviewed translations:

```bash
python3 scripts/i18n_import_csv.py /path/to/reviewed-translations.csv
```

5. QA in simulator/device with phone language set to French, Dutch, then English.

## Focused migration workflow

Use the priority mode to avoid trying to fix the full app in one pass:

```bash
python3 scripts/i18n_audit.py \
  --priority-only \
  --write-report /tmp/stibalert-i18n-priority.md \
  --export-hardcoded /tmp/stibalert-i18n-priority-hardcoded.csv
```

Recommended order:

1. Convert Home + stop detail + route planner strings.
2. Convert Reports + quick report flow strings.
3. Convert line detail + favorites strings.
4. Convert auth/onboarding strings.
5. Convert profile/settings strings.

Only after these screens are clean should `--fail-on-hardcoded` be considered for CI.

## Priority files to clean up first

These files have the most hardcoded UI candidates and should be localized first:

- `StibAlert/View/Profile/ProfileView.swift`
- `StibAlert/View/Reports/ReportsView.swift`
- `StibAlert/View/Favorites/FavoritesView.swift`
- `StibAlert/View/Auth/GuestTabPlaceholder.swift`
- `StibAlert/View/Decision/DecisionView.swift`
- `StibAlert/View/Profile/TransitPassSettingsView.swift`
- `StibAlert/View/Signalements/SignalementsView.swift`
- `StibAlert/View/Onboarding/PrivacyConsentView.swift`
- `StibAlert/OnBoardingView.swift`
- `StibAlert/View/Home/ArretDetailPage.swift`

## Rules going forward

- No new user-visible string should be added without going through `Localizable.xcstrings`.
- Use `LocalizedStringKey`/`String(localized:)` for static text.
- Use interpolation-friendly catalog entries for dynamic strings.
- Use `RelativeDateTimeFormatter`, `Date.FormatStyle`, and `.formatted()` for date/time/number formatting.
- Do not hardcode plural suffixes like `signalement\(count > 1 ? "s" : "")`; use string catalog plural variations.
