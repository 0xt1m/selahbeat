import SwiftUI
import SelahBeatCore

public enum RootSection: Hashable, CaseIterable {
    case metronome
    case services
    case library

    var title: String {
        switch self {
        case .metronome: return "Metronome"
        case .services: return "Services"
        case .library: return "Library"
        }
    }

    var symbol: String {
        switch self {
        case .metronome: return "metronome"
        case .services: return "list.bullet.rectangle.portrait"
        case .library: return "music.note.list"
        }
    }
}

public extension View {
    /// Pins the compact transport above the tab bar. Applied per tab rather
    /// than around the TabView, because a bar placed outside the TabView lands
    /// *below* the tab bar instead of above it.
    @ViewBuilder
    func withCompactTransport(_ model: AppModel) -> some View {
        self.safeAreaInset(edge: .bottom, spacing: 0) {
            CompactTransportBar(model: model)
        }
    }
}

/// The sidebar + detail layout, used by macOS always and by iPad whenever the
/// window is regular width. Shared so the two platforms cannot drift.
public struct WideRootLayout: View {
    @Bindable private var model: AppModel
    @State private var section: RootSection? = .metronome
    @State private var servicePath: [UUID] = []
    // Keep the sidebar out by default; on iPad it otherwise auto-collapses to
    // a toggle button, which hides the app's whole navigation.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            UpdateBanner(model: model)
            NavigationSplitView(columnVisibility: $columnVisibility) {
                List(RootSection.allCases, id: \.self, selection: $section) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
            } detail: {
                detail
            }
            .navigationSplitViewStyle(.balanced)
            TransportBar(model: model)
        }
        // Without this the sidebar selection and its icons come out system
        // blue, which fights the orange used everywhere else.
        .tint(Theme.accent)
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .metronome, .none:
            MetronomeView(model: model)
        case .library:
            SongsGridView(model: model)
        case .services:
            NavigationStack(path: $servicePath) {
                ServicesGridView(model: model) { id in
                    servicePath = [id]
                }
                .navigationDestination(for: UUID.self) { id in
                    ServiceDetailView(model: model, serviceID: id)
                }
            }
            .onChange(of: servicePath) { _, path in
                model.selectedServiceID = path.last
            }
        }
    }
}

/// The tab layout, for compact widths (iPhone, and iPad in a narrow split).
public struct CompactRootLayout: View {
    @Bindable private var model: AppModel
    @State private var tab: Tab
    @State private var servicePath: [UUID] = []

    public enum Tab: Hashable {
        case metronome, services, library

        /// Lets a screenshot or UI test open straight to a tab.
        public static var initial: Tab {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-tab-services") { return .services }
            if args.contains("-tab-library") { return .library }
            #endif
            return .metronome
        }
    }

    public init(model: AppModel) {
        self.model = model
        self._tab = State(initialValue: Tab.initial)
    }

    public var body: some View {
        VStack(spacing: 0) {
            UpdateBanner(model: model)
            TabView(selection: $tab) {
                MetronomeView(model: model)
                    .tabItem { Label("Metronome", systemImage: "metronome") }
                    .tag(Tab.metronome)

                NavigationStack(path: $servicePath) {
                    ServicesGridView(model: model) { id in
                        servicePath = [id]
                    }
                    .navigationDestination(for: UUID.self) { id in
                        ServiceDetailView(model: model, serviceID: id)
                    }
                }
                .withCompactTransport(model)
                .tabItem { Label("Services", systemImage: "list.bullet.rectangle.portrait") }
                .tag(Tab.services)

                NavigationStack {
                    SongsGridView(model: model)
                }
                .withCompactTransport(model)
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(Tab.library)
            }
            .tint(Theme.accent)
            .onChange(of: servicePath) { _, path in
                model.selectedServiceID = path.last
            }
        }
    }
}

/// Chooses the layout from the available width, so an iPad gets the sidebar
/// and a full-width transport instead of a stretched phone layout.
public struct SelahBeatRootView: View {
    @Bindable private var model: AppModel

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.isStageMode {
                StageModeView(model: model)
            } else {
                layout
            }
        }
        .preferredColorScheme(.dark)
        .task { model.startBackgroundSync() }
    }

    @ViewBuilder
    private var layout: some View {
        #if os(macOS)
        WideRootLayout(model: model)
        #else
        if horizontalSizeClass == .regular {
            WideRootLayout(model: model)
        } else {
            CompactRootLayout(model: model)
        }
        #endif
    }
}
