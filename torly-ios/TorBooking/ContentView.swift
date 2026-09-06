import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var isSignedIn = false
    @State private var selectedRole: AppRole?
    @State private var accountHasBothRoles = true
    @State private var businessOnboardingComplete = false
    @State private var businessProfile = BusinessProfileDraft()

    var body: some View {
        Group {
            if isSignedIn, selectedRole == .business, !businessOnboardingComplete {
                BusinessOnboardingFlow(profile: $businessProfile) {
                    businessOnboardingComplete = true
                }
            } else if isSignedIn, let role = selectedRole {
                AppShell(
                    selectedRole: $selectedRole,
                    businessProfile: $businessProfile,
                    accountHasBothRoles: accountHasBothRoles,
                    role: role
                )
            } else if isSignedIn {
                RoleSetupScreen(selectedRole: $selectedRole, accountHasBothRoles: $accountHasBothRoles)
            } else {
                LoginScreen {
                    isSignedIn = true
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.blue)
    }
}

struct LoginScreen: View {
    let onSignIn: () -> Void
    @State private var showLiveBusiness = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()

                VStack(spacing: 14) {
                    Image(uiImage: UIImage(contentsOfFile: Bundle.main.path(forResource: "Torly-AppIcon-1024", ofType: "png") ?? "") ?? UIImage())
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .blue.opacity(0.22), radius: 20, y: 12)

                    Text("Torly")
                        .font(.largeTitle.bold())
                    Text("Запись к мастерам за минуту. Бизнес настраивает ссылку один раз, клиенты сами выбирают день и час.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    SignInButton(title: "Войти в бизнес", systemImage: "person.crop.circle") { showLiveBusiness = true }
                    SignInButton(title: "Посмотреть демо", systemImage: "play.circle", action: onSignIn)
                }

                Text("Один аккаунт может быть и бизнесом, и клиентом.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(24)
            .background(Color(.systemGroupedBackground))
            .fullScreenCover(isPresented: $showLiveBusiness) { LiveBusinessView() }
        }
    }
}

struct RoleSetupScreen: View {
    @Binding var selectedRole: AppRole?
    @Binding var accountHasBothRoles: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Как начать?")
                    .font(.largeTitle.bold())
                Text("В Torly роль не привязана навсегда: владелец салона может вести свой календарь и сам записываться к другим мастерам.")
                    .foregroundStyle(.secondary)

                Toggle("Я и бизнес, и клиент", isOn: $accountHasBothRoles)
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                RoleChoiceCard(
                    icon: "briefcase",
                    title: "У меня бизнес",
                    text: "Настроить услуги, часы, ссылку для Instagram и принимать записи."
                ) {
                    selectedRole = .business
                }

                RoleChoiceCard(
                    icon: "magnifyingglass",
                    title: "Я клиент",
                    text: "Найти мастера, открыть месяц, выбрать день и свободный час."
                ) {
                    selectedRole = .client
                }

                Spacer()
            }
            .padding()
            .background(Color(.systemGroupedBackground))
        }
    }
}

struct BusinessOnboardingFlow: View {
    @Binding var profile: BusinessProfileDraft
    let onFinish: () -> Void
    @State private var step = 0
    @State private var selectedPhoto: PhotosPickerItem?

