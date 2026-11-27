import SwiftUI
import DevCompanionCore

/// Auto-wrapping horizontal flow layout (`Layout` protocol) that places buttons, filter chips, and controls at their full intrinsic width and wraps onto new rows when horizontal space runs out.
/// Eliminates squished buttons ("tombol gepeng") across all window widths.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    init(spacing: CGFloat = 8, verticalSpacing: CGFloat? = nil) {
        self.horizontalSpacing = spacing
        self.verticalSpacing = verticalSpacing ?? spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let maxWidth = proposal.width ?? .infinity
        return ResponsiveBreakpointEngine.computeFlowPlacements(
            itemSizes: sizes,
            maxWidth: maxWidth,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        ).totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let result = ResponsiveBreakpointEngine.computeFlowPlacements(
            itemSizes: sizes,
            maxWidth: bounds.width,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        )
        for placement in result.placements where placement.index < subviews.count {
            let pt = CGPoint(
                x: bounds.minX + placement.origin.x,
                y: bounds.minY + placement.origin.y
            )
            subviews[placement.index].place(
                at: pt,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: placement.size.width, height: placement.size.height)
            )
        }
    }
}

/// Footer bar for progressive lazy-loaded lists showing `Loaded X of Y` and an instant `Load More` button.
struct ProgressiveLoadMoreFooter: View {
    let loadedCount: Int
    let totalCount: Int
    let onLoadMore: () -> Void

    var body: some View {
        if loadedCount < totalCount {
            HStack(spacing: 10) {
                Text("Showing \(loadedCount) of \(totalCount) items")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(CompanionTheme.textSecondary)
                Spacer()
                Button("Load More (+\(min(ProgressiveListChunker.defaultPageSize, totalCount - loadedCount)))") {
                    onLoadMore()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(CompanionTheme.glassLow)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(CompanionTheme.hairlineBorder, lineWidth: 1)
                    )
            )
        }
    }
}

extension View {
    /// Prevents buttons or chips from horizontally compressing or wrapping label characters vertically.
    func preventSquish() -> some View {
        self
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
