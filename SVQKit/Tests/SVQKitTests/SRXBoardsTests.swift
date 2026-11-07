import XCTest
@testable import SVQKit

/// SRX board names come from Roland's owner's manuals (see Reference Material/SRX Lists).
/// These checks use an independent Roland document: Supplemental Note SN 132, "Selecting
/// Internal and SRX-Series Sounds Via MIDI", which lists each board's banks and patch counts.
final class SRXBoardsTests: XCTestCase {
    func testBanksAndCountsMatchRolandsBankSelectNote() throws {
        // board: (patch LSBs, patch count, rhythm LSB, rhythm count), from SN 132.
        let expected: [Int: ([Int], Int, Int?, Int)] = [
            1: ([0], 41, 0, 79), 2: ([1], 50, nil, 0), 3: ([2], 128, 2, 12), 4: ([3], 128, nil, 0),
            5: ([4, 5, 6], 312, 4, 34), 6: ([7, 8, 9, 10], 449, 7, 5), 7: ([11, 12, 13, 14], 475, 11, 11),
            8: ([15, 16, 17, 18], 448, 15, 21), 9: ([19, 20, 21, 22], 414, 19, 12), 10: ([23], 100, nil, 0),
        ]
        for (number, (lsbs, patches, rhythmLSB, rhythms)) in expected {
            let board = try XCTUnwrap(SRXBoards.boards[number], "SRX-\(number)")
            XCTAssertEqual(board.patchLSBs, lsbs, "SRX-\(number)")
            XCTAssertEqual(board.patches.count, patches, "SRX-\(number)")
            XCTAssertEqual(board.rhythmLSB, rhythmLSB, "SRX-\(number)")
            XCTAssertEqual(board.rhythmSets.count, rhythms, "SRX-\(number)")
        }
        // Later boards, from SN 132 v3.00 (2007).
        for (number, lsb, patches) in [(11, 24, 42), (12, 26, 105), (97, 97, 12), (98, 98, 78)] {
            XCTAssertEqual(SRXBoards.boards[number]?.patchLSBs, [lsb], "SRX-\(number)")
            XCTAssertEqual(SRXBoards.boards[number]?.patches.count, patches, "SRX-\(number)")
        }
        // SRX-99, from Roland Japan's list: 64 patches at LSB 105 (not 99).
        XCTAssertEqual(SRXBoards.boards[99]?.patchLSBs, [105])
        XCTAssertEqual(SRXBoards.boards[99]?.patches.count, 64)
    }

    func testNamesAreDisplayable() {
        for (number, board) in SRXBoards.boards {
            for name in board.patches + board.rhythmSets {
                XCTAssertEqual(name.isEmpty, number == 97, "SRX-\(number)") // SRX-97's names aren't known
                XCTAssertLessThanOrEqual(name.count, 12, "SRX-\(number) \(name)")
                XCTAssertTrue(name.unicodeScalars.allSatisfy { (0x20 ... 0x7E).contains($0.value) }, "SRX-\(number) \(name)")
            }
        }
    }

    func testSelectingSRXSoundsByBankSelect() {
        // SN 132's examples: SRX-03 Patch 017 is 93/2/17; SRX-06 Patch 271 "Full Brass" is 93/9/15.
        let chorus = SRXBoards.patch(lsb: 2, program: 16)
        XCTAssertEqual(chorus?.board, 3)
        XCTAssertEqual(chorus?.number, 17)
        XCTAssertEqual(chorus?.name, "Chorus LA") // SN 132 prints "ChorusLA"; the SRX-03 manual "Chorus LA"

        var part = FantomPart(number: 1)
        part.bankMSB = 93
        part.bankLSB = 9
        part.program = 14
        XCTAssertEqual(part.displayName, "SRX-06 271 Full Brass")

        part.bankMSB = 92
        part.bankLSB = 11
        part.program = 0
        XCTAssertTrue(part.isRhythmSet)
        XCTAssertEqual(part.displayName, "SRX-07 001 Ring Kit")

        part.bankMSB = 93
        part.bankLSB = 24
        part.program = 0
        XCTAssertEqual(part.displayName, "SRX-11 001 Superb Grand")

        part.bankLSB = 105
        part.program = 39
        XCTAssertEqual(part.displayName, "SRX-99 040 OnMicPremier")

        part.bankLSB = 97 // SRX-97: Bank Select known, names not
        part.program = 2
        XCTAssertEqual(part.displayName, "SRX-97 003")

        // Names keep the exact spacing of Roland's lists.
        XCTAssertEqual(SRXBoards.patch(lsb: 0, program: 0)?.name, "Kick 1  Menu")
        XCTAssertEqual(SRXBoards.patch(lsb: 13, program: 315 - 256)?.name, "H 2 O")

        part.bankLSB = 90 // no known board
        XCTAssertEqual(part.displayName, "SRX 003")
    }
}
