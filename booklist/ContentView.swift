import SwiftUI

// MARK: - Navigation selection

/// What is currently selected in the sidebar.
enum SidebarSelection: Hashable {
    case inbox
    case all
    case folder(UUID)
}

// MARK: - View mode

/// Layout mode for the content area.
enum ViewMode: String, CaseIterable {
    case masonry = "Masonry"
    case grid    = "Grid"
    case list    = "List"

    var iconName: String {
        switch self {
        case .masonry: "rectangle.3.group"
        case .grid:    "square.grid.2x2"
        case .list:    "list.bullet"
        }
    }
}

// MARK: - Sort option

enum SortOption: String, CaseIterable {
    case recent       = "Recent"
    case alphabetical = "A–Z"
    case random       = "Random"
}

// MARK: - Root view

struct ContentView: View {
    @State private var selection: SidebarSelection? = .inbox

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            ContentAreaView(selection: selection ?? .inbox)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

#Preview {
    ContentView()
}