    private let titles = [
        "Профиль бизнеса",
        "Тип бизнеса",
        "Дни записи",
        "Услуги и цены",
        "Фото страницы",
        "Готовая ссылка"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Шаг \(step + 1) из \(titles.count)")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                    Text(titles[step])
                        .font(.largeTitle.bold())
                    ProgressView(value: Double(step + 1), total: Double(titles.count))
                        .tint(.blue)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))

                ScrollView {
                    stepContent
                        .padding()
                }
                .background(Color(.systemGroupedBackground))

                HStack(spacing: 12) {
                    Button {
                        step = max(0, step - 1)
                    } label: {
                        Label("Назад", systemImage: "chevron.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(step == 0)

                    Button {
                        if step == titles.count - 1 {
                            onFinish()
                        } else {
                            step += 1
                        }
                    } label: {
                        Label(step == titles.count - 1 ? "Открыть кабинет" : "Дальше", systemImage: step == titles.count - 1 ? "checkmark.circle" : "chevron.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                .padding()
                .background(Color(.systemBackground))
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            BusinessIdentityStep(profile: $profile)
        case 1:
            BusinessCategoryStep(profile: $profile)
        case 2:
            BusinessDaysStep(profile: $profile)
        case 3:
            BusinessServicesStep(profile: $profile)
        case 4:
            BusinessPhotoStep(profile: $profile, selectedPhoto: $selectedPhoto)
        default:
            BusinessLaunchStep(profile: profile)
        }
    }
}

struct BusinessIdentityStep: View {
    @Binding var profile: BusinessProfileDraft
    private let previousSources = ["WhatsApp", "Instagram DM", "Google Calendar", "Блокнот", "Не было записи"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Название бизнеса", text: $profile.name)
                    .textContentType(.organizationName)
                TextField("Телефон бизнеса", text: $profile.phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                TextField("Адрес бизнеса", text: $profile.address)
                    .textContentType(.fullStreetAddress)
            }
            .textFieldStyle(.roundedBorder)
            .card()

            VStack(alignment: .leading, spacing: 12) {
                Text("Где была запись до Torly?")
                    .font(.headline)

                Picker("Источник", selection: $profile.previousBookingSource) {
                    ForEach(previousSources, id: \.self) { source in
                        Text(source).tag(source)
                    }
                }
                .pickerStyle(.inline)

                if profile.previousBookingSource == "Google Calendar" {
                    Toggle("Подготовить импорт из Google Calendar", isOn: $profile.wantsGoogleCalendarImport)
                    Label("Позже подключим Google и подтянем старые записи в календарь Torly.", systemImage: "calendar.badge.plus")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }
}

struct BusinessCategoryStep: View {
    @Binding var profile: BusinessProfileDraft
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Выбери направление. Список можно расширять: нам важно сразу покрыть маленькие бизнесы, которые живут в WhatsApp.")
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Demo.businessCategories) { category in
                    Button {
                        profile.category = category
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: category.icon)
                                .font(.title2)
                                .foregroundStyle(profile.category == category ? .white : .blue)
                                .frame(width: 42, height: 42)
                                .background(profile.category == category ? Color.blue : Color.blue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text(category.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(category.examples)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                        .padding()
                        .background(Color(.systemBackground))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(profile.category == category ? Color.blue : Color.clear, lineWidth: 2)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct BusinessDaysStep: View {
    @Binding var profile: BusinessProfileDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Для Израиля суббота заранее выключена. Владелец может включить её вручную.", systemImage: "moon.stars")
                .foregroundStyle(.secondary)
                .card()

            VStack(spacing: 8) {
                ForEach($profile.workDays) { $day in
                    HStack {
                        Toggle(day.title, isOn: $day.isOpen)
                        TextField("Часы", text: $day.hours)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(day.isOpen ? .primary : .secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
            .card()
        }
    }
}

struct BusinessServicesStep: View {
    @Binding var profile: BusinessProfileDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach($profile.services) { $service in
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Название услуги", text: $service.name)
                        .textFieldStyle(.roundedBorder)
                    Stepper("\(currencySymbol(profile.currencyId))\(service.price)", value: $service.price, in: 10...900, step: 5)
                    Stepper("\(service.minutes) мин", value: $service.minutes, in: 10...240, step: 5)
                }
                .card()
            }

            Button {
                profile.services.append(Service(name: "Новая услуга", price: 100, minutes: 45))
            } label: {
                Label("Добавить услугу", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
    }
}

struct BusinessPhotoStep: View {
    @Binding var profile: BusinessProfileDraft
    @Binding var selectedPhoto: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: profile.hasCustomBackground ? [.blue.opacity(0.75), .indigo.opacity(0.75)] : [Color(.secondarySystemGroupedBackground), .blue.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 220)

                VStack(alignment: .leading, spacing: 6) {
                    Image("Torly-AppIcon-1024")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text(profile.name)
                        .font(.title2.bold())
                    Text(profile.category.title)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(profile.hasCustomBackground ? "Фото выбрано" : "Добавить свою картинку", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .onChange(of: selectedPhoto) { newValue in
                profile.hasCustomBackground = newValue != nil
                profile.backgroundLabel = newValue == nil ? "Чистый светлый фон" : "Свое фото бизнеса"
            }

            Text("Эта картинка станет фоном публичной страницы записи и карточки бизнеса.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}

struct BusinessLaunchStep: View {
    let profile: BusinessProfileDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Профиль зарегистрирован. Вот как бизнес будет выглядеть для клиента.")
                .foregroundStyle(.secondary)

            BusinessPublicProfileCard(profile: profile)
        }
    }
}

struct AppShell: View {
    @Binding var selectedRole: AppRole?
    @Binding var businessProfile: BusinessProfileDraft
    let accountHasBothRoles: Bool
    let role: AppRole

    var body: some View {
        VStack(spacing: 0) {
            if accountHasBothRoles {
                Picker("Роль", selection: Binding(
                    get: { selectedRole ?? role },
                    set: { selectedRole = $0 }
                )) {
                    ForEach(AppRole.allCases) { role in
                        Text(role.rawValue).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
            }

            if role == .business {
                BusinessTabs(profile: $businessProfile)
            } else {
                ClientTabs()
            }
        }
    }
}

struct BusinessTabs: View {
    @Binding var profile: BusinessProfileDraft

    var body: some View {
        TabView {
            BusinessDashboardScreen(profile: profile)
                .tabItem { Label("Главная", systemImage: "house") }

            BusinessCalendarScreen(profile: profile)
                .tabItem { Label("Календарь", systemImage: "calendar") }

            BusinessSetupScreen(profile: $profile)
                .tabItem { Label("Настройки", systemImage: "slider.horizontal.3") }

            ClientsScreen()
                .tabItem { Label("Клиенты", systemImage: "person.2") }

            AnalyticsScreen()
                .tabItem { Label("Отчеты", systemImage: "chart.bar") }
        }
        .tint(.blue)
    }
}

struct ClientTabs: View {
    var body: some View {
        TabView {
            ClientExploreScreen()
                .tabItem { Label("Найти", systemImage: "magnifyingglass") }

            MyAppointmentsScreen()
                .tabItem { Label("Мои записи", systemImage: "calendar.badge.clock") }

            ClientProfileScreen()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
        }
        .tint(.blue)
    }
}

struct BusinessDashboardScreen: View {
    let profile: BusinessProfileDraft

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Torly")
                            .font(.largeTitle.bold())
                        Text("Твоя ссылка уже готова. Клиент открывает её из Instagram или WhatsApp, выбирает услугу, день и свободный час.")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            PillLabel(text: "EN/HE")
                            PillLabel(text: profile.timezoneId)
                            PillLabel(text: "\(currencySymbol(profile.currencyId))39 после trial")
                        }
                        Label(profile.publicBookingUrl.replacingOccurrences(of: "https://", with: ""), systemImage: "link")
                            .font(.system(.callout, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .card()

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        Metric(title: "Записи сегодня", value: "12", icon: "calendar")
                        Metric(title: "Выручка", value: "₪890", icon: "chart.bar")
                        Metric(title: "Клиенты", value: "86", icon: "person.2")
                        Metric(title: "WA utility", value: "412/500", icon: "message")
                    }

                    WhatsAppCostCard()

                    Text("Публичная страница")
                        .font(.title3.bold())

                    BusinessPublicProfileCard(profile: profile)

                    Text("Команда и расписания")
                        .font(.title3.bold())

                    StaffScheduleOverview()

                    Text("Быстрая настройка")
                        .font(.title3.bold())

                    SetupChecklist()
                        .card()

                    Text("Ближайшие записи")
                        .font(.title3.bold())

                    ForEach(Demo.bookings.prefix(3)) { booking in
                        BookingRow(booking: booking)
                            .card()
                    }

                    Text("Лист ожидания")
                        .font(.title3.bold())

                    WaitlistPreview()

                    Text("Каркас функций")
                        .font(.title3.bold())

                    ProductFeatureGrid()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Кабинет")
        }
    }
}

struct BusinessCalendarScreen: View {
    let profile: BusinessProfileDraft
    @State private var selectedDay = Demo.today
    @State private var isMenuOpen = false

    var body: some View {
        ZStack(alignment: .leading) {
            DarkCalendarWorkspace(
                profile: profile,
                selectedDay: $selectedDay,
                isMenuOpen: $isMenuOpen
            )

            if isMenuOpen {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                            isMenuOpen = false
                        }
                    }

                BusinessSideMenu(isOpen: $isMenuOpen)
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: isMenuOpen)
    }
}

struct DarkCalendarWorkspace: View {
    let profile: BusinessProfileDraft
    @Binding var selectedDay: Int
    @Binding var isMenuOpen: Bool

    private let weekDays = [
        ("Sun", 30),
        ("Mon", 31),
        ("Tue", 1),
        ("Wed", 2),
        ("Thu", 3),
        ("Fri", 4),
        ("Sat", 5)
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(red: 0.11, green: 0.12, blue: 0.15)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                DarkCalendarHeader(
                    profile: profile,
                    selectedDay: $selectedDay,
                    isMenuOpen: $isMenuOpen,
                    weekDays: weekDays
                )

                DarkCalendarTimeline(profile: profile, selectedDay: selectedDay)
            }

            DarkActionRail()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 18)
                .padding(.bottom, 34)

            VStack(alignment: .trailing, spacing: 14) {
                CoachBubble(text: "כאן קובעים תורים והפסקות", alignment: .trailing)
                    .padding(.trailing, 4)

                Button {
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 46, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 82, height: 82)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(color: .blue.opacity(0.35), radius: 18, y: 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 22)
            .padding(.bottom, 34)
        }
        .preferredColorScheme(.dark)
    }
}

struct DarkCalendarHeader: View {
    let profile: BusinessProfileDraft
    @Binding var selectedDay: Int
    @Binding var isMenuOpen: Bool
    let weekDays: [(String, Int)]

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        isMenuOpen = true
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottomLeading) {
                    if !isMenuOpen {
                        CoachBubble(text: "זה התפריט", alignment: .leading)
                            .offset(x: -2, y: 58)
                    }
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("Torly")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("September")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.35))
                }

                Spacer()

                HStack(spacing: 18) {
                    Circle()
                        .fill(.white)
                        .frame(width: 54, height: 54)
                    Image(systemName: "bell")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white.opacity(0.86))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            HStack {
                ForEach(weekDays, id: \.1) { item in
                    Button {
                        selectedDay = item.1
                    } label: {
                        VStack(spacing: 7) {
                            Text(item.0)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.6))
                            Text(String(format: "%02d", item.1))
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 46, height: 46)
                                .background(selectedDay == item.1 ? Color.blue : Color.clear)
                                .clipShape(Circle())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)

            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 56)

                Text(profile.name)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(Color(red: 0.12, green: 0.13, blue: 0.16))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

struct DarkCalendarTimeline: View {
    let profile: BusinessProfileDraft
    let selectedDay: Int
    private let hours = ["12:00", "13:00", "14:00", "15:00", "16:00", "17:00"]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color(red: 0.10, green: 0.11, blue: 0.14)

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(hours, id: \.self) { hour in
                            Text(hour)
                                .font(.system(size: 19, weight: .regular))
                                .foregroundStyle(.white.opacity(0.38))
                                .frame(width: 78, height: 116, alignment: .topTrailing)
                                .padding(.trailing, 10)
                                .padding(.top, 24)
                        }
                    }
                    .background(Color(red: 0.12, green: 0.13, blue: 0.16))

                    ZStack(alignment: .topLeading) {
                        DiagonalHatch()
                            .opacity(0.85)

                        VStack(spacing: 0) {
                            ForEach(hours, id: \.self) { _ in
                                Rectangle()
                                    .fill(.white.opacity(0.07))
                                    .frame(height: 1)
                                    .frame(maxWidth: .infinity)

                                Color.clear.frame(height: 115)
                            }
                        }

                        DarkBookingBlock(
                            time: "13:15",
                            title: "Алекс Розен",
                            service: "Борода + контур",
                            price: "₪49"
                        )
                        .frame(width: max(220, proxy.size.width - 128), height: 74)
                        .offset(x: 22, y: 145)

                        CoachBubble(text: "כאן משתפים את העמוד שלך עם לקוחות", alignment: .leading)
                            .offset(x: 92, y: 372)

                        CoachBubble(text: "היי, אני אלה. אעזור לך להכיר את המערכת", alignment: .leading)
                            .offset(x: -42, y: 248)
                    }
                }
            }
        }
    }
}

