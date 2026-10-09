import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ReloCalcBackup: Codable {
    let version: String
    let exported: String?
    let started: Bool?
    let profile: Profile
    let income: Income
    let expenses: Expenses
    let firstDay: FirstDay
    let setup: Setup
    let weekly: Weekly

    struct Profile: Codable {
        let name: String
        let city: String
        let savings: Double
        let currency: String
    }

    struct Income: Codable {
        let wage: Double
        let hours: Double
        let workDays: Int
        let tax: Double
        let overtimeRate: Double
        let overtimeHours: Double

        enum CodingKeys: String, CodingKey {
            case wage
            case hours = "hrs"
            case workDays
            case tax
            case overtimeRate = "otRate"
            case overtimeHours = "otHours"
        }
    }

    struct Expenses: Codable {
        let transport: Double
        let food: Double
        let housing: Double
        let misc: Double
        let workDays: Int
        let housingType: String
    }

    struct FirstDay: Codable {
        let airportTransport: Double
        let airportToSite: Double
        let siteToHotel: Double
        let hotel: Double
        let food: Double
        let other: Double

        enum CodingKeys: String, CodingKey {
            case airportTransport = "f1"
            case airportToSite = "f2"
            case siteToHotel = "f3"
            case hotel = "f4"
            case food = "f5"
            case other = "f6"
        }
    }

    struct Setup: Codable {
        let deposit: Double
        let sim: Double
        let groceries: Double
        let equipment: Double
        let visa: Double

        enum CodingKeys: String, CodingKey {
            case deposit = "s1"
            case sim = "s2"
            case groceries = "s3"
            case equipment = "s4"
            case visa = "s5"
        }
    }

    struct Weekly: Codable {
        let startDay: Int
    }

    init(model: ReloCalcModel) {
        version = "1.0"
        exported = ISO8601DateFormatter().string(from: Date())
        started = true
        profile = Profile(
            name: model.userName,
            city: model.city,
            savings: model.savings,
            currency: model.currency.rawValue
        )
        income = Income(
            wage: model.wage,
            hours: model.hoursPerDay,
            workDays: model.incomeDays,
            tax: model.taxRate,
            overtimeRate: model.overtimeRate,
            overtimeHours: model.overtimeHours
        )
        expenses = Expenses(
            transport: model.transport,
            food: model.food,
            housing: model.housing,
            misc: model.misc,
            workDays: model.expenseDays,
            housingType: model.housingIsHotel ? "hotel" : "apt"
        )
        firstDay = FirstDay(
            airportTransport: model.toAirport,
            airportToSite: model.airportToSite,
            siteToHotel: model.siteToHotel,
            hotel: model.firstHotel,
            food: model.firstFood,
            other: model.firstOther
        )
        setup = Setup(
            deposit: model.deposit,
            sim: model.sim,
            groceries: model.groceries,
            equipment: model.equipment,
            visa: model.visa
        )
        weekly = Weekly(startDay: model.startDay)
    }

    func validate() throws {
        guard version == "1.0",
              let currency = Currency(rawValue: profile.currency),
              Currency.allCases.contains(currency) else {
            throw ReloCalcBackupError.unsupported
        }

        try requireNonnegative([
            ("savings", profile.savings),
            ("wage", income.wage),
            ("overtime rate", income.overtimeRate),
            ("overtime hours", income.overtimeHours),
            ("transport", expenses.transport),
            ("food", expenses.food),
            ("housing", expenses.housing),
            ("miscellaneous", expenses.misc),
            ("airport transport", firstDay.airportTransport),
            ("airport-to-site transport", firstDay.airportToSite),
            ("site-to-hotel transport", firstDay.siteToHotel),
            ("first-night hotel", firstDay.hotel),
            ("first-day food", firstDay.food),
            ("other first-day costs", firstDay.other),
            ("security deposit", setup.deposit),
            ("SIM / phone plan", setup.sim),
            ("groceries / supplies", setup.groceries),
            ("work equipment", setup.equipment),
            ("visa / permit fees", setup.visa)
        ])
        try requireRange("hours per day", income.hours, 1...24)
        try requireRange("tax rate", income.tax, 0...100)
        try requireRange("overtime hours", income.overtimeHours, 0...80)

        guard [4, 5].contains(income.workDays),
              [4, 5].contains(expenses.workDays),
              (0...6).contains(weekly.startDay),
              ["hotel", "apt"].contains(expenses.housingType) else {
            throw ReloCalcBackupError.invalidSchedule
        }
    }

    func apply(to model: ReloCalcModel) throws {
        guard let currency = Currency(rawValue: profile.currency) else {
            throw ReloCalcBackupError.unsupported
        }
        model.userName = profile.name
        model.city = profile.city
        model.savings = profile.savings
        model.currency = currency
        model.wage = income.wage
        model.hoursPerDay = income.hours
        model.incomeDays = income.workDays
        model.taxRate = income.tax
        model.overtimeRate = income.overtimeRate
        model.overtimeHours = income.overtimeHours
        model.transport = expenses.transport
        model.food = expenses.food
        model.housing = expenses.housing
        model.misc = expenses.misc
        model.expenseDays = expenses.workDays
        model.housingIsHotel = expenses.housingType == "hotel"
        model.toAirport = firstDay.airportTransport
        model.airportToSite = firstDay.airportToSite
        model.siteToHotel = firstDay.siteToHotel
        model.firstHotel = firstDay.hotel
        model.firstFood = firstDay.food
        model.firstOther = firstDay.other
        model.deposit = setup.deposit
        model.sim = setup.sim
        model.groceries = setup.groceries
        model.equipment = setup.equipment
        model.visa = setup.visa
        model.startDay = weekly.startDay
    }

    private func requireNonnegative(_ values: [(String, Double)]) throws {
        for (name, value) in values {
            guard value.isFinite, value >= 0 else {
                throw ReloCalcBackupError.invalidNumber(name)
            }
        }
    }

    private func requireRange(_ name: String, _ value: Double, _ range: ClosedRange<Double>) throws {
        guard value.isFinite, range.contains(value) else {
            throw ReloCalcBackupError.invalidNumber(name)
        }
    }
}

