import Foundation

enum AppRole: String, CaseIterable, Identifiable {
    case business = "Бизнес"
    case client = "Клиент"

    var id: String { rawValue }
}

struct Service: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var price: Int
    var minutes: Int

    var duration: String {
        "\(minutes) мин"
    }
}

struct Booking: Identifiable, Hashable {
    var id = UUID()
    var day: Int
    var time: String
    var client: String
    var service: Service
    var phone: String
    var status: String
}

struct ClientCard: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var phone: String
    var visits: Int
    var totalSpent: Int
    var note: String
    var noShowCount: Int = 0
}

struct StaffMember: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var role: String
    var hours: String
    var breakTime: String
    var vacation: String
    var load: String
}

struct WaitlistEntry: Identifiable, Hashable {
    var id = UUID()
    var client: String
    var service: String
    var preferredTime: String
    var notification: String
}

struct WhatsAppPackage: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var messages: Int
    var cost: String
    var price: String
}

struct Plan: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var price: String
    var note: String
}

struct LocaleOption: Identifiable, Hashable {
    var id: String
    var name: String
    var direction: String
}

struct CurrencyOption: Identifiable, Hashable {
    var id: String
    var symbol: String
}

struct CountryOption: Identifiable, Hashable {
    var id: String
    var name: String
    var defaultCurrency: String
    var phonePrefix: String
}

struct TimezoneOption: Identifiable, Hashable {
    var id: String
    var city: String
}

struct BusinessCategory: Identifiable, Hashable {
    var id: String
    var title: String
    var icon: String
    var examples: String
}

struct BusinessProfileDraft: Hashable {
    var name: String
    var phone: String
    var address: String
    var previousBookingSource: String
    var wantsGoogleCalendarImport: Bool
    var category: BusinessCategory
    var countryId: String
    var localeId: String
    var currencyId: String
    var timezoneId: String
    var workDays: [WorkDay]
    var services: [Service]
    var hasCustomBackground: Bool
    var backgroundLabel: String

    var publicBookingUrl: String {
        "https://torly.app/\(slug)"
    }

    var slug: String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    init() {
        name = "Barber Dizengoff"
        phone = "+972 52 444 1091"
        address = "Dizengoff 99, Tel Aviv"
        previousBookingSource = "WhatsApp"
        wantsGoogleCalendarImport = false
        category = Demo.businessCategories[0]
        countryId = "IL"
        localeId = "en"
        currencyId = "ILS"
        timezoneId = "Asia/Jerusalem"
        workDays = Demo.workDays
        services = [
            Service(name: "Мужская стрижка", price: 79, minutes: 35),
            Service(name: "Борода + контур", price: 49, minutes: 25)
        ]
        hasCustomBackground = false
        backgroundLabel = "Чистый светлый фон"
    }
}

struct BusinessListing: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var category: String
    var city: String
    var rating: String
    var nextSlot: String
    var services: [Service]
}

struct WorkDay: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var isOpen: Bool
    var hours: String
}

enum Demo {
    static let today = Calendar.current.component(.day, from: Date())

    static let services = [
        Service(name: "Мужская стрижка", price: 79, minutes: 35),
        Service(name: "Борода + контур", price: 49, minutes: 25),
        Service(name: "Маникюр гель", price: 120, minutes: 70),
        Service(name: "Окрашивание", price: 180, minutes: 90)
    ]

    static let bookings = [
        Booking(day: today, time: "09:30", client: "Даниэль Коэн", service: services[0], phone: "052-444-1091", status: "Подтверждено"),
        Booking(day: today, time: "11:00", client: "Майя Леви", service: services[2], phone: "054-118-7712", status: "WhatsApp"),
        Booking(day: min(today + 1, 28), time: "13:15", client: "Алекс Розен", service: services[1], phone: "050-220-8820", status: "Ждет"),
        Booking(day: min(today + 3, 28), time: "17:45", client: "Ной Шапиро", service: services[3], phone: "052-810-4000", status: "Новая")
    ]

