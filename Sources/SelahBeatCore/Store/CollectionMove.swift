import Foundation

extension Array {
    /// SwiftUI's `move(fromOffsets:toOffset:)` lives in SwiftUI, and the core
    /// module deliberately does not import it. Same semantics, so a
    /// `.onMove` handler can pass its arguments straight through.
    public mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty else { return }
        let moving = source.compactMap { indices.contains($0) ? self[$0] : nil }
        guard !moving.isEmpty else { return }

        var result = self
        for index in source.sorted(by: >) where result.indices.contains(index) {
            result.remove(at: index)
        }

        let removedBefore = source.filter { $0 < destination }.count
        let insertionPoint = Swift.max(0, Swift.min(destination - removedBefore, result.count))
        result.insert(contentsOf: moving, at: insertionPoint)
        self = result
    }
}
