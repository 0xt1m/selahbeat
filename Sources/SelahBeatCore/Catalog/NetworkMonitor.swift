import Foundation
import Network
import Observation

/// Reachability, used ONLY as a UI hint and to skip pointless requests.
/// Correctness never depends on it — reachability is famously a lie, so every
/// request is still attempted with a short timeout.
@MainActor
@Observable
public final class NetworkMonitor {
    public private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.selahbeat.network")

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
