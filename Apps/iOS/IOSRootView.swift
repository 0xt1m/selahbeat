import SwiftUI
import SelahBeatCore
import SelahBeatUI

/// iOS entry point. The layout choice (sidebar on iPad, tabs on iPhone) lives
/// in SelahBeatRootView so both platforms share it.
struct IOSRootView: View {
    @Bindable var model: AppModel

    var body: some View {
        SelahBeatRootView(model: model)
    }
}
