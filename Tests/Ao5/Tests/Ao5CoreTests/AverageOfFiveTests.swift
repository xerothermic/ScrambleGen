import XCTest
@testable import Ao5Core

final class AverageOfFiveTests: XCTestCase {
    private func solves(_ cs: [Int], _ penalties: [Int: Ao5Penalty] = [:]) -> [Ao5Solve] {
        cs.enumerated().map { Ao5Solve(millis: $1, penalty: penalties[$0] ?? .none) }
    }

    func testBasicAverageDropsFastestAndSlowest() {
        // 9.00 8.00 10.00 7.00 11.00 -> drop 7.00 (idx 3) and 11.00 (idx 4); (9+8+10)/3 = 9.00
        let r = AverageOfFive.compute(solves([9000, 8000, 10000, 7000, 11000]))!
        XCTAssertEqual(r.dropped, [3, 4])
        XCTAssertEqual(r.averageMillis, 9000)
        XCTAssertEqual(r.bestMillis, 7000)
    }

    func testWrongCountIsNil() {
        XCTAssertNil(AverageOfFive.compute(solves([9000, 8000, 10000, 7000])))
        XCTAssertNil(AverageOfFive.compute([]))
    }

    func testRoundingToCentisecond() {
        // middle sum 1000 ms -> 333.33 ms -> 330; 1001 -> 333.67 -> 330; 1100 -> 366.67 -> 370
        XCTAssertEqual(AverageOfFive.compute(solves([1, 333, 333, 334, 9999]))!.averageMillis, 330)
        XCTAssertEqual(AverageOfFive.compute(solves([1, 333, 333, 335, 9999]))!.averageMillis, 330)
        XCTAssertEqual(AverageOfFive.compute(solves([1, 350, 375, 375, 9999]))!.averageMillis, 370)
        // exact half of a centisecond rounds up: sum 45 -> 15 ms -> 20
        XCTAssertEqual(AverageOfFive.compute(solves([0, 15, 15, 15, 50]))!.averageMillis, 20)
        XCTAssertEqual(AverageOfFive.compute(solves([1000, 12340, 12350, 12350, 99999]))!.averageMillis, 12350)
        XCTAssertEqual(AverageOfFive.compute(solves([1000, 12340, 12340, 12350, 99999]))!.averageMillis, 12340)
    }

    func testPlus2IsAddedAndCanChangeWhichIsDropped() {
        // 8.00+2 = 10.00 becomes the slowest of 9.00 8.00(+2) 9.50 9.60 9.70
        let r = AverageOfFive.compute(solves([9000, 8000, 9500, 9600, 9700], [1: .plus2]))!
        XCTAssertEqual(r.dropped, [0, 1])          // 9.00 fastest, 10.00 slowest
        XCTAssertEqual(r.averageMillis, (9500 + 9600 + 9700 + 1) / 3)  // 9600
        XCTAssertEqual(r.bestMillis, 9000)
    }

    func testPlus2CountsForBestSingle() {
        let r = AverageOfFive.compute(solves([5000, 9000, 9000, 9000, 9000], [0: .plus2]))!
        XCTAssertEqual(r.bestMillis, 7000)
    }

    func testOneDNFIsDroppedAsSlowest() {
        let r = AverageOfFive.compute(solves([9000, 8000, 10000, 7000, 11000], [4: .dnf]))!
        XCTAssertEqual(r.dropped, [3, 4])          // fastest 7.00 and the DNF
        XCTAssertEqual(r.averageMillis, 9000)
        XCTAssertEqual(r.bestMillis, 7000)
    }

    func testDNFWithSlowRawTimeStillSlowest() {
        // the raw time of a DNF is irrelevant
        let r = AverageOfFive.compute(solves([9000, 8000, 10000, 7000, 1], [4: .dnf]))!
        XCTAssertEqual(r.dropped, [3, 4])
        XCTAssertEqual(r.bestMillis, 7000)
    }

    func testTwoDNFsMakeAverageDNF() {
        let r = AverageOfFive.compute(solves([9000, 8000, 10000, 7000, 11000], [0: .dnf, 2: .dnf]))!
        XCTAssertNil(r.averageMillis)
        XCTAssertEqual(r.bestMillis, 7000)
        XCTAssertEqual(r.dropped.count, 2)
    }

    func testAllDNF() {
        let r = AverageOfFive.compute(solves([1, 2, 3, 4, 5],
            [0: .dnf, 1: .dnf, 2: .dnf, 3: .dnf, 4: .dnf]))!
        XCTAssertNil(r.averageMillis)
        XCTAssertNil(r.bestMillis)
        XCTAssertEqual(r.dropped.count, 2)
    }

