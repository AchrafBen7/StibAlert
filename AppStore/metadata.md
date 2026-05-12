# App Store Connect metadata — StibAlert

Ready-to-copy content for App Store Connect submission. Update bracketed
placeholders before pasting.

---

## 1. App Information

- **Name**: StibAlert
- **Subtitle (30 chars max)**: Alertes transport, en vrai
- **Bundle ID**: com.ehb.StibAlert (already set in Xcode)
- **SKU**: stibalert-ios-v1
- **Primary language**: French (Belgium)
- **Category**:
  - Primary: Travel
  - Secondary: Navigation
- **Content rights**: Does not contain, show, or access third-party content
- **Age rating**:
  - Frequent/Intense Mature/Suggestive Themes: None
  - Profanity: None (community reports moderated)
  - **Rating: 4+**

---

## 2. Pricing & Availability

- **Price**: Free (Tier 0)
- **Availability**:
  - Belgium ✓ (primary)
  - France ✓ (cross-border commuters)
  - Netherlands ✓ (Bxl-Amsterdam axis)
  - Luxembourg ✓
- **Pre-orders**: No
- **App Store Distribution**: Available
- **Bulk Purchasing (Business Plans)**: Not enabled at launch

---

## 3. App Privacy

### Data collected (declare these in App Store Connect → App Privacy):

| Data Type | Used | Linked to user | Tracking |
|---|---|---|---|
| Email Address | ✓ (account) | ✓ | ✗ |
| Name | ✓ (account) | ✓ | ✗ |
| Precise Location | ✓ (signalements + recommendations) | ✗ (never stored) | ✗ |
| Coarse Location | ✓ | ✗ | ✗ |
| Photos | ✓ (optional, on signalement) | ✗ | ✗ |
| Device ID | ✓ (anti-spam, hashed SHA256) | ✗ | ✗ |
| User Content (description) | ✓ | ✓ (linked to userId) | ✗ |
| Crash Data | ✗ until Sentry wired | — | — |

### Privacy policy URL

`https://stib-alert.be/privacy`

(Already served by backend at `GET /privacy`. Ensure the domain is
pointed at the backend before submission.)

---

## 4. App Description (FR — primary)

### Promotional Text (170 chars max)

> Tes transports en commun, en vrai. Plan B avant que tu partes,
> alertes communautaires fiables, et un verdict clair quand ta
> ligne lâche.

### Description

> **StibAlert, c'est Waze des transports bruxellois.**
>
> Tu es à l'arrêt, ton tram ne vient pas. StibAlert te dit en 5 secondes :
> "Prends le bus 71 à 120m, +3 min vs normal. ETA 18 min."
>
> Pas de tableau de bord. Un verdict actif. Une alternative concrète.
>
> **CE QUE TU GAGNES**
>
> • Brief 15 min avant ton départ habituel : si ta ligne déraille,
>   on te prévient AVANT que tu sortes.
> • Position temps réel des trams et bus : tu vois où ils sont,
>   pas où ils devraient être théoriquement.
> • Plan B contextuel : on te propose le meilleur itinéraire selon
>   la situation actuelle, pas selon l'horaire papier.
> • Pourquoi cette recommandation : "ligne 92 sans signalement
>   cette semaine, ETA 18 min, 2 min à pied". Transparence totale.
> • Multimodal : transports + marche + vélo, on choisit pour toi.
>
> **TON RÔLE DANS LA COMMUNAUTÉ**
>
> • Signale en 3 taps. Anonyme ou identifié, à toi de voir.
> • Quand 3 personnes confirment, l'alerte devient visible pour
>   tout Bruxelles. Pas avant. Pas après.
> • Reçois des mercis quand ton signalement aide d'autres voyageurs.
>
> **CE QUE STIBALERT NE FAIT PAS**
>
> Pas de publicité ciblée. Pas de tracking. Pas de revente de tes
> données. Les coordonnées GPS ne sont jamais stockées : elles
> servent au moment du signalement, point.
>
> **LICENCES OFFICIELLES**
>
> Données STIB via les APIs publiques de Belgian Mobility. Alertes
> officielles certifiées et toujours distinguées des signalements
> communautaires.
>
> Conçu à Bruxelles pour les Bruxellois qui prennent vraiment les
> transports.

### Keywords (100 chars max, comma-separated, no spaces)

```
stib,bruxelles,transports,bus,tram,métro,mivb,brussels,perturbation,alerte,communauté,trajet
```

### Support URL

`https://stib-alert.be/support`

### Marketing URL

`https://stib-alert.be`

---

## 5. App Description (NL — secondary, for App Store NL/BE-NL)

### Promotional Text

> Jouw openbaar vervoer, eerlijk. Een plan B vóór je vertrekt,
> betrouwbare community-meldingen, en een helder verdict als
> jouw lijn vastloopt.

### Description (short — to be expanded by NL-native speaker)

> **StibAlert is de Waze van Brussels openbaar vervoer.**
>
> Je staat aan de halte, je tram komt niet. StibAlert vertelt je in
> 5 seconden: "Neem bus 71 op 120m, +3 min vs normaal. ETA 18 min."
>
> Geen dashboard. Een actief verdict. Een concreet alternatief.

(Full translation to be done by NL-native before submission.)

