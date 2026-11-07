import XCTest
@testable import SolveAverages

final class SolveAveragesTests: XCTestCase {
    private func t(_ s: String) -> SolveTime { SolveTime.parse(s)! }

    // MARK: Parsing

    func testParseSeconds() {
        XCTAssertEqual(t("12.34").centis, 1234)
        XCTAssertEqual(t("12.3").centis, 1230)
        XCTAssertEqual(t("12").centis, 1200)
        XCTAssertEqual(t("0.5").centis, 50)
        XCTAssertEqual(t("12.349").centis, 1234)  // truncated
    }

    func testParseMinutes() {
        XCTAssertEqual(t("1:02.34").centis, 6234)
        XCTAssertEqual(t("10:00").centis, 60000)
        XCTAssertNil(SolveTime.parse("1:75.00"))
    }

    func testParseDNFAndPenalty() {
        XCTAssertTrue(t("DNF").isDNF)
        XCTAssertTrue(t(" dnf ").isDNF)
        XCTAssertTrue(t("D").isDNF)
        let p = t("12.34+2")
        XCTAssertEqual(p.centis, 1434)
        XCTAssertTrue(p.plusTwo)
        XCTAssertEqual(t("12.34 +2").centis, 1434)
    }

    func testParseRejectsGarbage() {
        for bad in ["", " ", "abc", "1.2.3", "1:2:3", "-5", ".5", "12.", "+2", "1::2", "12,34"] {
            XCTAssertNil(SolveTime.parse(bad), bad)
        }
    }

    func testDigitEntry() {
        XCTAssertEqual(SolveTime.fromDigits("5")?.centis, 5)
        XCTAssertEqual(SolveTime.fromDigits("1234")?.centis, 1234)
        XCTAssertEqual(SolveTime.fromDigits("10234")?.centis, 6234)
        XCTAssertEqual(SolveTime.fromDigits("1234", plusTwo: true)?.centis, 1434)
        XCTAssertNil(SolveTime.fromDigits(""))
        XCTAssertNil(SolveTime.fromDigits("7777777"))
        XCTAssertNil(SolveTime.fromDigits("7500"))  // 75 s with no minutes digit
    }

    func testText() {
        XCTAssertEqual(SolveTime.time(842).text, "8.42")
        XCTAssertEqual(SolveTime.time(6234).text, "1:02.34")
        XCTAssertEqual(SolveTime.time(1234, plusTwo: true).text, "14.34+")
        XCTAssertEqual(SolveTime.dnf.text, "DNF")
    }

    func testStoredRoundTrip() {
        for x in [SolveTime.time(842), .time(6234), .time(1234, plusTwo: true), .dnf] {
            XCTAssertEqual(SolveTime(stored: x.stored), x)
        }
        XCTAssertNil(SolveTime(stored: "x"))
        XCTAssertNil(SolveTime(stored: ""))
    }

    // MARK: Average of 5

    private func ao5(_ xs: [String]) -> AverageResult? {
        SolveAverages.averageOf5(xs.map(t))
    }

    func testAo5DropsBestAndWorst() {
        let r = ao5(["10.00", "9.00", "11.00", "12.00", "8.00"])!
        XCTAssertEqual(r.centis, 1000)  // (10 + 9 + 11) / 3
        XCTAssertEqual(r.dropped, [4, 3])
        XCTAssertEqual(SolveAverages.displayTimes(
            ["10.00", "9.00", "11.00", "12.00", "8.00"].map(t), dropped: r.dropped),
            ["10.00", "9.00", "11.00", "(12.00)", "(8.00)"])
    }

    func testAo5OneDNFIsDroppedWorst() {
        let r = ao5(["10.00", "DNF", "11.00", "12.00", "8.00"])!
        XCTAssertEqual(r.centis, 1100)  // (10 + 11 + 12) / 3
        XCTAssertEqual(r.dropped, [4, 1])
    }

    func testAo5TwoDNFsIsDNF() {
        let r = ao5(["10.00", "DNF", "11.00", "DNF", "8.00"])!
        XCTAssertTrue(r.isDNF)
        XCTAssertEqual(r.text, "DNF")
        XCTAssertTrue(ao5(["DNF", "DNF", "DNF", "DNF", "DNF"])!.isDNF)
    }

    func testAo5Rounding() {
        // (10.00 + 10.00 + 10.01) / 3 = 10.00333 -> 10.00
        XCTAssertEqual(ao5(["10.00", "10.00", "10.01", "9.00", "11.00"])!.centis, 1000)
        // (10.00 + 10.01 + 10.01) / 3 = 10.00667 -> 10.01
        XCTAssertEqual(ao5(["10.00", "10.01", "10.01", "9.00", "11.00"])!.centis, 1001)
        // Exact halves round up.
        XCTAssertEqual(SolveAverages.roundedMean(sum: 3, count: 2), 2)   // 1.5 -> 2
        XCTAssertEqual(SolveAverages.roundedMean(sum: 5, count: 2), 3)   // 2.5 -> 3
        XCTAssertEqual(SolveAverages.roundedMean(sum: 4, count: 3), 1)   // 1.33 -> 1
        XCTAssertEqual(SolveAverages.roundedMean(sum: 5, count: 3), 2)   // 1.67 -> 2
    }

    func testAo5TiesAndAllEqual() {
        let r = ao5(["10.00", "10.00", "10.00", "10.00", "10.00"])!
        XCTAssertEqual(r.centis, 1000)
        XCTAssertEqual(Set(r.dropped).count, 2)  // two distinct solves dropped
    }

    func testAo5PenaltyCounts() {
        // 8.00+2 = 10.00
        let xs = [SolveTime.time(800, plusTwo: true), t("9.00"), t("11.00"), t("12.00"), t("13.00")]
        XCTAssertEqual(SolveAverages.averageOf5(xs)!.centis, 1100)  // drops 9.00 and 13.00
    }

    func testAo5NeedsFive() {
        XCTAssertNil(SolveAverages.averageOf5([t("10.00")]))
        XCTAssertNil(SolveAverages.averageOf5([]))
    }

    // MARK: Mean of 3

    func testMo3() {
        let r = SolveAverages.meanOf3(["10.00", "11.00", "12.00"].map(t))!
        XCTAssertEqual(r.centis, 1100)
        XCTAssertEqual(r.dropped, [])
        XCTAssertEqual(SolveAverages.meanOf3(["10.00", "10.00", "10.01"].map(t))!.centis, 1000)
        XCTAssertEqual(SolveAverages.meanOf3(["10.00", "10.01", "10.01"].map(t))!.centis, 1001)
    }

    func testMo3AnyDNFIsDNF() {
        XCTAssertTrue(SolveAverages.meanOf3(["10.00", "DNF", "12.00"].map(t))!.isDNF)
        XCTAssertNil(SolveAverages.meanOf3(["10.00", "11.00"].map(t)))
    }
}
