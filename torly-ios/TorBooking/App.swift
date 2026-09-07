import SwiftUI

@main
struct TorlyApp: App {
    @AppStorage("torly.language") private var language = "ru"
    init() { TorlyTheme.configureAppearance() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(TorlyTheme.accent)
                .environment(\.locale, Locale(identifier: language))
                .environment(\.layoutDirection, language == "he" ? .rightToLeft : .leftToRight)
        }
    }
}

enum TorlyLanguage {
    static let codes = ["he", "en", "es", "ru"]
    static let names = ["he": "עברית", "en": "English", "es": "Español", "ru": "Русский"]
    static var current: String {
        let saved = UserDefaults.standard.string(forKey: "torly.language") ?? "ru"
        return codes.contains(saved) ? saved : "ru"
    }
    static var locale: Locale { Locale(identifier: current) }
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    let path = Bundle.main.path(forResource: TorlyLanguage.current, ofType: "lproj")
    let bundle = path.flatMap(Bundle.init(path:)) ?? .main
    let value = bundle.localizedString(forKey: key, value: key, table: "Localizable")
    return arguments.isEmpty ? value : String(format: value, locale: TorlyLanguage.locale, arguments: arguments)
}

func localizedError(_ error: Error) -> String {
    if error is URLError { return L("Не удалось подключиться. Проверь интернет и попробуй ещё раз.") }
    return L(error.localizedDescription)
}

struct LanguagePicker: View {
    @AppStorage("torly.language") private var language = "ru"
    @Environment(\.locale) private var appLocale
    var body: some View {
        Picker(L("Язык приложения"), selection: $language) {
            ForEach(TorlyLanguage.codes, id: \.self) { code in
                Text(TorlyLanguage.names[code] ?? code).tag(code)
            }
        }
    }
}

struct LanguageSettings: View {
    @Environment(\.locale) private var appLocale
    var body: some View {
        TorlyForm {
            Section(L("Язык")) { LanguagePicker() }
        }.navigationTitle(L("Настройки"))
    }
}

enum TorlyTheme {
    // sRGB equivalents of the published SaaS design's OKLCH palette.
    static let background = Color(hex: 0x050E18)
    static let surface = Color(hex: 0x0E1824)
    static let text = Color(hex: 0xE9F4FA)
    static let accent = Color(hex: 0x21B1F6)
    static let muted = Color(hex: 0x92A8B9)
    static let border = Color(hex: 0x243142)
    static let success = Color(hex: 0x53CE9F)
    static let warning = Color(hex: 0xF7BC50)
    static let danger = Color(hex: 0xFB605F)

    static func statusColor(_ status: String) -> Color {
        switch status {
        case "confirmed", "completed": return success
        case "pending": return warning
        case "no_show": return danger
        default: return muted
        }
    }

    static func configureAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(surface)
        navigation.shadowColor = UIColor(border)
        navigation.titleTextAttributes = [.foregroundColor: UIColor(text)]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor(text)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(surface)
        tabs.shadowColor = UIColor(border)
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(muted)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(muted)]
            item.selected.iconColor = UIColor(accent)
            item.selected.titleTextAttributes = [.foregroundColor: UIColor(accent)]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(accent)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(background)], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(text)], for: .normal)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

private struct TorlySurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(TorlyTheme.background.ignoresSafeArea())
            .foregroundColor(TorlyTheme.text)
            .tint(TorlyTheme.accent)
            .toolbarBackground(TorlyTheme.surface, for: .navigationBar, .tabBar)
            .toolbarBackground(.visible, for: .navigationBar, .tabBar)
    }
}

struct TorlyForm<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        Form {
            content
                .listRowBackground(TorlyTheme.surface)
                .listRowSeparatorTint(TorlyTheme.border)
        }.modifier(TorlySurface())
    }
}

struct TorlyList<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        List {
            content
                .listRowBackground(TorlyTheme.surface)
                .listRowSeparatorTint(TorlyTheme.border)
        }.listStyle(.insetGrouped).modifier(TorlySurface())
    }
}

struct TorlyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(12)
            .foregroundStyle(TorlyTheme.background)
            .background(TorlyTheme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
