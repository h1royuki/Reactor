import Foundation
import Network

/// Whether the current connection costs the user money or data (cellular, hotspot, Low Data Mode).
@MainActor
final class NetworkStatus {
    static let shared = NetworkStatus()

    private(set) var isExpensive = false

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive || path.isConstrained
            Task { @MainActor in self?.isExpensive = expensive }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkStatus"))
    }
}
