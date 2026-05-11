# Integration Guide - Blockers Fixes

**Date:** May 12, 2026  
**Target:** Complete integration by May 14  
**Status:** In Progress

---

## 🔧 Integration Checklist

### ✅ BLOCKER #1: HomeView Overlays (DONE)
Already merged. No integration needed.

**Verification:**
```bash
git log --oneline | grep "resolve 5 critical"
# Should show commit dcf26ce
```

---

### ⚠️ BLOCKER #2: Date Decoder (DONE)
Already integrated in APIClient.swift. No additional work needed.

**Verification:**
```swift
// Already in APIClient - just verify it works
let testData = """
{"date": "2026-05-12T14:30:45.123Z"}
"""
decoder.decode(TestDTO.self, from: testData.data(using: .utf8)!)
// Should work without error
```

---

### 🔴 BLOCKER #3: Network Monitor & Offline Indicator (IN PROGRESS)

#### Step 1: Initialize NetworkConnectivityMonitor
Edit the root app view (likely `SplashView.swift` or app entry point):

```swift
import SwiftUI

@main
struct StibAlertApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationManager.self) private var pushNotificationManager
    @StateObject private var connectivity = NetworkConnectivityMonitor() // ADD THIS
    
    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(connectivity) // ADD THIS
        }
    }
}
```

**File to edit:** `StibAlert/StibAlertApp.swift`

#### Step 2: Add OfflineIndicator to HomeSearchHeaderOverlay
Edit `StibAlert/View/Home/HomeView.swift` - find the `HomeSearchHeaderOverlay` private struct:

```swift
private struct HomeSearchHeaderOverlay: View {
    @EnvironmentObject private var connectivity: NetworkConnectivityMonitor // ADD THIS
    
    // ... existing properties ...
    
    var body: some View {
        VStack(spacing: 10) {
            // ADD OFFLINE INDICATOR HERE
            if !connectivity.isConnected || connectivity.isConstrained {
                OfflineIndicator(
                    isConnected: connectivity.isConnected,
                    isConstrained: connectivity.isConstrained
                )
                .padding(.horizontal, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            HStack(spacing: 10) {
                HomeEditorialSearchField(query: $searchQuery, action: onOpenItineraryPlanner)
                // ... rest of code ...
```

**File to edit:** `StibAlert/View/Home/HomeView.swift`  
**Location:** Inside `private struct HomeSearchHeaderOverlay` body property (around line 2595)

#### Step 3: Verify Imports
Ensure `HomeSearchHeaderOverlay` imports `OfflineIndicator`:

Already should work since it's in the same view hierarchy. If not:

```swift
// At top of HomeView.swift
import SwiftUI
import MapKit
import Combine
import AVFoundation
import WidgetKit

// OfflineIndicator is in: StibAlert/View/Components/OfflineIndicator.swift
// Should be automatically imported with SwiftUI
```

#### Verification
```swift
// After integration, in Xcode:
1. Build: cmd+B
2. Run on device with Airplane Mode ON
3. Should see: "Vous êtes hors ligne" badge at top
4. Turn off Airplane Mode
5. Badge should disappear
```

---

### 🔴 BLOCKER #4: Tab Bar Accessibility (DONE)
Already merged. No integration needed.

**Verification:**
```bash
# Check AppTabBar has updated accessibility
grep -n "accessibilityHint\|accessibilityElement" \
  StibAlert/View/Main/AppTabBar.swift
# Should show enhancements on lines ~110+
```

---

### 🔴 BLOCKER #5: VoiceOver Accessibility (DONE - Utilities Ready)

#### Step 1: Use Accessibility Helpers in Stop Card
Edit stop card rendering (already in HomeStopPreviewCard):

```swift
// Already has error retry button with proper message
// Add accessibility context:

if detailError != nil {
    HStack(spacing: 10) {
        Text("Impossible de charger les passages.")
            .font(DS.Font.body)
            .foregroundStyle(DS.Color.inkMute)
            .accessibilityLabel("Erreur: Impossible de charger les passages")
        Spacer()
        Button(action: onRetry) {
            Label("Réessayer", systemImage: "arrow.clockwise")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Color.primary)
        }
        .accessibilityLabel("Réessayer")
        .accessibilityHint("Double-tap pour réessayer le chargement")
    }
}
```

**Location:** `StibAlert/View/Home/HomeView.swift` line ~3733

#### Step 2: Use Duration Formatter in Route Display
When displaying route times, use accessibility helper:

```swift
// In RouteRecommendationsSheet or similar:
import StibAlert // to access HomeViewAccessibility utilities

// OLD
Text(String(format: "%d min", duration))

// NEW
Text(formatDurationForA11y(duration))
    .accessibilityLabel(formatDurationForA11y(duration))
```

**Location:** Look for routes/itineraries being displayed

#### Step 3: Departure Information Display
When showing next departures, format for accessibility:

```swift
// OLD
Text("56 → Gare du Nord · 3 min")

// NEW
Text(formatDepartureForA11y(
    line: "56",
    destination: "Gare du Nord",
    minutesUntil: 3
))
.accessibilityLabel(
    formatDepartureForA11y(
        line: "56",
        destination: "Gare du Nord",
        minutesUntil: 3
    )
)
```

**Already implemented in:** `HomeStopPreviewCard` (lines ~3750-3780)  
**Helper file:** `StibAlert/View/Home/HomeViewAccessibility.swift`

