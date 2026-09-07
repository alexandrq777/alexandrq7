import SwiftUI
import UserNotifications

@main
struct TorlyApp: App {
    @UIApplicationDelegateAdaptor(TorlyAppDelegate.self) private var appDelegate
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

struct TorlyBrand: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(uiImage: UIImage(named: "Torly-AppIcon-1024.png") ?? UIImage())
                .resizable().scaledToFit().frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            Text("Torly").font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(TorlyTheme.accent)
        }.accessibilityElement(children: .combine)
    }
}

struct TorlyLoading: View {
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var walking = false
    @State private var arrived = false
    @State private var confirmed = false
    var body: some View {
        VStack(spacing: compact ? 0 : 22) {
            ZStack {
                Image(uiImage: UIImage(named: "Torly-AppIcon-1024.png") ?? UIImage())
                    .resizable().scaledToFit().frame(width: compact ? 22 : 112, height: compact ? 22 : 112)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 5 : 24))
                    .overlay {
                        if !compact {
                            ZStack {
                                Circle().fill(TorlyTheme.success)
                                Image(systemName: "checkmark").font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                    .scaleEffect(confirmed ? 1 : 0.1).opacity(confirmed ? 1 : 0)
                            }.frame(width: 38, height: 38).offset(x: 30, y: 16)
                        }
                    }
                    .rotationEffect(.degrees(reduceMotion || arrived ? 0 : (walking ? 7 : -7)))
                    .offset(x: reduceMotion || arrived ? 0 : (walking ? (compact ? 1 : 5) : (compact ? -1 : -5)), y: reduceMotion || arrived ? 0 : (walking ? (compact ? -1 : -5) : 0))
            }.frame(width: compact ? 28 : 140, height: compact ? 28 : 140)
            if !compact {
                Text("Torly").font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(TorlyTheme.accent)
            }
        }
        .frame(maxWidth: compact ? nil : .infinity, maxHeight: compact ? nil : .infinity)
        .background((compact ? Color.clear : TorlyTheme.background).ignoresSafeArea())
        .accessibilityElement(children: .ignore).accessibilityLabel("Torly")
        .task {
            if !reduceMotion { withAnimation(compact ? .easeInOut(duration: 0.25).repeatForever(autoreverses: true) : .easeInOut(duration: 0.18).repeatCount(6, autoreverses: true)) { walking = true } }
            if compact { return }
            try? await Task.sleep(nanoseconds: 1_150_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { arrived = true }
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.65)) { confirmed = true }
        }
    }
}

@MainActor
final class TorlyTouchFeedback: NSObject, UIGestureRecognizerDelegate {
    static let shared = TorlyTouchFeedback()
    private weak var installedWindow: UIWindow?
    private let tap = UITapGestureRecognizer()
    private let pan = UIPanGestureRecognizer()
    private let impact = UIImpactFeedbackGenerator(style: .soft)
    private let selection = UISelectionFeedbackGenerator()
    private var lastDistance: CGFloat = 0
    private var lastTick: CFTimeInterval = 0
    private var scrolling = false

    func install() {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow), window !== installedWindow else { return }
        installedWindow?.removeGestureRecognizer(tap)
        installedWindow?.removeGestureRecognizer(pan)
        tap.removeTarget(nil, action: nil)
        pan.removeTarget(nil, action: nil)
        tap.addTarget(self, action: #selector(tapped))
        pan.addTarget(self, action: #selector(panned))
        for gesture in [tap, pan] {
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            gesture.delegate = self
            window.addGestureRecognizer(gesture)
        }
        installedWindow = window
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === pan {
            var view = touch.view
            while let current = view {
                if current is UIScrollView { scrolling = true; return true }
                view = current.superview
            }
            scrolling = false
            return false
        }
        return true
    }

    @objc private func tapped() {
        guard UserDefaults.standard.object(forKey: "torly.haptics") as? Bool ?? true else { return }
        impact.impactOccurred(intensity: 0.45)
        impact.prepare()
    }

    @objc private func panned() {
        guard scrolling, UserDefaults.standard.object(forKey: "torly.scrollHaptics") as? Bool ?? true else { return }
        if pan.state == .began { lastDistance = 0; selection.prepare() }
        let distance = pan.translation(in: installedWindow).y
        let now = CACurrentMediaTime()
        if pan.state == .changed && abs(distance - lastDistance) >= 80 && now - lastTick >= 0.16 {
            selection.selectionChanged()
            lastDistance = distance
            lastTick = now
        }
    }
}

@MainActor
enum TorlyPrivacyShield {
    private static var covers: [UIView] = []
    static func update(hidden: Bool) {
        covers.forEach { $0.removeFromSuperview() }
        covers = []
        guard hidden else { return }
        // Cover the window itself so presented forms are hidden in snapshots too.
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.isKeyWindow {
                let cover = UIView(frame: window.bounds)
                cover.backgroundColor = UIColor(TorlyTheme.background)
                cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                let name = UILabel()
                name.text = "Torly"
                name.font = .boldSystemFont(ofSize: 28)
                name.textColor = UIColor(TorlyTheme.accent)
                name.translatesAutoresizingMaskIntoConstraints = false
                cover.addSubview(name)
                NSLayoutConstraint.activate([name.centerXAnchor.constraint(equalTo: cover.centerXAnchor), name.centerYAnchor.constraint(equalTo: cover.centerYAnchor)])
                window.addSubview(cover)
                covers.append(cover)
            }
        }
    }
}

final class TorlyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(UserDefaults.standard.object(forKey: "torly.sounds") as? Bool ?? true ? [.banner, .list, .sound] : [.banner, .list])
    }
}