struct DiagonalHatch: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 14
            var darkPath = Path()
            var lightPath = Path()

            for x in stride(from: -size.height, through: size.width + size.height, by: spacing) {
                darkPath.move(to: CGPoint(x: x, y: 0))
                darkPath.addLine(to: CGPoint(x: x + size.height, y: size.height))

                lightPath.move(to: CGPoint(x: x + 4, y: 0))
                lightPath.addLine(to: CGPoint(x: x + size.height + 4, y: size.height))
            }

            context.stroke(darkPath, with: .color(.black.opacity(0.28)), lineWidth: 5)
            context.stroke(lightPath, with: .color(.white.opacity(0.035)), lineWidth: 2)
        }
        .background(Color(red: 0.13, green: 0.15, blue: 0.19))
    }
}

struct DarkBookingBlock: View {
    let time: String
    let title: String
    let service: String
    let price: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(time)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(service)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Text(price)
                .font(.headline.bold())
                .foregroundStyle(.white)
        }
        .padding()
        .background(Color(red: 0.15, green: 0.20, blue: 0.31).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
    }
}

struct DarkActionRail: View {
    private let actions = [
        "person.crop.circle.fill",
        "square.and.arrow.up",
        "list.bullet",
        "bubble.left"
    ]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(actions, id: \.self) { icon in
                Button {
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: icon == "person.crop.circle.fill" ? 42 : 31, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 76, height: 76)
                        .background(Color(red: 0.13, green: 0.14, blue: 0.17))
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CoachBubble: View {
    let text: String
    let alignment: HorizontalAlignment

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Image(systemName: "xmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.trailing, 12)
        }
        .background(Color(red: 0.14, green: 0.14, blue: 0.14).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 12, y: 8)
    }
}

struct BusinessSideMenu: View {
    @Binding var isOpen: Bool
    @State private var darkTheme = true