    func testTiesDropTwoDifferentSolves() {
        let r = AverageOfFive.compute(solves([9000, 9000, 9000, 9000, 9000]))!
        XCTAssertEqual(r.dropped, [0, 4])          // stable: first fastest, last slowest
        XCTAssertEqual(r.averageMillis, 9000)
        XCTAssertEqual(r.bestMillis, 9000)
    }

    func testTiedFastestAndSlowest() {
        let r = AverageOfFive.compute(solves([7000, 7000, 9000, 11000, 11000]))!
        XCTAssertEqual(r.dropped, [0, 4])
        XCTAssertEqual(r.averageMillis, (7000 + 9000 + 11000) / 3)   // 9000
    }

    func testFormat() {
        XCTAssertEqual(AverageOfFive.format(8420), "8.42")
        XCTAssertEqual(AverageOfFive.format(12345), "12.34")     // truncated, no milliseconds
        XCTAssertEqual(AverageOfFive.format(50), "0.05")
        XCTAssertEqual(AverageOfFive.format(5), "0.00")
        XCTAssertEqual(AverageOfFive.format(62345), "1:02.34")
        XCTAssertEqual(AverageOfFive.format(600_000), "10:00.00")
        XCTAssertEqual(AverageOfFive.format(nil), "DNF")
    }

    func testLabel() {
        XCTAssertEqual(AverageOfFive.label(Ao5Solve(millis: 8420)), "8.42")
        XCTAssertEqual(AverageOfFive.label(Ao5Solve(millis: 8420, penalty: .plus2)), "10.42+")
        XCTAssertEqual(AverageOfFive.label(Ao5Solve(millis: 8420, penalty: .dnf)), "DNF")
        XCTAssertEqual(AverageOfFive.label(Ao5Solve(millis: 8420), parenthesized: true), "(8.42)")
        XCTAssertEqual(AverageOfFive.label(Ao5Solve(millis: 8420, penalty: .dnf), parenthesized: true), "(DNF)")
    }

    func testDigitEntry() {
        XCTAssertEqual(AverageOfFive.millis(fromDigits: ""), 0)
        XCTAssertEqual(AverageOfFive.millis(fromDigits: "5"), 50)             // 0.05
        XCTAssertEqual(AverageOfFive.millis(fromDigits: "842"), 8420)
        XCTAssertEqual(AverageOfFive.millis(fromDigits: "1234"), 12340)
        XCTAssertEqual(AverageOfFive.millis(fromDigits: "10234"), 62340)      // 1:02.34
        XCTAssertEqual(AverageOfFive.millis(fromDigits: "7599"), 75990)       // 75.99 s
        XCTAssertEqual(AverageOfFive.millis(fromDigits: "17599"), 135990)     // 1:75.99 = 2:15.99
        XCTAssertEqual(AverageOfFive.millis(fromDigits: "95999"), 599_990)    // 9:59.99
        XCTAssertEqual(AverageOfFive.millis(fromDigits: "123456"), 600_000)   // 12:34.56 clamps to 10:00.00
        XCTAssertEqual(AverageOfFive.maxMillis, 600_000)
    }

    // MARK: Crown mapping

    func testTinyDeltasAccumulate() {
        var m = Ao5CrownMapper()
        var total = 0
        var t = 0.0
        for _ in 0..<1000 { t += 0.5; total += m.millis(forDelta: 0.074, now: t) }   // smallest measured delta, 0.0212 detent each
        XCTAssertEqual(total, 21)                                                    // 74 units = 21.18 detents
    }

    func testFullSlowRevolutionYieldsAbout150ms() {
        var m = Ao5CrownMapper()
        var total = 0
        var t = 0.0
        for _ in 0..<524 { t += 0.5; total += m.millis(forDelta: 1.0, now: t) }   // 524 units = 1 rev, slow
        XCTAssertEqual(total, 150)
        XCTAssertEqual(m.unitsPerRev, 524.0)
    }

    func testNeverZeroForWholeDetent() {
        var m = Ao5CrownMapper()
        XCTAssertEqual(m.millis(forDelta: Ao5CrownMapper.defaultUnitsPerRev / Double(Ao5CrownMapper.defaultStepsPerRev), now: 1), 1)
        XCTAssertEqual(m.millis(forDelta: -Ao5CrownMapper.defaultUnitsPerRev / Double(Ao5CrownMapper.defaultStepsPerRev), now: 5), -1)
    }

    func testReversalDropsOppositeCarry() {
        var m = Ao5CrownMapper()
        XCTAssertEqual(m.millis(forDelta: 2.0, now: 1), 0)     // 0.57 detent carried
        XCTAssertEqual(m.millis(forDelta: -2.0, now: 2), 0)    // carry cleared, -0.57 carried
        XCTAssertEqual(m.millis(forDelta: -2.0, now: 3), -1)   // -1.14 -> -1
    }

