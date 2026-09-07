import SwiftUI

struct ContentView: View {
    @Environment(\.locale) private var appLocale
    @StateObject private var store = LiveBusinessStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("torly.privatePreview") private var privatePreview = true
    @State private var email = ""
    @State private var password = ""
    @State private var registering = false
    @State private var showBooking = false
    @State private var showService = false
    @State private var editingService: RemoteService?
    @State private var showStaff = false
    @State private var showBlock = false
    @State private var moving: RemoteBooking?
    @State private var staffFilter = ""
    @State private var search = ""
    @State private var launching = true
    @State private var selectedTab = 0
    @State private var showAlerts = false

    var body: some View {
        Group {
            if !store.signedIn { login }
            else if !store.loaded {
                NavigationStack {
                    VStack(spacing: 20) {
                        if store.busy { TorlyLoading() }
                        else {
                            Text(L("Загрузка аккаунта")).font(.headline)
                            Button(L("Повторить")) { Task { await store.perform { try await store.reload() } } }
                            Button(L("Выйти")) { Task { await store.signOut() } }
                        }
                    }.navigationTitle("Torly")
                }
            } else if store.business == nil {
                NavigationStack {
                    BusinessSetupForm(store: store, editing: false)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(L("Выйти")) { Task { await store.signOut() } }
                            }
                        }
                }
            } else {
                VStack(spacing: 0) {
                    brandHeader
                    TabView(selection: $selectedTab) {
                    calendar.tabItem { Label(L("Календарь"), systemImage: "calendar") }.tag(0)
                    clients.tabItem { Label(L("Клиенты"), systemImage: "person.2") }.tag(1)
                    services.tabItem { Label(L("Услуги"), systemImage: "scissors") }.tag(2)
                    business.tabItem { Label(L("Бизнес"), systemImage: "building.2") }.tag(3)
                    NavigationStack { AppSettings(store: store) }.tabItem { Label(L("Настройки"), systemImage: "gearshape") }.tag(4)
                }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(TorlyTheme.accent)
        .background(TorlyTheme.background.ignoresSafeArea())
        .alert("Torly", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .overlay { if launching { TorlyLoading().transition(.opacity) } }
        .task {
            TorlyTouchFeedback.shared.install()
            async let restored: Void = store.restore()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.2)) { launching = false }
            await restored
            TorlyTouchFeedback.shared.install()
        }
        .onChange(of: scenePhase) {
            TorlyPrivacyShield.update(hidden: privatePreview && $0 != .active)
            if $0 == .active { TorlyTouchFeedback.shared.install() }
            store.setActive($0 == .active)
        }
        .sheet(isPresented: $showBooking) { LiveBookingForm(store: store) }
        .sheet(isPresented: $showService) { LiveServiceForm(store: store, service: nil) }
        .sheet(item: $editingService) { LiveServiceForm(store: store, service: $0) }
        .sheet(isPresented: $showStaff) { StaffCreationForm(store: store) }
        .sheet(isPresented: $showBlock) { BlockForm(store: store) }
        .sheet(item: $moving) { MoveBookingForm(store: store, booking: $0) }
        .sheet(isPresented: $showAlerts) { notificationInbox }
    }