    private let menuItems = [
        ("Онлайн-профиль", "arrowshape.turn.up.right"),
        ("Календарь", "calendar"),
        ("Панель управления", "chart.pie.fill"),
        ("Подписка ₪39", "creditcard.fill"),
        ("Клиенты", "person.3.fill"),
        ("Услуги", "clock.fill"),
        ("Команда", "person.text.rectangle.fill"),
        ("Перерывы и отпуска", "pause.circle.fill"),
        ("Лист ожидания", "bell.badge.fill"),
        ("Отзывы и анкеты", "star.bubble.fill"),
        ("Сообщения", "envelope.fill"),
        ("Настройки", "gearshape.fill")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image("Torly-AppIcon-1024")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Torly")
                        .font(.title2.bold())
                    Text("Business")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        isOpen = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 34)
            .padding(.bottom, 24)

            VStack(spacing: 8) {
                ForEach(menuItems.indices, id: \.self) { index in
                    SideMenuRow(
                        title: menuItems[index].0,
                        icon: menuItems[index].1,
                        isSelected: index == 1
                    )
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            HStack(spacing: 16) {
                Image(systemName: "moon.fill")
                    .foregroundStyle(.white.opacity(0.8))
                Text("Тёмная тема")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $darkTheme)
                    .labelsHidden()
                    .tint(.blue)
            }
            .padding(22)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
            }
        }
        .frame(width: 316)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.12, green: 0.13, blue: 0.16))
        .foregroundStyle(.white)
        .ignoresSafeArea()
    }
}