    func testSpeedTiersAndBase() {
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 1, base: 1, accel: .normal), 1)
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 40, base: 1, accel: .normal), 10)
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 100, base: 1, accel: .normal), 100)
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 500, base: 1, accel: .normal), 1000)
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 500, base: 5, accel: .off), 5)
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 1, base: 10, accel: .normal), 10)
    }

    func testFastSpinAccelerates() {
        var m = Ao5CrownMapper()
        _ = m.millis(forDelta: 10.48, now: 1.00)
        let ms = m.millis(forDelta: 10.48, now: 1.02)      // 3 detents / 20 ms = 150/s
        XCTAssertEqual(ms, 3000)
    }

    func testStepsPerRevolutionSetting() {
        for n in [30, 100, 150, 1000] {
            var m = Ao5CrownMapper()
            m.stepsPerRev = n
            XCTAssertEqual(m.millis(forDelta: Ao5CrownMapper.defaultUnitsPerRev, now: 1), n)     // one revolution = n detents
            // carry works for any n: 8 deltas of 1/(8n) revolution = 1 detent total
            var m2 = Ao5CrownMapper()
            m2.stepsPerRev = n
            var total = 0
            for i in 0..<8 { total += m2.millis(forDelta: Ao5CrownMapper.defaultUnitsPerRev / (8.0 * Double(n)), now: 10 + Double(i)) }
            XCTAssertEqual(total, 1)
        }
    }

    func testGentleThresholdsAreHigher() {
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 40, base: 1, accel: .gentle), 1)
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 40, base: 1, accel: .normal), 10)
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 200, base: 1, accel: .gentle), 100)
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 300, base: 1, accel: .gentle), 1000)
    }

    func testCustomUnitsPerRev() {
        for u in [100.0, 524.0, 1500.0] {
            var m = Ao5CrownMapper()
            m.unitsPerRev = u
            XCTAssertEqual(m.millis(forDelta: u, now: 1), 150)
        }
    }

    func testCustomThresholds() {
        let c = (10.0, 20.0, 30.0)
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 5, base: 1, accel: .custom, custom: c), 1)
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 15, base: 1, accel: .custom, custom: c), 10)
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 25, base: 1, accel: .custom, custom: c), 100)
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 35, base: 1, accel: .custom, custom: c), 1000)
        var m = Ao5CrownMapper()
        m.accel = .custom
        m.customThresholds = c
        _ = m.millis(forDelta: 10.48, now: 1.00)
        XCTAssertEqual(m.millis(forDelta: 10.48, now: 1.02), 3000)   // 150/s >= 30
    }

    func testResolvedThresholds() {
        let c = (7.0, 8.0, 9.0)
        XCTAssertEqual(Ao5Accel.custom.cycled(by: 1), .off)
        XCTAssertEqual(Ao5Accel.off.cycled(by: -1), .custom)
        XCTAssertEqual(Ao5Accel.gentle.cycled(by: 1), .normal)
        XCTAssertNil(Ao5Accel.off.resolvedThresholds(custom: c))
        XCTAssertEqual(Ao5Accel.custom.resolvedThresholds(custom: c)!.0, 7)
        XCTAssertEqual(Ao5Accel.custom.resolvedThresholds(custom: c)!.2, 9)
        XCTAssertEqual(Ao5Accel.normal.resolvedThresholds(custom: c)!.0, 25)
        XCTAssertEqual(Ao5Accel.gentle.resolvedThresholds(custom: c)!.2, 260)
    }

    func testHapticClickOnDetentCrossing() {
        XCTAssertNil(Ao5Haptic.clickIndex(millis: 5, interval: 10, hapticIdx: 0))    // same detent
        XCTAssertEqual(Ao5Haptic.clickIndex(millis: 10, interval: 10, hapticIdx: 0), 1)
        XCTAssertEqual(Ao5Haptic.clickIndex(millis: 1000, interval: 10, hapticIdx: 0), 100)   // jump coalesces
        XCTAssertNil(Ao5Haptic.clickIndex(millis: 9, interval: 10, hapticIdx: 1))    // within hysteresis (margin 2)
        XCTAssertEqual(Ao5Haptic.clickIndex(millis: 7, interval: 10, hapticIdx: 1), 0)
        XCTAssertEqual(Ao5Haptic.clickIndex(millis: 110, interval: 100, hapticIdx: 0), 1)
    }

    func testAccelCycleCoversAllModes() {
        XCTAssertEqual(Ao5Accel.allCases.map(\.rawValue), [0, 1, 2, 3])
        XCTAssertNil(Ao5Accel.off.thresholds)
        XCTAssertEqual(Ao5CrownMapper.step(forSpeed: 500, base: 1, accel: .off), 1)
    }
}
