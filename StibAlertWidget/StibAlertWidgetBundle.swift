import WidgetKit
import SwiftUI

@main
struct StibAlertWidgetBundle: WidgetBundle {
    var body: some Widget {
        StibAlertWidget()
        MorningVerdictWidget()
        if #available(iOS 16.1, *) {
            JourneyLiveActivity()
        }
    }
}
