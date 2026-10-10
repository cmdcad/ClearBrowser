import Foundation
import Combine
import UserNotifications

// ISO strings preserve compatibility with CreditTrack JSON backups.
enum CreditPeriod: String, Codable, CaseIterable, Identifiable, Hashable {
    case weekly, biweekly, monthly, quarterly, annual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Bi-weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .annual: return "Annual"
        }
    }
    func advance(_ date: Date) -> Date {
        let component: Calendar.Component = self == .weekly || self == .biweekly ? .day : .month
        let amount = [CreditPeriod.weekly: 7, .biweekly: 14, .monthly: 1, .quarterly: 3, .annual: 12][self]!
        return Calendar.current.date(byAdding: component, value: amount, to: date) ?? date
    }
}

enum CreditDates {
    static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func date(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let value = formatter.date(from: string), self.string(value) == string else { return nil }
        return value
    }
    static func money(_ value: Double) -> String { value.formatted(.currency(code: "USD")) }
    static func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

struct CreditCard: Codable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var initialTotal: Double?
    var fixedPayment: Double
    var dueDate: String
    var period: CreditPeriod
    var totalPaid = 0.0
    var isActive = true
    var createdAt = ISO8601DateFormatter().string(from: Date())
    var due: Date { CreditDates.date(dueDate) ?? Date() }
    var remaining: Double? { initialTotal.map { max(0, CreditDates.rounded($0 - totalPaid)) } }
    var progress: Double { initialTotal.map { $0 > 0 ? min(1, totalPaid / $0) : 0 } ?? 0 }
    var daysUntilDue: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: due)).day ?? 0
    }
    var status: String {
        if !isActive { return "PAID OFF!" }
        if daysUntilDue < 0 { return "OVERDUE \(-daysUntilDue)d" }
        if daysUntilDue == 0 { return "DUE TODAY" }
        return "\(daysUntilDue) DAYS"
    }
}

struct CreditPayment: Codable, Identifiable {
    var id = UUID().uuidString
    let cardId: String
    let cardName: String?
    let amount: Double
    let paidDate: String
    let periodLabel: String
    let balanceBefore: Double?
    let balanceAfter: Double?
}

struct CreditReminder: Codable, Identifiable {
    var id = UUID().uuidString
    var daysBefore: Int
    var timeHour: Int
    var timeMinute: Int
    var appliesToAll: Bool
    var specificCardId: String?
    var isEnabled = true
    var label: String {
        daysBefore == 0 ? "Same day" : daysBefore == 1 ? "1 day before" : daysBefore == 7 ? "1 week before" : "\(daysBefore) days before"
    }
    var time: Date { Calendar.current.date(from: DateComponents(hour: timeHour, minute: timeMinute)) ?? Date() }
}

struct CreditBackup: Codable {
    var version = "1.0"
    var app = "CreditTrack"
    var exported = ISO8601DateFormatter().string(from: Date())
    var cards: [CreditCard]
    var payments: [CreditPayment]
    var reminders: [CreditReminder]

    func validate() throws {
        func nonnegative(_ value: Double) -> Bool { value.isFinite && value >= 0 && value <= 1_000_000_000 }
        guard version == "1.0", app == "CreditTrack",
              Set(cards.map(\.id)).count == cards.count,
              Set(payments.map(\.id)).count == payments.count,
              Set(reminders.map(\.id)).count == reminders.count,
              cards.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  nonnegative($0.fixedPayment) && $0.fixedPayment >= 0.01 && nonnegative($0.totalPaid) &&
                  ($0.initialTotal.map { nonnegative($0) && $0 >= 0.01 } ?? true) && CreditDates.date($0.dueDate) != nil }),
              payments.allSatisfy({ !$0.id.isEmpty && !$0.cardId.isEmpty && nonnegative($0.amount) && CreditDates.date($0.paidDate) != nil &&
                  ($0.balanceBefore.map(nonnegative) ?? true) && ($0.balanceAfter.map(nonnegative) ?? true) }),
              reminders.allSatisfy({ !$0.id.isEmpty && (0...365).contains($0.daysBefore) && (0...23).contains($0.timeHour) &&
                  (0...59).contains($0.timeMinute) && ($0.appliesToAll || cards.contains(where: { $0.id == $0.specificCardId })) }) else {
            throw NSError(domain: "CreditTrack", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file is not a valid CreditTrack 1.0 backup."])
        }
    }
}

