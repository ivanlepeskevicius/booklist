import SwiftUI

// MARK: - Navigation selection

/// What is currently selected in the sidebar.
enum SidebarSelection: Hashable {
    case inbox
    case wishlist
    case all
    case folder(UUID)
}

// MARK: - View mode

/// Layout mode for the content area.
enum ViewMode: String, CaseIterable {
    case masonry = "Masonry"
    case list    = "List"

    var iconName: String {
        switch self {
        case .masonry: "rectangle.3.group"
        case .list:    "list.bullet"
        }
    }
}

// MARK: - Sort option

enum SortOption: String, CaseIterable {
    case recent       = "Recent"
    case lastOpened   = "Last Opened"
    case alphabetical = "A–Z"
    case random       = "Random"
}

// MARK: - Root view

struct ContentView: View {
    @State private var selection: SidebarSelection? = .inbox
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            ContentAreaView(selection: selection ?? .inbox)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(preferredColorScheme)
        // Check for URLs left by the Share Extension whenever the app comes to the foreground.
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification
            ) {
                CaptureRouter.shared.checkPendingCapture()
            }
        }
    }
}

#Preview {
    ContentView()
}
