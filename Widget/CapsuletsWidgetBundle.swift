import SwiftUI
import WidgetKit

/// すべての capsulet のウィジェット。新しいウィジェットはここに足す
@main
struct CapsuletsWidgetBundle: WidgetBundle {
    var body: some Widget {
        FortuneMealWidget()
    }
}
