import SwiftUI
import ServiceManagement

struct AppSettingsView: View {
    @AppStorage("cardFontDesign")     private var cardFontDesign     = "system"
    @AppStorage("cardTextScale")      private var cardTextScale      = 1.0
    @AppStorage("cardSizeScale")      private var cardSizeScale      = 1.0
    @AppStorage("appearanceMode")     private var appearanceMode     = "system"
    @AppStorage("showInDock")         private var showInDock         = false
    @AppStorage("preferredCurrency")  private var preferredCurrency  = Locale.current.currency?.identifier ?? "USD"
    @AppStorage("staleDaysThreshold") private var staleDaysThreshold = 90
    @AppStorage("listShowSource")     private var listShowSource     = true
    @AppStorage("listShowSaved")      private var listShowSaved      = true
    @AppStorage("listShowLastOpened") private var listShowLastOpened = true
    @AppStorage("listShowPrice")      private var listShowPrice      = true

    @State private var launchAtLogin = false

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

    private var fontDesign: Font.Design {
        switch cardFontDesign {
        case "rounded":    return .rounded
        case "serif":      return .serif
        case "monospaced": return .monospaced
        default:           return .default
        }
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            cardsTab
                .tabItem { Label("Cards", systemImage: "rectangle.grid.2x2") }

            listTab
                .tabItem { Label("List", systemImage: "list.bullet") }

            wishlistTab
                .tabItem { Label("Wishlist", systemImage: "cart") }
        }
        .frame(width: 440, height: 540)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
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

    // MARK: - Cards tab

    private var cardsTab: some View {
        Form {
            Section("Typography") {
                Picker("Font", selection: $cardFontDesign) {
                    Text("System").tag("system")
                    Text("Rounded").tag("rounded")
                    Text("Serif").tag("serif")
                    Text("Mono").tag("monospaced")
                }
                .pickerStyle(.segmented)

                LabeledContent("Text size") {
                    HStack(spacing: 8) {
                        Text("A")
                            .font(.system(size: 11, design: fontDesign))
                            .foregroundStyle(.secondary)
                        Slider(value: $cardTextScale, in: 0.75...1.5, step: 0.05)
                            .frame(width: 180)
                        Text("A")
                            .font(.system(size: 16, design: fontDesign))
                            .foregroundStyle(.secondary)
                        Text("\(Int((cardTextScale * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: 36, alignment: .trailing)
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

            Section("Preview") {
                HStack {
                    Spacer()
                    previewCard
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - List tab

    private var listTab: some View {
        Form {
            Section {
                Toggle("Source", isOn: $listShowSource)
                Toggle("Saved", isOn: $listShowSaved)
                Toggle("Last Opened", isOn: $listShowLastOpened)
                Toggle("Price", isOn: $listShowPrice)
            } header: {
                Text("Visible Columns")
            } footer: {
                Text("Title and Actions columns are always visible.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Wishlist tab

    private var wishlistTab: some View {
        Form {
            Section("Currency") {
                Picker("Currency", selection: $preferredCurrency) {
                    ForEach(currencies, id: \.code) { currency in
                        Text(currency.label).tag(currency.code)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Live preview card

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.accentColor.opacity(0.08)
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            .frame(height: 80)

            VStack(alignment: .leading, spacing: 5) {
                Text("Design Systems That Scale")
                    .font(.system(size: 14 * cardTextScale, design: fontDesign))
                    .fontWeight(.medium)
                    .lineLimit(2)
                Text("A look at how design systems evolve as products grow.")
                    .font(.system(size: 12 * cardTextScale, design: fontDesign))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("Apr 21, 2026")
                    .font(.system(size: 10 * cardTextScale, design: fontDesign))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .frame(width: 200)
        .padding(.vertical, 4)
    }
}
