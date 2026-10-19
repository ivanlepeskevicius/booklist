import SwiftUI
import SwiftData
import ServiceManagement
import KeyboardShortcuts

struct AppSettingsView: View {
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Environment(\.modelContext) private var modelContext
    @State private var newTagName = ""
    @AppStorage("cardFontDesign")  private var cardFontDesign  = "system"
    @AppStorage("cardFontName")    private var cardFontName    = ""
    @AppStorage("cardTitleSize")   private var cardTitleSize   = 14.0
    @AppStorage("cardNoteSize")    private var cardNoteSize    = 12.0
    @AppStorage("cardSizeScale")   private var cardSizeScale   = 1.0
    @AppStorage("appearanceMode")     private var appearanceMode     = "system"
    @AppStorage("showInDock")         private var showInDock         = false
    @AppStorage("preferredCurrency")  private var preferredCurrency  = Locale.current.currency?.identifier ?? "USD"
    @AppStorage("staleDaysThreshold") private var staleDaysThreshold = 90
    @AppStorage("readerDefaultWeb")    private var readerDefaultWeb    = true
    @AppStorage("captureShortcutKey")  private var captureShortcutKey  = "t"
    @AppStorage("listShowSource")     private var listShowSource     = true
    @AppStorage("listShowSaved")      private var listShowSaved      = true
    @AppStorage("listShowLastOpened") private var listShowLastOpened = true
    @AppStorage("listShowPrice")      private var listShowPrice      = true
    @AppStorage("listShowTags")       private var listShowTags       = true

    @State private var launchAtLogin    = false
    @State private var systemFonts: [String] = []
    @FocusState private var isNewTagFocused: Bool

    // Sync tab state
    @AppStorage("syncEnabled") private var syncEnabled = false
    @State private var syncFolderName       = ""
    @State private var displayedLastSync: Date? = nil
    @State private var syncError: String?   = nil
    @State private var syncSuccess          = false

    private let currencies: [(code: String, label: String)] = [
        ("AUD", "AUD – Australian Dollar"),
        ("BRL", "BRL – Brazilian Real (R$)"),
        ("CAD", "CAD – Canadian Dollar"),
        ("CHF", "CHF – Swiss Franc (Fr)"),
        ("CNY", "CNY – Chinese Yuan (¥)"),
        ("DKK", "DKK – Danish Krone"),
        ("EUR", "EUR – Euro (€)"),
        ("GBP", "GBP – British Pound (£)"),
        ("INR", "INR – Indian Rupee (₹)"),
        ("JPY", "JPY – Japanese Yen (¥)"),
        ("KRW", "KRW – Korean Won (₩)"),
        ("MXN", "MXN – Mexican Peso"),
        ("NOK", "NOK – Norwegian Krone"),
        ("PLN", "PLN – Polish Złoty (zł)"),
        ("SEK", "SEK – Swedish Krona"),
        ("USD", "USD – US Dollar ($)"),
    ]

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            displayTab
                .tabItem { Label("Display", systemImage: "rectangle.grid.2x2") }

            tagsTab
                .tabItem { Label("Tags", systemImage: "tag") }