struct SideMenuRow: View {
    let title: String
    let icon: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(isSelected ? Color(red: 0.55, green: 0.68, blue: 1.0) : .white.opacity(0.88))

            Text(title)
                .font(.system(size: 19, weight: isSelected ? .bold : .regular))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(isSelected ? Color(red: 0.12, green: 0.18, blue: 0.31) : Color.clear)
        .clipShape(Capsule())
    }
}

struct BusinessSetupScreen: View {
    @Binding var profile: BusinessProfileDraft
    @State private var city = "Тель-Авив"
    @State private var autoReminders = true
    @State private var reminderHours = 24
    @State private var waitlist = true
    @State private var stripeReady = true
    @State private var noShowGuard = true
    @State private var reviewRequests = true
    @State private var intakeForms = true
    @State private var googleCalendar = true
    @State private var appleCalendar = true
    @State private var pushNotifications = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Профиль бизнеса") {
                    TextField("Название", text: $profile.name)
                    TextField("Телефон", text: $profile.phone)
                    TextField("Адрес", text: $profile.address)
                    TextField("Город", text: $city)
                    Label("Публичная ссылка: \(profile.publicBookingUrl.replacingOccurrences(of: "https://", with: ""))", systemImage: "link")
                }

                Section("Международный запуск") {
                    Picker("Страна", selection: $profile.countryId) {
                        ForEach(Demo.countries) { country in
                            Text("\(country.name) \(country.phonePrefix)").tag(country.id)
                        }
                    }

                    Picker("Язык страницы", selection: $profile.localeId) {
                        ForEach(Demo.locales) { locale in
                            Text("\(locale.name) · \(locale.direction)").tag(locale.id)
                        }
                    }

                    Picker("Валюта", selection: $profile.currencyId) {
                        ForEach(Demo.currencies) { currency in
                            Text("\(currency.symbol) \(currency.id)").tag(currency.id)
                        }
                    }

                    Picker("Часовой пояс", selection: $profile.timezoneId) {
                        ForEach(Demo.timezones) { timezone in
                            Text("\(timezone.city) · \(timezone.id)").tag(timezone.id)
                        }
                    }

                    Toggle("Stripe-ready подписка", isOn: $stripeReady)
                }

                Section("Сотрудники") {
                    ForEach(Demo.staff) { member in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(member.name)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(member.load)
                                    .foregroundStyle(.blue)
                            }
                            Text("\(member.role) · \(member.hours)")
                                .foregroundStyle(.secondary)
                            Text("Перерыв \(member.breakTime) · отпуск \(member.vacation)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                    } label: {
                        Label("Добавить сотрудника", systemImage: "person.badge.plus")
                    }
                }

                Section("Услуги и цены") {
                    ForEach($profile.services) { $service in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Название услуги", text: $service.name)
                            HStack {
                                Stepper("\(currencySymbol(profile.currencyId))\(service.price)", value: $service.price, in: 20...500, step: 5)
                                Spacer()
                                Stepper("\(service.minutes) мин", value: $service.minutes, in: 15...180, step: 5)
                            }
                        }
                    }