    private var brandHeader: some View {
                    VStack(spacing: 8) {
                        HStack {
                            TorlyBrand()
                            Spacer()
                            if store.busy { TorlyLoading(compact: true) }
                            Button { showAlerts = true } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "bell")
                                    let unread = store.alerts.filter { $0.readAt == nil }.count
                                    if unread > 0 { TorlyNumber(value: "\(unread)", font: .subheadline) }
                                }.font(.system(size: 22, weight: .semibold)).frame(minWidth: 56, minHeight: 48).contentShape(Rectangle())
                            }.accessibilityLabel(L("Уведомления"))
                        }
                        if store.alertBanner {
                            HStack {
                                Button { showAlerts = true; store.alertBanner = false } label: {
                                    Label(L("Новая онлайн-запись"), systemImage: "calendar.badge.plus")
                                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Button { store.alertBanner = false } label: { TorlyActionIcon(name: "xmark") }
                                    .accessibilityLabel(L("Закрыть"))
                            }
                        }
                    }
                        .padding(.horizontal, 20).padding(.vertical, 8)
                        .background(TorlyTheme.surface)
                        .overlay(alignment: .bottom) { Rectangle().fill(TorlyTheme.border).frame(height: 1) }
    }

    private var notificationInbox: some View {
        NavigationStack {
            TorlyList {
                if let error = store.alertsError {
                    Section { Text(error).foregroundStyle(TorlyTheme.warning) }
                }
                if store.alerts.isEmpty && store.alertsError == nil {
                    EmptyRow(title: L("Уведомлений пока нет"), symbol: "bell")
                }
                ForEach(store.alerts) { alert in
                    Button {
                        store.selectedBusinessId = alert.businessId
                        staffFilter = ""
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        store.day = formatter.date(from: alert.startsAt) ?? ISO8601DateFormatter().date(from: alert.startsAt) ?? Date()
                        selectedTab = 0
                        showAlerts = false
                        store.alertBanner = false
                        Task {
                            await store.readAlerts([alert.id])
                            await store.perform { try await store.loadBookings() }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: alert.readAt == nil ? "envelope.badge" : "envelope.open")
                                .foregroundStyle(alert.readAt == nil ? TorlyTheme.accent : TorlyTheme.muted)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("Новая онлайн-запись")).font(.body.weight(alert.readAt == nil ? .semibold : .regular))
                                Text(store.businesses.first { $0.id == alert.businessId }?.name ?? "Torly")
                                    .font(.body.bold()).foregroundStyle(.white)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward").font(.caption)
                        }.padding(.vertical, 4)
                    }
                }
            }.navigationTitle(L("Уведомления")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Закрыть")) { showAlerts = false } }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await store.readAlerts(store.alerts.filter { $0.readAt == nil }.map(\.id)); store.alertBanner = false }
                        } label: { TorlyActionIcon(name: "checkmark.circle") }
                            .accessibilityLabel(L("Отметить прочитанными"))
                            .disabled(store.busy || !store.alerts.contains { $0.readAt == nil })
                    }
                }
                .task { await store.loadAlerts() }
                .refreshable { await store.loadAlerts() }
        }
    }

    private var login: some View {
        NavigationStack {
            TorlyForm {
                Section { LanguagePicker() }
                Section {
                    VStack(spacing: 12) {
                        if let path = Bundle.main.path(forResource: "Torly-AppIcon-1024", ofType: "png"),
                           let icon = UIImage(contentsOfFile: path) {
                            Image(uiImage: icon).resizable().frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        Text("Torly").font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(.tint)
                        Text(L("Твой бизнес. Твоё время.")).foregroundStyle(TorlyTheme.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
                Section {
                    Picker(L("Аккаунт"), selection: $registering) {
                        Text(L("Войти")).tag(false)
                        Text(L("Регистрация")).tag(true)
                    }.pickerStyle(.segmented)
                    TextField("Email", text: $email, prompt: Text(L("Email")).foregroundColor(TorlyTheme.muted))
                        .keyboardType(.emailAddress).textContentType(.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(registering ? L("Пароль, минимум 12 символов") : L("Пароль"), text: $password,
                                prompt: Text(registering ? L("Пароль, минимум 12 символов") : L("Пароль")).foregroundColor(TorlyTheme.muted))
                        .textContentType(registering ? .newPassword : .password)
                    Button {
                        Task {
                            await store.signIn(email: email, password: password, registering: registering)
                            if store.signedIn { password = "" }
                        }
                    } label: {
                        HStack {
                            Text(registering ? L("Создать аккаунт") : L("Войти"))
                            Spacer()
                            if store.busy { ProgressView() } else { Image(systemName: "arrow.right") }
                        }
                    }.buttonStyle(TorlyPrimaryButtonStyle())
                    .disabled(store.busy || email.isEmpty || password.count < (registering ? 12 : 1))
                }
            }.navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var calendar: some View {
        NavigationStack {
            TorlyList {
                onlineBooking
                Section {
                    DatePicker(L("Дата"), selection: $store.day, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .fontWeight(.bold).foregroundStyle(TorlyTheme.accent)
                        .environment(\.timeZone, store.businessCalendar.timeZone)
                        .onChange(of: store.day) { _ in
                            Task { await store.perform { try await store.loadBookings() } }
                        }
                    if (store.business?.staff.count ?? 0) > 1 {
                        Picker(L("Сотрудник"), selection: $staffFilter) {
                            Text(L("Все")).tag("")
                            ForEach(store.business?.staff ?? []) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                Section(L("Записи")) {
                    let entries = store.bookings.filter { staffFilter.isEmpty || $0.staffId == staffFilter }
                    if entries.isEmpty {
                        EmptyRow(title: L("Записей пока нет"), symbol: "calendar")
                    }
                    ForEach(entries) { booking in bookingRow(booking) }
                }
                Section(L("Итоги дня")) {
                    TorlyValueRow(title: L("Записей"), value: "\(store.bookings.filter { $0.kind == "booking" && $0.status != "cancelled" }.count)")
                    TorlyValueRow(title: L("Завершено"), value: "\(store.bookings.filter { $0.kind == "booking" && $0.status == "completed" }.count)")
                    TorlyValueRow(title: L("Стоимость завершённых услуг"), value: money(store.bookings.filter { $0.kind == "booking" && $0.status == "completed" }.reduce(0) { $0 + ($1.priceMinor ?? 0) }))
                }
                Section {
                    Label(store.connected ? L("Календарь синхронизирован") : L("Переподключение…"),
                          systemImage: store.connected ? "checkmark.icloud" : "icloud.slash")
                        .font(.caption).foregroundStyle(TorlyTheme.muted)
                }
            }
            .navigationTitle(store.business?.name ?? L("Календарь"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(L("Новая запись"), systemImage: "calendar.badge.plus") { showBooking = true }
                            .disabled(!(store.business?.services.contains(where: \.active) ?? false))
                        Button(L("Перерыв или отпуск"), systemImage: "pause.circle") { showBlock = true }
                            .disabled(store.business?.staff.isEmpty ?? true)
                    } label: { TorlyActionIcon(name: "plus") }.accessibilityLabel(L("Добавить"))
                }
            }
            .refreshable { await store.perform { try await store.reload() } }
        }
    }

    private func bookingRow(_ booking: RemoteBooking) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TorlyNumber(value: "\(store.time(booking.startsAt)) – \(store.time(booking.endsAt))", font: .headline)
                Spacer()
                if ["pending", "confirmed"].contains(booking.status) {
                    Menu {
                        if booking.kind == "booking" {
                            if booking.status == "pending" {
                                Button(L("Подтвердить")) { Task { await store.update(booking, status: "confirmed") } }
                            }
                            Button(L("Перенести")) { moving = booking }
                            Button(L("Завершить")) { Task { await store.update(booking, status: "completed") } }
                            Button(L("Не пришёл")) { Task { await store.update(booking, status: "no_show") } }
                        }
                        Button(L("Отменить"), role: .destructive) { Task { await store.update(booking, status: "cancelled") } }
                    } label: { TorlyActionIcon(name: "ellipsis") }.accessibilityLabel(L("Действия с записью"))
                }
            }
            Text(booking.clientName ?? (booking.kind == "time_off" ? L("Отпуск") : L("Перерыв"))).font(.headline)
            Text([booking.serviceName, booking.staffName].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(TorlyTheme.muted)
            HStack(spacing: 6) {
                Circle().fill(TorlyTheme.statusColor(booking.status)).frame(width: 6, height: 6)
                Text(booking.statusTitle).font(.subheadline.weight(.medium))
            }.foregroundStyle(TorlyTheme.statusColor(booking.status))
        }.padding(.vertical, 5)
    }

    private var clients: some View {
        NavigationStack {
            TorlyList {
                if store.clients.isEmpty { EmptyRow(title: L("Клиентов пока нет"), symbol: "person.2") }
                ForEach(store.clients.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.phone.contains(search) }) { client in
                    NavigationLink {
                        ClientDetailForm(store: store, client: client)
                    } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(client.name).font(.body.bold()).foregroundStyle(.white)
                            TorlyNumber(value: client.phone, font: .subheadline)
                            if client.noShowCount > 0 {
                                Label(L("Неявки: %d", client.noShowCount), systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(TorlyTheme.warning)
                            }
                        }
                    }
                }
            }.navigationTitle(L("Клиенты")).navigationBarTitleDisplayMode(.inline)
                .searchable(text: $search, prompt: L("Имя или телефон"))
                .refreshable { await store.perform { try await store.loadClients() } }
        }
    }

    private var services: some View {
        NavigationStack {
            TorlyList {
                if store.business?.services.isEmpty ?? true {
                    EmptyRow(title: L("Услуг пока нет"), symbol: "scissors")
                    Button(L("Добавить услугу"), systemImage: "plus") { showService = true }
                }
                ForEach(store.business?.services ?? []) { service in
                    Button { editingService = service } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(service.name).font(.body.bold()).foregroundStyle(.white)
                                if service.active { TorlyNumber(value: L("%d мин", service.minutes ?? 0), font: .subheadline) }
                                else { Text(L("В архиве")).font(.subheadline).foregroundStyle(TorlyTheme.muted) }
                            }
                            Spacer()
                            if let price = service.priceMinor { TorlyNumber(value: money(price)) }
                            Image(systemName: "chevron.forward").font(.body.weight(.semibold))
                        }
                    }.swipeActions {
                        if service.active {
                            Button(L("В архив"), role: .destructive) {
                                Task {
                                    await store.perform {
                                        _ = try await store.request("/v1/services/\(service.id)", method: "DELETE")
                                        try await store.reload()
                                    }
                                }
                            }
                        }
                    }
                }
            }.navigationTitle(L("Услуги")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showService = true } label: { TorlyActionIcon(name: "plus") }.accessibilityLabel(L("Добавить услугу"))
                    }
                }
                .refreshable { await store.perform { try await store.reload() } }
        }
    }

    private var business: some View {
        NavigationStack {
            TorlyList {
                onlineBooking
                if store.businesses.count > 1 {
                    Picker(L("Бизнес"), selection: $store.selectedBusinessId) {
                        ForEach(store.businesses) { Text($0.name).tag($0.id) }
                    }.onChange(of: store.selectedBusinessId) { _ in
                        staffFilter = ""
                        Task { await store.perform { try await store.reload() } }
                    }
                }
                if let business = store.business {
                    Section {
                        Text(business.name).font(.title2.bold()).foregroundStyle(.white)
                        Label(business.address, systemImage: "mappin.and.ellipse")
                        Label { TorlyNumber(value: business.phone) } icon: { Image(systemName: "phone") }
                        Text(business.timezone).font(.caption).foregroundStyle(TorlyTheme.muted)
                        NavigationLink(L("Данные бизнеса")) { BusinessSetupForm(store: store, editing: true) }
                    }
                    Section(L("Команда и рабочие часы")) {
                        ForEach(business.staff) { staff in
                            NavigationLink { LiveHoursForm(store: store, staff: staff) } label: {
                                Label(staff.name, systemImage: "person.crop.circle").font(.body.bold()).foregroundStyle(.white)
                            }
                        }
                        Button(L("Добавить сотрудника"), systemImage: "person.badge.plus") { showStaff = true }
                    }
                }
                Section {
                    Button(L("Выйти из аккаунта"), role: .destructive) { Task { await store.signOut() } }
                        .disabled(store.busy)
                }
            }.navigationTitle(L("Мой бизнес")).navigationBarTitleDisplayMode(.inline)
        }
    }

    private func money(_ minor: Int) -> String {
        (Double(minor) / 100).formatted(.currency(code: store.business?.currency ?? "ILS").locale(TorlyLanguage.locale))
    }

    @ViewBuilder private var onlineBooking: some View {
        if let business = store.business,
           let url = URL(string: "https://torly.cybermemo.dev/book/" + business.slug.lowercased()) {
            Section(L("Онлайн-запись")) {
                Toggle(L("Принимать записи по ссылке"), isOn: Binding(
                    get: { store.business?.published ?? false },
                    set: { published in
                        Task {
                            await store.perform {
                                _ = try await store.request("/v1/businesses/\(business.id)/publishing",
                                    method: "PUT", body: ["published": published])
                                try await store.reload()
                            }
                        }
                    }
                )).disabled(store.busy)
                if business.published {
                    ShareLink(item: url) {
                        Label(L("Поделиться с клиентом"), systemImage: "square.and.arrow.up")
                    }.buttonStyle(TorlyPrimaryButtonStyle())
                    Link(destination: url) { Label(L("Открыть страницу записи"), systemImage: "safari") }
                    Text(url.absoluteString).font(.caption).foregroundStyle(TorlyTheme.muted)
                        .textSelection(.enabled)
                } else {
                    Text(L("Добавь услуги и рабочие часы, затем включи онлайн-запись."))
                        .font(.caption).foregroundStyle(TorlyTheme.muted)
                }
            }
        }
    }
}

