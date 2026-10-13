import SwiftUI

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
    case normal = "Normal Day", first = "First Day", setup = "Setup", recurring = "Recurring"
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
            case .recurring: recurring
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
                CustomExpenseEditor(items: $m.dailyExtras, currency: cur, frequency: .daily)
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
                CustomExpenseEditor(items: $m.arrivalExtras, currency: cur, frequency: .yearly, recurring: false)
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
                CustomExpenseEditor(items: $m.setupExtras, currency: cur, frequency: .yearly, recurring: false)
            }
            Card(title: "Setup Cost Total") {
                Text(m.money(m.setupTotal))
                    .font(.system(size: 32, weight: .heavy, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }
        }
    }
    private var recurring: some View {
        VStack(spacing: 12) {
            Card {
                Text("Include bills, subscriptions, credit cards and loan payments not already counted elsewhere.")
                    .font(.footnote).foregroundStyle(.secondary)
                CustomExpenseEditor(items: $m.recurringExtras, currency: cur, frequency: .monthly)
            }
            Card(title: "Recurring Summary") {
                SummaryRow(label: "Monthly", value: m.money(m.recurringMonthly), bold: true)
                SummaryRow(label: "Yearly", value: m.money(m.recurringYearly))
                Text("Weekly figures allocate recurring costs evenly; actual due dates may differ.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct CustomExpenseEditor: View {
    @Binding var items: [CustomExpense]
    let currency: String
    let frequency: ExpenseFrequency
    var recurring = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach($items) { $item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Expense name", text: $item.name).textFieldStyle(.roundedBorder)
                        Button(role: .destructive) { items.removeAll { $0.id == item.id } } label: {
                            Image(systemName: "trash")
                        }
                    }
                    NumberField(title: "Amount", value: $item.amount, prefix: currency)
                    if recurring {
                        Picker("Frequency", selection: $item.frequency) {
                            ForEach(ExpenseFrequency.allCases) { f in Text(f.rawValue.capitalized).tag(f) }
                        }
                        TextField("Category", text: $item.category).textFieldStyle(.roundedBorder)
                        Toggle("Autopay", isOn: $item.isAutopay)
                        Toggle("Set due date", isOn: Binding(
                            get: { item.dueDate != nil },
                            set: { item.dueDate = $0 ? Date() : nil }
                        ))
                        if item.dueDate != nil {
                            DatePicker("Due date", selection: Binding(
                                get: { item.dueDate ?? Date() },
                                set: { item.dueDate = $0 }
                            ), displayedComponents: .date)
                        }
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            Button { items.append(CustomExpense(frequency: frequency)) } label: {
                Label("Add Another", systemImage: "plus.circle")
            }
        }
    }
}

// MARK: - Dashboard

struct DashboardStep: View {
    @ObservedObject var m: ReloCalcModel

    var body: some View {
        VStack(spacing: 12) {
            gauge
            netSummary
            firstWeek
            runway
            breakEven
        }
    }

    private func netColor(_ n: Double) -> Color { n >= 0 ? .green : .red }

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
                row("Daily", m.netDaily, m.dailyExpense + m.recurringYearly / 365, m.dailyNet)
                row("Weekly", m.netWeekly, m.weeklyExpense + m.recurringWeekly, m.weeklyNet)
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
            SummaryRow(label: "Total Week 1 Expense", value: m.money(m.firstWeekExpense), bold: true)
            SummaryRow(label: "Income Week 1", value: m.money(m.netWeekly), color: .green)
            SummaryRow(label: "Net Week 1", value: m.signed(m.firstWeekNet), color: netColor(m.firstWeekNet))
        }
    }

    private var runway: some View {
        Card(title: "Runway") {
            SummaryRow(label: "Starting Savings", value: m.money(m.savings))
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
            Text("💡 You'll spend **\(m.weekExpensePct)%** of your first week's income on expenses. By week 2, this drops to **\(m.normalWeekExpensePct)%** as the special first-day costs are gone.")
                .font(.subheadline)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
