import XCTest
@testable import Ao5Core

final class AverageOfFiveTests: XCTestCase {
    private func solves(_ cs: [Int], _ penalties: [Int: Ao5Penalty] = [:]) -> [Ao5Solve] {
        cs.enumerated().map { Ao5Solve(centis: $1, penalty: penalties[$0] ?? .none) }
    }

    func testBasicAverageDropsFastestAndSlowest() {
        // 9.00 8.00 10.00 7.00 11.00 -> drop 7.00 (idx 3) and 11.00 (idx 4); (9+8+10)/3 = 9.00
        let r = AverageOfFive.compute(solves([900, 800, 1000, 700, 1100]))!
        XCTAssertEqual(r.dropped, [3, 4])
        XCTAssertEqual(r.averageCentis, 900)
        XCTAssertEqual(r.bestCentis, 700)
    }

    func testWrongCountIsNil() {
        XCTAssertNil(AverageOfFive.compute(solves([900, 800, 1000, 700])))
        XCTAssertNil(AverageOfFive.compute([]))
    }

    func testRoundingToCentisecond() {
        // middle sum 1000 -> 333.33 -> 333; 1001 -> 333.67 -> 334; 1002 -> 334
        XCTAssertEqual(AverageOfFive.compute(solves([1, 333, 333, 334, 9999]))!.averageCentis, 333)
        XCTAssertEqual(AverageOfFive.compute(solves([1, 333, 333, 335, 9999]))!.averageCentis, 334)
        XCTAssertEqual(AverageOfFive.compute(solves([1, 333, 334, 335, 9999]))!.averageCentis, 334)
        // sum 4 -> 1.33 -> 1; sum 5 -> 1.67 -> 2
        XCTAssertEqual(AverageOfFive.compute(solves([0, 1, 1, 2, 50]))!.averageCentis, 1)
        XCTAssertEqual(AverageOfFive.compute(solves([0, 1, 2, 2, 50]))!.averageCentis, 2)
    }

    func testPlus2IsAddedAndCanChangeWhichIsDropped() {
        // 8.00+2 = 10.00 becomes the slowest of 9.00 8.00(+2) 9.50 9.60 9.70
        let r = AverageOfFive.compute(solves([900, 800, 950, 960, 970], [1: .plus2]))!
        XCTAssertEqual(r.dropped, [0, 1])          // 9.00 fastest, 10.00 slowest
        XCTAssertEqual(r.averageCentis, (950 + 960 + 970 + 1) / 3)  // 960
        XCTAssertEqual(r.bestCentis, 900)
    }

    func testPlus2CountsForBestSingle() {
        let r = AverageOfFive.compute(solves([500, 900, 900, 900, 900], [0: .plus2]))!
        XCTAssertEqual(r.bestCentis, 700)
    }

    func testOneDNFIsDroppedAsSlowest() {
        let r = AverageOfFive.compute(solves([900, 800, 1000, 700, 1100], [4: .dnf]))!
        XCTAssertEqual(r.dropped, [3, 4])          // fastest 7.00 and the DNF
        XCTAssertEqual(r.averageCentis, 900)
        XCTAssertEqual(r.bestCentis, 700)
    }

    func testDNFWithSlowRawTimeStillSlowest() {
        // the raw time of a DNF is irrelevant
        let r = AverageOfFive.compute(solves([900, 800, 1000, 700, 1], [4: .dnf]))!
        XCTAssertEqual(r.dropped, [3, 4])
        XCTAssertEqual(r.bestCentis, 700)
    }

    func testTwoDNFsMakeAverageDNF() {
        let r = AverageOfFive.compute(solves([900, 800, 1000, 700, 1100], [0: .dnf, 2: .dnf]))!
        XCTAssertNil(r.averageCentis)
        XCTAssertEqual(r.bestCentis, 700)
        XCTAssertEqual(r.dropped.count, 2)
    }

    func testAllDNF() {
        let r = AverageOfFive.compute(solves([1, 2, 3, 4, 5],
            [0: .dnf, 1: .dnf, 2: .dnf, 3: .dnf, 4: .dnf]))!
        XCTAssertNil(r.averageCentis)
        XCTAssertNil(r.bestCentis)
        XCTAssertEqual(r.dropped.count, 2)
    }

    func testTiesDropTwoDifferentSolves() {
        let r = AverageOfFive.compute(solves([900, 900, 900, 900, 900]))!
        XCTAssertEqual(r.dropped, [0, 4])          // stable: first fastest, last slowest
        XCTAssertEqual(r.averageCentis, 900)
        XCTAssertEqual(r.bestCentis, 900)
    }

    func testTiedFastestAndSlowest() {
        let r = AverageOfFive.compute(solves([700, 700, 900, 1100, 1100]))!
        XCTAssertEqual(r.dropped, [0, 4])
        XCTAssertEqual(r.averageCentis, (700 + 900 + 1100) / 3)   // 900
    }

    func testFormat() {
        XCTAssertEqual(AverageOfFive.format(842), "8.42")
        XCTAssertEqual(AverageOfFive.format(5), "0.05")
        XCTAssertEqual(AverageOfFive.format(6242), "1:02.42")
        XCTAssertEqual(AverageOfFive.format(nil), "DNF")
    }

    func testLabel() {
        XCTAssertEqual(AverageOfFive.label(Ao5Solve(centis: 842)), "8.42")
        XCTAssertEqual(AverageOfFive.label(Ao5Solve(centis: 842, penalty: .plus2)), "10.42+")
        XCTAssertEqual(AverageOfFive.label(Ao5Solve(centis: 842, penalty: .dnf)), "DNF")
        XCTAssertEqual(AverageOfFive.label(Ao5Solve(centis: 842), parenthesized: true), "(8.42)")
        XCTAssertEqual(AverageOfFive.label(Ao5Solve(centis: 842, penalty: .dnf), parenthesized: true), "(DNF)")
    }

    func testDigitEntry() {
        XCTAssertEqual(AverageOfFive.centis(fromDigits: ""), 0)
        XCTAssertEqual(AverageOfFive.centis(fromDigits: "5"), 5)
        XCTAssertEqual(AverageOfFive.centis(fromDigits: "842"), 842)
        XCTAssertEqual(AverageOfFive.centis(fromDigits: "1234"), 1234)
        XCTAssertEqual(AverageOfFive.centis(fromDigits: "10234"), 6234)    // 1:02.34
        XCTAssertEqual(AverageOfFive.centis(fromDigits: "7599"), 7599)     // 75.99 s
        XCTAssertEqual(AverageOfFive.centis(fromDigits: "17599"), 13599)   // 1:75.99 = 2:15.99
        XCTAssertEqual(AverageOfFive.centis(fromDigits: "123456"), 75456)  // 12:34.56
    }
}
