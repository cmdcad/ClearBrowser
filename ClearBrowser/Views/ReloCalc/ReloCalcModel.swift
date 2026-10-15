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
    private let defaults: UserDefaults
    private var autosaveCancellable: AnyCancellable?

    // Profile
    @Published var userName = ""
    @Published var city = ""
    @Published var savings = 10000.0
    @Published var expectedBonus: Double?
    var availableFunds: Double {
        guard let bonus = expectedBonus, bonus.isFinite, bonus >= 0 else { return savings }
        return savings + bonus
    }
    @Published var currency: Currency = .usd

    // Income
    @Published var wage = 40.0
    @Published var hoursPerDay = 8.0
    @Published var incomeDays = 5
    @Published var taxRate = 15.0
    @Published var overtimeRate = 0.0
    @Published var overtimeHours = 0.0

    @Published var obligations: [RecurringObligation] = []

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var shouldSaveInitialValues = true
        if let data = defaults.data(forKey: autosaveKey) {
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
    var monthlyLivingExpense: Double { weeklyExpense * 4.33 }
    var monthlyObligations: Double { obligations.reduce(0) { $0 + $1.monthlyAmount } }
    var annualObligations: Double { monthlyObligations * 12 }
    var obligationBurden: Double? { netMonthly > 0 ? monthlyObligations / netMonthly * 100 : nil }
    var monthlyExpense: Double { monthlyLivingExpense + monthlyObligations }
    var yearlyExpense: Double { weeklyExpense * 52 + annualObligations }

    var firstDayTransport: Double { toAirport + airportToSite + siteToHotel }
    var firstDayTotal: Double { firstDayTransport + firstHotel + firstFood + firstOther + arrivalExtraCost }
    var firstDayDiff: Double { firstDayTotal - dailyExpense }

    var setupTotal: Double { deposit + sim + groceries + equipment + visa + setupExtraCost }

    // MARK: Dashboard
    var dailyNet: Double { netDaily - dailyExpense - annualObligations / 365 }
    var weeklyNet: Double { netWeekly - weeklyExpense - annualObligations / 52 }
    var monthlyNet: Double { netMonthly - monthlyExpense }
    var yearlyNet: Double { netYearly - yearlyExpense }

    var firstWeekNormalDays: Int {
        weekRows.filter { !$0.isFirst && $0.isExpenseWorkday }.count
    }
    var firstWeekNormalCost: Double { Double(firstWeekNormalDays) * dailyExpense }
    var firstWeekReducedDays: Int { 6 - firstWeekNormalDays }
    var firstWeekReducedCost: Double { Double(firstWeekReducedDays) * reducedDailyExpense }
    var firstWeekExpense: Double { firstDayTotal + firstWeekNormalCost + firstWeekReducedCost + annualObligations / 52 }
    var firstWeekNet: Double { netWeekly - firstWeekExpense }

    /// Months savings last if income stops. nil = no expenses (infinite).
    var runwayNoIncome: Double? { monthlyExpense > 0 ? availableFunds / monthlyExpense : nil }
    /// Months until savings run out at current net. nil = net positive.
    var monthsUntilDepleted: Double? { monthlyNet < 0 ? availableFunds / abs(monthlyNet) : nil }

    var relocationCost: Double { setupTotal + max(firstDayDiff, 0) }
    var breakEvenDays: Int? { dailyNet > 0 ? Int(ceil(relocationCost / dailyNet)) : nil }

    var score: Int {
        let savRate = netMonthly > 0 ? monthlyNet / netMonthly * 100 : 0
        let s1 = min(max(savRate, 0) / 25 * 40, 40)
        let s2 = min((runwayNoIncome ?? .infinity) / 6 * 25, 25)
        let s3 = dailyNet > 0 ? 20.0 : 0
        let s4: Double = availableFunds > monthlyExpense * 3 ? 15 : (availableFunds > monthlyExpense ? 10 : 5)
        return Int((s1 + s2 + s3 + s4).rounded())
    }
    var verdict: Verdict {
        guard netMonthly > 0, monthlyNet > 0,
              (obligationBurden ?? 100) <= 50 else { return .atRisk }
        return availableFunds >= relocationCost && score >= 70 && (obligationBurden ?? 100) <= 30 ? .thriving : .manageable
    }

    /// Scenario values are previews only and never mutate saved inputs.
    func whatIf(hourlyIncrease: Double, monthlyRentReduction: Double) -> ReloScenario {
        let increase = hourlyIncrease.isFinite ? max(0, hourlyIncrease) : 0
        let requestedReduction = monthlyRentReduction.isFinite ? max(0, monthlyRentReduction) : 0
        let reduction = min(requestedReduction, max(housing * 7 * 4.33, 0))
        let income = netMonthly + increase * hoursPerDay * Double(incomeDays) * 4.33 * netFactor
        let burn = monthlyExpense - reduction
        let surplus = income - burn
        let ratio = income > 0 ? monthlyObligations / income * 100 : 100
        let dailySurplus = dailyNet + increase * hoursPerDay * netFactor + reduction / (7 * 4.33)
        let runway = burn > 0 ? availableFunds / burn : nil
        let savingsRate = income > 0 ? surplus / income * 100 : 0
        let savingsScore: Double = min(max(savingsRate, 0) / 25 * 40, 40)
        let runwayScore: Double = min((runway ?? .infinity) / 6 * 25, 25)
        let surplusScore: Double = dailySurplus > 0 ? 20 : 0
        let reservesScore: Double
        if availableFunds > burn * 3 { reservesScore = 15 }
        else if availableFunds > burn { reservesScore = 10 }
        else { reservesScore = 5 }
        let totalScore = savingsScore + runwayScore + surplusScore + reservesScore
        let score = Int(totalScore.rounded())
        let result: Verdict
        if income <= 0 || surplus <= 0 || ratio > 50 { result = .atRisk }
        else if availableFunds >= relocationCost && score >= 70 && ratio <= 30 { result = .thriving }
        else { result = .manageable }
        return ReloScenario(netMonthly: income, monthlyExpense: burn, monthlySurplus: surplus,
                            rentReduction: reduction, score: score, verdict: result, runway: runway)
    }

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
            let expense = (i == 0 ? firstDayTotal : (isExpenseWorkday ? dailyExpense : reducedDailyExpense)) + annualObligations / 52 / 7
            return WeekDayRow(id: i, name: dayNames[idx], income: income, expense: expense,
                              isFirst: i == 0, isWeekend: weekend, isExpenseWorkday: isExpenseWorkday)
        }
    }
    var weekIncome: Double { weekRows.reduce(0) { $0 + $1.income } }
    var weekExpense: Double { weekRows.reduce(0) { $0 + $1.expense } }
    var weekExpensePct: Int { weekIncome > 0 ? Int(weekExpense / weekIncome * 100) : 0 }
    var normalWeekExpensePct: Int { netWeekly > 0 ? Int((weeklyExpense + annualObligations / 52) / netWeekly * 100) : 0 }

    private func saveInputs() {
        do {
            let data = try ReloCalcExportFormat.json.data(for: self)
            defaults.set(data, forKey: autosaveKey)
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


enum ObligationCategory: String, Codable, CaseIterable, Identifiable {
    case phone = "Phone", creditCard = "Credit Card", loan = "Loan", insurance = "Insurance"
    case subscription = "Subscription", childSupport = "Child Support", other = "Other"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .phone: return "iphone"; case .creditCard: return "creditcard.fill"
        case .loan: return "building.columns.fill"; case .insurance: return "shield.fill"
        case .subscription: return "tv.fill"; case .childSupport: return "figure.child"
        case .other: return "list.clipboard.fill"
        }
    }
    var color: Color {
        switch self {
        case .phone: return .blue; case .creditCard: return .red; case .loan: return .yellow
        case .insurance: return .green; case .subscription: return .purple
        case .childSupport: return .orange; case .other: return .gray
        }
    }
}