            syncTab
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 440, height: 540)
        .onAppear {
            launchAtLogin       = SMAppService.mainApp.status == .enabled
            syncFolderName      = SyncService.syncFolderDisplayName
            displayedLastSync   = SyncService.lastSyncDate
            if systemFonts.isEmpty {
                systemFonts = NSFontManager.shared.availableFontFamilies.sorted()
            }
        }
    }

    // MARK: - General tab

    private var generalTab: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section {
                KeyboardShortcuts.Recorder("Save link from anywhere", name: .captureFromAnywhere)

                Picker("Save link in booklist", selection: $captureShortcutKey) {
                    Text("⌘T").tag("t")
                    Text("⌘N").tag("n")
                    Text("⌘B").tag("b")
                    Text("⌘K").tag("k")
                    Text("None").tag("none")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Copy a link in any app, press your shortcut, and booklist opens with it ready to save.")
                    .foregroundStyle(.secondary)
            }

            Section("Reader") {
                Picker("Default view", selection: $readerDefaultWeb) {
                    Text("Web preview").tag(true)
                    Text("Reader").tag(false)
                }
                .pickerStyle(.segmented)
            }

            Section("Wishlist") {
                Picker("Currency", selection: $preferredCurrency) {
                    ForEach(currencies, id: \.code) { currency in
                        Text(currency.label).tag(currency.code)
                    }
                }
            }

            Section("System") {
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, show in
                        NSApp.setActivationPolicy(show ? .regular : .accessory)
                    }

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                if SMAppService.mainApp.status == .requiresApproval {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Approval required in System Settings.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Spacer()
                        Button("Open Settings") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .buttonStyle(.link)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Display tab

    private var displayTab: some View {
        Form {
            Section("Typography") {
                Picker("Font", selection: $cardFontName) {
                    Text("System Default").tag("")
                    Divider()
                    ForEach(systemFonts, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)

                if cardFontName.isEmpty {
                    Picker("Style", selection: $cardFontDesign) {
                        Text("Default").tag("system")
                        Text("Rounded").tag("rounded")
                        Text("Serif").tag("serif")
                        Text("Mono").tag("monospaced")
                    }
                    .pickerStyle(.segmented)
                }

                Text("The quick brown fox jumps over the lazy dog")
                    .font(cardFontName.isEmpty ? .system(size: 13) : .custom(cardFontName, size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .animation(.default, value: cardFontName)

                LabeledContent("Title size") {
                    HStack(spacing: 8) {
                        Stepper("", value: $cardTitleSize, in: 10...22, step: 1)
                            .labelsHidden()
                        Text("\(Int(cardTitleSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .leading)
                    }
                }

                LabeledContent("Note size") {
                    HStack(spacing: 8) {
                        Stepper("", value: $cardNoteSize, in: 9...18, step: 1)
                            .labelsHidden()
                        Text("\(Int(cardNoteSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .leading)
                    }
                }
            }

            Section("Layout") {
                LabeledContent("Card size") {
                    HStack(spacing: 8) {
                        Image(systemName: "square")
                            .foregroundStyle(.secondary)
                        Slider(value: $cardSizeScale, in: 0.6...1.6, step: 0.1)
                            .frame(width: 180)
                        Image(systemName: "square.fill")
                            .foregroundStyle(.secondary)
                        Text("\(Int((cardSizeScale * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                LabeledContent("Mark stale after") {
                    HStack(spacing: 8) {
                        Stepper("", value: $staleDaysThreshold, in: 7...365, step: 7)
                            .labelsHidden()
                        Text("\(staleDaysThreshold) days")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .leading)
                    }
                }
            }

            Section {
                Toggle("Source", isOn: $listShowSource)
                Toggle("Saved", isOn: $listShowSaved)
                Toggle("Last Opened", isOn: $listShowLastOpened)
                Toggle("Tags", isOn: $listShowTags)
                Toggle("Price", isOn: $listShowPrice)
            } header: {
                Text("List Columns")
            } footer: {
                Text("Title and Actions columns are always visible.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Sync tab

    private var syncTab: some View {
        Form {
            Section {
                Toggle("Auto-sync on launch and quit", isOn: $syncEnabled)
            } footer: {
                Text("When enabled, your data is saved when you quit and restored on launch. Point to a folder in your iCloud Drive or Dropbox to keep everything in sync across Macs.")
                    .foregroundStyle(.secondary)
            }

            Section("Sync Folder") {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(syncFolderName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(syncFolderName == "Not configured" ? .secondary : .primary)
                    Spacer()
                    Button(syncFolderName == "Not configured" ? "Choose…" : "Change…") {
                        if SyncService.chooseSyncFolder() != nil {
                            syncFolderName = SyncService.syncFolderDisplayName
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last synced")
                        if let date = displayedLastSync {
                            Text(date, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Never")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Sync Now") { syncNow() }
                        .disabled(SyncService.syncFolderURL == nil)
                }

                if let error = syncError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if syncSuccess {
                    Label("Synced successfully", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func syncNow() {
        syncError   = nil
        syncSuccess = false
        // If no folder is set yet, ask the user to pick one first.
        if SyncService.syncFolderURL == nil {
            guard SyncService.chooseSyncFolder() != nil else { return }
            syncFolderName = SyncService.syncFolderDisplayName
        }
        do {
            try SyncService.export(context: modelContext)
            displayedLastSync = SyncService.lastSyncDate
            syncSuccess = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                syncSuccess = false
            }
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - Tag creation

    private func createTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !allTags.contains(where: { $0.name.lowercased() == name.lowercased() })
        else { return }
        modelContext.insert(Tag(name: name, color: Tag.randomColor()))
        newTagName = ""
    }

    // MARK: - Tags tab

    private var tagsTab: some View {
        VStack(spacing: 0) {
            // Creation row — sits above the List to avoid the List's default top inset
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 15))
                TextField("New tag…", text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isNewTagFocused)
                    .onSubmit { createTag() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(.quaternary.opacity(isNewTagFocused ? 1 : 0.5))
            )
            .focusRing(when: isNewTagFocused, cornerRadius: 7)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            Divider()
                .padding(.top, 8)
            List {
                Section {
                    if allTags.isEmpty {
                        Text("No tags yet — create one above.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(allTags) { tag in
                            TagSettingRow(tag: tag) {
                                modelContext.delete(tag)
                            }
                        }
                    }
                } header: {
                    Text("All Tags")
                } footer: {
                    Text("Click a name to rename. Click the color dot to change it.")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
        }
    }

}

// MARK: - Tag settings row

private struct TagSettingRow: View {
    @Bindable var tag: Tag
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false
    @State private var showColorPicker   = false

    var body: some View {
        HStack(spacing: 10) {
            TextField("", text: $tag.name)
                .textFieldStyle(.plain)
                .font(.body)

            Spacer()

            // Color dot — tap to open palette picker
            Button {
                showColorPicker.toggle()
            } label: {
                Circle()
                    .fill(Color(hex: tag.color))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                ColorSwatchPicker(colorHex: $tag.color)
                    .padding(14)
                    .frame(width: 280)
            }

            Text("\(tag.bookmarks.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(minWidth: 16, alignment: .trailing)

            Button {
                if tag.bookmarks.isEmpty { onDelete() }
                else { showDeleteConfirm = true }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .confirmationDialog(
            "Delete \"#\(tag.name)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This tag is used by \(tag.bookmarks.count) bookmark\(tag.bookmarks.count == 1 ? "" : "s"). Removing the tag won't delete those bookmarks.")
        }
    }
}