enum ReloCalcBackupError: LocalizedError {
    case unsupported
    case invalidSchedule
    case invalidNumber(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "This file is not a supported ReloCalc version 1.0 backup."
        case .invalidSchedule:
            return "The backup contains an invalid workweek, housing type, or start day."
        case .invalidNumber(let field):
            return "The backup contains an invalid value for \(field)."
        }
    }
}

enum ReloCalcExportFormat: String, CaseIterable, Identifiable {
    case csv
    case text
    case json

    var id: Self { self }

    var title: String {
        switch self {
        case .csv: return "CSV Spreadsheet"
        case .text: return "Text Summary"
        case .json: return "JSON Backup"
        }
    }

    var detail: String {
        switch self {
        case .csv: return "Export your calculations as a spreadsheet."
        case .text: return "Preview, save, or share a readable report."
        case .json: return "Save your inputs or transfer them to another device."
        }
    }

    var symbol: String {
        switch self {
        case .csv: return "tablecells"
        case .text: return "text.alignleft"
        case .json: return "curlybraces"
        }
    }

    var filename: String {
        switch self {
        case .csv: return "ReloCalc_Report"
        case .text: return "ReloCalc_Summary"
        case .json: return "ReloCalc_Backup"
        }
    }

    var contentType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .text: return .plainText
        case .json: return .json
        }
    }

    func data(for model: ReloCalcModel) throws -> Data {
        switch self {
        case .csv:
            return Data(csvReport(for: model).utf8)
        case .text:
            return Data(textReport(for: model).utf8)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(ReloCalcBackup(model: model))
        }
    }

    func preview(for model: ReloCalcModel) -> String? {
        switch self {
        case .csv: return csvReport(for: model)
        case .text: return textReport(for: model)
        case .json: return nil
        }
    }

    private func csvReport(for model: ReloCalcModel) -> String {
        var rows: [[String]] = [
            ["ReloCalc Financial Report"],
            ["Generated", ISO8601DateFormatter().string(from: Date())],
            ["Name", model.userName.isEmpty ? "N/A" : model.userName],
            ["City", model.city.isEmpty ? "N/A" : model.city],
            ["Currency", model.currency.rawValue],
            ["Starting Savings", number(model.savings)],
            [],
            ["=== INCOME ==="],
            ["Hourly Wage", number(model.wage)],
            ["Hours / Day", number(model.hoursPerDay)],
            ["Work Days / Week", String(model.incomeDays)],
            ["Tax Rate", number(model.taxRate) + "%"],
            ["Period", "Gross", "Net"],
            ["Daily", number(model.grossDaily), number(model.netDaily)],
            ["Weekly", number(model.grossWeekly), number(model.netWeekly)],
            ["Monthly", number(model.grossMonthly), number(model.netMonthly)],
            ["Yearly", number(model.grossYearly), number(model.netYearly)],
            [],
            ["=== DAILY EXPENSES ==="],
            ["Transport", number(model.transport)],
            ["Food", number(model.food)],
            ["Housing", number(model.housing)],
            ["Miscellaneous", number(model.misc)],
            ["Workday Total", number(model.dailyExpense)],
            ["Rest Day Total", number(model.reducedDailyExpense)],
            ["Expense Work Days / Week", String(model.expenseDays)],
            ["Weekly", number(model.weeklyExpense)],
            ["Monthly", number(model.monthlyExpense)],
            ["Yearly", number(model.yearlyExpense)],
            [],
            ["=== FIRST DAY ==="],
            ["Transport (3 legs)", number(model.firstDayTransport)],
            ["Hotel", number(model.firstHotel)],
            ["Food", number(model.firstFood)],
            ["Other", number(model.firstOther)],
            ["Total", number(model.firstDayTotal)],
            [],
            ["=== SETUP COSTS ==="],
            ["Security Deposit", number(model.deposit)],
            ["SIM / Phone Plan", number(model.sim)],
            ["Groceries / Supplies", number(model.groceries)],
            ["Work Equipment", number(model.equipment)],
            ["Visa / Permit Fees", number(model.visa)],
            ["Total One-Time", number(model.setupTotal)],
            [],
            ["=== DASHBOARD ==="],
            ["Feasibility Score", "\(model.score)%"],
            ["Status", model.verdict.title],
            ["Daily Net", number(model.dailyNet)],
            ["Weekly Net", number(model.weeklyNet)],
            ["Monthly Net", number(model.monthlyNet)],
            ["Yearly Net", number(model.yearlyNet)],
            ["Relocation Cost", number(model.relocationCost)],
            ["Break-Even", model.breakEvenDays.map { String($0) } ?? "Never"],
            [],
            ["=== FIRST WEEK ==="],
            ["Day", "Income", "Expense", "Net"]
        ]

        for row in model.weekRows {
            rows.append([
                row.name + (row.isFirst ? " *" : ""),
                number(row.income),
                number(row.expense),
                number(row.net)
            ])
        }
        rows.append([
            "TOTAL",
            number(model.weekIncome),
            number(model.weekExpense),
            number(model.weekIncome - model.weekExpense)
        ])
        return rows.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n")
    }

    private func textReport(for model: ReloCalcModel) -> String {
        let dayNames = model.weekRows.map { $0.name }
        var lines = [
            "RELOCALC FINANCIAL REPORT",
            "",
            "Name: \(model.userName.isEmpty ? "N/A" : model.userName) | City: \(model.city.isEmpty ? "N/A" : model.city)",
            "Generated: \(Date.now.formatted(date: .numeric, time: .omitted))",
            "Starting Savings: \(model.money(model.savings))",
            "",
            "FEASIBILITY SCORE",
            "\(model.score)% — \(model.verdict.title)",
            "",
            "INCOME (\(model.incomeDays) workdays/week)",
            "Hourly: \(model.money(model.wage))/hr × \(model.hoursPerDay) hrs",
            "Daily: \(model.money(model.netDaily)) net",
            "Weekly: \(model.money(model.netWeekly)) net",
            "Monthly: \(model.money(model.netMonthly)) net",
            "Yearly: \(model.money(model.netYearly)) net",
            "",
            "EXPENSES (\(model.expenseDays) full-cost days/week)",
            "Transport: \(model.money(model.transport))/workday",
            "Food: \(model.money(model.food))/day",
            "Housing: \(model.money(model.housing))/day",
            "Miscellaneous: \(model.money(model.misc))/workday",
            "Workday total: \(model.money(model.dailyExpense))",
            "Rest day total: \(model.money(model.reducedDailyExpense))",
            "Weekly: \(model.money(model.weeklyExpense))",
            "Monthly: \(model.money(model.monthlyExpense))",
            "",
            "FIRST DAY",
            "Total: \(model.money(model.firstDayTotal)) (vs normal workday \(model.signed(model.firstDayDiff)))",
            "",
            "SETUP COSTS",
            "One-time: \(model.money(model.setupTotal))",
            "",
            "NET INCOME",
            "Daily: \(model.signed(model.dailyNet))",
            "Weekly: \(model.signed(model.weeklyNet))",
            "Monthly: \(model.signed(model.monthlyNet))",
            "Yearly: \(model.signed(model.yearlyNet))",
            "",
            "ANALYSIS",
            "Relocation cost: \(model.money(model.relocationCost))",
            "Break-even: \(model.breakEvenDays.map { "Day \($0)" } ?? "Never")",
            model.monthsUntilDepleted.map { "Funds deplete in \(String(format: "%.1f", $0)) months" }
                ?? "Net Positive — Savings grow over time",
            "",
            "FIRST WEEK",
            "Day | Income | Expense | Net"
        ]

        for (index, row) in model.weekRows.enumerated() {
            let name = dayNames[index] + (row.isFirst ? " *" : "")
            lines.append("\(name) | \(model.money(row.income)) | \(model.money(row.expense)) | \(model.signed(row.net))")
        }
        lines.append("TOTAL | \(model.money(model.weekIncome)) | \(model.money(model.weekExpense)) | \(model.signed(model.weekIncome - model.weekExpense))")
        return lines.joined(separator: "\n")
    }

    private func number(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func csvCell(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

struct ReloCalcExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText, .plainText]
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ReloCalcExportStep: View {
    @ObservedObject var model: ReloCalcModel
    @State private var exportFormat: ReloCalcExportFormat = .json
    @State private var exportData = Data()
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var preview: ReportPreview?
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            Card(title: "Your data is saved on this device") {
                Text("Your current inputs stay on this device automatically. Export a JSON backup to move your plan to another device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(model.autosaveError ?? statusMessage ?? "Autosave is on for this device.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(model.autosaveError == nil ? (statusMessage == nil ? .green : .secondary) : .red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            Card(title: "Export a report") {
                ForEach(ReloCalcExportFormat.allCases) { format in
                    exportButton(format)
                }
            }

            Card(title: "Restore your plan") {
                Text("Import a version 1.0 ReloCalc JSON backup. This replaces the current plan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    isImporting = true
                } label: {
                    exportRow(
                        title: "Import Backup",
                        detail: "Restore inputs from a ReloCalc JSON backup.",
                        symbol: "square.and.arrow.down",
                        tint: .purple
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: ReloCalcExportDocument(data: exportData),
            contentType: exportFormat.contentType,
            defaultFilename: exportFormat.filename
        ) { result in
            switch result {
            case .success:
                statusMessage = "\(exportFormat.title) saved."
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importBackup(result)
        }
        .sheet(item: $preview) { report in
            NavigationStack {
                ScrollView {
                    Text(report.text)
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(report.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { preview = nil }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack {
                            ShareLink(item: report.text)
                            Button("Save") { beginExport(report.format) }
                        }
                    }
                }
            }
        }
        .alert("Couldn’t complete file operation", isPresented: isShowingError) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown file error occurred.")
        }
    }

    private func exportButton(_ format: ReloCalcExportFormat) -> some View {
        Button {
            if let report = format.preview(for: model) {
                preview = ReportPreview(format: format, text: report)
            } else {
                beginExport(format)
            }
        } label: {
            exportRow(
                title: format.title,
                detail: format.detail,
                symbol: format.symbol,
                tint: format == .csv ? .green : (format == .text ? .blue : .orange)
            )
        }
        .buttonStyle(.plain)
    }

    private func exportRow(title: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func beginExport(_ format: ReloCalcExportFormat) {
        do {
            exportData = try format.data(for: model)
            exportFormat = format
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else {
                throw CocoaError(.fileNoSuchFile)
            }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let backup = try JSONDecoder().decode(ReloCalcBackup.self, from: data)
            try backup.validate()
            try backup.apply(to: model)
            statusMessage = "Backup restored."
        } catch is CancellationError {
            return
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

private struct ReportPreview: Identifiable {
    let id = UUID()
    let format: ReloCalcExportFormat
    let text: String

    var title: String { "\(format.title) Preview" }
}
