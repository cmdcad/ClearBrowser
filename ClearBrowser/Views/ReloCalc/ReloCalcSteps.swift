import SwiftUI
import Charts

// MARK: - Start

struct StartStep: View {
    @ObservedObject var m: ReloCalcModel

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Image(systemName: "globe").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Ready to Relocate?").font(.title3.bold())
                Text("Let's figure out if you can thrive in your new city.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)

            Card(title: "Your Profile") {
                textField("Your Name (optional)", text: $m.userName, placeholder: "e.g. Tosin")
                textField("Relocating To (optional)", text: $m.city, placeholder: "e.g. Austin, TX")
            }
            Card(title: "Starting Finances") {
                NumberField(title: "Starting Savings", value: $m.savings, prefix: m.currency.rawValue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expected Bonus (optional)").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    HStack {
                        Text(m.currency.rawValue).foregroundStyle(.secondary)
                        TextField("Leave blank if none", value: $m.expectedBonus, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.system(.body, design: .monospaced))
                            .accessibilityLabel("Expected Bonus, optional")
                        if m.expectedBonus != nil {
                            Button { m.expectedBonus = nil } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel("Clear expected bonus")
                        }
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    Text("One-time take-home amount available for the move. Included in available funds, not monthly income.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let bonus = m.expectedBonus, bonus < 0 || !bonus.isFinite {
                        Text("Enter a nonnegative bonus or leave it blank.").font(.caption).foregroundStyle(.red)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Currency").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Currency", selection: $m.currency) {
                        ForEach(Currency.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private func textField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Income

struct IncomeStep: View {
    @ObservedObject var m: ReloCalcModel

    var body: some View {
        VStack(spacing: 12) {
            Card(title: "Earnings") {
                NumberField(title: "Hourly Wage", value: $m.wage, prefix: m.currency.rawValue, suffix: "/hr")
                NumberField(title: "Hours Per Day", value: $m.hoursPerDay, suffix: "hrs")
                DaysPicker(title: "Income Work Week", days: $m.incomeDays)
                DisclosureGroup("Advanced Options") {
                    VStack(spacing: 12) {
                        NumberField(title: "Tax Rate", value: $m.taxRate, suffix: "%")
                        NumberField(title: "Overtime Rate", value: $m.overtimeRate,
                                    prefix: m.currency.rawValue, suffix: "/hr")
                        NumberField(title: "Overtime Hrs / Week", value: $m.overtimeHours, suffix: "hrs")
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline.weight(.semibold))
            }

            Card(title: "Income Summary") {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Period").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Gross").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Net").frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    row("Daily", m.grossDaily, m.netDaily)
                    row("Weekly", m.grossWeekly, m.netWeekly)
                    row("Monthly", m.grossMonthly, m.netMonthly)
                    row("Yearly", m.grossYearly, m.netYearly)
                }
            }
        }
    }

    private func row(_ label: String, _ gross: Double, _ net: Double) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Text(m.money(gross)).font(.system(.footnote, design: .monospaced).weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(m.money(net)).font(.system(.footnote, design: .monospaced).weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .minimumScaleFactor(0.7)
        .lineLimit(1)
    }
}

// MARK: - Expenses

private enum ExpenseSection: String, CaseIterable, Identifiable {
    case normal = "Normal Day", first = "First Day", setup = "Setup"
    var id: String { rawValue }
}

struct ExpensesStep: View {
    @ObservedObject var m: ReloCalcModel
    @State private var section: ExpenseSection = .normal

    var body: some View {
        VStack(spacing: 12) {
            Picker("Section", selection: $section) {
                ForEach(ExpenseSection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch section {
            case .normal: normal
            case .first: first
            case .setup: setup
            }
        }
    }

    private var cur: String { m.currency.rawValue }

    private var normal: some View {
        VStack(spacing: 12) {
            Card {
                DaysPicker(title: "Expense Work Week", days: $m.expenseDays)
                Text("Rest days include food and housing only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NumberField(title: "Transport / day", value: $m.transport, prefix: cur, suffix: "/day")
                NumberField(title: "Food / day", value: $m.food, prefix: cur, suffix: "/day")
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Housing", selection: $m.housingIsHotel) {
                        Text("Apartment").tag(false)
                        Text("Hotel").tag(true)
                    }
                    .pickerStyle(.segmented)
                    NumberField(title: "Housing / day", value: $m.housing, prefix: cur, suffix: "/day")
                }
                NumberField(title: "Miscellaneous / day", value: $m.misc, prefix: cur, suffix: "/day")
            }
            Card(title: "Expense Summary") {
                SummaryRow(label: "Transport", value: m.money(m.transport))
                SummaryRow(label: "Food", value: m.money(m.food))
                SummaryRow(label: "Housing", value: m.money(m.housing))
                SummaryRow(label: "Misc", value: m.money(m.misc))
                Divider()
                SummaryRow(label: "Workday Total", value: m.money(m.dailyExpense), bold: true)
                SummaryRow(label: "Rest Day Total", value: m.money(m.reducedDailyExpense))
                SummaryRow(label: "Weekly", value: m.money(m.weeklyExpense))
                SummaryRow(label: "Recurring Bills / month", value: m.money(m.monthlyObligations))
                SummaryRow(label: "Monthly", value: m.money(m.monthlyExpense))
                SummaryRow(label: "Yearly", value: m.money(m.yearlyExpense))
            }
        }
    }

    private var first: some View {
        VStack(spacing: 12) {
            Card {
                Text("Your arrival-day costs — typically higher than a normal day.")
                    .font(.footnote).foregroundStyle(.secondary)
                NumberField(title: "Transport to Airport", value: $m.toAirport, prefix: cur)
                NumberField(title: "Airport to Work Site", value: $m.airportToSite, prefix: cur)
                NumberField(title: "Work Site to Hotel", value: $m.siteToHotel, prefix: cur)
                NumberField(title: "Hotel (First Night)", value: $m.firstHotel, prefix: cur)
                NumberField(title: "Food (First Day)", value: $m.firstFood, prefix: cur)
                NumberField(title: "Other First-Day Costs", value: $m.firstOther, prefix: cur)
            }
            Card(title: "First Day Total") {
                SummaryRow(label: "Transport (3 legs)", value: m.money(m.firstDayTransport))
                SummaryRow(label: "Hotel", value: m.money(m.firstHotel))
                SummaryRow(label: "Food", value: m.money(m.firstFood))
                SummaryRow(label: "Other", value: m.money(m.firstOther))
                Divider()
                SummaryRow(label: "Total First Day", value: m.money(m.firstDayTotal), bold: true)
                SummaryRow(label: "vs Normal Day", value: m.signed(m.firstDayDiff),
                           color: m.firstDayDiff > 0 ? .red : .green)
            }
        }
    }

    private var setup: some View {
        VStack(spacing: 12) {
            Card {
                Text("One-time costs during relocation (not recurring).")
                    .font(.footnote).foregroundStyle(.secondary)
                NumberField(title: "Security Deposit", value: $m.deposit, prefix: cur)
                NumberField(title: "SIM / Phone Plan", value: $m.sim, prefix: cur)
                NumberField(title: "Groceries / Supplies", value: $m.groceries, prefix: cur)
                NumberField(title: "Work Equipment", value: $m.equipment, prefix: cur)
                NumberField(title: "Visa / Permit Fees", value: $m.visa, prefix: cur)
            }
            Card(title: "Setup Cost Total") {
                Text(m.money(m.setupTotal))
                    .font(.system(size: 32, weight: .heavy, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Dashboard

struct DashboardStep: View {
    @ObservedObject var m: ReloCalcModel
    @State private var hourlyIncrease = 0.0
    @State private var rentReduction = 0.0

    var body: some View {
        VStack(spacing: 12) {
            gauge
            whatIfControls
            allocation
            netSummary
            firstWeek
            runway
            breakEven
        }
    }

    private func netColor(_ n: Double) -> Color { n >= 0 ? .green : .red }

    private var whatIfControls: some View {
        let scenario = m.whatIf(hourlyIncrease: hourlyIncrease, monthlyRentReduction: rentReduction)
        return Card(title: "What If") {
            Text("Try a scenario without changing your saved inputs. The dashboard below remains your current plan.")
                .font(.footnote).foregroundStyle(.secondary)
            Toggle("Earn \(m.money(5))/hr more", isOn: Binding(
                get: { hourlyIncrease > 0 }, set: { hourlyIncrease = $0 ? 5 : 0 }))
            HStack {
                Text("Hourly increase")
                Spacer()
                Text("+\(m.money(hourlyIncrease))/hr").monospacedDigit()
            }.font(.caption)
            Slider(value: $hourlyIncrease, in: 0...20, step: 1)
                .accessibilityLabel("What if hourly wage increase")
            Toggle("Rent \(m.money(200))/month less", isOn: Binding(
                get: { rentReduction > 0 }, set: { rentReduction = $0 ? 200 : 0 }))
            HStack {
                Text("Monthly rent reduction")
                Spacer()
                Text(m.money(scenario.rentReduction)).monospacedDigit()
            }.font(.caption)
            Slider(value: $rentReduction, in: 0...1000, step: 25)
                .accessibilityLabel("What if monthly rent reduction")
            Text("Rent reduction is capped at your current monthly housing cost.")
                .font(.caption2).foregroundStyle(.secondary)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Current plan").font(.caption).foregroundStyle(.secondary)
                    Text(m.verdict.title).font(.caption.bold()).foregroundStyle(m.verdict.color)
                }
                Spacer()
                Image(systemName: "arrow.right")
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("What If · \(scenario.score)%").font(.caption).foregroundStyle(.secondary)
                    Text(scenario.verdict.title).font(.caption.bold()).foregroundStyle(scenario.verdict.color)
                }
            }
            SummaryRow(label: "Scenario Monthly Surplus", value: m.signed(scenario.monthlySurplus), color: netColor(scenario.monthlySurplus), bold: true)
            SummaryRow(label: "Change / Month", value: m.signed(scenario.monthlySurplus - m.monthlyNet), color: .green)
            SummaryRow(label: "Runway Without Income", value: scenario.runway.map { String(format: "%.1f months", $0) } ?? "∞")
            Button("Reset Scenario") { hourlyIncrease = 0; rentReduction = 0 }
                .disabled(hourlyIncrease == 0 && rentReduction == 0)
        }
    }

    private var allocation: some View {
        Card(title: "Monthly Financial Health") {
            SummaryRow(label: "Net Income", value: m.money(m.netMonthly), color: .green)
            SummaryRow(label: "Living Expenses", value: m.money(m.monthlyLivingExpense))
            SummaryRow(label: "Recurring Bills", value: m.money(m.monthlyObligations))
            Divider()
            SummaryRow(label: "Surplus / Deficit", value: m.signed(m.monthlyNet), color: netColor(m.monthlyNet), bold: true)
            SummaryRow(label: "Obligation Burden", value: m.obligationBurden.map { String(format: "%.1f%%", $0) } ?? "N/A — no net income")
            Chart {
                SectorMark(angle: .value("Amount", m.monthlyLivingExpense), innerRadius: .ratio(0.65))
                    .foregroundStyle(by: .value("Category", "Living Expenses"))
                SectorMark(angle: .value("Amount", m.monthlyObligations), innerRadius: .ratio(0.65))
                    .foregroundStyle(by: .value("Category", "Recurring Bills"))
                SectorMark(angle: .value("Amount", max(m.monthlyNet, 0)), innerRadius: .ratio(0.65))
                    .foregroundStyle(by: .value("Category", "Surplus"))
            }
            .chartForegroundStyleScale(["Living Expenses": Color.blue, "Recurring Bills": Color.orange, "Surplus": Color.green])
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let frame = proxy.plotFrame {
                        let plot = geometry[frame]
                        VStack(spacing: 3) {
                            Text("Net Monthly").font(.caption2).foregroundStyle(.secondary)
                            Text(m.money(m.netMonthly)).font(.system(.caption, design: .monospaced).bold())
                        }
                        .position(x: plot.midX, y: plot.midY)
                    }
                }
            }
            .frame(height: 200)
            .accessibilityLabel("Monthly income allocation")
            if m.monthlyNet < 0 {
                Text("Expenses exceed income by \(m.money(abs(m.monthlyNet))) per month.")
                    .font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var gauge: some View {
        Card {
            VStack(spacing: 4) {
                Text("\(m.score)%")
                    .font(.system(size: 52, weight: .heavy, design: .monospaced))
                Text(m.verdict.title).font(.subheadline.weight(.bold))
                Text(m.verdict.message).font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(m.verdict.color)
            .frame(maxWidth: .infinity)
            ProgressView(value: Double(m.score), total: 100).tint(m.verdict.color)
            HStack {
                Text("At Risk"); Spacer(); Text("Manageable"); Spacer(); Text("Thriving")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var netSummary: some View {
        Card(title: "Net Income Summary") {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("Period").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Income").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Expense").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Net").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                row("Daily", m.netDaily, m.dailyExpense + m.annualObligations / 365, m.dailyNet)
                row("Weekly", m.netWeekly, m.weeklyExpense + m.annualObligations / 52, m.weeklyNet)
                row("Monthly", m.netMonthly, m.monthlyExpense, m.monthlyNet)
                row("Yearly", m.netYearly, m.yearlyExpense, m.yearlyNet)
            }
        }
    }

    private func row(_ label: String, _ inc: Double, _ exp: Double, _ net: Double) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Text(m.money(inc)).frame(maxWidth: .infinity, alignment: .trailing)
            Text(m.money(exp)).frame(maxWidth: .infinity, alignment: .trailing)
            Text(m.signed(net)).foregroundStyle(netColor(net))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .minimumScaleFactor(0.7).lineLimit(1)
    }

    private var firstWeek: some View {
        Card(title: "First Week Total") {
            SummaryRow(label: "Day 1 (Special)", value: m.money(m.firstDayTotal))
            SummaryRow(
                label: "Days 2-7 (\(m.firstWeekNormalDays) workdays + \(m.firstWeekReducedDays) rest days)",
                value: "\(m.money(m.firstWeekNormalCost)) + \(m.money(m.firstWeekReducedCost))"
            )
            Divider()
            SummaryRow(label: "Recurring Bills (weekly estimate)", value: m.money(m.annualObligations / 52))
            SummaryRow(label: "Total Week 1 Expense", value: m.money(m.firstWeekExpense), bold: true)
            SummaryRow(label: "Income Week 1", value: m.money(m.netWeekly), color: .green)
            SummaryRow(label: "Net Week 1", value: m.signed(m.firstWeekNet), color: netColor(m.firstWeekNet))
        }
    }

    private var runway: some View {
        Card(title: "Runway") {
            SummaryRow(label: "Starting Savings", value: m.money(m.savings))
            if let bonus = m.expectedBonus {
                SummaryRow(label: "Expected Bonus", value: m.money(bonus))
            }
            SummaryRow(label: "Available Funds", value: m.money(m.availableFunds), bold: true)
            SummaryRow(label: "Monthly Living Costs", value: m.money(m.monthlyLivingExpense))
            SummaryRow(label: "Monthly Recurring Bills", value: m.money(m.monthlyObligations))
            SummaryRow(label: "Total Monthly Burn", value: m.money(m.monthlyExpense), bold: true)
            SummaryRow(label: "Monthly Net", value: m.signed(m.monthlyNet), color: netColor(m.monthlyNet))
            SummaryRow(label: "If income stops",
                       value: m.runwayNoIncome.map { String(format: "%.1f months", $0) } ?? "∞")
            let positive = m.monthsUntilDepleted == nil
            Text(positive
                 ? "✅ Net Positive — Savings grow over time"
                 : "⚠️ Funds deplete in " + String(format: "%.1f", m.monthsUntilDepleted ?? 0) + " months")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(positive ? .green : .red)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background((positive ? Color.green : Color.red).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var breakEven: some View {
        Card(title: "Break-Even Analysis") {
            SummaryRow(label: "Total Relocation Cost", value: m.money(m.relocationCost))
            SummaryRow(label: "Daily Net Surplus", value: m.signed(m.dailyNet), color: netColor(m.dailyNet))
            let days = m.breakEvenDays
            VStack(spacing: 3) {
                Text("BREAK-EVEN POINT").font(.caption).foregroundStyle(.secondary)
                Text(days.map { "Day \($0) (~" + String(format: "%.1f", Double($0) / 7) + " wks)" } ?? "Never")
                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                    .foregroundStyle(days == nil ? .red : .green)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background((days == nil ? Color.red : Color.green).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Weekly

struct WeeklyStep: View {
    @ObservedObject var m: ReloCalcModel
    private let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(spacing: 12) {
            Card(title: "What day do you start?") {
                Picker("Start day", selection: $m.startDay) {
                    ForEach(0..<7, id: \.self) { Text(names[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Card(title: "Your First Week") {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text("").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Income").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Expense").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Net").frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)

                    ForEach(m.weekRows) { r in
                        HStack(spacing: 6) {
                            Text(r.name + (r.isFirst ? " ★" : ""))
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(r.income > 0 ? m.money(r.income) : "—").foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(m.money(r.expense)).foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(m.signed(r.net)).foregroundStyle(r.net >= 0 ? .green : .red)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .minimumScaleFactor(0.7).lineLimit(1)
                        .opacity((r.isWeekend || !r.isExpenseWorkday) && !r.isFirst ? 0.7 : 1)
                    }

                    Divider()
                    HStack(spacing: 6) {
                        Text("Total").font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(m.money(m.weekIncome)).frame(maxWidth: .infinity, alignment: .trailing)
                        Text(m.money(m.weekExpense)).frame(maxWidth: .infinity, alignment: .trailing)
                        Text(m.signed(m.weekIncome - m.weekExpense))
                            .foregroundStyle((m.weekIncome - m.weekExpense) >= 0 ? .green : .red)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.7).lineLimit(1)
                }
            }
            Text("Weekly recurring bills are averaged across the days, not scheduled by due date.").font(.caption).foregroundStyle(.secondary)
            Text("💡 You'll spend **\(m.weekExpensePct)%** of your first week's income on expenses. By week 2, this drops to **\(m.normalWeekExpensePct)%** as the special first-day costs are gone.")
                .font(.subheadline)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}


// MARK: - Recurring bills

struct RecurringBillsStep: View {
    @ObservedObject var m: ReloCalcModel
    @State private var draft = RecurringObligation()
    @State private var editingID: UUID?
    @State private var showForm = false
    @State private var showBalance = false
    @State private var showAPR = false
    @State private var sortByAmount = false
    @State private var deleteID: UUID?
    @State private var resetBills = false
    @State private var validationError: String?

    private var sortedBills: [RecurringObligation] {
        m.obligations.sorted {
            if sortByAmount && $0.monthlyAmount != $1.monthlyAmount { return $0.monthlyAmount > $1.monthlyAmount }
            if !sortByAmount && $0.category != $1.category {
                return (ObligationCategory.allCases.firstIndex(of: $0.category) ?? 0) < (ObligationCategory.allCases.firstIndex(of: $1.category) ?? 0)
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    private var burdenColor: Color {
        guard let percent = m.obligationBurden else { return m.monthlyObligations > 0 ? .red : .secondary }
        return percent <= 30 ? .green : (percent <= 50 ? .orange : .red)
    }
    var body: some View {
        VStack(spacing: 12) {
            Card(title: "Recurring Bills & Obligations") {
                Text("Bills that follow you wherever you live. Keep destination living expenses separate to avoid counting a bill twice.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    editingID = nil; draft = RecurringObligation()
                    showBalance = false; showAPR = false; validationError = nil
                    withAnimation { showForm = true }
                } label: { Label("Add Bill", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).clipShape(Capsule())
                Picker("Sort bills", selection: $sortByAmount) {
                    Text("Category").tag(false)
                    Text("Monthly amount").tag(true)
                }.pickerStyle(.segmented)
            }
            if showForm { editor }
            if m.obligations.isEmpty {
                Card {
                    Text("No recurring bills yet.").font(.headline)
                    Text("Add phone plans, loan payments, insurance, or subscriptions.").font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                ForEach(sortedBills) { bill in
                    if !sortByAmount && sortedBills.first(where: { $0.category == bill.category })?.id == bill.id {
                        Text(bill.category.rawValue).font(.subheadline.bold())
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                    billCard(bill)
                        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                            if value.translation.width < -80 && abs(value.translation.height) < 40 { deleteID = bill.id }
                        })
                }
            }
            Card(title: "Obligations Summary") {
                SummaryRow(label: "Total Monthly", value: m.money(m.monthlyObligations), bold: true)
                SummaryRow(label: "Total Annual", value: m.money(m.annualObligations))
                SummaryRow(label: "Bills", value: String(m.obligations.count))
                SummaryRow(label: "% of Net Income", value: m.obligationBurden.map { String(format: "%.1f%%", $0) } ?? "N/A — no net income", color: burdenColor)
                ProgressView(value: min(max((m.obligationBurden ?? 0) / 100, 0), 1)).tint(burdenColor)
                    .animation(.easeInOut, value: m.monthlyObligations)
                Text("Low: ≤30% · Moderate: >30–50% · High: >50%")
                    .font(.caption).foregroundStyle(.secondary)
                if !m.obligations.isEmpty {
                    Button("Reset All Bills", role: .destructive) { resetBills = true }.font(.footnote)
                }
            }
        }
        .alert("Delete bill?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("Cancel", role: .cancel) { deleteID = nil }
            Button("Delete", role: .destructive) {
                if let id = deleteID {
                    m.obligations.removeAll { $0.id == id }
                    if editingID == id { showForm = false; editingID = nil }
                }
                deleteID = nil
            }
        } message: { Text("This removes the bill from your plan and updates your totals.") }
        .alert("Reset all recurring bills?", isPresented: $resetBills) {
            Button("Cancel", role: .cancel) { }
            Button("Reset Bills", role: .destructive) { m.obligations = []; showForm = false; editingID = nil }
        } message: { Text("Your income, living expenses, and relocation costs will be kept.") }
    }
    private var editor: some View {
        Card(title: editingID == nil ? "Add Bill" : "Edit Bill") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Bill name", text: $draft.name).textFieldStyle(.roundedBorder).accessibilityLabel("Bill name")
                Picker("Category", selection: $draft.category) {
                    ForEach(ObligationCategory.allCases) { Text($0.rawValue).tag($0) }
                }
                NumberField(title: "Payment Amount", value: $draft.amount, prefix: m.currency.rawValue)
                Picker("Payment Frequency", selection: $draft.frequency) {
                    ForEach(ObligationFrequency.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Include remaining balance", isOn: $showBalance)
                if showBalance {
                    NumberField(title: "Remaining Balance", value: Binding(get: { draft.remainingBalance ?? 0 }, set: { draft.remainingBalance = $0 }), prefix: m.currency.rawValue)
                    Toggle("Include APR", isOn: $showAPR)
                    if showAPR {
                        NumberField(title: "Interest Rate (APR)", value: Binding(get: { draft.apr ?? 0 }, set: { draft.apr = $0 }), suffix: "%")
                    }
                }
                Toggle("Auto-Pay", isOn: $draft.autoPay)
                Text("Auto-Pay is a label only; this app does not make payments.").font(.caption).foregroundStyle(.secondary)
                TextField("Notes (optional)", text: $draft.notes, axis: .vertical).textFieldStyle(.roundedBorder).accessibilityLabel("Bill notes")
                if let validationError { Text(validationError).font(.footnote).foregroundStyle(.red) }
                HStack {
                    Button("Save Bill") { save() }.buttonStyle(.borderedProminent)
                    Button("Cancel") { withAnimation { showForm = false }; validationError = nil }
                }
            }
        }
    }
    private func save() {
        var bill = draft
        bill.name = bill.name.trimmingCharacters(in: .whitespacesAndNewlines)
        bill.remainingBalance = showBalance ? (bill.remainingBalance ?? 0) : nil
        bill.apr = showBalance && showAPR ? (bill.apr ?? 0) : nil
        if let error = bill.validationMessage { validationError = error; return }
        if let id = editingID, let index = m.obligations.firstIndex(where: { $0.id == id }) {
            m.obligations[index] = bill
        } else {
            guard m.obligations.count < 1000 else { validationError = "Your plan can contain up to 1,000 bills."; return }
            m.obligations.append(bill)
        }
        withAnimation { showForm = false }
        editingID = nil; validationError = nil
    }
    private func billCard(_ bill: RecurringObligation) -> some View {
        Card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: bill.category.icon).font(.title2).foregroundStyle(bill.category.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(bill.name).font(.headline)
                    Text(bill.category.rawValue).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(bill.category.color.opacity(0.12), in: Capsule())
                    if bill.autoPay { Label("Auto-Pay", systemImage: "arrow.triangle.2.circlepath").font(.caption) }
                }
                Spacer(minLength: 4)
                Menu {
                    Button("Edit", systemImage: "pencil") {
                        draft = bill; editingID = bill.id
                        showBalance = bill.remainingBalance != nil; showAPR = bill.apr != nil
                        validationError = nil; withAnimation { showForm = true }
                    }
                    Button("Duplicate", systemImage: "doc.on.doc") {
                        draft = bill; draft.id = UUID(); draft.name += " (copy)"; editingID = nil
                        showBalance = bill.remainingBalance != nil; showAPR = bill.apr != nil
                        validationError = nil; withAnimation { showForm = true }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleteID = bill.id }
                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Actions for \(bill.name)")
            }
            Text("\(m.money(bill.amount)) / \(bill.frequency.rawValue.lowercased())")
                .font(.system(.subheadline, design: .monospaced).bold())
            Text("\(m.money(bill.monthlyAmount)) monthly equivalent").font(.caption).foregroundStyle(.secondary)
            if !bill.notes.isEmpty { Text(bill.notes).font(.footnote).foregroundStyle(.secondary) }
            if let balance = bill.remainingBalance {
                Divider()
                SummaryRow(label: "Remaining Balance", value: m.money(balance))
                if let payoff = bill.payoff {
                    Text(payoff.months == 0 ? "Paid off" : "Estimated payoff: \(payoff.months) months")
                        .font(.footnote.bold())
                    if let date = payoff.date(), payoff.months > 0 {
                        Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                    }
                    SummaryRow(label: "Estimated Interest", value: m.money(payoff.interest))
                    ProgressView(value: balance > 0 ? min(max((bill.monthlyAmount - balance * (bill.apr ?? 0) / 1200) / balance, 0), 1) : 1)
                    Text("Projected share of remaining principal covered in one month. Assumes unchanged payments and APR.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("No payoff within 100 years at this payment; it may not cover monthly interest.")
                        .font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }
}
