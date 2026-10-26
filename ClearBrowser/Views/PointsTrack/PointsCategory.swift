import Foundation

struct PointsCategory: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var currentPoints: Decimal = 0
    var dailyPoints: Decimal = 280
    var monthlyBonusPoints: Decimal = 1_250
    var pointsPerReward: Decimal = 6_500
    var rewardDollars: Decimal = 5

    private enum CodingKeys: String, CodingKey {
        case id, name, currentPoints, dailyPoints, monthlyBonusPoints, pointsPerReward, rewardDollars
    }

    init(
        id: UUID = UUID(),
        name: String,
        currentPoints: Decimal = 0,
        dailyPoints: Decimal = 280,
        monthlyBonusPoints: Decimal = 1_250,
        pointsPerReward: Decimal = 6_500,
        rewardDollars: Decimal = 5
    ) {
        self.id = id
        self.name = name
        self.currentPoints = currentPoints
        self.dailyPoints = dailyPoints
        self.monthlyBonusPoints = monthlyBonusPoints
        self.pointsPerReward = pointsPerReward
        self.rewardDollars = rewardDollars
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        currentPoints = try container.decode(Decimal.self, forKey: .currentPoints)
        dailyPoints = try container.decode(Decimal.self, forKey: .dailyPoints)
        monthlyBonusPoints = try container.decodeIfPresent(Decimal.self, forKey: .monthlyBonusPoints) ?? 1_250
        pointsPerReward = try container.decode(Decimal.self, forKey: .pointsPerReward)
        rewardDollars = try container.decode(Decimal.self, forKey: .rewardDollars)
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        [currentPoints, dailyPoints, monthlyBonusPoints, pointsPerReward, rewardDollars].allSatisfy {
            !$0.isNaN && $0 >= 0 && $0 <= Decimal(1_000_000_000_000 as Int64)
        } && pointsPerReward >= Decimal(string: "0.000001")! && rewardDollars >= Decimal(string: "0.000001")!
    }

    func points(after days: Int) -> Decimal {
        let safeDays = max(0, days)
        let completedMonths = safeDays / 30
        return currentPoints + dailyPoints * Decimal(safeDays) + monthlyBonusPoints * Decimal(completedMonths)
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
