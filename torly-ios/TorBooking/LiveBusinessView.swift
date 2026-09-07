import SwiftUI
import Security
import UserNotifications

struct RemoteService: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let priceMinor: Int?
    let minutes: Int?
    let active: Bool
}

struct RemoteStaff: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct RemoteHours: Decodable {
    let staffId: String
    let weekday: Int
    let opensAt: String
    let closesAt: String
}

struct RemoteBusiness: Decodable, Identifiable {
    let id: String
    let name: String
    let address: String
    let phone: String
    let timezone: String
    let currency: String
    let categoryId: String
    let country: String
    let locale: String
    let slug: String
    let published: Bool
    let services: [RemoteService]
    let staff: [RemoteStaff]
    let hours: [RemoteHours]
}

struct RemoteBooking: Decodable, Identifiable {
    let id: String
    let startsAt: String
    let endsAt: String
    let clientName: String?
    let serviceName: String?
    let staffName: String
    let staffId: String
    let status: String
    let revision: Int
    let kind: String
    let priceMinor: Int?

    var statusTitle: String {
        ["pending": L("Ожидает подтверждения"), "confirmed": L("Подтверждено"), "cancelled": L("Отменено"), "completed": L("Завершено"), "no_show": L("Не пришёл")][status] ?? status
    }
}

private struct OwnerResponse: Decodable { let businesses: [RemoteBusiness] }
private struct BookingResponse: Decodable { let bookings: [RemoteBooking] }
struct BookingAlert: Decodable, Identifiable {
    let id: String
    let businessId: String
    let bookingId: String
    let createdAt: String
    let readAt: String?
    let startsAt: String
}
private struct AlertsResponse: Decodable { let alerts: [BookingAlert] }
private struct SlotResponse: Decodable { let slots: [String] }
private struct SessionResponse: Decodable { let token: String }
private struct APIMessage: Decodable { let error: String? }
struct RemoteCategory: Decodable, Identifiable {
    let id: String
    let nameEn: String
    let nameHe: String
}
struct RemoteClient: Decodable, Identifiable {
    let id: String
    let name: String
    let phone: String
    let note: String
    let noShowCount: Int
    let visits: Int
}
private struct CategoryResponse: Decodable { let categories: [RemoteCategory] }
private struct ClientResponse: Decodable { let clients: [RemoteClient] }

private enum SessionKeychain {
    static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.torly.session",
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> String? {
        var attributes = query(account)
        attributes[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String?, account: String) throws {
        SecItemDelete(query(account) as CFDictionary)
        guard let token else { return }
        var attributes = query(account)
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw URLError(.cannotWriteToFile)
        }
    }
}

