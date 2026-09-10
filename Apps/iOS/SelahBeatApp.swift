import SwiftUI
import SelahBeatCore
import SelahBeatUI

@main
struct SelahBeatApp: App {
    @State private var model = AppModel.live()
    @State private var isReady = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    IOSRootView(model: model)
                } else {
                    Color(white: 0.11).ignoresSafeArea()
                }
            }
            .task {
                await model.bootstrap()
                isReady = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Flush immediately on background: worst-case data loss should be
            // zero when the user swipes away, not 400 ms.
            if phase != .active {
                Task { await model.flush() }
            }
        }
    }
}
