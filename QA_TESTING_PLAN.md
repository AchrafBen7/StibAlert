# QA Testing Plan - 5 Blockers Fix Validation

**Phase:** Pre-Launch QA  
**Timeline:** May 12-14, 2026 (Days 1-3)  
**Status:** Ready for Testing  
**Commit:** dcf26ce

---

## 📋 Test Objectives

1. Verify type-check performance on HomeView
2. Validate date decoding with all 6 format types
3. Test network offline/constrained indicators
4. Confirm tab bar positioning iOS 17.5+
5. Full VoiceOver accessibility workflow

---

## 🔴 TEST #1: HomeView Type-Check Performance

### Setup
```bash
# Clean build
cmd+shift+K (or Xcode menu > Product > Clean Build Folder)
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# Rebuild
cmd+B
```

### Success Criteria
✅ HomeView.swift compiles without timeout  
✅ Type-check completes in < 2 seconds  
✅ No warnings about view complexity  

### Test Procedure
1. Open HomeView.swift in Xcode
2. Select line 513 (start of body)
3. Observe compilation indicator
4. Note: Time should be < 2s

**Expected Result:**
```
✓ Type-check completed in 1.2s
✓ No complexity warnings
✓ Build succeeds
```

---

## 📅 TEST #2: Date Decoding - All 6 Formats

### Test Data Preparation
Create test JSON with all 6 date formats:

```json
{
  "iso8601_full": "2026-05-12T14:30:45.123Z",
  "iso8601_basic": "2026-05-12T14:30:45Z",
  "iso8601_colon_tz": "2026-05-12T14:30:45+02:00",
  "unix_timestamp_ms": 1715515845123,
  "unix_timestamp_sec": 1715515845,
  "legacy_integer": 1715515845
}
```

### Test Endpoints (STIB API)

| Endpoint | Expected Format | Test Command |
|----------|-----------------|--------------|
| `/api/transport/overview` | ISO8601 + Unix | curl to STIB backend |
| `/api/stop/{id}/detail` | ISO8601 | Check departures |
| Route recommendations | Mixed (Google) | Search → route → check times |

### Success Criteria
✅ All 6 formats decode without error  
✅ All dates are valid and usable  
✅ No "Réponse serveur illisible" errors  

### Test Procedure
1. Build app with date decoder fix
2. Test each endpoint type:
   ```swift
   // HomeView: Trigger itinerary search
   - Search for destination
   - Verify route returned (dates from Google)
   - Check departure times displayed
   
   // Stop detail: View next departures
   - Search stop
   - Open stop preview
   - Verify times loaded (ISO8601 dates from backend)
   ```

3. **Edge Case Tests:**
   ```
   Test timezone handling:
   - Device timezone: London (GMT)
   - API returns: 2026-05-12T14:30:00+02:00 (Paris)
   - Display should show: correct local time
   
   Test milliseconds vs seconds:
   - Google: 1715515845 (seconds)
   - Should decode as 2026-05-12T14:30:45Z
   - Not year 3000+ (millisecond misparse)
   ```

**Expected Result:**
```
✓ All 6 date formats parse correctly
✓ Times display correctly in UI
✓ No decoding errors in console
✓ Edge cases handled gracefully
```

---

## 🌐 TEST #3: Network Offline/Constrained Indicators

### Setup

#### Test 1: Offline (Airplane Mode)
```swift
1. Enable Airplane Mode
   Settings → Airplane Mode → ON

2. Launch app
   Should show: "Vous êtes hors ligne" (red badge)
   
3. Open HomeSearchHeaderOverlay
   Should display offline indicator
   
4. Disable Airplane Mode
   Indicator should fade out
```

#### Test 2: Constrained (Low Bandwidth)
```swift
1. Xcode → Window → Devices and Simulators
2. Select active device
3. Network Link Conditioner:
   - Download LNC from Additional Tools
   - Enable "Constrained" profile
   
4. App should show: "Connexion limitée" (yellow badge)
5. Verify data still loads (with latency)
```

