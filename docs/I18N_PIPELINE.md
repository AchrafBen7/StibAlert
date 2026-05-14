# StibAlert i18n pipeline

Source language: French (`fr`).

## Current baseline

Run:

```bash
python3 scripts/i18n_audit.py \
  --write-report /tmp/stibalert-i18n-audit.md \
  --export-missing /tmp/stibalert-i18n-missing.csv
```

Current audit result:

- `Localizable.xcstrings`: 509 keys.
- French coverage: 509/509 via source-language fallback.
- Dutch coverage: 40/509, 469 missing.
- English coverage: 59/509, 450 missing.
- Swift UI hardcoded candidates still outside the catalog: 674.

## Fast launch workflow

1. Export missing NL/EN strings with `scripts/i18n_audit.py`.
2. Fill `/tmp/stibalert-i18n-missing.csv` with machine translation as a bootstrap.
3. Send only visible product strings to native review, prioritizing Dutch.
4. Import reviewed translations:

```bash
python3 scripts/i18n_import_csv.py /path/to/reviewed-translations.csv
```

5. QA in simulator/device with phone language set to French, Dutch, then English.

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