                    Button {
                        profile.services.append(Service(name: "Новая услуга", price: 100, minutes: 45))
                    } label: {
                        Label("Добавить услугу", systemImage: "plus")
                    }
                }

                Section("Рабочие часы") {
                    ForEach($profile.workDays) { $day in
                        HStack {
                            Toggle(day.title, isOn: $day.isOpen)
                            Spacer()
                            TextField("Часы", text: $day.hours)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(day.isOpen ? .primary : .secondary)
                        }
                    }
                }

                Section("Напоминания") {
                    Toggle("WhatsApp utility подтверждение", isOn: $autoReminders)
                    Stepper("За \(reminderHours) часов до записи", value: $reminderHours, in: 2...72, step: 2)
                    Toggle("Лист ожидания при отмене", isOn: $waitlist)
                    Toggle("Push-уведомления владельцу", isOn: $pushNotifications)
                    Label("Шаблоны WhatsApp: English + Hebrew", systemImage: "message.badge")
                }

                Section("WhatsApp пакеты") {
                    ForEach(Demo.whatsappPackages) { pack in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(pack.name)
                                    .fontWeight(.semibold)
                                Text("\(pack.messages) сообщений · себестоимость \(pack.cost)")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(pack.price).bold()
                        }
                    }
                }

                Section("Правила записи") {
                    Toggle("No-show защита", isOn: $noShowGuard)
                    Toggle("Отзывы после визита", isOn: $reviewRequests)
                    Toggle("Формы и анкеты перед записью", isOn: $intakeForms)
                    Label("Клиент может подтвердить, отменить или перенести запись.", systemImage: "arrow.triangle.2.circlepath")
                }

                Section("Синхронизация календарей") {
                    Toggle("Google Calendar", isOn: $googleCalendar)
                    Toggle("Apple Calendar", isOn: $appleCalendar)
                    Label("Свободные слоты считаются с учетом перерывов, отпусков и расписания сотрудника.", systemImage: "calendar.badge.checkmark")
                }

                Section("Не в первом этапе") {
                    Label("Налоговые счета / квитанции", systemImage: "xmark.circle")
                    Label("Бухгалтерия", systemImage: "xmark.circle")
                    Label("Фискальный складской учет", systemImage: "xmark.circle")
                }
            }
            .navigationTitle("Настройки")
        }
    }
}

struct ClientsScreen: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Клиентские карточки") {
                    ForEach(Demo.clients) { client in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(client.name)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("₪\(client.totalSpent)")
                                    .fontWeight(.bold)
                            }
                            Text("\(client.phone) · \(client.visits) визитов")
                                .foregroundStyle(.secondary)
                            Text(client.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Label("\(client.noShowCount) no-show", systemImage: client.noShowCount > 0 ? "shield.lefthalf.filled.badge.checkmark" : "checkmark.shield")
                                    .font(.caption.bold())
                                    .foregroundStyle(client.noShowCount > 0 ? .orange : .blue)
                                Spacer()
                                Label("История записей", systemImage: "clock.arrow.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section("Защита от no-show") {
                    Label("Пометка риска после 2 пропусков", systemImage: "exclamationmark.shield")
                    Label("Дополнительное подтверждение в WhatsApp", systemImage: "message.badge")
                    Label("Позже: депозит для риск-клиентов", systemImage: "creditcard")
                }
            }
            .navigationTitle("Клиенты")
            .toolbar {
                Button {
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
    }
}

struct AnalyticsScreen: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Неделя") {
                    AnalyticsRow(title: "Записей", value: "48", trend: "+18%")
                    AnalyticsRow(title: "Отмен", value: "3", trend: "-2")
                    AnalyticsRow(title: "Средний чек", value: "₪96", trend: "+₪8")
                    AnalyticsRow(title: "Повторные клиенты", value: "64%", trend: "+7%")
                }

                Section("Отчёты") {
                    Label("Выручка по сотрудникам", systemImage: "person.2.wave.2")
                    Label("Загрузка календаря", systemImage: "calendar")
                    Label("Отзывы и рейтинг", systemImage: "star")
                    Label("Эффект напоминаний WhatsApp", systemImage: "message")
                }

                Section("Онлайн-запись") {
                    AnalyticsRow(title: "Записей 24/7", value: "31", trend: "+12")
                    AnalyticsRow(title: "Из Instagram/WhatsApp", value: "68%", trend: "+9%")
                    AnalyticsRow(title: "Из листа ожидания", value: "5", trend: "+3")
                }

                Section("Тариф") {
                    ForEach(Demo.plans) { plan in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(plan.name).fontWeight(.semibold)
                                Text(plan.note).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(plan.price).bold()
                        }
                    }
                }
            }
            .navigationTitle("Отчеты")
        }
    }
}

struct ClientExploreScreen: View {
    @State private var selectedBusiness = Demo.businesses[0]
    @State private var selectedService = Demo.businesses[0].services[0]
    @State private var selectedDay = Demo.today
    @State private var selectedSlot = "10:15"
    @State private var didBook = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Выбери мастера")
                        .font(.title3.bold())