@MainActor
final class CreditTrackModel: ObservableObject {
    @Published private(set) var cards: [CreditCard] = []
    @Published private(set) var payments: [CreditPayment] = []
    @Published private(set) var reminders: [CreditReminder] = []
    @Published var error: String?
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var notificationNote: String?
    private let storageKey = "credittrack.native.v1"
    private var schedulingTask: Task<Void, Never>?
    var active: [CreditCard] { cards.filter(\.isActive).sorted { $0.dueDate < $1.dueDate } }
    var known: [CreditCard] { cards.filter { $0.initialTotal != nil } }
    var initial: Double { known.reduce(0) { $0 + ($1.initialTotal ?? 0) } }
    var paid: Double { known.reduce(0) { $0 + min($1.totalPaid, $1.initialTotal ?? 0) } }
    var debt: Double { known.reduce(0) { $0 + ($1.remaining ?? 0) } }
    var backup: CreditBackup { CreditBackup(cards: cards, payments: payments, reminders: reminders) }

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            do {
                let saved = try JSONDecoder().decode(CreditBackup.self, from: data)
                try saved.validate()
                cards = saved.cards; payments = saved.payments; reminders = saved.reminders
            } catch { self.error = "Saved CreditTrack data could not be loaded. Restore a JSON backup." }
        }
        refreshNotifications()
    }
    private func save() {
        do { UserDefaults.standard.set(try JSONEncoder().encode(backup), forKey: storageKey) }
        catch { self.error = "Unable to save CreditTrack: \(error.localizedDescription)" }
        scheduleNotifications()
    }
    func upsert(_ card: CreditCard) {
        var value = card
        value.isActive = value.remaining.map { $0 > 0 } ?? true
        if let index = cards.firstIndex(where: { $0.id == card.id }) { cards[index] = value }
        else { cards.append(value) }
        save()
    }
    func delete(_ card: CreditCard) {
        cards.removeAll { $0.id == card.id }
        reminders.removeAll { !$0.appliesToAll && $0.specificCardId == card.id }
        save()
    }
    @discardableResult func pay(_ id: String) -> CreditCard? {
        guard let index = cards.firstIndex(where: { $0.id == id }), cards[index].isActive else { return nil }
        var card = cards[index]
        let before = card.remaining
        card.totalPaid = CreditDates.rounded(card.totalPaid + card.fixedPayment)
        let after = card.remaining
        payments.append(CreditPayment(cardId: card.id, cardName: card.name, amount: card.fixedPayment,
            paidDate: CreditDates.string(Date()), periodLabel: card.due.formatted(.dateTime.month(.wide).year()), balanceBefore: before, balanceAfter: after))
        if after == 0 { card.isActive = false }
        else { card.dueDate = CreditDates.string(card.period.advance(card.due)) }
        cards[index] = card
        save()
        return card.isActive ? nil : card
    }
    func addReminder(_ reminder: CreditReminder) { reminders.append(reminder); save() }
    func toggleReminder(_ id: String, enabled: Bool) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[i].isEnabled = enabled; save()
    }
    func deleteReminder(_ id: String) { reminders.removeAll { $0.id == id }; save() }
    func restore(_ backup: CreditBackup) throws {
        try backup.validate()
        cards = backup.cards.map { var c = $0; c.isActive = c.remaining.map { $0 > 0 } ?? true; return c }
        payments = backup.payments; reminders = backup.reminders; save()
    }
    func exportJSON() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }
    func exportCSV() -> Data {
        var rows: [[String]] = [["CreditTrack", CreditDates.string(Date())], [], ["Cards"],
            ["Name", "Total", "Payment", "Period", "Due", "Paid", "Remaining", "Progress %", "Status"]]
        rows += cards.map { [$0.name, $0.initialTotal.map(String.init(describing:)) ?? "", String($0.fixedPayment), $0.period.title,
            $0.dueDate, String($0.totalPaid), $0.remaining.map(String.init(describing:)) ?? "", String($0.progress * 100), $0.status] }
        rows += [[], ["Payment History"], ["Date", "Creditor", "Amount", "Before", "After"]]
        rows += payments.map { [$0.paidDate, name(for: $0), String($0.amount), $0.balanceBefore.map(String.init(describing:)) ?? "", $0.balanceAfter.map(String.init(describing:)) ?? ""] }
        rows += [[], ["Summary"], ["Total debt", String(initial)], ["Total paid", String(paid)], ["Remaining", String(debt)]]
        let csv = rows.map { row in row.map { value in
            let safe = value.first.map { "=+@-".contains($0) } == true ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",") }.joined(separator: "\r\n")
        return Data(csv.utf8)
    }
    func name(for payment: CreditPayment) -> String { cards.first { $0.id == payment.cardId }?.name ?? payment.cardName ?? "Deleted creditor" }
    func requestNotifications() {
        Task {
            do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]); refreshNotifications() }
            catch { self.error = error.localizedDescription }
        }
    }
    func refreshNotifications() {
        Task {
            notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            scheduleNotifications()
        }
    }
    // iOS local notifications work even when the app is closed. Own only our requests.
    func scheduleNotifications() {
        schedulingTask?.cancel()
        let cardSnapshot = active, reminderSnapshot = reminders.filter(\.isEnabled)
        schedulingTask = Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard !Task.isCancelled else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("credittrack.") }.map(\.identifier))
            guard notificationStatus == .authorized || notificationStatus == .provisional else { return }
            var upcoming: [(Date, CreditReminder, CreditCard)] = []
            for reminder in reminderSnapshot {
                for card in cardSnapshot where reminder.appliesToAll || reminder.specificCardId == card.id {
                    guard let day = Calendar.current.date(byAdding: .day, value: -reminder.daysBefore, to: card.due),
                          let fire = Calendar.current.date(bySettingHour: reminder.timeHour, minute: reminder.timeMinute, second: 0, of: day), fire > Date() else { continue }
                    upcoming.append((fire, reminder, card))
                }
            }
            let otherCount = pending.filter { !$0.identifier.hasPrefix("credittrack.") }.count
            let capacity = max(0, 64 - otherCount)
            notificationNote = upcoming.count > capacity ? "Only the next \(capacity) alerts can be scheduled. Open CreditTrack after payments to refresh reminders." : nil
            for (fire, reminder, card) in upcoming.sorted(by: { $0.0 < $1.0 }).prefix(capacity) {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = "💳 Payment Reminder"
                content.body = "\(card.name) payment of \(CreditDates.money(card.fixedPayment)) is due \(reminder.daysBefore == 0 ? "TODAY" : "in \(reminder.daysBefore) days")."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
                do { try await center.add(UNNotificationRequest(identifier: "credittrack.\(reminder.id).\(card.id)", content: content, trigger: trigger)) }
                catch { self.error = "Unable to schedule reminder: \(error.localizedDescription)" }
            }
        }
    }
}