@MainActor
final class LiveBusinessStore: ObservableObject {
    @Published var serverAddress = UserDefaults.standard.string(forKey: "torly.server") ?? "https://torly.cybermemo.dev"
    @Published var businesses: [RemoteBusiness] = []
    @Published var bookings: [RemoteBooking] = []
    @Published var selectedBusinessId = ""
    @Published var day = Date()
    @Published var signedIn = false
    @Published var busy = false
    @Published var error: String?
    @Published var connected = false
    @Published var loaded = false
    @Published var clients: [RemoteClient] = []
    @Published var categories: [RemoteCategory] = []
    @Published var alerts: [BookingAlert] = []
    @Published var alertBanner = false
    @Published var alertsError: String?
    private var alertPollTask: Task<Void, Never>?
    private var loadingAlerts = false
    private var token: String?
    private var baseURL: URL?
    private var streamTask: Task<Void, Never>?
    private var active = true
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    var business: RemoteBusiness? { businesses.first { $0.id == selectedBusinessId } }
    var businessCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: business?.timezone ?? "Asia/Jerusalem") ?? .gmt
        return calendar
    }

    func configure() throws {
        guard let url = URL(string: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, ["", "/"].contains(url.path) else {
            throw NSError(domain: "Torly", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Укажи HTTPS-адрес сервера, например https://api.example.com")])
        }
        baseURL = url
        serverAddress = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func request(_ path: String, method: String = "GET", body: Any? = nil) async throws -> Data {
        guard let baseURL, let url = URL(string: path, relativeTo: baseURL) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let requestedToken = token
        let (data, response) = try await URLSession.shared.data(for: request)
        guard requestedToken == token else { throw CancellationError() }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 { clearSession() }
            let message = (try? decoder.decode(APIMessage.self, from: data))?.error
            throw NSError(domain: "Torly", code: status, userInfo: [NSLocalizedDescriptionKey: L(message ?? "Сервер недоступен. Попробуй ещё раз.")])
        }
        return data
    }

    func signIn(email: String, password: String, registering: Bool = false) async {
        await perform {
            self.clearSession()
            try self.configure()
            let data = try await self.request(registering ? "/v1/accounts" : "/v1/session", method: "POST", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password])
            let session = try self.decoder.decode(SessionResponse.self, from: data)
            try SessionKeychain.save(session.token, account: self.serverAddress)
            self.token = session.token
            UserDefaults.standard.set(self.serverAddress, forKey: "torly.server")
            self.signedIn = true
            try await self.reload()
            self.startEvents()
        }
    }

    func restore() async {
        guard !serverAddress.isEmpty, !signedIn else { return }
        await perform {
            try self.configure()
            guard let saved = SessionKeychain.read(self.serverAddress) else { return }
            self.token = saved
            self.signedIn = true
            try await self.reload()
            self.startEvents()
        }
    }

    func clearSession() {
        alertPollTask?.cancel()
        alertPollTask = nil
        alerts = []
        alertBanner = false
        alertsError = nil
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        streamTask?.cancel()
        streamTask = nil
        try? SessionKeychain.save(nil, account: serverAddress)
        token = nil
        signedIn = false
        connected = false
        businesses = []
        bookings = []
        clients = []
        loaded = false
    }

    func signOut() async {
        await perform {
            _ = try await self.request("/v1/session", method: "DELETE")
            self.clearSession()
        }
    }

    func reload() async throws {
        let data = try await request("/v1/owner")
        businesses = try decoder.decode(OwnerResponse.self, from: data).businesses
        if !businesses.contains(where: { $0.id == selectedBusinessId }) {
            selectedBusinessId = businesses.first?.id ?? ""
        }
        try await loadBookings()
        try await loadClients()
        loaded = true
    }

    func loadClients() async throws {
        guard let business else { clients = []; return }
        let selected = business.id
        let data = try await request("/v1/clients?businessId=\(selected)")
        if selected == selectedBusinessId {
            clients = try decoder.decode(ClientResponse.self, from: data).clients
        }
    }

    func loadCategories() async throws {
        categories = try decoder.decode(CategoryResponse.self, from: await request("/v1/categories")).categories
    }

    func loadBookings() async throws {
        guard let business else { bookings = []; return }
        let selected = business.id
        let start = businessCalendar.startOfDay(for: day)
        let end = businessCalendar.date(byAdding: .day, value: 1, to: start)!
        var components = URLComponents()
        components.path = "/v1/bookings"
        components.queryItems = [URLQueryItem(name: "businessId", value: selected), URLQueryItem(name: "from", value: Self.iso(start)), URLQueryItem(name: "to", value: Self.iso(end))]
        let data = try await request(components.string!)
        if selected == selectedBusinessId && start == businessCalendar.startOfDay(for: day) {
            bookings = try decoder.decode(BookingResponse.self, from: data).bookings
        }
    }

    func available(serviceId: String, staffId: String, date: Date) async throws -> [String] {
        guard let business else { return [] }
        let formatter = DateFormatter()
        formatter.calendar = businessCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = businessCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var components = URLComponents()
        components.path = "/v1/availability"
        components.queryItems = ["businessId": business.id, "staffId": staffId, "serviceId": serviceId, "date": formatter.string(from: date)].map { URLQueryItem(name: $0.key, value: $0.value) }
        return try decoder.decode(SlotResponse.self, from: await request(components.string!)).slots
    }

    func update(_ booking: RemoteBooking, status: String) async {
        await perform {
            _ = try await self.request("/v1/bookings/\(booking.id)", method: "PATCH", body: ["revision": booking.revision, "status": status])
            try await self.reload()
        }
    }

    func perform(_ action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do { try await action() }
        catch is CancellationError { }
        catch { self.error = localizedError(error) }
    }

    func setActive(_ value: Bool) {
        active = value
        if value && signedIn { startEvents() }
        else {
            streamTask?.cancel(); streamTask = nil; connected = false
            alertPollTask?.cancel(); alertPollTask = nil
        }
    }

    func loadAlerts() async {
        guard signedIn, loaded, !loadingAlerts else { return }
        loadingAlerts = true
        defer { loadingAlerts = false }
        do {
            let data = try await request("/v1/alerts")
            let incoming = try decoder.decode(AlertsResponse.self, from: data).alerts
            alerts = incoming
            alertsError = nil
            let key = "torly.seenAlerts." + serverAddress
            let previous = UserDefaults.standard.stringArray(forKey: key) ?? []
            let seen = Set(previous)
            let newAlerts = incoming.filter { $0.readAt == nil && !seen.contains($0.id) }
            guard !newAlerts.isEmpty else { return }
            if UserDefaults.standard.object(forKey: "torly.inAppAlerts") as? Bool ?? true { alertBanner = true }
            // The inbox retains unread alerts independently of OS permission or SSE delivery.
            await TorlyNotifications.shared.send()
            let currentIds = Set(incoming.map(\.id))
            UserDefaults.standard.set(Array((previous.filter { !currentIds.contains($0) } + incoming.map(\.id)).suffix(1000)), forKey: key)
        } catch is CancellationError { }
        catch { alertsError = localizedError(error) }
    }

    func readAlerts(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        await perform {
            _ = try await self.request("/v1/alerts/read", method: "POST", body: ["ids": ids])
            await self.loadAlerts()
        }
    }

    private func startEvents() {
        streamTask?.cancel()
        guard active, let baseURL, let token else { return }
        alertPollTask?.cancel()
        alertPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.signedIn else { return }
                await self.loadAlerts()
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            }
        }
        streamTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.signedIn else { return }
                do {
                    var request = URLRequest(url: baseURL.appendingPathComponent("v1/events"))
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.timeoutInterval = 60
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.userAuthenticationRequired) }
                    self.connected = true
                    try await self.reload()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if line == "event: calendar" { try await self.reload() }
                        if line == "event: online-booking" { await self.loadAlerts() }
                    }
                } catch {
                    if Task.isCancelled { return }
                }
                self.connected = false
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            }
        }
    }

    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    func time(_ value: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.timeZone = businessCalendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct LiveBusinessView: View {
    @Environment(\.locale) private var appLocale
    var body: some View { ContentView() }
}

struct LiveServiceForm: View {
    @Environment(\.locale) private var appLocale
    @ObservedObject var store: LiveBusinessStore
    let service: RemoteService?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var price = ""
    @State private var minutes = 60
    @State private var error: String?
    @State private var saving = false
    @State private var requestKey = UUID().uuidString

    var body: some View {
        NavigationStack {
            TorlyForm {
                TextField(L("Название"), text: $name)
                TextField(L("Цена (%@)", store.business?.currency ?? "ILS"), text: $price).keyboardType(.decimalPad).font(.body.bold()).foregroundStyle(TorlyTheme.accent)
                Stepper(value: $minutes, in: 5...480, step: 5) { TorlyNumber(value: L("%d мин", minutes)) }
                if let error { Text(error).foregroundStyle(TorlyTheme.danger) }
            }
            .navigationTitle(L("Услуга"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Сохранить")) {
                        Task {
                            let normalized = price.replacingOccurrences(of: ",", with: ".")
                            guard normalized.range(of: #"^\d{1,7}(\.\d{1,2})?$"#, options: .regularExpression) != nil, let decimal = Decimal(string: normalized), decimal >= 0, decimal <= 1000000 else { error = L("Укажи корректную цену"); return }
                            saving = true
                            defer { saving = false }
                            do {
                                var body: [String: Any] = ["name":name, "priceMinor":NSDecimalNumber(decimal: decimal * 100).intValue,"minutes":minutes]
                                if service == nil { body["businessId"] = store.selectedBusinessId; body["requestKey"] = requestKey }
                                _ = try await store.request(service.map { "/v1/services/\($0.id)" } ?? "/v1/services", method: service == nil ? "POST" : "PUT", body: body)
                                try await store.reload()
                                dismiss()
                            } catch { self.error = localizedError(error) }
                        }
                    }.disabled(saving || name.isEmpty || price.isEmpty)
                }
            }
            .onAppear { name = service?.name ?? ""; minutes = service?.minutes ?? 60; price = service?.priceMinor.map { String(format: "%.2f", Double($0)/100) } ?? "" }
        }
    }
}

struct LiveBookingForm: View {
    @Environment(\.locale) private var appLocale
    @ObservedObject var store: LiveBusinessStore
    @Environment(\.dismiss) private var dismiss
    @State private var serviceId = ""
    @State private var staffId = ""
    @State private var slots: [String] = []
    @State private var slot = ""
    @State private var name = ""
    @State private var phone = "+972"
    @State private var error: String?
    @State private var loading = false
    @State private var saving = false
    @State private var requestKey = UUID().uuidString

    var body: some View {
        NavigationStack {
            TorlyForm {
                Picker(L("Услуга"), selection: $serviceId) {
                    Text(L("Выбрать")).tag("")
                    ForEach(store.business?.services.filter(\.active) ?? []) { Text($0.name).tag($0.id) }
                }
                Picker(L("Сотрудник"), selection: $staffId) {
                    Text(L("Выбрать")).tag("")
                    ForEach(store.business?.staff ?? []) { Text($0.name).tag($0.id) }
                }
                if loading { ProgressView() }
                Picker(L("Время"), selection: $slot) {
                    Text(L("Выбрать")).tag("")
                    ForEach(slots, id: \.self) { Text(store.time($0)).bold().foregroundStyle(TorlyTheme.accent).tag($0) }
                }
                if !loading && slots.isEmpty { Text(L("Нет свободного времени")).foregroundStyle(TorlyTheme.muted) }
                TextField(L("Имя клиента"), text: $name)
                TextField(L("Телефон"), text: $phone).keyboardType(.phonePad).font(.body.bold()).foregroundStyle(TorlyTheme.accent)
                if let error { Text(error).foregroundStyle(TorlyTheme.danger) }
            }
            .disabled(saving)
            .navigationTitle(L("Новая запись"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Записать")) {
                        Task {
                            guard let business = store.business else { return }
                            saving = true
                            defer { saving = false }
                            do {
                                _ = try await store.request("/v1/bookings", method: "POST", body: ["businessId":business.id,"staffId":staffId,"serviceId":serviceId,"startsAt":slot,"clientName":name,"clientPhone":phone,"requestKey":requestKey])
                                try await store.reload()
                                dismiss()
                            } catch { self.error = localizedError(error) }
                        }
                    }.disabled(saving || loading || slot.isEmpty || name.isEmpty)
                }
            }
            .task(id: "\(serviceId)|\(staffId)") {
                slots = []; slot = ""; requestKey = UUID().uuidString
                guard !serviceId.isEmpty, !staffId.isEmpty else { return }
                loading = true
                defer { loading = false }
                do {
                    let result = try await store.available(serviceId: serviceId, staffId: staffId, date: store.day)
                    try Task.checkCancellation()
                    slots = result
                } catch { if !Task.isCancelled { self.error = localizedError(error) } }
            }
            .onChange(of: slot) { _ in requestKey = UUID().uuidString }
            .onChange(of: name) { _ in requestKey = UUID().uuidString }
            .onChange(of: phone) { _ in requestKey = UUID().uuidString }
            .onAppear { staffId = store.business?.staff.first?.id ?? ""; serviceId = store.business?.services.first(where: \.active)?.id ?? "" }
        }
    }
}