private struct EmptyRow: View {
    @Environment(\.locale) private var appLocale
    let title: String
    let symbol: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light))
                .foregroundStyle(TorlyTheme.accent)
                .frame(width: 60, height: 60)
                .background(TorlyTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TorlyTheme.border, lineWidth: 1))
            Text(title).foregroundStyle(TorlyTheme.muted)
        }.frame(maxWidth: .infinity).padding(.vertical, 26)
    }
}

private struct BusinessSetupForm: View {
    @Environment(\.locale) private var appLocale
    @ObservedObject var store: LiveBusinessStore
    let editing: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var name = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var categoryId = ""
    @State private var staffName = ""
    @State private var timezone = "Asia/Jerusalem"
    @State private var currency = "ILS"
    @State private var country = "IL"
    @State private var locale = "he"
    @State private var open = [true, true, true, true, true, false, false]
    @State private var starts = Array(repeating: "09:00", count: 7)
    @State private var ends = Array(repeating: "17:00", count: 7)
    @State private var requestKey = UUID().uuidString
    @State private var saving = false
    @State private var error: String?
    private let titles = [L("Данные бизнеса"), L("Категория"), L("Рабочие часы")]

    var body: some View {
        TorlyForm {
            Section { LanguagePicker() }
            if !editing {
                Section {
                    ProgressView(value: Double(step + 1), total: 3)
                    Text(L("Шаг %d из 3", step + 1)).font(.caption).foregroundStyle(TorlyTheme.muted)
                }
            }
            if editing || step == 0 {
                Section(L("Бизнес")) {
                    TextField(L("Название бизнеса"), text: $name)
                    TextField(L("Телефон с кодом страны"), text: $phone).keyboardType(.phonePad).font(.body.bold()).foregroundStyle(TorlyTheme.accent)
                    TextField(L("Адрес"), text: $address)
                    if !editing { TextField(L("Твоё имя"), text: $staffName) }
                }
                Section(L("Регион")) {
                    Picker(L("Страна"), selection: $country) {
                        Text(L("Israel")).tag("IL"); Text(L("United States")).tag("US")
                        Text(L("United Kingdom")).tag("GB"); Text(L("Germany")).tag("DE")
                        Text(L("France")).tag("FR"); Text(L("Spain")).tag("ES")
                    }
                    Picker(L("Валюта"), selection: $currency) {
                        ForEach(["ILS", "USD", "EUR", "GBP"], id: \.self) { Text($0).tag($0) }
                    }
                    Picker(L("Часовой пояс"), selection: $timezone) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                    }
                    Picker(L("Язык бизнеса"), selection: $locale) {
                        ForEach(TorlyLanguage.codes, id: \.self) { Text(TorlyLanguage.names[$0] ?? $0).tag($0) }
                    }
                }
            }
            if editing || step == 1 {
                Section(L("Категория")) {
                    if store.categories.isEmpty {
                        Button(L("Загрузить категории")) { Task { await loadCategories() } }
                    }
                    Picker(L("Вид бизнеса"), selection: $categoryId) {
                        Text(L("Выбрать")).tag("")
                        ForEach(store.categories) { Text(TorlyLanguage.current == "he" ? $0.nameHe : L($0.nameEn)).tag($0.id) }
                    }.pickerStyle(.inline)
                }
            }
            if !editing && step == 2 {
                HoursFields(open: $open, starts: $starts, ends: $ends)
            }
            if let error { Section { Text(error).foregroundStyle(TorlyTheme.danger) } }
            Section {
                Button(editing ? L("Сохранить") : step == 2 ? L("Создать бизнес") : L("Продолжить")) {
                    if !editing && step < 2 { step += 1 }
                    else { Task { await save() } }
                }.disabled(saving || !valid)
                if saving { ProgressView() }
                if !editing && step > 0 { Button(L("Назад")) { step -= 1 }.disabled(saving) }
            }
        }
        .disabled(saving)
        .navigationTitle(editing ? L("Данные бизнеса") : titles[step])
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if editing, let b = store.business {
                name = b.name; phone = b.phone; address = b.address; categoryId = b.categoryId
                timezone = b.timezone; currency = b.currency; country = b.country; locale = b.locale
            }
            await loadCategories()
        }
    }

    private var valid: Bool {
        let details = !name.trimmingCharacters(in: .whitespaces).isEmpty && !address.trimmingCharacters(in: .whitespaces).isEmpty
            && phone.range(of: #"^\+[1-9]\d{7,14}$"#, options: .regularExpression) != nil
            && (editing || !staffName.trimmingCharacters(in: .whitespaces).isEmpty)
        if editing { return details && !categoryId.isEmpty }
        if step == 0 { return details }
        if step == 1 { return !categoryId.isEmpty }
        return validHours(open: open, starts: starts, ends: ends)
    }

    private func loadCategories() async {
        do { try await store.loadCategories() } catch { self.error = localizedError(error) }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            var payload: [String: Any] = ["name":name,"phone":phone,"address":address,"categoryId":categoryId,
                                         "timezone":timezone,"currency":currency,"country":country,"locale":locale]
            if !editing {
                payload["staffName"] = staffName
                payload["hours"] = hoursPayload(open: open, starts: starts, ends: ends)
                payload["requestKey"] = requestKey
            }
            _ = try await store.request(editing ? "/v1/businesses/\(store.selectedBusinessId)" : "/v1/businesses",
                                        method: editing ? "PUT" : "POST", body: payload)
            try await store.reload()
            if editing { dismiss() }
        } catch { self.error = localizedError(error) }
    }
}

