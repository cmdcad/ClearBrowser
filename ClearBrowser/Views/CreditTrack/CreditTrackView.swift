import SwiftUI
import UniformTypeIdentifiers

private enum CreditTab: String, CaseIterable {
    case cards = "Cards", summary = "Summary", reminders = "Reminders", history = "History"
    var icon: String {
        switch self {
        case .cards: return "creditcard.fill"
        case .summary: return "chart.pie.fill"
        case .reminders: return "bell.fill"
        case .history: return "clock.fill"
        }
    }
}

private struct CreditHistoryCreditor: Identifiable {
    let id: String
    let name: String
}

private struct CreditExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct CreditTrackView: View {
    let onClose: () -> Void
    @StateObject private var model = CreditTrackModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: CreditTab = .cards
    @State private var editingCard: CreditCard?
    @State private var addingCard = false
    @State private var payingCard: CreditCard?
    @State private var deletingCard: CreditCard?
    @State private var paidOffCard: CreditCard?
    @State private var addingReminder = false
    @State private var editingReminder: CreditReminder?
    @State private var historyFilter: String?
    @State private var importing = false
    @State private var pendingBackup: CreditBackup?
    @State private var exporting = false
    @State private var exportDocument = CreditExportDocument(data: Data())
    @State private var exportType: UTType = .json
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    switch tab {
                    case .cards: cardsContent
                    case .summary: summaryContent
                    case .reminders: remindersContent
                    case .history: historyContent
                    }
                }
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
                .padding(16)
                .padding(.bottom, 64)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(model.isRestoringCloud)
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.isRestoringCloud {
                    HStack { ProgressView(); Text("Checking saved CreditTrack data…").font(.caption) }
                        .frame(maxWidth: .infinity).padding(10).background(.bar)
                }
            }
            bottomBar
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottomTrailing) {
            if tab == .cards {
                Button { addingCard = true } label: {
                    Image(systemName: "plus").font(.title2).foregroundStyle(.white)
                        .frame(width: 52, height: 52).background(Color.blue.gradient, in: Circle())
                        .shadow(color: .blue.opacity(0.25), radius: 8, y: 4)
                }
                .accessibilityLabel("Add creditor")
                .disabled(model.isRestoringCloud)
                .padding(.trailing, 20).padding(.bottom, 76)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(.footnote).padding(12)
                    .foregroundStyle(.white).background(.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, 76).allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $addingCard) {
            CreditCardEditor(card: nil) { model.upsert($0); showToast("Creditor saved") }
        }
        .sheet(item: $editingCard) { card in
            CreditCardEditor(card: card) { model.upsert($0); showToast("Creditor saved") }
        }
        .sheet(item: $payingCard) { card in
            CreditPaymentConfirmation(card: card) {
                paidOffCard = model.pay(card.id)
                payingCard = nil
                showToast("Payment recorded")
            }
        }
        .sheet(isPresented: $addingReminder) {
            CreditReminderEditor(cards: model.active) { model.upsertReminder($0); showToast("Reminder saved") }
        }
        .sheet(item: $editingReminder) { reminder in
            CreditReminderEditor(cards: model.cards, reminder: reminder) {
                model.upsertReminder($0); showToast("Reminder updated")
            }
        }
        .alert("Delete creditor?", isPresented: Binding(get: { deletingCard != nil }, set: { if !$0 { deletingCard = nil } })) {
            Button("Cancel", role: .cancel) { deletingCard = nil }
            Button("Delete", role: .destructive) {
                if let card = deletingCard { model.delete(card) }
                deletingCard = nil; showToast("Creditor deleted")
            }
        } message: { Text("Payment history will be retained.") }
        .alert("Restore backup?", isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } })) {
            Button("Cancel", role: .cancel) { pendingBackup = nil }
            Button("Replace data", role: .destructive) {
                if let backup = pendingBackup {
                    do { try model.restore(backup); historyFilter = nil; showToast("Backup restored") }
                    catch { model.error = error.localizedDescription }
                }
                pendingBackup = nil
            }
        } message: { Text("This replaces your current cards, payments, and reminders.") }
        .alert("CreditTrack", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let backup = try JSONDecoder().decode(CreditBackup.self, from: Data(contentsOf: url))
                try backup.validate(); pendingBackup = backup
            } catch { model.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: exportType,
            defaultFilename: "CreditTrack-\(CreditDates.string(Date()))") { result in
                switch result {
                case .success: showToast("Export saved")
                case .failure(let error): model.error = error.localizedDescription
                }
            }
        .overlay {
            if let card = paidOffCard {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Text("🎉").font(.system(size: 64))
                        Text("Card Paid Off!").font(.title2.bold())
                        Text("Congratulations! You've paid off \(card.name).")
                            .multilineTextAlignment(.center)
                        Button("Awesome!") { withAnimation { paidOffCard = nil } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(28).frame(maxWidth: 400)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    .padding(24)
                    .transition(.scale.combined(with: .opacity))
                }
                .accessibilityAddTraits(.isModal)
            }
        }
        .animation(.spring(response: 0.4), value: paidOffCard?.id)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshNotifications(); model.refreshCloud() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) { Label("Apps", systemImage: "chevron.left") }
                .frame(minHeight: 44)
            Spacer()
            Label("CreditTrack", systemImage: "creditcard.fill").font(.headline)
            Spacer()
        }
        .foregroundStyle(.white).padding(.horizontal, 20).padding(.vertical, 8)
        .background(LinearGradient(colors: [.blue, Color(red: 0.05, green: 0.28, blue: 0.63)], startPoint: .leading, endPoint: .trailing))
    }
    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(CreditTab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon).font(.system(size: 20))
                        Text(item.rawValue).font(.caption2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(tab == item ? Color.blue : Color.secondary)
                    .background(tab == item ? Color.blue.opacity(0.08) : Color.clear)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }.background(.bar)
    }
    private var cardsContent: some View {
        VStack(spacing: 14) {
            if model.cards.isEmpty {
                CreditEmptyState(icon: "creditcard", title: "No credit cards yet", message: "Tap + to add your first creditor")
            } else {
                ForEach(model.cards.sorted { lhs, rhs in
                    if lhs.isActive != rhs.isActive { return lhs.isActive }
                    return lhs.dueDate < rhs.dueDate
                }) { card in
                    Card {
                        HStack {
                            Text(card.name).font(.headline)
                            Spacer()
                            Text(card.status).font(.caption2.bold())
                                .padding(6).foregroundStyle(card.tint)
                                .background(card.tint.opacity(0.12), in: Capsule())
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(CreditDates.money(card.fixedPayment)).monospacedDigit().bold()
                                Text(card.period.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(card.due, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption).foregroundStyle(card.tint)
                        }
                        if card.initialTotal != nil {
                            ProgressView(value: card.progress).tint(card.tint)
                            HStack {
                                Text("\(CreditDates.money(card.remaining ?? 0)) remaining")
                                Spacer()
                                Text("\(Int(card.progress * 100))%")
                            }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        HStack {
                            if card.isActive {
                                Button { payingCard = card } label: {
                                    Label("Mark Paid", systemImage: "checkmark.circle")
                                        .frame(maxWidth: .infinity, minHeight: 32)
                                }.buttonStyle(.borderedProminent)
                            } else { Text("Congratulations!").foregroundStyle(.green); Spacer() }
                            Button { editingCard = card } label: { Image(systemName: "pencil").frame(width: 36, height: 36) }
                                .buttonStyle(.bordered).accessibilityLabel("Edit \(card.name)")
                            Button(role: .destructive) { deletingCard = card } label: { Image(systemName: "trash").frame(width: 36, height: 36) }
                                .buttonStyle(.bordered).accessibilityLabel("Delete \(card.name)")
                        }
                    }
                }
            }
        }
    }
    private var summaryContent: some View {
        VStack(spacing: 16) {
            Card(title: "Total debt") {
                Text(CreditDates.money(model.debt)).font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(model.debt > 0 ? .red : .green).frame(maxWidth: .infinity)
                ProgressView(value: model.initial > 0 ? model.paid / model.initial : 0).tint(.green)
                Text("\(CreditDates.money(model.paid)) paid of \(CreditDates.money(model.initial))")
                    .font(.caption).foregroundStyle(.secondary)
                if model.active.contains(where: { $0.initialTotal == nil }) {
                    Text("Cards without starting balances are excluded from debt and payoff estimates.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Card(title: "Monthly snapshot") {
                CreditValueRow(title: "Total Monthly Payments", value: CreditDates.money(model.active.reduce(0) { $0 + $1.fixedPayment }))
                Text("Sum of active fixed payments; billing cycles may differ.").font(.caption).foregroundStyle(.secondary)
                CreditValueRow(title: "Cards Active", value: "\(model.active.count)")
                CreditValueRow(title: "Cards Paid Off", value: "\(model.cards.count - model.active.count)")
                CreditValueRow(title: "Next Payment Due", value: model.active.first?.due.formatted(date: .abbreviated, time: .omitted) ?? "None")
            }
            Card(title: "Payoff timeline") {
                ForEach(model.active) { card in
                    HStack {
                        Text(card.name)
                        Spacer()
                        Text(card.remaining.map { "\(Int(ceil($0 / card.fixedPayment))) months left" } ?? "Balance not set")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: card.progress).tint(card.tint)
                }
                if let payoff = payoffDate {
                    Label("Debt-free by: \(payoff.formatted(date: .abbreviated, time: .omitted))", systemImage: "target")
                        .font(.subheadline).foregroundStyle(.green)
                } else { Text(model.active.isEmpty ? "No outstanding debt." : "Set starting balances for an estimate.").foregroundStyle(.secondary) }
                Text("Estimate assumes monthly payments, excludes interest, and includes only known balances.").font(.caption).foregroundStyle(.secondary)
            }
            Card(title: "This month") {
                ForEach(model.active) { card in
                    HStack {
                        Image(systemName: paidThisMonth(card) ? "checkmark.circle.fill" : card.daysUntilDue <= 0 ? "exclamationmark.triangle.fill" : "square")
                            .foregroundStyle(paidThisMonth(card) ? .green : card.tint)
                        VStack(alignment: .leading) {
                            Text(card.name)
                            Text(card.due, format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(CreditDates.money(card.fixedPayment)).monospacedDigit()
                    }
                }
                if model.active.isEmpty { Text("No payments scheduled.").foregroundStyle(.secondary) }
            }
            Card(title: "Cloud backup") {
                Label(model.syncStatus, systemImage: "icloud")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Cards, payments, and reminder settings sync to your signed-in ClearBrowser account. Future notifications are recreated after restoration.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Refresh Cloud Backup") { model.refreshCloud() }.buttonStyle(.bordered)
                    .disabled(model.isRestoringCloud)
            }
            Card(title: "Export & backup") {
                exportButton("CSV Export", subtitle: "For Excel, Google Sheets", icon: "tablecells", color: .green) {
                    exportDocument = CreditExportDocument(data: model.exportCSV()); exportType = .commaSeparatedText; exporting = true
                }
                exportButton("JSON Backup", subtitle: "Save & restore later", icon: "archivebox", color: .orange) {
                    do { exportDocument = CreditExportDocument(data: try model.exportJSON()); exportType = .json; exporting = true }
                    catch { model.error = error.localizedDescription }
                }
                exportButton("Import Backup", subtitle: "Restore saved JSON", icon: "square.and.arrow.down", color: .purple) { importing = true }
            }
        }
    }
    private var payoffDate: Date? {
        model.active.compactMap { card -> Date? in
            guard let remaining = card.remaining else { return nil }
            let months = ceil(remaining / card.fixedPayment)
            guard months < 120_000 else { return nil }
            return Calendar.current.date(byAdding: .month, value: Int(months), to: Date())
        }.max()
    }
    private func paidThisMonth(_ card: CreditCard) -> Bool {
        let prefix = String(CreditDates.string(Date()).prefix(7))
        return model.payments.contains { $0.cardId == card.id && $0.paidDate.hasPrefix(prefix) }
    }
    private var remindersContent: some View {
        VStack(spacing: 16) {
            Card(title: "Notifications") {
                switch model.notificationStatus {
                case .notDetermined:
                    Text("Get payment reminders even when CreditTrack is closed.")
                    Button("Enable Notifications") { model.requestNotifications() }.buttonStyle(.borderedProminent)
                case .denied:
                    Text("Notifications are blocked. Enable them for ClearBrowser in Settings.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.buttonStyle(.bordered)
                default:
                    Label("Notifications enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Text("Alerts are scheduled for each card’s next due date and refreshed when you record a payment.")
                    .font(.caption).foregroundStyle(.secondary)
                if let note = model.notificationNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                Text("Past reminder times are skipped.").font(.caption).foregroundStyle(.secondary)
            }
            if model.reminders.isEmpty {
                CreditEmptyState(icon: "bell", title: "No reminders yet", message: "Choose when you want a payment reminder.")
            }
            ForEach(model.reminders) { reminder in
                Card {
                    HStack {
                        Button { editingReminder = reminder } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(reminder.label).font(.headline)
                                    Image(systemName: "pencil").font(.caption).foregroundStyle(.blue)
                                }
                                Text(reminder.time, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                                Text(reminder.appliesToAll ? "All cards" : (model.cards.first { $0.id == reminder.specificCardId }?.name ?? "Deleted creditor") + " only")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !reminder.isEnabled {
                                    Text("Paused").font(.caption).foregroundStyle(.secondary)
                                } else if let next = model.nextReminderDates[reminder.id] {
                                    Text("Next alert: \(next.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("No upcoming alert scheduled").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit reminder: \(reminder.label)")
                        .accessibilityHint("Change the time, days before payment, or cards.")
                        Spacer(minLength: 4)
                        Toggle("Enable reminder", isOn: Binding(get: { reminder.isEnabled }, set: { model.toggleReminder(reminder.id, enabled: $0) }))
                            .labelsHidden().fixedSize().tint(.green)
                        Button(role: .destructive) { model.deleteReminder(reminder.id) } label: {
                            Image(systemName: "xmark").frame(width: 44, height: 44)
                        }.accessibilityLabel("Delete reminder")
                    }
                }
            }
            Button { addingReminder = true } label: { Label("Add Reminder", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 36) }
                .buttonStyle(.borderedProminent)
        }
    }
    private var filteredPayments: [CreditPayment] {
        model.payments.filter { historyFilter == nil || $0.cardId == historyFilter }.sorted { $0.paidDate > $1.paidDate }
    }
    private var historyMonths: [String] { Array(Set(filteredPayments.map { String($0.paidDate.prefix(7)) })).sorted(by: >) }
    private var historyCreditors: [CreditHistoryCreditor] {
        var result = model.cards.map { CreditHistoryCreditor(id: $0.id, name: $0.name) }
        for payment in model.payments where !result.contains(where: { $0.id == payment.cardId }) {
            result.append(CreditHistoryCreditor(id: payment.cardId, name: model.name(for: payment)))
        }
        return result
    }
    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    filterButton("All", id: nil)
                    ForEach(historyCreditors, id: \.id) { creditor in filterButton(creditor.name, id: creditor.id) }
                }
            }
            if filteredPayments.isEmpty {
                CreditEmptyState(icon: "clock", title: "No payments yet", message: "Payments appear here when you mark a card as paid.")
            }
            ForEach(historyMonths, id: \.self) { month in
                Text(CreditDates.date(month + "-01")?.formatted(.dateTime.month(.wide).year()).uppercased() ?? month)
                    .font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(filteredPayments.filter { $0.paidDate.hasPrefix(month) }) { payment in
                    Card {
                        Label(model.name(for: payment), systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
                        Text("\(CreditDates.money(payment.amount)) · \(CreditDates.date(payment.paidDate)?.formatted(date: .abbreviated, time: .omitted) ?? payment.paidDate)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Balance: \(payment.balanceBefore.map(CreditDates.money) ?? "Not set") → \(payment.balanceAfter.map(CreditDates.money) ?? "Not set")")
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private func filterButton(_ name: String, id: String?) -> some View {
        Button(name) { historyFilter = id }.buttonStyle(.bordered)
            .tint(historyFilter == id ? .blue : .gray).frame(minHeight: 44)
    }
    private func exportButton(_ title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }.frame(minHeight: 44).padding(10)
        }.buttonStyle(.plain).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
    private func showToast(_ message: String) {
        toastTask?.cancel(); toast = message
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { toast = nil }
        }
    }
}

private extension CreditCard {
    var tint: Color { !isActive ? .green : daysUntilDue < 0 ? .red : daysUntilDue <= 3 ? .orange : .green }
}
private struct CreditValueRow: View {
    let title: String
    let value: String
    var body: some View { HStack { Text(title).font(.subheadline); Spacer(); Text(value).font(.subheadline).monospacedDigit().bold() } }
}
private struct CreditEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(.vertical, 50).frame(maxWidth: .infinity)
    }
}

private struct CreditCardEditor: View {
    @Environment(\.dismiss) private var dismiss
    let card: CreditCard?
    let onSave: (CreditCard) -> Void
    @State private var name: String
    @State private var total: String
    @State private var payment: String
    @State private var due: Date
    @State private var period: CreditPeriod
    @State private var validation: String?
    init(card: CreditCard?, onSave: @escaping (CreditCard) -> Void) {
        self.card = card; self.onSave = onSave
        _name = State(initialValue: card?.name ?? "")
        _total = State(initialValue: card?.initialTotal.map { String($0) } ?? "")
        _payment = State(initialValue: card.map { String($0.fixedPayment) } ?? "")
        _due = State(initialValue: card?.due ?? Date())
        _period = State(initialValue: card?.period ?? .monthly)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Creditor") { TextField("Creditor Name", text: $name) }
                Section("Amounts") {
                    TextField("Total Amount Owed ($) · optional", text: $total).keyboardType(.decimalPad)
                    TextField("Fixed Payment Amount ($)", text: $payment).keyboardType(.decimalPad)
                }
                Section("Schedule") {
                    DatePicker("Next Due Date", selection: $due, displayedComponents: .date)
                    Picker("Billing Period", selection: $period) { ForEach(CreditPeriod.allCases) { Text($0.title).tag($0) } }
                }
                if let validation { Text(validation).foregroundStyle(.red) }
            }
            .navigationTitle(card == nil ? "Add Creditor" : "Edit Creditor").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
    }
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTotal = total.trimmingCharacters(in: .whitespaces)
        let amount = Double(payment)
        let balance = normalizedTotal.isEmpty ? nil : Double(normalizedTotal)
        guard !trimmed.isEmpty, let amount, amount.isFinite, amount > 0, amount <= 1_000_000_000,
              normalizedTotal.isEmpty || (balance != nil && balance!.isFinite && balance! > 0 && balance! <= 1_000_000_000) else {
            validation = "Enter a creditor name and positive amounts up to $1 billion. The starting balance is optional."; return
        }
        var value = card ?? CreditCard(name: trimmed, initialTotal: balance, fixedPayment: amount, dueDate: CreditDates.string(due), period: period)
        value.name = trimmed; value.initialTotal = balance.map(CreditDates.rounded)
        value.fixedPayment = CreditDates.rounded(amount); value.dueDate = CreditDates.string(due); value.period = period
        guard value.fixedPayment > 0, value.initialTotal == nil || value.initialTotal! > 0 else { validation = "Amounts must be at least $0.01."; return }
        onSave(value); dismiss()
    }
}

private struct CreditPaymentConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    let card: CreditCard
    let onConfirm: () -> Void
    var after: Double? { card.remaining.map { max(0, CreditDates.rounded($0 - card.fixedPayment)) } }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Card(title: card.name) {
                    Text(CreditDates.money(card.fixedPayment)).font(.system(size: 34, weight: .bold, design: .monospaced))
                    Text(card.due, format: .dateTime.month(.wide).year()).foregroundStyle(.secondary)
                    CreditValueRow(title: "Remaining after payment", value: after.map(CreditDates.money) ?? "Not set")
                    CreditValueRow(title: "Next due date", value: after == 0 ? "Paid off" : card.period.advance(card.due).formatted(date: .abbreviated, time: .omitted))
                    if after == 0 { Label("This will pay off the card!", systemImage: "party.popper.fill").foregroundStyle(.green) }
                }
                Button(action: onConfirm) { Text("Confirm Payment").frame(maxWidth: .infinity, minHeight: 36) }.buttonStyle(.borderedProminent)
                Spacer()
            }.padding().background(Color(.systemGroupedBackground))
                .navigationTitle("Confirm Payment").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}

private struct CreditReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    let cards: [CreditCard]
    let reminder: CreditReminder?
    let onSave: (CreditReminder) -> Void
    @State private var daysBefore: Int
    @State private var time: Date
    @State private var scope: String

    init(cards: [CreditCard], reminder: CreditReminder? = nil, onSave: @escaping (CreditReminder) -> Void) {
        self.cards = cards
        self.reminder = reminder
        self.onSave = onSave
        _daysBefore = State(initialValue: reminder?.daysBefore ?? 0)
        _time = State(initialValue: reminder?.time ?? Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date())
        _scope = State(initialValue: reminder?.appliesToAll == false ? reminder?.specificCardId ?? "all" : "all")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("When?") {
                    Picker("Remind me", selection: $daysBefore) {
                        Text("Same day").tag(0)
                        Text("1 day before").tag(1)
                        Text("2 days before").tag(2)
                        Text("3 days before").tag(3)
                        Text("1 week before").tag(7)
                        if ![0, 1, 2, 3, 7].contains(daysBefore) {
                            Text("\(daysBefore) days before").tag(daysBefore)
                        }
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }
                Section("Apply to?") {
                    Picker("Cards", selection: $scope) {
                        Text("All cards").tag("all")
                        ForEach(cards) { Text($0.name + ($0.isActive ? " only" : " only (paid off)")).tag($0.id) }
                    }
                }
            }
            .navigationTitle(reminder == nil ? "Add Reminder" : "Edit Reminder").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                        var updated = reminder ?? CreditReminder(daysBefore: daysBefore, timeHour: parts.hour ?? 9, timeMinute: parts.minute ?? 0,
                            appliesToAll: scope == "all", specificCardId: scope == "all" ? nil : scope)
                        updated.daysBefore = daysBefore
                        updated.timeHour = parts.hour ?? 9
                        updated.timeMinute = parts.minute ?? 0
                        updated.appliesToAll = scope == "all"
                        updated.specificCardId = scope == "all" ? nil : scope
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}
