import Foundation

@MainActor
final class ClipSettings: ObservableObject {
    @Published var clipWindowSeconds: Int {
        didSet {
            AppGroup.clipWindowSeconds = clipWindowSeconds
            NotificationCenter.default.post(name: .clipWindowDidChange, object: nil)
        }
    }

    init() {
        clipWindowSeconds = AppGroup.clipWindowSeconds
    }
}
