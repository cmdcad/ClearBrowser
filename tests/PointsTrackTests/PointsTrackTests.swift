import XCTest
@testable import ClearBrowser

final class PointsTrackTests: XCTestCase {
    func testDefaultRewardAndOneYearProjection() {
        let category = PointsCategory(name: "Hotmail")
        XCTAssertTrue(category.isValid)
        XCTAssertEqual(category.dailyPoints, 280)
        XCTAssertEqual(category.points(after: 365), 102_200)
        XCTAssertEqual(NSDecimalNumber(decimal: category.value(after: 365)).doubleValue, 78.6153846154, accuracy: 0.0000001)
        XCTAssertEqual(category.redeemable(after: 365), 75)
    }

    func testProjectionIncludesExistingBalance() {
        let category = PointsCategory(name: "Hotmail", currentPoints: 6_500)
        XCTAssertEqual(category.value(), 5)
        XCTAssertEqual(category.points(after: 365), 108_700)
        XCTAssertEqual(category.redeemable(after: 365), 80)
    }

    func testDifferentRatesAreConvertedBeforeSumming() {
        let categories = [
            PointsCategory(name: "Hotmail", currentPoints: 6_500),
            PointsCategory(name: "Other", currentPoints: 1_000, dailyPoints: 10, pointsPerReward: 1_000, rewardDollars: 2)
        ]
        XCTAssertEqual(PointsCategory.totalValue(categories), 7)
        XCTAssertEqual(PointsCategory.totalRedeemable(categories), 7)
        XCTAssertEqual(PointsCategory.totalValue(categories, days: 100), categories[0].value(after: 100) + 4)
    }

    func testPartialBalancesAreNotPooledForRedemption() {
        let categories = [PointsCategory(name: "First", currentPoints: 3_250), PointsCategory(name: "Second", currentPoints: 3_250)]
        XCTAssertEqual(PointsCategory.totalValue(categories), 5)
        XCTAssertEqual(PointsCategory.totalRedeemable(categories), 0)
    }

    func testZeroDaysAndNoDailyEarningsKeepBalance() {
        let category = PointsCategory(name: "Paused", currentPoints: 6_500, dailyPoints: 0)
        XCTAssertEqual(category.value(after: 365), 5)
        XCTAssertEqual(category.value(after: 0), 5)
        XCTAssertEqual(category.points(after: -1), 6_500)
        XCTAssertEqual(PointsCategory.totalValue([]), 0)
    }

    func testInvalidConversionsAndNegativeBalancesAreRejected() {
        XCTAssertFalse(PointsCategory(name: "  ").isValid)
        XCTAssertFalse(PointsCategory(name: "Test", currentPoints: -1).isValid)
        XCTAssertFalse(PointsCategory(name: "Test", dailyPoints: -1).isValid)
        XCTAssertFalse(PointsCategory(name: "Test", pointsPerReward: 0).isValid)
        XCTAssertFalse(PointsCategory(name: "Test", rewardDollars: 0).isValid)
        XCTAssertFalse(PointsCategory(name: "Test", currentPoints: .nan).isValid)
        XCTAssertFalse(PointsCategory(name: "Test", pointsPerReward: Decimal(string: "0.00000001")!).isValid)
    }

    func testParserRejectsTrailingJunkAndAcceptsLocaleDecimal() {
        XCTAssertNil(PointsFormat.parse("6500abc", locale: Locale(identifier: "en_US")))
        XCTAssertNil(PointsFormat.parse("-280", locale: Locale(identifier: "en_US")))
        XCTAssertNil(PointsFormat.parse("", locale: Locale(identifier: "en_US")))
        XCTAssertEqual(PointsFormat.parse("5,50", locale: Locale(identifier: "de_DE")), Decimal(string: "5.5"))
        XCTAssertEqual(PointsFormat.parse("6500", locale: Locale(identifier: "en_US")), 6_500)
    }

    @MainActor
    func testSavedCategoryCanBeEditedReloadedAndDeleted() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("categories.json")
        let model = PointsTrackModel(fileURL: file)
        var category = PointsCategory(name: "Hotmail", currentPoints: 6_500)
        XCTAssertTrue(model.save(category))
        category.currentPoints = 13_000
        XCTAssertTrue(model.save(category))
        let reloaded = PointsTrackModel(fileURL: file)
        XCTAssertEqual(reloaded.categories, [category])
        reloaded.delete(category)
        XCTAssertTrue(PointsTrackModel(fileURL: file).categories.isEmpty)
    }

    @MainActor
    func testCorruptStorageIsPreserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("categories.json")
        let original = Data("broken backup".utf8)
        try original.write(to: file)
        let model = PointsTrackModel(fileURL: file)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.save(PointsCategory(name: "New")))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}
