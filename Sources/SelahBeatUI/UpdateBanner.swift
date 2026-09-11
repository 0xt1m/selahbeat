import SwiftUI
import SelahBeatCore

/// Shown only when a newer release exists and the user has not skipped it.
/// Never blocks anything.
public struct UpdateBanner: View {
    @Bindable private var model: AppModel
    @Environment(\.openURL) private var openURL

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        if let release = model.updates.availableUpdate {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Theme.accent)
                Text("SelahBeat \(release.version) is available")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()

                if model.updater != nil {
                    Button {
                        if model.updater?.canInstallUpdates == true {
                            model.updater?.installUpdate()
                        } else {
                            // Sparkle busy or unable to check: at least get the
                            // user to the download rather than doing nothing.
                            openURL(release.url)
                        }
                    } label: {
                        Text("Update Now")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button("What's new") { openURL(release.url) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Button("Skip") { model.updates.skip(release) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                Button {
                    model.updates.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Theme.surfaceRaised)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
        }
    }
}
