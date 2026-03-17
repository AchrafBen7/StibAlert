studentehb --> AchrafBen7
Stib Alert



STIB Alert 🚆🚍🚇

STIB Alert is een intelligente applicatie voor het melden en volgen van verstoringen in het openbaar vervoer (trams, bussen en metro's). De app combineert realtime meldingen met AI-ondersteunde validatie en community-feedback, zodat gebruikers altijd up-to-date zijn en alternatieve routes aangeboden krijgen.

Sources; 

Apple SwiftUI Documentation 
ISO8601DateFormatter Reference --> ViewModel/MeldingenViewModel.swift

Backend realtime STIB:

De backend expose maintenant une passerelle vers la nouvelle plateforme Belgian Mobility pour les datasets STIB-MIVB.

Variables d'environnement backend:

`BELGIAN_MOBILITY_API_BASE_URL=https://api.belgianmobility.io`
`BELGIAN_MOBILITY_API_KEY=...`
`BELGIAN_MOBILITY_API_KEY_HEADER=x-api-key`

Routes disponibles:

`GET /api/stib/travellers-information`
`GET /api/stib/waiting-times`
`GET /api/stib/vehicle-positions`

Exemples de filtres:

`/api/stib/travellers-information?line=6`
`/api/stib/waiting-times?stopId=5710`
`/api/stib/vehicle-positions?line=7`

Ajoute `includeRaw=true` pour voir la réponse brute de la plateforme si tu veux adapter finement le mapping ensuite.
