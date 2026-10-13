import SwiftUI
import Combine

enum Currency: String, CaseIterable, Identifiable {
    case usd = "$", eur = "€", gbp = "£", ngn = "₦", cad = "C$", aud = "A$"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .usd: return "USD ($)"
        case .eur: return "EUR (€)"
        case .gbp: return "GBP (£)"
        case .ngn: return "NGN (₦)"
        case .cad: return "CAD (C$)"
        case .aud: return "AUD (A$)"
        }
    }
}

enum Verdict {
    case thriving, manageable, atRisk
    var title: String {
        switch self {
        case .thriving: return "THRIVING"
        case .manageable: return "MANAGEABLE"
        case .atRisk: return "AT RISK"
        }
    }
    var message: String {
        switch self {
        case .thriving: return "Strong financial position — you can thrive here!"
        case .manageable: return "Feasible but tight — watch your spending carefully."
        case .atRisk: return "High risk — consider alternatives or reducing costs."
        }
    }
    var color: Color {
        switch self {
        case .thriving: return .green
        case .manageable: return .orange
        case .atRisk: return .red
        }
    }
}

struct WeekDayRow: Identifiable {
    let id: Int
    let name: String
    let income: Double
    let expense: Double
    let isFirst: Bool
    let isWeekend: Bool
    let isExpenseWorkday: Bool
    var net: Double { income - expense }
}

enum ExpenseFrequency: String, Codable, CaseIterable, Identifiable {
 case daily, weekly, biweekly, monthly, quarterly, yearly
 var id: String { rawValue }
 var annualFactor: Double {
  switch self {
  case .daily: return 365
  case .weekly: return 52
  case .biweekly: return 26
  case .monthly: return 12
  case .quarterly: return 4
  case .yearly: return 1
  }
 }
}
struct CustomExpense: Codable, Identifiable {
 var id = UUID()
 var name = ""
 var amount = 0.0
 var frequency: ExpenseFrequency = .monthly
 var category = "Other"
 var dueDate: Date? = nil
 var isAutopay = false
 var annualCost: Double { amount * frequency.annualFactor }
}
final class ReloCalcModel: ObservableObject {
    @Published private(set) var autosaveError: String?

    private let autosaveKey = "relocalc.inputs.v1"
    private var autosaveCancellable: AnyCancellable?

    // Profile
    @Published var userName = ""
    @Published var city = ""
    @Published var savings = 10000.0
    @Published var currency: Currency = .usd

    // Income
    @Published var wage = 40.0
    @Published var hoursPerDay = 8.0
    @Published var incomeDays = 5
    @Published var taxRate = 15.0
    @Published var overtimeRate = 0.0
    @Published var overtimeHours = 0.0

    // Normal-day expenses
    @Published var expenseDays = 5
    @Published var transport = 15.0
    @Published var food = 25.0
    @Published var housing = 50.0
    @Published var housingIsHotel = false
    @Published var misc = 10.0

    // First day
    @Published var toAirport = 30.0
    @Published var airportToSite = 25.0
    @Published var siteToHotel = 15.0
    @Published var firstHotel = 120.0
    @Published var firstFood = 30.0
    @Published var firstOther = 50.0

    // Setup (one-time)
    @Published var deposit = 1500.0
    @Published var sim = 50.0
    @Published var groceries = 200.0
    @Published var equipment = 300.0
    @Published var visa = 0.0

    @Published var dailyExtras: [CustomExpense] = []
    @Published var arrivalExtras: [CustomExpense] = []
    @Published var setupExtras: [CustomExpense] = []
    @Published var recurringExtras: [CustomExpense] = []
    var dailyExtraCost: Double { dailyExtras.reduce(0) { $0 + $1.annualCost / 365 } }
    var arrivalExtraCost: Double { arrivalExtras.reduce(0) { $0 + $1.amount } }
    var setupExtraCost: Double { setupExtras.reduce(0) { $0 + $1.amount } }
    var recurringYearly: Double { recurringExtras.reduce(0) { $0 + $1.annualCost } }
    var recurringWeekly: Double { recurringYearly / 52 }
    var recurringMonthly: Double { recurringYearly / 12 }

    // Weekly detail: 0 = Mon … 6 = Sun
    @Published var startDay = 2