enum ObligationFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly = "Weekly", biweekly = "Bi-weekly", monthly = "Monthly", quarterly = "Quarterly", annual = "Annual"
    var id: String { rawValue }
    var monthlyFactor: Double {
        switch self {
        case .weekly: return 4.333; case .biweekly: return 2.167
        case .monthly: return 1; case .quarterly: return 1.0 / 3; case .annual: return 1.0 / 12
        }
    }
}

struct ObligationPayoff {
    let months: Int
    let interest: Double
    func date(from start: Date = .now) -> Date? { Calendar.current.date(byAdding: .month, value: months, to: start) }
}

struct RecurringObligation: Codable, Identifiable {
    var id = UUID()
    var name = ""
    var category: ObligationCategory = .other
    var amount = 0.0
    var frequency: ObligationFrequency = .monthly
    var remainingBalance: Double?
    var apr: Double?
    var autoPay = false
    var notes = ""
    var monthlyAmount: Double { amount * frequency.monthlyFactor }
    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a bill name." }
        if name.count > 200 || notes.count > 5000 { return "Shorten the bill name or notes." }
        if !amount.isFinite || amount <= 0 || amount > 1_000_000_000 { return "Enter a payment greater than zero and at most 1 billion." }
        if let balance = remainingBalance, !balance.isFinite || balance < 0 || balance > 1_000_000_000 { return "Enter a valid nonnegative remaining balance." }
        if let rate = apr, !rate.isFinite || !(0...100).contains(rate) { return "APR must be between 0 and 100%." }
        return nil
    }
    /// Monthly-equivalent estimate, including a smaller final payment.
    /// nil means the payment does not cover interest or exceeds the 100-year estimate limit.
    var payoff: ObligationPayoff? {
        guard let initial = remainingBalance, initial.isFinite, initial >= 0,
              monthlyAmount.isFinite, monthlyAmount > 0 else { return nil }
        if initial == 0 { return ObligationPayoff(months: 0, interest: 0) }
        let rate = (apr ?? 0) / 100 / 12
        guard monthlyAmount > initial * rate else { return nil }
        var balance = initial, interest = 0.0
        for month in 1...1200 {
            let charge = balance * rate
            interest += charge
            balance = max(0, balance + charge - monthlyAmount)
            if balance < 0.000001 { return ObligationPayoff(months: month, interest: interest) }
        }
        return nil
    }
}


struct ReloScenario {
    let netMonthly: Double
    let monthlyExpense: Double
    let monthlySurplus: Double
    let rentReduction: Double
    let score: Int
    let verdict: Verdict
    let runway: Double?
}