    static let clients = [
        ClientCard(name: "Даниэль Коэн", phone: "052-444-1091", visits: 8, totalSpent: 640, note: "Любит утренние слоты", noShowCount: 0),
        ClientCard(name: "Майя Леви", phone: "054-118-7712", visits: 5, totalSpent: 600, note: "Напоминать за день", noShowCount: 0),
        ClientCard(name: "Алекс Розен", phone: "050-220-8820", visits: 3, totalSpent: 210, note: "Часто пишет в WhatsApp", noShowCount: 1),
        ClientCard(name: "Лиор Адам", phone: "050-661-9002", visits: 4, totalSpent: 390, note: "No-show guard: просить подтверждение", noShowCount: 2)
    ]

    static let staff = [
        StaffMember(name: "Daniel", role: "Барбер", hours: "09:00-18:00", breakTime: "13:00-13:30", vacation: "нет", load: "82%"),
        StaffMember(name: "Maya", role: "Ногти", hours: "10:00-20:00", breakTime: "15:00-15:30", vacation: "11 сен", load: "76%"),
        StaffMember(name: "Noa", role: "Кожа", hours: "09:30-16:30", breakTime: "12:30-13:00", vacation: "нет", load: "54%")
    ]

    static let waitlist = [
        WaitlistEntry(client: "Roni", service: "Маникюр гель", preferredTime: "Сегодня после 16:00", notification: "WhatsApp при свободном слоте"),
        WaitlistEntry(client: "Tamar", service: "Мужская стрижка", preferredTime: "Завтра утром", notification: "Push владельцу + WhatsApp клиенту"),
        WaitlistEntry(client: "Niv", service: "Чистка лица", preferredTime: "Любой четверг", notification: "Авто-предложение отмененного слота")
    ]

    static let workDays = [
        WorkDay(title: "Вс", isOpen: true, hours: "09:00-18:00"),
        WorkDay(title: "Пн", isOpen: true, hours: "09:00-18:00"),
        WorkDay(title: "Вт", isOpen: true, hours: "10:00-19:00"),
        WorkDay(title: "Ср", isOpen: true, hours: "09:00-18:00"),
        WorkDay(title: "Чт", isOpen: true, hours: "10:00-20:00"),
        WorkDay(title: "Пт", isOpen: true, hours: "09:00-14:00"),
        WorkDay(title: "Сб", isOpen: false, hours: "Закрыто")
    ]

    static let plans = [
        Plan(name: "Trial", price: "₪0", note: "первые 2 месяца бесплатно"),
        Plan(name: "Torly Pro", price: "₪39", note: "основной тариф после trial"),
        Plan(name: "WhatsApp Active", price: "+₪19", note: "дополнительный пакет активным бизнесам")
    ]

    static let whatsappPackages = [
        WhatsAppPackage(name: "Включено", messages: 500, cost: "≈ ₪8.5", price: "в тарифе ₪39"),
        WhatsAppPackage(name: "Active", messages: 1200, cost: "≈ ₪20", price: "+₪19"),
        WhatsAppPackage(name: "Studio", messages: 2500, cost: "≈ ₪42", price: "+₪39")
    ]

    static let locales = [
        LocaleOption(id: "en", name: "English", direction: "LTR"),
        LocaleOption(id: "he", name: "עברית", direction: "RTL")
    ]

    static let currencies = [
        CurrencyOption(id: "ILS", symbol: "₪"),
        CurrencyOption(id: "USD", symbol: "$"),
        CurrencyOption(id: "EUR", symbol: "€"),
        CurrencyOption(id: "GBP", symbol: "£")
    ]

    static let countries = [
        CountryOption(id: "IL", name: "Israel", defaultCurrency: "ILS", phonePrefix: "+972"),
        CountryOption(id: "US", name: "United States", defaultCurrency: "USD", phonePrefix: "+1"),
        CountryOption(id: "GB", name: "United Kingdom", defaultCurrency: "GBP", phonePrefix: "+44"),
        CountryOption(id: "DE", name: "Germany", defaultCurrency: "EUR", phonePrefix: "+49"),
        CountryOption(id: "FR", name: "France", defaultCurrency: "EUR", phonePrefix: "+33"),
        CountryOption(id: "ES", name: "Spain", defaultCurrency: "EUR", phonePrefix: "+34")
    ]