private var dayNames: [String] { [L("Воскресенье"), L("Понедельник"), L("Вторник"), L("Среда"), L("Четверг"), L("Пятница"), L("Суббота")] }

private func validHours(open: [Bool], starts: [String], ends: [String]) -> Bool {
    (0..<7).filter { open[$0] }.allSatisfy {
        starts[$0].range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil &&
        ends[$0].range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil &&
        starts[$0] < ends[$0]
    }
}

private func hoursPayload(open: [Bool], starts: [String], ends: [String]) -> [[String: Any]] {
    (0..<7).filter { open[$0] }.map { ["weekday":$0,"opensAt":starts[$0],"closesAt":ends[$0]] }
}

private struct HoursFields: View {
    @Environment(\.locale) private var appLocale
    @Binding var open: [Bool]
    @Binding var starts: [String]
    @Binding var ends: [String]
    var body: some View {
        ForEach(0..<7) { day in
            Section {
                Toggle(dayNames[day], isOn: $open[day])
                if open[day] {
                    HStack {
                        TextField("09:00", text: $starts[day]).keyboardType(.numbersAndPunctuation).font(.body.bold()).foregroundStyle(TorlyTheme.accent)
                        Text("–")
                        TextField("17:00", text: $ends[day]).keyboardType(.numbersAndPunctuation).font(.body.bold()).foregroundStyle(TorlyTheme.accent)
                    }
                }
            }
        }
    }
}