                    ForEach(Demo.businesses) { business in
                        Button {
                            selectedBusiness = business
                            selectedService = business.services[0]
                            didBook = false
                        } label: {
                            BusinessListingRow(business: business, isSelected: selectedBusiness == business)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(selectedBusiness.name)
                            .font(.title2.bold())
                        Text("\(selectedBusiness.category) · \(selectedBusiness.city) · ★ \(selectedBusiness.rating)")
                            .foregroundStyle(.secondary)

                        Picker("Услуга", selection: $selectedService) {
                            ForEach(selectedBusiness.services) { service in
                                Text("\(service.name), ₪\(service.price)").tag(service)
                            }
                        }

                        MonthCalendar(selectedDay: $selectedDay, markedDays: [Demo.today, min(Demo.today + 1, 28), min(Demo.today + 3, 28)])

                        Text("Свободное время")
                            .font(.headline)

                        TimeSlotGrid(selectedSlot: $selectedSlot, slots: Demo.slots, disabled: ["09:00", "12:30"])

                        Button {
                            didBook = true
                        } label: {
                            Label("Записаться на \(selectedSlot)", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                    .card()

                    if didBook {
                        Label("Запись создана: день \(selectedDay), \(selectedSlot). Подтверждение уйдет в WhatsApp.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Запись")
        }
    }
}

struct MyAppointmentsScreen: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Ближайшие") {
                    AppointmentRow(business: "Barber Dizengoff", service: "Мужская стрижка", date: "Сегодня, 15:00", status: "Подтверждено")
                    AppointmentRow(business: "Nails by Maya", service: "Маникюр гель", date: "Завтра, 10:30", status: "Ждет")
                }

                Section("Действия") {
                    Label("Перенести запись", systemImage: "calendar.badge.clock")
                    Label("Отменить запись", systemImage: "xmark.circle")
                    Label("Написать бизнесу", systemImage: "message")
                }
            }
            .navigationTitle("Мои записи")
        }
    }
}

struct ClientProfileScreen: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Профиль") {
                    Label("Александр", systemImage: "person")
                    Label("+972 52 000 0000", systemImage: "phone")
                }

                Section("Аккаунт") {
                    Label("Избранные мастера", systemImage: "star")
                    Label("История записей", systemImage: "clock.arrow.circlepath")
                    Label("Добавить свой бизнес", systemImage: "briefcase")
                }
            }
            .navigationTitle("Профиль")
        }
    }
}

struct MonthCalendar: View {
    @Binding var selectedDay: Int
    let markedDays: Set<Int>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdayTitles = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(monthTitle)
                    .font(.headline)
                Spacer()
                Button {
                } label: {
                    Image(systemName: "chevron.right")
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(height: 24)
                }

                ForEach(0..<leadingEmptyDays, id: \.self) { _ in
                    Color.clear.frame(height: 42)
                }

                ForEach(1...daysInMonth, id: \.self) { day in
                    Button {
                        selectedDay = day
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(day)")
                                .font(.subheadline.weight(selectedDay == day ? .bold : .regular))
                            Circle()
                                .fill(markedDays.contains(day) ? Color.blue : Color.clear)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(selectedDay == day ? Color.blue.opacity(0.18) : Color(.secondarySystemGroupedBackground))
                        .foregroundStyle(selectedDay == day ? .blue : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var currentMonthDate: Date {
        Date()
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: currentMonthDate).capitalized
    }

    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: currentMonthDate)?.count ?? 30
    }

    private var leadingEmptyDays: Int {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month], from: currentMonthDate)
        let firstDay = calendar.date(from: components) ?? currentMonthDate
        return calendar.component(.weekday, from: firstDay) - 1
    }
}

struct TimeSlotGrid: View {
    @Binding var selectedSlot: String
    let slots: [String]
    let disabled: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(slots, id: \.self) { slot in
                let isDisabled = disabled.contains(slot)
                Button {
                    if !isDisabled {
                        selectedSlot = slot
                    }
                } label: {
                    Text(slot)
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(isDisabled ? .gray.opacity(0.35) : (selectedSlot == slot ? .blue : .gray.opacity(0.55)))
                .disabled(isDisabled)
            }
        }
    }
}

struct BusinessPublicProfileCard: View {
    let profile: BusinessProfileDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: profile.hasCustomBackground ? [.blue.opacity(0.8), .blue.opacity(0.7)] : [Color.blue.opacity(0.18), Color(.secondarySystemGroupedBackground)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 170)

                HStack(alignment: .bottom, spacing: 12) {
                    Image("Torly-AppIcon-1024")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name)
                            .font(.title2.bold())
                        Text("\(profile.category.title) · \(profile.address)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()
            }

            HStack(spacing: 8) {
                PillLabel(text: profile.localeId.uppercased())
                PillLabel(text: profile.currencyId)
                PillLabel(text: profile.timezoneId)
            }

            HStack(spacing: 10) {
                if let url = wazeURL(for: profile.address) {
                    Link(destination: url) {
                        ProfileActionButton(title: "Waze", icon: "location.fill")
                    }
                }

                if let url = phoneURL(for: profile.phone) {
                    Link(destination: url) {
                        ProfileActionButton(title: "Phone", icon: "phone.fill")
                    }
                }

                if let url = whatsappURL(for: profile.phone) {
                    Link(destination: url) {
                        ProfileActionButton(title: "WhatsApp", icon: "message.fill")
                    }
                }
            }

