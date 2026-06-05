# StibAlert

StibAlert is an iOS mobility app for Brussels public transport. The project started as a STIB/MIVB incident app and has evolved into a multi-operator transport companion covering STIB/MIVB, SNCB/NMBS, De Lijn, TEC, Villo and community reports.

The current TestFlight name is still `StibAlert`. The product direction is broader than STIB only, so the final public name may change.

This project started as a personal project before becoming a final-year project. Some files, comments, labels and internal naming are therefore still written in French. The product itself targets French and Dutch users, while the codebase is being progressively cleaned and localized.

## Mission

The app helps travellers in Brussels make better transport decisions by combining:

- official traffic information from operators;
- real-time and theoretical departures where available;
- community incident reports;
- route planning and disruption-aware alternatives;
- favourites and proactive alerts;
- an AI assistant that explains network status using the data available inside the app.

The long-term goal is a "Waze for public transport": live context, user reports, rerouting and personal alerts for everyday commuters.

## Main Features

- Live map with stops, stations, Villo stations, disruptions and community clusters.
- Multi-operator coverage:
  - STIB/MIVB stops, lines, theoretical schedules, official traveller information and route shapes.
  - SNCB/NMBS Brussels stations, departures and official traffic information.
  - De Lijn and TEC stops, lines and disruptions around the current viewport.
  - Villo station availability.
- Route planner with transport, bike and walking options.
- Active trip monitoring and rerouting prompts when a route is affected.
- Community reporting flow for stops, stations and operators.
- Favourites for stops, stations and lines.
- Push notification foundation for favourite stops and community clusters.
- FR/NL localization infrastructure via `Localizable.xcstrings`.
- Siri/App Intents and widget foundation.
- STIB AI assistant backed by the Node/Express backend and Gemini/OpenAI-compatible streaming.

Backend repository:

[AchrafBen7/BelDetailing-Backend](https://github.com/AchrafBen7/BelDetailing-Backend)

## Build

From the iOS repo:

```bash
cd "/Users/achrafbenali/Documents/Projet - Stib/StibAlert-main"
xcodebuild -project StibAlert.xcodeproj -scheme StibAlert -destination 'platform=iOS Simulator,name=iPhone 17' build
```

For an archive:

```bash
xcodebuild \
  -project StibAlert.xcodeproj \
  -scheme StibAlert \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /private/tmp/StibAlert-TestFlight.xcarchive \
  archive
```

## Backend

The backend is a Node/Express API deployed separately, currently used for:

- user reports and community clusters;
- official/operator data proxying and caching;
- STIB theoretical schedules;
- SNCB/iRail data;
- De Lijn and TEC viewport endpoints;
- push notification logic;
- STIB AI streaming endpoint.

## Data Sources

The app uses a mix of static, cached and live data:

- STIB/MIVB open data and Belgian Mobility endpoints.
- STIB theoretical schedules imported from local JSON parts.
- STIB official `TravellersInformation`.
- SNCB/NMBS stations from `sncb-brussels-stations.json`.
- SNCB/iRail live departures and disturbances.
- De Lijn and TEC datasets exposed through the backend.
- Villo station data.
- Community reports stored by the backend.

## Bronnen

The project is based on public mobility data, official platform documentation and implementation references used to understand, build and validate the app.

Open data and public transport:

- [Belgian Mobility Open Data](https://data.belgianmobility.io/)
- [STIB/MIVB Open Data API portal](https://api-management-opendata-production.developer.azure-api.net/)
- [De Lijn Open Data](https://data.delijn.be/)
- [iRail API documentation](https://docs.irail.be/)
- [GTFS Schedule reference](https://gtfs.org/documentation/schedule/reference/)
- [GTFS Realtime reference](https://gtfs.org/documentation/realtime/reference/)
- [JCDecaux Developer API](https://developer.jcdecaux.com/)
- [Belgian public open data portal](https://data.gov.be/)

iOS and Apple platform documentation:

- [SwiftUI documentation](https://developer.apple.com/documentation/swiftui)
- [MapKit documentation](https://developer.apple.com/documentation/mapkit)
- [Core Location documentation](https://developer.apple.com/documentation/corelocation)
- [UserNotifications documentation](https://developer.apple.com/documentation/usernotifications)
- [App Intents documentation](https://developer.apple.com/documentation/appintents)
- [WidgetKit documentation](https://developer.apple.com/documentation/widgetkit)
- [ActivityKit documentation](https://developer.apple.com/documentation/activitykit)
- [URLSession documentation](https://developer.apple.com/documentation/foundation/urlsession)
- [String Catalog localization](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
- [TestFlight documentation](https://developer.apple.com/help/app-store-connect/test-a-beta-version/overview-of-testing-with-testflight/)

Backend, cloud and AI:

- [Node.js documentation](https://nodejs.org/docs/latest/api/)
- [Express documentation](https://expressjs.com/)
- [MongoDB documentation](https://www.mongodb.com/docs/)
- [Mongoose documentation](https://mongoosejs.com/docs/)
- [Render Web Services documentation](https://render.com/docs/web-services)
- [OneSignal iOS SDK documentation](https://documentation.onesignal.com/docs/ios-sdk-setup)
- [Gemini API documentation](https://ai.google.dev/gemini-api/docs)
- [OpenAI API documentation](https://platform.openai.com/docs/)

## AI Usage

AI tools were used as development assistants during the project. They were not used as a replacement for implementation ownership or testing.

Codex and Claude Code were used for:

- internal bug fixing and code investigation;
- reviewing app behavior after TestFlight feedback;
- analysing UI and UX coherence across screens;
- checking design-system consistency;
- helping refactor large SwiftUI files into smaller components;
- drafting documentation, QA notes and technical context;
- comparing implementation choices against official documentation.

All code changes still require local review, build validation and manual product testing before being considered ready.

## Localization

The app targets French and Dutch. The string catalog is:

```text
StibAlert/Localizable.xcstrings
```

Important rule: new visible UI text should use the localization layer instead of hardcoded French strings. Some older screens may still contain hardcoded copy and should be migrated progressively.

## Current Product Status

The app is suitable for internal TestFlight validation, with the following areas requiring extra QA:

- route planner state reset and map polyline cleanup;
- route search suggestions and address quality;
- guest mode UX;
- FR/NL consistency across route and report screens;
- physical-device keyboard behavior in the reporting flow;
- push notification behavior for favourite stops and community clusters;
- De Lijn/TEC line filtering by proximity/region;
- STIB AI output formatting and route explanation quality.

## Design System

The app uses a dedicated design system to keep the interface coherent across the map, reports, schedules, favourites, onboarding, sheets and AI assistant.

The design system centralizes:

- colors and status tokens;
- typography and spacing;
- transport line badges;
- reusable buttons and cards;
- sheet and overlay styling;
- operator-specific UI patterns.

The goal is to avoid hardcoded styling in feature screens and keep the app visually consistent as new operators and features are added.

## Useful Project Docs

- `CONTEXT.md` at workspace root for handoff context.