    static let timezones = [
        TimezoneOption(id: "Asia/Jerusalem", city: "Jerusalem"),
        TimezoneOption(id: "Europe/London", city: "London"),
        TimezoneOption(id: "Europe/Berlin", city: "Berlin"),
        TimezoneOption(id: "Europe/Paris", city: "Paris"),
        TimezoneOption(id: "America/New_York", city: "New York")
    ]

    static let businessCategories = [
        BusinessCategory(id: "nails", title: "Ногти", icon: "paintbrush", examples: "маникюр, педикюр, гель"),
        BusinessCategory(id: "barber", title: "Барбер / мужская парикмахерская", icon: "scissors", examples: "стрижки, борода, контур"),
        BusinessCategory(id: "lashes", title: "Ресницы", icon: "eye", examples: "наращивание, ламинирование"),
        BusinessCategory(id: "brows", title: "Брови", icon: "eyebrow", examples: "форма, окрашивание, ламинирование"),
        BusinessCategory(id: "hair-styling", title: "Стилисты / дизайн волос", icon: "comb", examples: "укладка, окрашивание, уход"),
        BusinessCategory(id: "skin-care", title: "Уход за кожей", icon: "sparkles", examples: "чистка, пилинг, аппаратный уход"),
        BusinessCategory(id: "hair-removal", title: "Эпиляция / удаление волос", icon: "wand.and.stars", examples: "воск, лазер, шугаринг"),
        BusinessCategory(id: "makeup", title: "Макияж", icon: "face.smiling", examples: "вечерний, свадебный, пробный"),
        BusinessCategory(id: "tanning", title: "Загар", icon: "sun.max", examples: "солярий, моментальный загар"),
        BusinessCategory(id: "tattoo-piercing", title: "Татуировки и пирсинг", icon: "pencil.and.scribble", examples: "сеансы, коррекция, украшения"),
        BusinessCategory(id: "injections-fillers", title: "Инъекции / филлеры", icon: "cross.vial", examples: "ботокс, филлеры, консультации"),
        BusinessCategory(id: "massage", title: "Массаж", icon: "figure.mind.and.body", examples: "релакс, спорт, терапия"),
        BusinessCategory(id: "dentistry", title: "Стоматология", icon: "cross.case", examples: "гигиена, лечение, консультации"),
        BusinessCategory(id: "veterinary", title: "Ветеринария", icon: "stethoscope", examples: "прием, вакцинация, груминг"),
        BusinessCategory(id: "fitness", title: "Фитнес", icon: "figure.strengthtraining.traditional", examples: "тренировки, пилатес, йога"),
        BusinessCategory(id: "consulting-holistic", title: "Консультации / холистическая терапия", icon: "leaf", examples: "коучинг, терапия, диагностика"),
        BusinessCategory(id: "optics", title: "Оптика", icon: "eyeglasses", examples: "проверка зрения, подбор очков"),
        BusinessCategory(id: "other", title: "Другое", icon: "square.grid.2x2", examples: "любой сервис по записи")
    ]

    static let businesses = [
        BusinessListing(name: "Barber Dizengoff", category: "Барбер", city: "Тель-Авив", rating: "4.9", nextSlot: "Сегодня 15:00", services: [services[0], services[1]]),
        BusinessListing(name: "Nails by Maya", category: "Ногти", city: "Рамат-Ган", rating: "4.8", nextSlot: "Завтра 10:30", services: [services[2]]),
        BusinessListing(name: "Studio Hair TLV", category: "Парикмахер", city: "Тель-Авив", rating: "4.7", nextSlot: "Пт 12:00", services: [services[0], services[3]])
    ]

    static let slots = ["09:00", "09:30", "10:15", "11:00", "12:30", "15:00", "16:15", "17:45"]
}