            ShareLink(item: profile.publicBookingUrl) {
                Label("Поделиться ссылкой для записи", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .card()
    }
}

struct ProfileActionButton: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.headline)
            Text(title)
                .font(.caption.bold())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(Color.blue.opacity(0.12))
        .foregroundStyle(.blue)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct BookingRow: View {
    let booking: Booking

    var body: some View {
        HStack(spacing: 12) {
            Text(booking.time)
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(booking.client).fontWeight(.semibold)
                Text("\(booking.service.name) · \(booking.phone)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(booking.status)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.blue.opacity(0.14))
                .clipShape(Capsule())
        }
    }
}

struct BusinessListingRow: View {
    let business: BusinessListing
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: business.category == "Ногти" ? "paintbrush" : "scissors")
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(isSelected ? Color.blue : Color.indigo)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(business.name)
                    .fontWeight(.semibold)
                Text("\(business.category) · \(business.city)")
                    .foregroundStyle(.secondary)
                Text("Ближайшее: \(business.nextSlot)")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            Spacer()

            Text("★ \(business.rating)")
                .font(.caption.bold())
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct AppointmentRow: View {
    let business: String
    let service: String
    let date: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(business).fontWeight(.semibold)
                Spacer()
                Text(status)
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }
            Text(service)
                .foregroundStyle(.secondary)
            Label(date, systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

struct WhatsAppCostCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("WhatsApp utility", systemImage: "message.fill")
                    .font(.headline)
                Spacer()
                Text("412 / 500")
                    .font(.headline.bold())
                    .foregroundStyle(.blue)
            }

            Text("500 напоминаний входят в тариф ₪39. Для активных бизнесов есть пакеты, где отдельно видна себестоимость сообщений.")
                .foregroundStyle(.secondary)

            ForEach(Demo.whatsappPackages) { pack in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pack.name).fontWeight(.semibold)
                        Text("\(pack.messages) сообщений · \(pack.cost)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(pack.price).bold()
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .card()
    }
}

struct StaffScheduleOverview: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(Demo.staff) { member in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(member.name)
                                .fontWeight(.semibold)
                            Text("\(member.role) · \(member.hours)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(member.load)
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                    }

                    Text("Перерыв \(member.breakTime) · отпуск \(member.vacation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ProgressView(value: Double(member.load.replacingOccurrences(of: "%", with: "")) ?? 0, total: 100)
                        .tint(.blue)
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

struct WaitlistPreview: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(Demo.waitlist) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.client)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("уведомить")
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                    }
                    Text(item.service)
                        .foregroundStyle(.secondary)
                    Text("\(item.preferredTime) · \(item.notification)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

struct ProductFeatureGrid: View {
    private let features = [
        ("Онлайн-запись 24/7", "link"),
        ("Подтвердить / отменить / перенести", "arrow.triangle.2.circlepath"),
        ("Отзывы", "star.bubble"),
        ("Формы и анкеты", "list.clipboard"),
        ("Google / Apple Calendar", "calendar.badge.checkmark"),
        ("Push-уведомления", "bell.badge"),
        ("No-show guard", "shield.lefthalf.filled"),
        ("Без бухгалтерии в MVP", "xmark.seal")
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(features, id: \.0) { feature in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: feature.1)
                        .foregroundStyle(.blue)
                    Text(feature.0)
                        .font(.caption.bold())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

struct SetupChecklist: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChecklistRow(done: true, title: "Добавлены услуги и цены")
            ChecklistRow(done: true, title: "Рабочие часы настроены")
            ChecklistRow(done: true, title: "Язык, валюта и timezone выбраны")
            ChecklistRow(done: true, title: "Ссылка готова для Instagram")
            ChecklistRow(done: true, title: "Подключить WhatsApp-напоминания")
            ChecklistRow(done: true, title: "No-show, отзывы и анкеты включены")
        }
    }
}

struct ChecklistRow: View {
    let done: Bool
    let title: String

    var body: some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? .blue : .secondary)
    }
}

struct Metric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.blue)
            Text(value).font(.title.bold())
            Text(title).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct PillLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.blue.opacity(0.12))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
    }
}

struct AnalyticsRow: View {
    let title: String
    let value: String
    let trend: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).fontWeight(.bold)
            Text(trend)
                .font(.caption.bold())
                .foregroundStyle(.blue)
        }
    }
}

func currencySymbol(_ id: String) -> String {
    Demo.currencies.first { $0.id == id }?.symbol ?? "₪"
}

func phoneURL(for phone: String) -> URL? {
    let cleanPhone = phone.filter { $0.isNumber || $0 == "+" }
    return URL(string: "tel://\(cleanPhone)")
}

func whatsappURL(for phone: String) -> URL? {
    let cleanPhone = phone.filter(\.isNumber)
    return URL(string: "https://wa.me/\(cleanPhone)")
}

func wazeURL(for address: String) -> URL? {
    let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address
    return URL(string: "https://waze.com/ul?q=\(encoded)&navigate=yes")
}

struct SignInButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
    }
}

struct RoleChoiceCard: View {
    let icon: String
    let title: String
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.blue)
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    func card() -> some View {
        self
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
