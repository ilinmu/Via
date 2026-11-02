import Combine
import CoreGraphics

@MainActor
public final class PanelMetrics: ObservableObject {
    @Published var maxHeight: CGFloat

    init(maxHeight: CGFloat = 680) {
        self.maxHeight = maxHeight
    }
}