---

## 6. App Description (EN — tertiary, for international)

### Promotional Text

> Brussels public transit, honestly. A Plan B before you leave,
> reliable community alerts, and a clear verdict when your line fails.

### Description (short — to be expanded)

> **StibAlert is the Waze for Brussels public transit.**
>
> You're at the stop, your tram isn't coming. StibAlert tells you in
> 5 seconds: "Take bus 71, 120m walk, +3 min vs normal. ETA 18 min."
>
> No dashboard. An active verdict. A concrete alternative.

---

## 7. Screenshots required

App Store requires at least one set in the **6.7" Display** size
(1290×2796 px for iPhone 14/15/16 Pro Max). Optionally provide:
- 6.5" Display (1284×2778 px)
- 5.5" Display (1242×2208 px) — required only if you target iPhone 8 Plus

### Suggested screens (in order)

1. **HomeView with active cluster pin** + DecisionView slide-up
   Caption: *"Le verdict apparaît dès que tu ouvres l'app."*
2. **DecisionView routine mode** with vehicle position visualizer
   Caption: *"Vois où est ton tram, pas où il devrait être."*
3. **DecisionView trip mode** with multimodal alternatives
   Caption: *"Plan B en 5 secondes, transports + marche + vélo."*
4. **Pre-trip push notification** (mockup)
   Caption: *"15 min avant ton départ, on te prévient. Si rien, silence."*
5. **Profile ContributionsCard**
   Caption: *"Tes signalements aident la communauté."*
6. **Reports/Live feed**
   Caption: *"Tout ce qui se passe sur ton réseau, en temps réel."*

Generate these via Simulator → Hardware → Screenshot, then upload
through Transporter or App Store Connect.

### App Preview video (optional but recommended)

15-30 seconds showing: open app → verdict → take alternative.
Audio is muted by default in App Store, so use captions.

---

## 8. App Review Information

- **Sign-in required for full functionality**: Yes
- **Demo account**:
  - Email: `demo@stib-alert.be`
  - Password: `StibAlert2026!`
  - **Setup before submission**: create this account, give it
    routine.enabled=true with realistic Brussels stops, seed 3-4
    test clusters via the admin panel.
- **Contact**:
  - First: Achraf
  - Last: Benali
  - Phone: [your number]
  - Email: privacy@stib-alert.be
- **Notes for reviewer**:
  > StibAlert relies on real-time community reports + STIB official
  > perturbations data. To experience the killer feature
  > (DecisionView auto-trigger), the demo account is pre-configured
  > with routine.enabled=true and 4 favorite lines (56, 92, 71, 81).
  > A few test clusters are seeded on those lines so the verdict
  > screen is non-empty.
  >
  > The app does not contain user-generated content moderation
  > shortcuts: a report can be flagged by any user, and admins
  > review them via the web dashboard (separate, not in this app).
  >
  > Anonymous signalements are accepted (no account required) but
  > rate-limited by device. The full network only activates with
  > a registered account.

---

## 9. Version Release

- **Release**: Manual release after approval (so you can coordinate
  comms / press release)
- **Phased release**: Yes (gradual rollout over 7 days — safety net)
- **Reset summary rating after new version**: No

---

## 10. What's New in this version

```
Premier lancement public 🎉

• Verdict actif : à 8h32 quand ton tram déraille, StibAlert te dit quoi faire
• Position temps réel des trams/bus + ETA réelle (pas l'horaire théorique)
• Push pré-trajet 15 min avant ton départ habituel
• Mode offline : tes derniers signalements sauvegardés
• Communauté : 3 signalements = alerte visible pour tout Bruxelles
• Mercis : reçois un push quand ton signalement aide d'autres voyageurs
```

---

## 11. Pre-submission checklist

- [ ] App icon: `1024.png` is a real PNG (verified via `file`)
- [ ] App icon: 1024×1024 RGB, no alpha, no rounded corners
- [ ] Build number incremented in Xcode (CFBundleVersion)
- [ ] Marketing version set (CFBundleShortVersionString)
- [ ] Demo account created in production DB
- [ ] Demo account has routine.enabled=true + 3-4 seed clusters
- [ ] Privacy policy live at https://stib-alert.be/privacy
- [ ] Support page live at https://stib-alert.be/support
- [ ] Backend reachable from outside (HTTPS, not localhost)
- [ ] All env vars set in production (`OPENAI_API_KEY`,
      `BELGIAN_MOBILITY_API_KEY`, `MONGO_URI`, `REDIS_URL`,
      `ONESIGNAL_*`, `JWT_SECRET`)
- [ ] OneSignal app registered, APNS certificates uploaded
- [ ] Push notification permission requested only on user action
      (not at launch)
- [ ] `NSLocationWhenInUseUsageDescription` in Info.plist is clear:
      *"Pour détecter ton arrêt et te proposer le meilleur Plan B"*
- [ ] All other `NS*UsageDescription` keys filled (camera if photo
      reports, etc.)
- [ ] No third-party tracking SDKs included (or all declared in
      Privacy Manifest)
- [ ] Screenshots uploaded for at least 6.7" display
- [ ] Test in airplane mode: app doesn't crash, shows cached
      clusters + offline indicator
- [ ] Test on iPhone SE (smallest screen) for layout
