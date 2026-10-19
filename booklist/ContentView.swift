import SwiftUI
import SwiftData

// MARK: - Navigation selection

// The value types below are `nonisolated`: the target defaults to MainActor, which would
// also make their Equatable/Codable conformances main-actor-only (unusable from tests).

/// What is currently selected in the sidebar.
nonisolated enum SidebarSelection: Hashable {
    case inbox
    case wishlist
    case all
    case folder(UUID)
}

// MARK: - View mode

/// Layout mode for the content area.
nonisolated enum ViewMode: String, CaseIterable {
    case masonry = "Masonry"
    case list    = "List"

    var iconName: String {
        switch self {
        case .masonry: "rectangle.3.group"
        case .list:    "list.bullet"
        }
    }
}

// MARK: - Per-item view mode

nonisolated extension SidebarSelection {
    /// Stable key for per-item preferences.
    var storageKey: String {
        switch self {
        case .inbox:          "inbox"
        case .wishlist:       "wishlist"
        case .all:            "all"
        case .folder(let id): "folder-\(id.uuidString)"
        }
    }
}

/// Remembers the view mode chosen for each sidebar item (V3). Persisted as JSON in
/// UserDefaults — local to this Mac, not part of sync.
nonisolated struct ViewModeMemory: Codable, Equatable {
    private var modes: [String: String] = [:]

    init() {}

    init(data: Data) {
        self = (try? JSONDecoder().decode(Self.self, from: data)) ?? Self()
    }

    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    func mode(for selection: SidebarSelection) -> ViewMode? {
        modes[selection.storageKey].flatMap(ViewMode.init(rawValue:))
    }

    mutating func remember(_ mode: ViewMode, for selection: SidebarSelection) {
        modes[selection.storageKey] = mode.rawValue
    }
}

// MARK: - Sort option

enum SortOption: String, CaseIterable {
    case recent       = "Recent"
    case lastOpened   = "Last Opened"
    case alphabetical = "A–Z"
    case random       = "Random"
}

// MARK: - Card size

/// Named presets for the masonry `cardSizeScale` (which maps to a column count in
/// `MasonryLayout.columnCount`). Settings › Display still offers the fine-grained slider.
nonisolated enum CardSize: CaseIterable {
    case small, medium, large, extraLarge

    var label: String {
        switch self {
        case .small:      "Small"
        case .medium:     "Medium"
        case .large:      "Large"
        case .extraLarge: "Extra Large"
        }
    }

    /// 5, 3, 2 and 1 columns respectively.
    var scale: Double {
        switch self {
        case .small:      0.7
        case .medium:     1.0
        case .large:      1.2
        case .extraLarge: 1.5
        }
    }

    /// The preset matching a scale, or nil if the slider is set between presets.
    static func matching(_ scale: Double) -> CardSize? {
        allCases.first { abs($0.scale - scale) < 0.05 }
    }

    /// Next preset scale up or down from any scale (including in-between slider values),
    /// or nil at the ends.
    static func step(from scale: Double, larger: Bool) -> Double? {
        let scales = allCases.map(\.scale)
        return larger
            ? scales.first { $0 > scale + 0.05 }
            : scales.last { $0 < scale - 0.05 }
    }
}

// MARK: - Root view

struct ContentView: View {
    @State private var selection: SidebarSelection? = .inbox
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager

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
        // The app supplies its own ModelContainer, so the modelContainer(for:isUndoEnabled:)
        // shortcut isn't available — bind the window's undo manager manually so Edit › Undo
        // (⌘Z) reverts SwiftData changes such as deletes and moves.
        .onAppear { modelContext.undoManager = undoManager }
    }
}

#Preview {
    ContentView()
}
