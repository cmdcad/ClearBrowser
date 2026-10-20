import Foundation

struct PointsCategory: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var currentPoints: Decimal = 0
    var dailyPoints: Decimal = 280
    var pointsPerReward: Decimal = 6_500
    var rewardDollars: Decimal = 5

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        [currentPoints, dailyPoints, pointsPerReward, rewardDollars].allSatisfy {
            !$0.isNaN && $0 >= 0 && $0 <= Decimal(1_000_000_000_000 as Int64)
        } && pointsPerReward >= Decimal(string: "0.000001")! && rewardDollars >= Decimal(string: "0.000001")!
    }

    func points(after days: Int) -> Decimal {
        currentPoints + dailyPoints * Decimal(max(0, days))
    }

    func value(after days: Int = 0) -> Decimal {
        guard isValid else { return 0 }
        return points(after: days) / pointsPerReward * rewardDollars
    }

    /// Rewards belong to each category; leftover points cannot be pooled.
    func redeemable(after days: Int = 0) -> Decimal {
        guard isValid else { return 0 }
        var units = points(after: days) / pointsPerReward
        var whole = Decimal()
        NSDecimalRound(&whole, &units, 0, .down)
        return whole * rewardDollars
    }

    static func totalValue(_ categories: [PointsCategory], days: Int = 0) -> Decimal {
        categories.reduce(0) { $0 + $1.value(after: days) }
    }

    static func totalRedeemable(_ categories: [PointsCategory], days: Int = 0) -> Decimal {
        categories.reduce(0) { $0 + $1.redeemable(after: days) }
    }
}

enum PointsFormat {
    static func number(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }

    static func money(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "$0.00"
    }

    /// Validate the entire input, rather than silently accepting a numeric prefix.
    static func parse(_ input: String, locale: Locale = .current) -> Decimal? {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = raw.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
        guard normalized.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func input(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
}