private struct StaffCreationForm: View {
    @Environment(\.locale) private var appLocale
    @ObservedObject var store: LiveBusinessStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var open = [true, true, true, true, true, false, false]
    @State private var starts = Array(repeating: "09:00", count: 7)
    @State private var ends = Array(repeating: "17:00", count: 7)
    @State private var requestKey = UUID().uuidString
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            TorlyForm {
                TextField(L("Имя сотрудника"), text: $name)
                HoursFields(open: $open, starts: $starts, ends: $ends)
                if let error { Text(error).foregroundStyle(TorlyTheme.danger) }
            }.disabled(saving)
                .navigationTitle(L("Новый сотрудник"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Добавить")) {
                            Task {
                                saving = true
                                defer { saving = false }
                                do {
                                    _ = try await store.request("/v1/staff", method: "POST", body: [
                                        "businessId":store.selectedBusinessId,"name":name,"requestKey":requestKey,
                                        "hours":hoursPayload(open: open, starts: starts, ends: ends)])
                                    try await store.reload()
                                    dismiss()
                                } catch { self.error = localizedError(error) }
                            }
                        }.disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty || !validHours(open: open, starts: starts, ends: ends))
                    }
                }
        }
    }
}

private struct ClientDetailForm: View {
    @Environment(\.locale) private var appLocale
    @ObservedObject var store: LiveBusinessStore
    let client: RemoteClient
    @State private var note = ""
    @State private var message: String?
    @State private var saving = false

