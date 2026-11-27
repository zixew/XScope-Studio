import Foundation
import CoreGraphics

// MARK: - Progressive Lazy List Chunker (Handles 1,000+ to 10,000+ Items Without Main-Thread Lag)
public enum ProgressiveListChunker {
    public static let defaultPageSize: Int = 50
    public static let prefetchThreshold: Int = 8

    /// Returns the currently materialized prefix slice (`0 ..< min(limit, items.count)`).
    public static func visibleSlice<T>(of items: [T], limit: Int) -> ArraySlice<T> {
        let clamped = max(0, min(max(limit, defaultPageSize), items.count))
        return items.prefix(clamped)
    }

    /// Returns true when the row at `currentIndex` is within `threshold` items of the current visible limit and more items remain.
    public static func shouldLoadMore(
        currentIndex: Int,
        currentLimit: Int,
        totalCount: Int,
        threshold: Int = prefetchThreshold
    ) -> Bool {
        guard currentLimit < totalCount else { return false }
        let triggerIndex = max(0, currentLimit - max(1, threshold))
        return currentIndex >= triggerIndex
    }

    /// Computes the next visible limit when loading the next batch of items.
    public static func nextLimit(
        currentLimit: Int,
        totalCount: Int,
        pageSize: Int = defaultPageSize
    ) -> Int {
        guard totalCount > 0 else { return defaultPageSize }
        return min(totalCount, max(currentLimit, defaultPageSize) + max(1, pageSize))
    }
}

// MARK: - True Off-Screen Cell Recycling / Destruction Window
public enum VirtualRecycleWindow {
    public static let defaultOverscan: Int = 4

    /// Computes the exact active row range kept alive in memory for a viewport.
    /// Any index outside `activeRange` (e.g. rows `0..<22` when scrolled to `26..38`) is destroyed/recycled.
    public static func computeActiveRange(
        firstVisibleIndex: Int,
        lastVisibleIndex: Int,
        totalCount: Int,
        overscan: Int = defaultOverscan
    ) -> Range<Int> {
        guard totalCount > 0 else { return 0..<0 }
        let clampedFirst = max(0, min(firstVisibleIndex, totalCount - 1))
        let clampedLast = max(clampedFirst, min(lastVisibleIndex, totalCount - 1))
        let start = max(0, clampedFirst - max(0, overscan))
        let end = min(totalCount, clampedLast + max(0, overscan) + 1)
        return start..<end
    }
}

// MARK: - Responsive Breakpoint & Anti-Squish Layout Engine
public enum ResponsiveViewportTier: String, Sendable, Equatable, CaseIterable {
    case compact   // < 1050pt
    case standard  // 1050pt ..< 1320pt
    case wide      // >= 1320pt
}

public struct ResponsiveRowPlacement: Sendable, Equatable {
    public let index: Int
    public let origin: CGPoint
    public let size: CGSize

    public init(index: Int, origin: CGPoint, size: CGSize) {
        self.index = index
        self.origin = origin
        self.size = size
    }
}

public struct ResponsiveFlowMeasureResult: Sendable, Equatable {
    public let placements: [ResponsiveRowPlacement]
    public let totalSize: CGSize
    public let rowCount: Int

    public init(placements: [ResponsiveRowPlacement], totalSize: CGSize, rowCount: Int) {
        self.placements = placements
        self.totalSize = totalSize
        self.rowCount = rowCount
    }
}

public enum ResponsiveBreakpointEngine {
    public static let compactMaxWidth: CGFloat = 1050
    public static let standardMaxWidth: CGFloat = 1320

    public static func tier(forWindowWidth width: CGFloat) -> ResponsiveViewportTier {
        if width < compactMaxWidth {
            return .compact
        } else if width < standardMaxWidth {
            return .standard
        } else {
            return .wide
        }
    }

    /// Computes the number of adaptive KPI columns (`2` on compact, `4` on standard/wide) so cards never compress below 180pt.
    public static func kpiGridColumnCount(forContentWidth width: CGFloat, minCardWidth: CGFloat = 185, spacing: CGFloat = 12) -> Int {
        let safeWidth = max(minCardWidth, width)
        let possible = Int((safeWidth + spacing) / (minCardWidth + spacing))
        return max(1, min(4, possible))
    }

    /// Returns whether a 2-column or 3-column master-detail view should stack vertically to prevent squished panels.
    public static func shouldStackMasterDetail(forContentWidth width: CGFloat, minimumSideBySideWidth: CGFloat = 760) -> Bool {
        width < minimumSideBySideWidth
    }

    /// Computes adaptive left-column width for master-detail views (`260..340pt`).
    public static func adaptiveMasterColumnWidth(forContentWidth width: CGFloat) -> CGFloat {
        if width < 820 {
            return 260
        } else if width < 1080 {
            return 300
        } else {
            return 340
        }
    }

    /// Pure deterministic flow layout calculation used by `FlowLayout` and verified in unit tests.
    /// Guarantees every item preserves its full intrinsic width (`size.width`) without ever squishing ("gepeng") unless a single item exceeds `maxWidth`.
    public static func computeFlowPlacements(
        itemSizes: [CGSize],
        maxWidth: CGFloat,
        horizontalSpacing: CGFloat = 8,
        verticalSpacing: CGFloat = 8
    ) -> ResponsiveFlowMeasureResult {
        guard !itemSizes.isEmpty else {
            return ResponsiveFlowMeasureResult(placements: [], totalSize: .zero, rowCount: 0)
        }

        let effectiveMaxWidth = maxWidth > 0 && maxWidth.isFinite ? maxWidth : 10_000
        var placements: [ResponsiveRowPlacement] = []
        placements.reserveCapacity(itemSizes.count)

        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var maxUsedWidth: CGFloat = 0
        var rows = 1

        for (idx, rawSize) in itemSizes.enumerated() {
            // Preserve full intrinsic width of buttons/chips so they never squish
            let itemWidth = max(1, rawSize.width)
            let itemHeight = max(1, rawSize.height)

            if currentX > 0 && (currentX + itemWidth > effectiveMaxWidth) {
                currentX = 0
                currentY += currentRowHeight + verticalSpacing
                currentRowHeight = 0
                rows += 1
            }

            let origin = CGPoint(x: currentX, y: currentY)
            let placedSize = CGSize(width: itemWidth, height: itemHeight)
            placements.append(ResponsiveRowPlacement(index: idx, origin: origin, size: placedSize))

            currentX += itemWidth + horizontalSpacing
            currentRowHeight = max(currentRowHeight, itemHeight)
            maxUsedWidth = max(maxUsedWidth, origin.x + itemWidth)
        }

        let totalHeight = currentY + currentRowHeight
        return ResponsiveFlowMeasureResult(
            placements: placements,
            totalSize: CGSize(width: maxUsedWidth, height: totalHeight),
            rowCount: rows
        )
    }
}