#### Test 3: Error Handling
```swift
1. Open HomeStopPreviewCard (offline)
2. Departures should show error:
   "Impossible de charger les passages."
   
3. "Réessayer" button present
4. Click retry when connectivity restored
5. Data loads successfully
```

### Success Criteria
✅ Offline indicator shows when offline  
✅ Constrained indicator shows on 2G/3G  
✅ Retry button works after connectivity restored  
✅ Error message is clear + actionable  

### Test Procedure
**Device:** iPhone 14, iOS 17.5+

1. **Offline Test** (5 min)
   - [ ] Enable Airplane Mode
   - [ ] Verify indicator appears
   - [ ] Disable Airplane Mode
   - [ ] Verify indicator disappears

2. **Error + Retry Test** (5 min)
   - [ ] Go offline
   - [ ] Tap stop to load detail
   - [ ] See error + retry button
   - [ ] Enable connectivity
   - [ ] Tap retry
   - [ ] Departures load

3. **Constrained Test** (5 min)
   - [ ] Use Network Link Conditioner
   - [ ] Enable constrained mode
   - [ ] Verify "Connexion limitée" shows
   - [ ] App is usable (slow but functional)

**Expected Result:**
```
✓ All 3 network states display correctly
✓ Retry mechanism works
✓ No crashes on network changes
✓ Indicators appear/disappear smoothly
```

---

## 📱 TEST #4: Tab Bar iOS 17.5+ Rendering

### Setup
**Devices to test:**
- iPhone SE (2nd gen) - iOS 17.5
- iPhone 14 - iOS 17.5+
- iPhone 15 Pro - iOS 18 beta (if available)

### Test Procedure

#### Test 1: Alignment
```swift
1. Open HomeView
2. Observe tab bar at bottom
3. Check alignment:
   - Should be 6pt + 8pt padding = 14pt from bottom
   - Not offset 46pt below screen
   - Not overlapping content
```

#### Test 2: Scroll Behavior
```swift
1. Open ReportsView (scrollable content)
2. Scroll up/down
3. Tab bar should:
   - Stay fixed at bottom
   - Not jitter or move
   - Not overlap scroll content
```

#### Test 3: Tab Switching
```swift
1. Tap each tab in sequence
2. Animations should:
   - Be smooth (spring, dampingFraction: 0.82)
   - Not cause layout shift
   - Feel native/iOS standard
```

### Success Criteria
✅ Tab bar always aligned to bottom  
✅ Padding consistent across iOS 17-18  
✅ No jitter or layout shifts  
✅ Tab switching feels native  

**Expected Result:**
```
✓ iOS 17.5: Aligned correctly
✓ iOS 18: No regression
✓ All devices: Consistent experience
✓ No layout warnings in Xcode
```

---

## ♿ TEST #5: VoiceOver Accessibility - Full Workflow

### Setup
**Device:** iPhone 14, iOS 17.5+

Enable VoiceOver:
```
Settings → Accessibility → VoiceOver → ON
```

### Test Procedure

#### Part A: Navigation Bar
```swift
1. Home screen loads
2. Swipe right (next element)
3. Should announce: "Carte, onglet, sélectionné"
   OR "Carte, onglet, double-tap pour sélectionner"

4. Double-tap any unselected tab
5. Should announce: "Lignes, onglet, sélectionné"

Expected:
✓ All 5 tabs are announced
✓ Selected/unselected state clear
✓ Hints explain how to activate
```

#### Part B: Search & Itinerary
```swift
1. Tap search field
2. Should announce: 
   "Champ de recherche d'itinéraire"
   + "Double-tap for keyboard"

3. Type destination address
4. Wait for suggestions
5. Each suggestion should be announced:
   "Gare de Nord, double-tap to select"

6. Select destination
7. Route options should be announced:
   "Ligne 56 vers Gare du Nord, dans 3 minutes"
   + "Direct, pas de correspondances"
```