    var body: some View {
        TorlyForm {
            Section {
                if let url = URL(string: "tel:\(client.phone)") { Link(destination: url) { TorlyNumber(value: client.phone) } }
                TorlyValueRow(title: L("Завершённых визитов"), value: "\(client.visits)")
                TorlyValueRow(title: L("Неявки"), value: "\(client.noShowCount)")
            }
            Section(L("Заметка")) { TextEditor(text: $note).frame(minHeight: 140) }
            if let message { Text(message) }
            Button(L("Сохранить")) {
                Task {
                    saving = true
                    defer { saving = false }
                    do {
                        _ = try await store.request("/v1/clients/\(client.id)", method: "PUT", body: ["note":note])
                        try await store.loadClients()
                        message = L("Сохранено")
                    } catch { message = localizedError(error) }
                }
            }.disabled(saving || note.count > 2000)
        }.navigationTitle(client.name).onAppear { note = client.note }
    }
}

private struct BlockForm: View {
    @Environment(\.locale) private var appLocale
    @ObservedObject var store: LiveBusinessStore
    @Environment(\.dismiss) private var dismiss
    @State private var staffId = ""
    @State private var kind = "break"
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var requestKey = UUID().uuidString
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            TorlyForm {
                Picker(L("Тип"), selection: $kind) {
                    Text(L("Перерыв")).tag("break"); Text(L("Отпуск")).tag("time_off")
                }.pickerStyle(.segmented)
                Picker(L("Сотрудник"), selection: $staffId) {
                    Text(L("Выбрать")).tag("")
                    ForEach(store.business?.staff ?? []) { Text($0.name).tag($0.id) }
                }
                DatePicker(L("Начало"), selection: $start)
                DatePicker(L("Окончание"), selection: $end, in: start...)
                if let error { Text(error).foregroundStyle(TorlyTheme.danger) }
            }.environment(\.timeZone, store.businessCalendar.timeZone)
                .disabled(saving)
                .navigationTitle(L("Недоступное время"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Сохранить")) {
                            Task {
                                saving = true
                                defer { saving = false }
                                do {
                                    _ = try await store.request("/v1/blocks", method: "POST", body: [
                                        "staffId":staffId,"kind":kind,"startsAt":LiveBusinessStore.iso(start),
                                        "endsAt":LiveBusinessStore.iso(end),"requestKey":requestKey])
                                    try await store.reload()
                                    dismiss()
                                } catch { self.error = localizedError(error) }
                            }
                        }.disabled(saving || staffId.isEmpty || end <= start)
                    }
                }.onAppear { staffId = store.business?.staff.first?.id ?? "" }
        }
    }
}

private struct MoveBookingForm: View {
    @Environment(\.locale) private var appLocale
    @ObservedObject var store: LiveBusinessStore
    let booking: RemoteBooking
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date().addingTimeInterval(3600)
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            TorlyForm {
                Text(booking.clientName ?? "")
                DatePicker(L("Новые дата и время"), selection: $start, in: Date()...)
                if let error { Text(error).foregroundStyle(TorlyTheme.danger) }
            }.environment(\.timeZone, store.businessCalendar.timeZone)
                .disabled(saving)
                .navigationTitle(L("Перенести запись"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("Отмена")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Перенести")) {
                            Task {
                                saving = true
                                defer { saving = false }
                                do {
                                    _ = try await store.request("/v1/bookings/\(booking.id)", method: "PATCH",
                                                                body: ["revision":booking.revision,"startsAt":LiveBusinessStore.iso(start)])
                                    store.day = start
                                    try await store.reload()
                                    dismiss()
                                } catch { self.error = localizedError(error) }
                            }
                        }.disabled(saving)
                    }
                }
        }
    }
}
