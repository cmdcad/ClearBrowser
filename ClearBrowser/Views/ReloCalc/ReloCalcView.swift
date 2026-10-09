import SwiftUI

enum ReloStep: Int, CaseIterable {
    case start, income, expenses, dashboard, weekly, export
    var title: String {
        switch self {
        case .start: return "Start"
        case .income: return "Income"
        case .expenses: return "Expenses"
        case .dashboard: return "Dashboard"
        case .weekly: return "Weekly"
        case .export: return "Save & Export"
        }
    }
}

/// Drop-in view. Usage: `ReloCalcView()` or `ReloCalcView(model: myModel)`.
struct ReloCalcView: View {
    @StateObject private var model: ReloCalcModel
    @State private var step: ReloStep = .start
    private let action: () -> Void
    private let buttonTitle: String

    init(
        model: ReloCalcModel = ReloCalcModel(),
        action: @escaping () -> Void = {},
        buttonTitle: String = "Close"
    ) {
        _model = StateObject(wrappedValue: model)
        self.action = action
        self.buttonTitle = buttonTitle
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch step {
                    case .start: StartStep(m: model)
                    case .income: IncomeStep(m: model)
                    case .expenses: ExpensesStep(m: model)
                    case .dashboard: DashboardStep(m: model)
                    case .weekly: WeeklyStep(m: model)
                    case .export: ReloCalcExportStep(model: model)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            navBar
        }
        .background(Color(.systemGroupedBackground))
    }

    // Single slim bar: bb  •  title + dots  •  ff
    private var navBar: some View {
        HStack {
            //New Nav Button
            Button(action: action) {
                Label(buttonTitle, systemImage: "chevron.left")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { move(-1) } label: {
                Image(systemName: "chevron.left.circle.fill").font(.title2)
            }
            .disabled(step == .start)
            .accessibilityLabel("Back")

            Spacer()
            VStack(spacing: 3) {
                Text(step.title).font(.footnote.weight(.semibold))
                HStack(spacing: 5) {
                    ForEach(ReloStep.allCases, id: \.self) { s in
                        Circle()
                            .fill(s == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            Spacer()

            Button { move(1) } label: {
                Image(systemName: "chevron.right.circle.fill").font(.title2)
            }
            .disabled(step == .export)
            .accessibilityLabel("Forward")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func move(_ delta: Int) {
        guard let next = ReloStep(rawValue: step.rawValue + delta) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }
}

// MARK: - Shared components

struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct NumberField: View {
    let title: String
    @Binding var value: Double
    var prefix: String? = nil
    var suffix: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                if let prefix { Text(prefix).foregroundStyle(.secondary) }
                TextField("0", value: $value, format: .number)
                    .keyboardType(.decimalPad)
                    .font(.system(.body, design: .monospaced))
                if let suffix { Text(suffix).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct DaysPicker: View {
    let title: String
    @Binding var days: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker(title, selection: $days) {
                Text("4 Days").tag(4)
                Text("5 Days").tag(5)
            }
            .pickerStyle(.segmented)
        }
    }
}

struct SummaryRow: View {
    let label: String
    let value: String
    var color: Color = .primary
    var bold = false
    var body: some View {
        HStack {
            Text(label).foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundStyle(color)
        }
        .font(bold ? .subheadline.weight(.bold) : .footnote)
    }
}
