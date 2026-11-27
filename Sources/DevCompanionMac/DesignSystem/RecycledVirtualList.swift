import SwiftUI
import AppKit

/// Identifiable + Equatable wrapper for plain value lists (`[String]`, indexed stack frames, etc.)
struct RecycledIndexItem<Value: Equatable>: Identifiable, Equatable {
    let id: Int
    let value: Value
}

/// Identifiable + Equatable wrapper for unique string lists (branches, module paths) preserving stable identity across filters.
struct RecycledStringItem: Identifiable, Equatable {
    var id: String { value }
    let value: String
}

private let recycledHostingCellIdentifier = NSUserInterfaceItemIdentifier("RecycledHostingCell")

/// True virtualized, cell-recycling list backed by AppKit `NSTableView`.
/// Only visible rows (+ small overscan) exist in memory; off-screen rows (e.g., rows 1–20 when scrolled to 26+)
/// are automatically detached, cleared via `prepareForReuse()`, and recycled/destroyed.
struct RecycledVirtualList<Item: Identifiable & Equatable, RowContent: View>: NSViewRepresentable {
    let items: [Item]
    var rowSpacing: CGFloat = 8
    @ViewBuilder let rowContent: (Item) -> RowContent

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, rowSpacing: rowSpacing, rowContent: rowContent)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = NSTableView()
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.selectionHighlightStyle = .none
        tableView.usesAutomaticRowHeights = true
        tableView.intercellSpacing = NSSize(width: 0, height: rowSpacing)
        tableView.focusRingType = .none
        tableView.style = .plain
        tableView.floatsGroupRows = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("VirtualRowColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        context.coordinator.tableView = tableView

        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let oldIDs = coordinator.itemIDs
        let newIDs = items.map(\.id)
        let oldItems = coordinator.items

        coordinator.items = items
        coordinator.rowContent = rowContent
        coordinator.rowSpacing = rowSpacing

        guard let tableView = coordinator.tableView else { return }

        if oldIDs != newIDs {
            tableView.reloadData()
        } else if oldItems != items {
            // Item count & IDs are identical (e.g. selection highlight or property changed):
            // Update only currently materialized visible cells in-place without resetting scroll position.
            coordinator.refreshVisibleCellsInPlace(in: tableView)
        } else {
            // Selection/external state may have changed: refresh visible cells in-place
            coordinator.refreshVisibleCellsInPlace(in: tableView)
        }
    }

    // MARK: - Coordinator (NSTableViewDataSource & NSTableViewDelegate)
    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var items: [Item]
        var itemIDs: [Item.ID] { items.map(\.id) }
        var rowSpacing: CGFloat
        var rowContent: (Item) -> RowContent
        weak var tableView: NSTableView?

        init(items: [Item], rowSpacing: CGFloat, rowContent: @escaping (Item) -> RowContent) {
            self.items = items
            self.rowSpacing = rowSpacing
            self.rowContent = rowContent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < items.count else { return nil }
            let item = items[row]

            let cell: RecycledHostingCellView<RowContent>
            if let reused = tableView.makeView(withIdentifier: recycledHostingCellIdentifier, owner: nil) as? RecycledHostingCellView<RowContent> {
                cell = reused
            } else {
                cell = RecycledHostingCellView<RowContent>(frame: .zero)
                cell.identifier = recycledHostingCellIdentifier
            }
            cell.configure(with: rowContent(item))
            return cell
        }

        /// Called by AppKit immediately when a row scrolls off-screen: destroys/clears the hosted SwiftUI view tree.
        func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
            for subview in rowView.subviews {
                if let cell = subview as? RecycledHostingCellView<RowContent> {
                    cell.clearHostedContent()
                }
            }
        }

        func refreshVisibleCellsInPlace(in tableView: NSTableView) {
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound, visibleRows.length > 0 else { return }
            let endRow = min(items.count, visibleRows.location + visibleRows.length)
            for row in visibleRows.location..<endRow {
                if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? RecycledHostingCellView<RowContent> {
                    cell.configure(with: rowContent(items[row]))
                }
            }
        }
    }
}

/// Reusable `NSTableCellView` hosting a single SwiftUI row view and releasing it when recycled/removed off-screen.
private final class RecycledHostingCellView<Content: View>: NSTableCellView {
    private var hostingView: NSHostingView<AnyView>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        clearHostedContent()
    }

    func configure(with rootView: Content) {
        let wrapped = AnyView(rootView.frame(maxWidth: .infinity, alignment: .leading))
        if let hostingView {
            hostingView.rootView = wrapped
        } else {
            let hv = NSHostingView(rootView: wrapped)
            hv.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hv)
            NSLayoutConstraint.activate([
                hv.leadingAnchor.constraint(equalTo: leadingAnchor),
                hv.trailingAnchor.constraint(equalTo: trailingAnchor),
                hv.topAnchor.constraint(equalTo: topAnchor),
                hv.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            self.hostingView = hv
        }
    }

    /// Destroys the SwiftUI view hierarchy inside this cell when scrolled off-screen.
    func clearHostedContent() {
        hostingView?.rootView = AnyView(EmptyView())
    }
}