#### Part C: Stop Preview
```swift
1. Open map
2. Tap any stop marker
3. Should announce:
   "Arrêt: [Stop Name]"
   + "[Line numbers]"
   + "[Next departure time]"

4. Lines should be listed:
   "Lignes: 56, 57, 58"

5. Departures should be spoken:
   "Ligne 56 vers Gare du Nord, dans 3 minutes"
```

#### Part D: Error State (Offline)
```swift
1. Enable Airplane Mode
2. Try to load stop detail
3. Should announce:
   "Erreur: Impossible de charger les passages"
   + "Réessayer, double-tap"

4. Disable Airplane Mode
5. Tap Retry
6. Should announce: "Chargement en cours..."
7. Once loaded: "Arrêt: [name]..." (as above)
```

### Success Criteria

✅ All UI elements have labels  
✅ Labels are clear + concise  
✅ Hints explain how to interact  
✅ Complex info (routes, times) spoken correctly  
✅ No missing elements  
✅ Rotor navigation works (vertical swipe 2-finger)  

### Accessibility Inspector Validation
```swift
1. Xcode → Product → Run Accessibility Inspector
2. Tap each element in app
3. Inspector should show:
   - Identifier (label)
   - Value (time, line info)
   - Hint (how to activate)
   - Traits (.button, .selected, etc.)
```

**Expected Output:**
```
✓ 100% of interactive elements labeled
✓ No "Ignored" elements (unintended)
✓ Traits are appropriate
✓ VoiceOver can navigate all screens
✓ Rotor shows all major landmarks
```

---

## 🔄 Cross-Platform Testing

| Device | iOS | Status | Notes |
|--------|-----|--------|-------|
| iPhone SE (2nd) | 17.5 | [ ] Test | Smallest screen |
| iPhone 14 | 17.5+ | [ ] Test | Standard |
| iPhone 14 Pro | 18 | [ ] Test | Latest |
| iPhone 15 Pro | 18 | [ ] Test | New form factor |
| iPad Air | 17.5 | [ ] Test | Larger screen |

---

## 📊 Test Result Template

```markdown
## Test Execution: [Blocker #]

**Device:** [Model] - iOS [Version]  
**Tester:** [Name]  
**Date:** [YYYY-MM-DD]  
**Duration:** [Time]  

### Results
- [ ] Test 1: PASS / FAIL
- [ ] Test 2: PASS / FAIL
- [ ] Test 3: PASS / FAIL

### Issues Found
[If any, describe with reproduction steps]

### Screenshots
[Attach any relevant screenshots]

### Sign-off
Tester: ________________  Date: __________
```

---

## 🚨 Critical Paths to Monitor

During testing, watch for:

1. **Type-Check Hangs**
   - If HomeView hangs during compilation
   - Check: Did overlay extraction work?
   - Fix: Clean build, verify imports in HomeViewOverlays.swift

2. **Date Decode Crashes**
   - If app crashes on API response
   - Check: Is decoder handling all formats?
   - Fix: Add logging to decoder, check JSON format

3. **Network State Misdetection**
   - Indicator shows offline but device has WiFi
   - Check: NetworkConnectivityMonitor path status
   - Fix: May need platform-specific handling

4. **Tab Bar Overlaps**
   - If tab bar covers content on some iOS versions
   - Check: SafeAreaInsets value
   - Fix: Adjust padding constants

5. **VoiceOver Skips**
   - If some elements not announced
   - Check: accessibilityElement(children:) settings
   - Fix: May need to break apart nested views

---

## ✅ Sign-Off Checklist

Before declaring blockers "RESOLVED":

- [ ] All 5 blockers tested on iOS 17.5+
- [ ] No new crashes introduced
- [ ] No regressions in existing features
- [ ] All tests documented with results
- [ ] Screenshots captured for record
- [ ] Developer notified of any issues
- [ ] Ready for beta release (TestFlight Day 5)

---

**QA Phase Duration:** May 12-14 (3 days)  
**Next Phase:** Beta Build #1 (May 15)  
**Contact:** QA Lead