    init() {
        var shouldSaveInitialValues = true
        if let data = UserDefaults.standard.data(forKey: autosaveKey) {
            do {
                let backup = try JSONDecoder().decode(ReloCalcBackup.self, from: data)
                try backup.validate()
                try backup.apply(to: self)
            } catch {
                shouldSaveInitialValues = false
                autosaveError = "Saved data couldn't be restored: \(error.localizedDescription)"
            }
        }

        autosaveCancellable = objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.saveInputs()
            }
        }

        if shouldSaveInitialValues {
            saveInputs()
        }
    }

    // MARK: Formatting
    func money(_ n: Double) -> String {
        let s = abs(n).formatted(.number.precision(.fractionLength(2)))
        return (n < 0 ? "-" : "") + currency.rawValue + s
    }
    func signed(_ n: Double) -> String { (n >= 0 ? "+" : "") + money(n) }

    // MARK: Income
    private var netFactor: Double { 1 - taxRate / 100 }
    var grossDaily: Double { wage * hoursPerDay }
    var grossWeekly: Double { grossDaily * Double(incomeDays) + overtimeRate * overtimeHours }
    var grossMonthly: Double { grossWeekly * 4.33 }
    var grossYearly: Double { grossWeekly * 52 }
    var netDaily: Double { grossDaily * netFactor }
    var netWeekly: Double { grossWeekly * netFactor }
    var netMonthly: Double { grossMonthly * netFactor }
    var netYearly: Double { grossYearly * netFactor }

    // MARK: Expenses
    var dailyExpense: Double { transport + food + housing + misc + dailyExtraCost }
    var reducedDailyExpense: Double { food + housing + dailyExtraCost }
    var weeklyExpense: Double {
        dailyExpense * Double(expenseDays)
            + reducedDailyExpense * Double(7 - expenseDays)
    }
    var monthlyExpense: Double { weeklyExpense * 52 / 12 + recurringMonthly }
    var yearlyExpense: Double { weeklyExpense * 52 + recurringYearly }

    var firstDayTransport: Double { toAirport + airportToSite + siteToHotel }
    var firstDayTotal: Double { firstDayTransport + firstHotel + firstFood + firstOther + arrivalExtraCost }
    var firstDayDiff: Double { firstDayTotal - dailyExpense }

    var setupTotal: Double { deposit + sim + groceries + equipment + visa + setupExtraCost }

    // MARK: Dashboard
    var dailyNet: Double { netDaily - dailyExpense - recurringYearly / 365 }
    var weeklyNet: Double { netWeekly - weeklyExpense - recurringWeekly }
    var monthlyNet: Double { netMonthly - monthlyExpense }
    var yearlyNet: Double { netYearly - yearlyExpense }

    var firstWeekNormalDays: Int {
        weekRows.filter { !$0.isFirst && $0.isExpenseWorkday }.count
    }
    var firstWeekNormalCost: Double { Double(firstWeekNormalDays) * dailyExpense }
    var firstWeekReducedDays: Int { 6 - firstWeekNormalDays }
    var firstWeekReducedCost: Double { Double(firstWeekReducedDays) * reducedDailyExpense }
    var firstWeekExpense: Double { firstDayTotal + firstWeekNormalCost + firstWeekReducedCost + recurringWeekly }
    var firstWeekNet: Double { netWeekly - firstWeekExpense }

    /// Months savings last if income stops. nil = no expenses (infinite).
    var runwayNoIncome: Double? { monthlyExpense > 0 ? savings / monthlyExpense : nil }
    /// Months until savings run out at current net. nil = net positive.
    var monthsUntilDepleted: Double? { monthlyNet < 0 ? savings / abs(monthlyNet) : nil }

    var relocationCost: Double { setupTotal + max(firstDayDiff, 0) }
    var breakEvenDays: Int? { dailyNet > 0 ? Int(ceil(relocationCost / dailyNet)) : nil }

    var score: Int {
        let savRate = netMonthly > 0 ? monthlyNet / netMonthly * 100 : 0
        let s1 = min(max(savRate, 0) / 25 * 40, 40)
        let s2 = min((runwayNoIncome ?? .infinity) / 6 * 25, 25)
        let s3 = dailyNet > 0 ? 20.0 : 0
        let s4: Double = savings > monthlyExpense * 3 ? 15 : (savings > monthlyExpense ? 10 : 5)
        return Int((s1 + s2 + s3 + s4).rounded())
    }
    var verdict: Verdict { score >= 70 ? .thriving : (score >= 40 ? .manageable : .atRisk) }

    // MARK: Weekly detail
    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var weekRows: [WeekDayRow] {
        var worked = 0
        var expenseWorked = 0
        return (0..<7).map { i in
            let idx = (startDay + i) % 7
            let weekend = idx >= 5
            var income = 0.0
            if !weekend && worked < incomeDays { income = netDaily; worked += 1 }
            let isExpenseWorkday = !weekend && expenseWorked < expenseDays
            if isExpenseWorkday { expenseWorked += 1 }
            let expense = (i == 0 ? firstDayTotal : (isExpenseWorkday ? dailyExpense : reducedDailyExpense)) + recurringWeekly / 7
            return WeekDayRow(id: i, name: dayNames[idx], income: income, expense: expense,
                              isFirst: i == 0, isWeekend: weekend, isExpenseWorkday: isExpenseWorkday)
        }
    }
    var weekIncome: Double { weekRows.reduce(0) { $0 + $1.income } }
    var weekExpense: Double { weekRows.reduce(0) { $0 + $1.expense } }
    var weekExpensePct: Int { weekIncome > 0 ? Int(weekExpense / weekIncome * 100) : 0 }
    var normalWeekExpensePct: Int { netWeekly > 0 ? Int(weeklyExpense / netWeekly * 100) : 0 }

    private func saveInputs() {
        do {
            let data = try ReloCalcExportFormat.json.data(for: self)
            UserDefaults.standard.set(data, forKey: autosaveKey)
            if autosaveError != nil {
                autosaveError = nil
            }
        } catch {
            let message = "Inputs couldn't be saved: \(error.localizedDescription)"
            if autosaveError != message {
                autosaveError = message
            }
        }
    }
}