@MainActor
final class TorlyNotifications: ObservableObject {
    static let shared = TorlyNotifications()
    @Published var authorization: UNAuthorizationStatus = .notDetermined
    @Published var error: String?
    @Published var testing = false
    var allowed: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }

    func refresh() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestPermission() async {
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        catch { self.error = localizedError(error) }
        await refresh()
    }

    func send(test: Bool = false) async {
        guard test || (UserDefaults.standard.object(forKey: "torly.bookingAlerts") as? Bool ?? true) else { return }
        await refresh()
        guard allowed, !Task.isCancelled else { return }
        let content = UNMutableNotificationContent()
        content.title = test ? L("Проверка уведомлений") : L("Новая онлайн-запись")
        content.body = test ? L("Уведомления на этом устройстве разрешены.") : L("Клиент записался через вашу ссылку.")
        if UserDefaults.standard.object(forKey: "torly.sounds") as? Bool ?? true { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content,
                                             trigger: test ? UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false) : nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            if UserDefaults.standard.object(forKey: "torly.haptics") as? Bool ?? true {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch { self.error = localizedError(error) }
    }
}

struct AppSettings: View {
    @ObservedObject var store: LiveBusinessStore
    @ObservedObject private var notifications = TorlyNotifications.shared
    @Environment(\.locale) private var appLocale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage("torly.bookingAlerts") private var bookingAlerts = true
    @AppStorage("torly.sounds") private var sounds = true
    @AppStorage("torly.haptics") private var haptics = true
    @AppStorage("torly.scrollHaptics") private var scrollHaptics = true
    @AppStorage("torly.inAppAlerts") private var inAppAlerts = true
    @AppStorage("torly.privatePreview") private var privatePreview = true
    @State private var confirmSignOut = false

    var body: some View {
        TorlyForm {
            Section(L("Язык")) { LanguagePicker() }
            Section(L("Уведомления")) {
                Toggle(isOn: $inAppAlerts) { Label(L("Баннеры в приложении"), systemImage: "app.badge") }
                Toggle(isOn: Binding(get: { bookingAlerts && notifications.allowed }, set: { enabled in
                    if !enabled { bookingAlerts = false; return }
                    Task {
                        await notifications.requestPermission()
                        bookingAlerts = notifications.allowed
                        if !notifications.allowed { openSystemSettings() }
                    }
                })) { Label(L("Уведомления iPhone"), systemImage: "bell") }
                Toggle(isOn: $sounds) { Label(L("Звук уведомлений"), systemImage: "speaker.wave.2") }
                NavigationLink {
                    TorlyForm {
                        Section {
                            LabeledContent(L("Разрешение iPhone"), value: notifications.allowed ? L("Разрешено") : L("Не разрешено"))
                            LabeledContent(L("Push в фоне"), value: L("Не подключён"))
                            Button(L("Настройки iPhone"), systemImage: "arrow.up.forward.app") { openSystemSettings() }
                            Button(L("Проверить уведомление"), systemImage: "bell.badge") {
                                Task {
                                    notifications.testing = true
                                    await notifications.send(test: true)
                                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                                    notifications.testing = false
                                }
                            }.disabled(!notifications.allowed || notifications.testing)
                        }
                    }.navigationTitle(L("Уведомления")).navigationBarTitleDisplayMode(.inline)
                } label: { Label(L("Разрешения и проверка"), systemImage: "checkmark.shield") }
            }
            Section(L("Звуки и отклик")) {
                Toggle(isOn: $haptics) { Label(L("Отклик при нажатии"), systemImage: "hand.tap") }
                Toggle(isOn: $scrollHaptics) { Label(L("Отклик при прокрутке"), systemImage: "hand.draw") }
            }
            Section(L("Конфиденциальность")) {
                Toggle(isOn: $privatePreview) { Label(L("Скрывать предпросмотр"), systemImage: "eye.slash") }
                NavigationLink {
                    TorlyForm {
                        Section(L("Данные аккаунта")) { Text(L("Данные бизнеса и записей хранятся на сервере Torly. Доступ к аккаунту защищён паролем; ключ сеанса хранится в Связке ключей iPhone.")) }
                        Section(L("Онлайн-профиль")) { Text(L("При публикации имя бизнеса, адрес, телефон, услуги и свободное время доступны по ссылке записи. Публикацию можно отключить в разделе бизнеса.")) }
                        Section(L("Уведомления")) { Text(L("Уведомления не содержат имён, телефонов или названий услуг клиентов.")) }
                    }.navigationTitle(L("Данные и доступ"))
                } label: { Label(L("Данные и доступ"), systemImage: "hand.raised") }
            }
            Section(L("Аккаунт")) {
                Button(L("Обновить данные"), systemImage: "arrow.clockwise") { Task { await store.perform { try await store.reload() } } }
                    .disabled(store.busy)
                Button(L("Выйти"), role: .destructive) { confirmSignOut = true }
            }
            Section(L("О приложении")) {
                LabeledContent("Torly", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
            }
        }.navigationTitle(L("Настройки"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await notifications.refresh() }
            .onChange(of: scenePhase) { if $0 == .active { Task { await notifications.refresh() } } }
            .confirmationDialog(L("Выйти из аккаунта?"), isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button(L("Выйти"), role: .destructive) { Task { await store.signOut() } }
                Button(L("Отмена"), role: .cancel) { }
            }
            .alert("Torly", isPresented: Binding(get: { notifications.error != nil }, set: { if !$0 { notifications.error = nil } })) {
                Button("OK") { notifications.error = nil }
            } message: { Text(notifications.error ?? "") }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
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
        }.toggleStyle(.switch).modifier(TorlySurface())
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
