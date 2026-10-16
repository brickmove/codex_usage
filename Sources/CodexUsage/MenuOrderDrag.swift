import Foundation
import UsageCore

/// A local reorder gesture never exports metric data or accepts drops from another application.
enum MenuOrderDrag {
    static func target(at point: CGPoint, frames: [MenuMetric: CGRect], selected: [MenuMetric], viewport: CGRect? = nil) -> MenuMetric? {
        if let viewport, !viewport.contains(point) { return nil }
        let rows = selected.compactMap { metric in frames[metric].map { (metric, $0) } }
        let bounds = rows.reduce(CGRect.null) { $0.union($1.1) }
        guard bounds.contains(point) else { return nil }
        // Include the small gaps between selected rows, so releasing over a separator still works.
        return rows.min { abs($0.1.midY - point.y) < abs($1.1.midY - point.y) }?.0
    }
}