struct LiveHoursForm: View {
    @Environment(\.locale) private var appLocale
    @ObservedObject var store: LiveBusinessStore
    let staff: RemoteStaff
    @State private var open = Array(repeating: false, count: 7)
    @State private var starts = Array(repeating: "07:00", count: 7)
    @State private var ends = Array(repeating: "15:00", count: 7)
    @State private var message: String?
    @State private var saving = false
    private var weekdays: [String] { [L("Воскресенье"),L("Понедельник"),L("Вторник"),L("Среда"),L("Четверг"),L("Пятница"),L("Суббота")] }

    var body: some View {
        TorlyForm {
            ForEach(0..<7) { day in
                Section {
                    Toggle(weekdays[day], isOn: $open[day])
                    if open[day] {
                        HStack {
                            TextField(L("С"), text: $starts[day]).keyboardType(.numbersAndPunctuation).font(.body.bold()).foregroundStyle(TorlyTheme.accent)
                            Text("–")
                            TextField(L("До"), text: $ends[day]).keyboardType(.numbersAndPunctuation).font(.body.bold()).foregroundStyle(TorlyTheme.accent)
                        }
                    }
                }
            }
            if let message { Text(message) }
            Button(L("Сохранить")) {
                Task {
                    saving = true
                    defer { saving = false }
                    do {
                        let data: [[String: Any]] = (0..<7).filter { open[$0] }.map { ["weekday":$0,"opensAt":starts[$0],"closesAt":ends[$0]] }
                        _ = try await store.request("/v1/staff/\(staff.id)/hours", method: "PUT", body: data)
                        try await store.reload()
                        message = L("Сохранено")
                    } catch { message = localizedError(error) }
                }
            }.disabled(saving)
        }
        .navigationTitle(staff.name)
        .onAppear {
            for day in store.business?.hours.filter({ $0.staffId == staff.id }) ?? [] {
                open[day.weekday] = true
                starts[day.weekday] = String(day.opensAt.prefix(5))
                ends[day.weekday] = String(day.closesAt.prefix(5))
            }
        }
    }
}
