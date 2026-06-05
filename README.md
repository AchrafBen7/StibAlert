# StibAlert

School project — Erasmushogeschool Brussel (EHB)
Multimedia & Creative Technology · 2025-2026

## About the project

StibAlert is an iOS app for Brussels public transport that I designed and built myself. It started as a STIB/MIVB incident app and grew into a multi-operator companion covering STIB/MIVB, NMBS/SNCB, De Lijn, TEC and Villo, combined with community reports and an AI assistant.

It is not just a timetable viewer. The goal is a "Waze for public transport": a live map, real-time and theoretical departures, official disruptions, community alerts, disruption-aware route planning and proactive notifications for everyday commuters in Brussels.

The project pairs a SwiftUI iOS app with a separate Node/Express backend. It began as a personal project before becoming a final-year project, so some internal naming and comments are still in French; the product itself targets French and Dutch users.

## The app

The app is organized around five tabs, plus the STIB·AI assistant:

- **Kaart** — live map: stops, stations, Villo, disruptions, community clusters and route preview.
- **Dienstregeling** — schedules and next departures per stop and line.
- **Verkeersinfo** — line-status grid with official and community disruptions per line.
- **Favorieten** — favourite stops, stations and lines.
- **Profiel** — account, languages, MOBIB pass (NFC) and privacy.
- **STIB·AI** — assistant (chat + voice) that explains the network status using the data available inside the app.

The interface is fully bilingual (FR/NL) through a String Catalog.

## Tech stack

**iOS app**

- Swift / SwiftUI
- MapKit + Core Location
- UserNotifications, App Intents (Siri), WidgetKit / ActivityKit
- Core NFC (MOBIB pass reading)
- String Catalog (FR/NL)
- Swift packages: SocketIO, OneSignal, DotLottie, GoogleMaps3D

**Backend**

- Node.js + Express
- MongoDB (Mongoose) + Redis
- OneSignal (push notifications)
- Gemini / OpenAI-compatible streaming (STIB·AI)
- Deployed on Render

## Getting started

The iOS app is this repository. The backend lives in a separate repo: [AchrafBen7/Stib-Alert-Backend](https://github.com/AchrafBen7/Stib-Alert-Backend).

Requirements: Xcode 16+ (iOS 17+).

```bash
xcodebuild -project StibAlert.xcodeproj -scheme StibAlert \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Production archive (TestFlight):

```bash
xcodebuild -project StibAlert.xcodeproj -scheme StibAlert \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /private/tmp/StibAlert-TestFlight.xcarchive archive
```

Backend (Node.js 18+):

```bash
npm install
npm start
```

The backend needs environment variables (MongoDB, Redis, OneSignal, AI key). These secrets are intentionally **not** committed.

## Bronnenlijst

Kernbronnen, gegroepeerd per onderdeel van het project.

### App & framework

| Bron | Gebruikt voor | Code |
|------|----------------|------|
| SwiftUI | UI, schermen, componenten | `StibAlert/View/` |
| MapKit | live kaart, annotaties, polylines | `View/Home/HomeMapLayer.swift` |
| Core Location | locatie van de gebruiker | `View/Search/SearchLocationManager.swift` |
| MapKit Local Search | adres-/halte-zoeken | `View/Home/HomeView.swift`, `Networking/NearbyStopService.swift` |
| Core NFC | MOBIB-kaart lezen | `Networking/MobibNFCReader.swift` |
| String Catalog | FR/NL-lokalisatie | `StibAlert/Localizable.xcstrings` |
| Apple Developer documentatie | SwiftUI, MapKit, App Intents, WidgetKit | `StibAlert/` |

### Kaart, lijnen & voertuigen

| Bron | Gebruikt voor | Code |
|------|----------------|------|
| STIB/MIVB Open Data | haltes, lijnen, reizigersinfo | `Networking/`, `View/Signalements/LigneDetailPage.swift` |
| Lijntracés (GeoJSON) | tekening van de lijnen op de kaart | `View/Home/LineShapesLoader.swift` |
| Live voertuigposities | trams/bussen op het tracé | `Networking/VehicleTrackingService.swift`, `View/Home/HomeMapLayer.swift` |
| Theoretische dienstregeling | uren per halte/lijn | `View/Schedules/`, lokale JSON-delen |

### Operatoren & open data

| Bron | Gebruikt voor | Code |
|------|----------------|------|
| Belgian Mobility Open Data | gedeelde mobiliteitsdata | `Stib-Alert-Backend/backend/services/` |
| iRail API | NMBS/SNCB-vertrektijden & storingen | `Networking/SNCBStationService.swift` |
| De Lijn Open Data | De Lijn-haltes & lijnen | `Networking/OperatorStopService.swift` |
| TEC | TEC-haltes & lijnen | `Networking/OperatorStopService.swift` |
| JCDecaux (Villo) | beschikbaarheid deelfietsen | `View/Home/` (Villo-markers) |
| GTFS (Schedule & Realtime) | formaten dienstregeling/realtime | `Networking/` |

### Backend & cloud

| Bron | Gebruikt voor | Code |
|------|----------------|------|
| Node.js + Express | REST-API & SSE | `Stib-Alert-Backend/backend/app.js` |
| MongoDB + Mongoose | meldingen, clusters, gebruikers | `backend/models/` |
| Redis | caching van operator-data | `backend/services/` |
| Render | hosting van de backend | deploy |
| OneSignal | pushmeldingen | `backend/`, iOS OneSignal SDK |

### STIB·AI

| Bron | Gebruikt voor | Code |
|------|----------------|------|
| Gemini API | uitleg netwerkstatus (chat + stem) | `backend/controllers/stibAiController.js` |
| OpenAI-compatibele streaming | streaming-antwoorden | `View/Home/HomeAI/STIBAIClient.swift` |
| Speech / AVFoundation | spraakherkenning assistent | `View/Home/HomeAI/VoiceAssistant.swift` |

### Design

| Bron | Gebruikt voor | Code |
|------|----------------|------|
| Eigen designsysteem | kleuren, typografie, lijnbadges, componenten | `StibAlert/Design/` |
| Apple Human Interface Guidelines | UI-consistentie | hele app |

## AI usage

AI tools (Codex, Claude Code) were used as development assistants: bug fixing, code investigation, checking UI/UX coherence, splitting large SwiftUI files into smaller components, and drafting documentation. Every change still required local review, a successful build and manual testing before being considered done.
