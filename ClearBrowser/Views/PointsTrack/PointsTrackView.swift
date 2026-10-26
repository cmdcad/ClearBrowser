import SwiftUI

@MainActor
struct PointsTrackView: View {
    let onClose: () -> Void
    @StateObject private var model = PointsTrackModel()
    @AppStorage("PointsTrack.projectionDays") private var days = 365
    @State private var editing: PointsCategory?
    @State private var deleting: PointsCategory?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) { Label("Apps", systemImage: "chevron.left") }
                Spacer()
                Text("PointsTrack").font(.headline)
                Spacer()
                Button { editing = PointsCategory(name: "") } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add points category")
            }.padding()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summary
                    projection
                    HStack {
                        Text("Categories").font(.title2.bold())
                        Spacer()
                        Button("Add") { editing = PointsCategory(name: "") }
                    }
                    if model.categories.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Start with an account or rewards program").font(.headline)
                            Text("Add a category such as Hotmail, enter its current points, and set its daily maximum and reward conversion.")
                                .foregroundStyle(.secondary)
                            Button("Add category") { editing = PointsCategory(name: "") }.buttonStyle(.borderedProminent)
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                    ForEach(model.categories) { category in categoryCard(category) }
                }.padding().frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $editing) { category in
            PointsCategoryEditor(category: category) { model.save($0) }
        }
        .alert("PointsTrack", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("Delete \(deleting?.name ?? "category")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete category", role: .destructive) {
                if let deleting { model.delete(deleting) }
                deleting = nil
            }
        } message: { Text("This removes the category and its saved balance.") }
        .onChange(of: days) { _, value in days = min(36_500, max(0, value)) }
        .onAppear { days = min(36_500, max(0, days)) }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current points value").font(.subheadline)
            Text(PointsFormat.money(PointsCategory.totalValue(model.categories))).font(.largeTitle.bold())
                .contentTransition(.numericText())
            metric("Redeemable in whole rewards", PointsFormat.money(PointsCategory.totalRedeemable(model.categories)))
            Divider()
            Text("Value includes partial rewards. Redeemable value counts complete reward units within each category.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
    }

    private var projection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What could I have?").font(.title3.bold())
            HStack {
                ForEach([30, 90, 365], id: \.self) { value in
                    Button(value == 365 ? "1 year" : "\(value) days") { days = value }
                        .buttonStyle(.bordered).tint(days == value ? .teal : .gray)
                }
            }
            HStack {
                Text("Days from now")
                Spacer()
                TextField("Days", value: $days, format: .number.grouping(.never))
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 100)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Projection days")
            }
            let projected = PointsCategory.totalValue(model.categories, days: days)
            metric("Projected total", PointsFormat.money(projected), prominent: true)
            metric("Additional value", PointsFormat.money(projected - PointsCategory.totalValue(model.categories)))
            metric("Whole rewards available", PointsFormat.money(PointsCategory.totalRedeemable(model.categories, days: days)))
            Text("Assumes you earn each category’s daily maximum every day and its monthly bonus for each completed 30-day period, with unchanged conversion rates and no redemptions or expiry. One year means 365 days. Updating the projection does not change your saved balances.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func categoryCard(_ category: PointsCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.name).font(.headline)
                Spacer()
                Menu {
                    Button("Edit balance and settings") { editing = category }
                    Button("Delete", role: .destructive) { deleting = category }
                } label: { Image(systemName: "ellipsis.circle").font(.title2) }
                    .accessibilityLabel("Options for \(category.name)")
            }
            metric("Current points", PointsFormat.number(category.currentPoints))
            metric("Current value", PointsFormat.money(category.value()))
            metric("Redeemable now", PointsFormat.money(category.redeemable()))
            Text("\(PointsFormat.number(category.pointsPerReward)) points = \(PointsFormat.money(category.rewardDollars)) · Up to \(PointsFormat.number(category.dailyPoints))/day + \(PointsFormat.number(category.monthlyBonusPoints))/month")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            metric("In \(days) days", PointsFormat.money(category.value(after: days)), prominent: true)
            Text("\(PointsFormat.number(category.points(after: days))) projected points")
                .font(.caption).foregroundStyle(.secondary)
            Button("Update balance") { editing = category }.font(.subheadline)
        }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func metric(_ label: String, _ value: String, prominent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(prominent ? .bold : .semibold).multilineTextAlignment(.trailing)
        }.font(prominent ? .headline : .subheadline)
    }
}

private struct PointsCategoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    private let original: PointsCategory
    private let onSave: (PointsCategory) -> Bool
    @State private var name: String
    @State private var balance: String
    @State private var daily: String
    @State private var monthlyBonus: String
    @State private var units: String
    @State private var dollars: String
    @State private var saveError: String?

    init(category: PointsCategory, onSave: @escaping (PointsCategory) -> Bool) {
        original = category
        self.onSave = onSave
        _name = State(initialValue: category.name)
        _balance = State(initialValue: category.currentPoints == 0 ? "" : PointsFormat.input(category.currentPoints))
        _daily = State(initialValue: category.dailyPoints == 0 ? "" : PointsFormat.input(category.dailyPoints))
        _monthlyBonus = State(initialValue: category.monthlyBonusPoints == 0 ? "" : PointsFormat.input(category.monthlyBonusPoints))
        _units = State(initialValue: PointsFormat.input(category.pointsPerReward))
        _dollars = State(initialValue: PointsFormat.input(category.rewardDollars))
    }

    private var draft: PointsCategory? {
        guard let balance = parseZeroAllowed(balance), let daily = parseZeroAllowed(daily),
              let monthlyBonus = parseZeroAllowed(monthlyBonus),
              let units = PointsFormat.parse(units), let dollars = PointsFormat.parse(dollars) else { return nil }
        var category = original
        category.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        category.currentPoints = balance
        category.dailyPoints = daily
        category.monthlyBonusPoints = monthlyBonus
        category.pointsPerReward = units
        category.rewardDollars = dollars
        return category.isValid ? category : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") { TextField("Name, e.g. Hotmail", text: $name) }
                Section("Points") {
                    field("Currently earned", value: $balance)
                    field("Maximum per day", value: $daily)
                    field("Monthly search bonus", value: $monthlyBonus)
                }
                Section {
                    field("Points per reward", value: $units)
                    field("Reward value (USD)", value: $dollars)
                } header: { Text("Conversion") } footer: { Text("Default: 6,500 points = $5. Each category can use a different conversion. The default monthly search bonus is 1,250 points.") }
                if let draft {
                    Section("Current balance value") {
                        LabeledContent("Estimated value", value: PointsFormat.money(draft.value()))
                        LabeledContent("Whole rewards", value: PointsFormat.money(draft.redeemable()))
                    }
                } else {
                    Text("Enter a name and valid amounts. Balances and daily points may be zero; conversion amounts must be at least 0.000001. Maximum per field: 1 trillion. Enter numbers without grouping separators.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let saveError { Text(saveError).foregroundStyle(.red) }
            }
            .navigationTitle(original.name.isEmpty ? "Add category" : "Edit category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let draft else { return }
                        if onSave(draft) { dismiss() }
                        else { saveError = "Changes could not be saved. Your previous balance is unchanged." }
                    }.disabled(draft == nil)
                }
            }
        }
    }

    private func field(_ label: String, value: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, text: value, prompt: Text("0")).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(maxWidth: 150).accessibilityLabel(label)
        }
    }

    private func parseZeroAllowed(_ input: String) -> Decimal? {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 0 }
        return PointsFormat.parse(input)
    }
}
