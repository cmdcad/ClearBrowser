import XCTest
@testable import ClearBrowser

final class RecurringBillsTests: XCTestCase {
    func testFrequencyNormalization() {
        let expected: [(ObligationFrequency, Double)] = [(.weekly, 433.3), (.biweekly, 216.7), (.monthly, 100), (.quarterly, 100.0 / 3), (.annual, 100.0 / 12)]
        for (frequency, monthly) in expected {
            var bill = RecurringObligation(); bill.amount = 100; bill.frequency = frequency
            XCTAssertEqual(bill.monthlyAmount, monthly, accuracy: 0.000001)
        }
    }
    func testPayoffHandlesZeroAPRFinalPaymentAndInsufficientPayment() throws {
        var bill = RecurringObligation(); bill.amount = 300; bill.remainingBalance = 1000
        XCTAssertEqual(bill.payoff?.months, 4)
        XCTAssertEqual(bill.payoff?.interest, 0)
        bill.apr = 12
        let payoff = try XCTUnwrap(bill.payoff)
        XCTAssertEqual(payoff.months, 4)
        XCTAssertEqual(payoff.interest, 22.48371, accuracy: 0.00001)
        bill.amount = 10
        XCTAssertNil(bill.payoff)
        bill.remainingBalance = 0
        XCTAssertEqual(bill.payoff?.months, 0)
    }
    func testInvalidNumbersAreRejected() {
        var bill = RecurringObligation(); bill.name = "Phone"; bill.amount = 60
        XCTAssertNil(bill.validationMessage)
        bill.amount = .nan; XCTAssertNotNil(bill.validationMessage)
        bill.amount = 60; bill.apr = 101; XCTAssertNotNil(bill.validationMessage)
        bill.apr = nil; bill.remainingBalance = -1; XCTAssertNotNil(bill.validationMessage)
    }
    @MainActor
    func testBillsAffectBurnSurplusRunwayAndBackup() throws {
        let suite = "ReloCalcTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ReloCalcModel(defaults: defaults)
        let baselineBurn = model.monthlyExpense
        let baselineNet = model.monthlyNet
        var bill = RecurringObligation(); bill.name = "Insurance"; bill.amount = 120; bill.frequency = .annual
        model.obligations = [bill]
        XCTAssertEqual(model.monthlyExpense, baselineBurn + 10, accuracy: 0.000001)
        XCTAssertEqual(model.monthlyNet, baselineNet - 10, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(model.runwayNoIncome), model.savings / (baselineBurn + 10), accuracy: 0.000001)
        let encoded = try ReloCalcExportFormat.json.data(for: model)
        let restored = try JSONDecoder().decode(ReloCalcBackup.self, from: encoded)
        try restored.validate()
        XCTAssertEqual(restored.obligations?.first?.id, bill.id)
        XCTAssertTrue(String(decoding: try ReloCalcExportFormat.csv.data(for: model), as: UTF8.self).contains("Insurance"))
        XCTAssertTrue(String(decoding: try ReloCalcExportFormat.text.data(for: model), as: UTF8.self).contains("Insurance"))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy["version"] = "1.0"; legacy.removeValue(forKey: "obligations")
        let oldBackup = try JSONDecoder().decode(ReloCalcBackup.self, from: JSONSerialization.data(withJSONObject: legacy))
        try oldBackup.validate(); try oldBackup.apply(to: model)
        XCTAssertTrue(model.obligations.isEmpty)
        legacy["version"] = "2.0"
        let damagedBackup = try JSONDecoder().decode(ReloCalcBackup.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertThrowsError(try damagedBackup.validate())
    }
}