#### Step 4: Test with VoiceOver
```swift
1. Enable VoiceOver:
   Settings → Accessibility → VoiceOver → ON

2. Navigate HomeView:
   - Swipe right: should announce each UI element
   - Listen for: stop name, lines, next departure times
   - Double-tap: should trigger actions

3. Test error state (offline):
   - Enable Airplane Mode
   - Try to load stop
   - Should announce: "Erreur: Impossible de charger les passages"
   - "Réessayer" button should be available

4. Rotor navigation:
   - Swipe up with 2 fingers
   - Should show: landmarks, images, headings
   - Can jump between major sections
```

---

## 📝 Files to Review Before Merge

### Modified Files
1. **StibAlert/Networking/APIClient.swift**
   - ✅ Date decoder enhanced
   - ✅ Supports 6 formats
   - ✅ Validates ranges
   - Check: imports, no compilation errors

2. **StibAlert/View/Home/HomeView.swift**
   - ✅ Body simplified
   - ✅ Overlays extracted
   - Check: all overlay references exist
   - Check: state variables properly accessed

3. **StibAlert/View/Home/HomeBottomChromeOverlay.swift**
   - ✅ Added safe area padding
   - ✅ Added accessibility label
   - Check: tab bar still displays properly

4. **StibAlert/View/Main/AppTabBar.swift**
   - ✅ Enhanced accessibility
   - ✅ Better hints and traits
   - Check: no visual changes

### New Files
1. **StibAlert/View/Home/HomeViewOverlays.swift**
   - ✅ All 4 ViewBuilders defined
   - ✅ All closures properly captured
   - Check: imports complete

2. **StibAlert/Networking/NetworkConnectivityMonitor.swift**
   - ✅ Uses NWPathMonitor
   - ✅ Published @properties
   - Check: no memory leaks

3. **StibAlert/View/Components/OfflineIndicator.swift**
   - ✅ Conditional rendering
   - ✅ Uses DS.Color tokens
   - Check: Creates directory first if needed
   - **Action:** `mkdir -p StibAlert/View/Components`

4. **StibAlert/View/Home/HomeViewAccessibility.swift**
   - ✅ Helper functions defined
   - ✅ Reusable formatters
   - ✅ No view implementation (only utilities)
   - Check: can be imported in tests

---

## 🔗 Dependencies

### New Imports Required
```swift
// For NetworkConnectivityMonitor
import Network  // Already available in iOS 13+

// For OfflineIndicator
import SwiftUI  // Already available

// For HomeViewAccessibility
import SwiftUI  // Already available
```

### Framework Dependencies
- ✅ All using standard Swift/SwiftUI
- ✅ No new third-party dependencies
- ✅ No CocoaPods required
- ✅ No SPM packages required

---

## 🧪 Quick Sanity Checks

Run these commands to verify integration:

```bash
# 1. Verify all files created
ls -la StibAlert/View/Home/HomeView*.swift
ls -la StibAlert/View/Home/HomeViewOverlays.swift
ls -la StibAlert/Networking/NetworkConnectivityMonitor.swift
ls -la StibAlert/View/Components/OfflineIndicator.swift

# 2. Check imports
grep "import Network" StibAlert/Networking/NetworkConnectivityMonitor.swift
grep "import SwiftUI" StibAlert/View/Components/OfflineIndicator.swift

# 3. Verify compilation
cd StibAlert && swift build 2>&1 | grep -i error

# 4. Check git status
git status --short
```

---

## ⚠️ Common Integration Issues

### Issue 1: "NetworkConnectivityMonitor not found"
**Cause:** Not added to `@main` app struct  
**Fix:** Add `@StateObject private var connectivity = NetworkConnectivityMonitor()`

### Issue 2: "OfflineIndicator colors not displaying"
**Cause:** DS.Color tokens not available in component file  
**Fix:** Check that DesignSystem.swift is imported in Xcode build phases

### Issue 3: "HomeViewOverlays can't access state"
**Cause:** State variables not passed as parameters  
**Fix:** Verify all @State bindings are properly captured in method signatures

### Issue 4: "Type-checker still slow"
**Cause:** Overlays still being defined inline somewhere  
**Fix:** Search entire file for `.overlay(` and verify using ViewBuilders

### Issue 5: "VoiceOver doesn't announce stop card"
**Cause:** accessibilityElement not set on container  
**Fix:** Wrap in `Group { }.accessibilityElement(children: .combine)`

---

## 📅 Integration Timeline

| Day | Task | Status |
|-----|------|--------|
| May 12 | Fixes completed | ✅ DONE |
| May 13-14 | QA Testing | 🔲 TODO |
| May 14 Evening | Final integration review | 🔲 TODO |
| May 15 | Beta build #1 | 🔲 TODO |

---

## ✅ Integration Sign-Off

Before declaring integration complete:

- [ ] All files created in correct locations
- [ ] All imports verified
- [ ] App builds without errors
- [ ] App builds without warnings (accessibility)
- [ ] Type-check completes in < 2s
- [ ] OfflineIndicator shows when offline
- [ ] VoiceOver can navigate full app
- [ ] Tab bar positioned correctly
- [ ] Date decoding works with API calls
- [ ] No regressions in existing features

---

**Prepared by:** Claude Code  
**Date:** May 12, 2026  
**Reviewed by:** [QA Lead]  
**Approved by:** [Tech Lead]
