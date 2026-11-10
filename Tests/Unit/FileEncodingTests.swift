//
//  FileEncodingTests.swift
//  MacPadTests
//
//  Encoding detection and round-tripping. M2 grows this into the byte-for-byte
//  corpus across the full code-page menu.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import MacPad

final class FileEncodingTests: XCTestCase {

    func testDetectsByteOrderMarks() {
        XCTAssertEqual(FileEncoding.detect(in: Data([0xEF, 0xBB, 0xBF, 0x41])), .utf8WithBOM)
        XCTAssertEqual(FileEncoding.detect(in: Data([0xFF, 0xFE, 0x41, 0x00])),
                       .utf16LittleEndianWithBOM)
        XCTAssertEqual(FileEncoding.detect(in: Data([0xFE, 0xFF, 0x00, 0x41])),
                       .utf16BigEndianWithBOM)
    }

    func testPlainASCIIIsTreatedAsUTF8() {
        XCTAssertEqual(FileEncoding.detect(in: Data("hello".utf8)), .utf8)
    }

    func testValidUTF8WithoutBOMIsTreatedAsUTF8() {
        XCTAssertEqual(FileEncoding.detect(in: Data("héllo ☃".utf8)), .utf8)
    }

    /// Bytes that are not valid UTF-8 fall back to the 8-bit code page, which
    /// is what Windows editors label "ANSI".
    func testInvalidUTF8FallsBackToSingleByte() {
        // 0x93 and 0x94 are smart quotes in Windows-1252 and invalid UTF-8.
        let data = Data([0x93, 0x48, 0x69, 0x94])
        XCTAssertEqual(FileEncoding.detect(in: data), FileEncoding.ansiDefault)
    }

    func testRoundTripPreservesContent() throws {
        let samples = ["hello", "héllo ☃", "line1\nline2", "", "tabs\tand\tspaces"]
        let encodings: [FileEncoding] = [
            .utf8, .utf8WithBOM, .utf16LittleEndianWithBOM, .utf16BigEndianWithBOM,
        ]
        for encoding in encodings {
            for sample in samples {
                let encoded = try XCTUnwrap(encoding.encode(sample),
                                            "\(encoding.displayName) could not encode “\(sample)”")
                let decoded = try XCTUnwrap(encoding.decode(encoded),
                                            "\(encoding.displayName) could not decode its own output")
                XCTAssertEqual(decoded, sample, "round trip failed for \(encoding.displayName)")
            }
        }
    }

    func testBOMIsStrippedOnDecodeAndAddedOnEncode() throws {
        let encoded = try XCTUnwrap(FileEncoding.utf8WithBOM.encode("A"))
        XCTAssertEqual(Array(encoded), [0xEF, 0xBB, 0xBF, 0x41])
        XCTAssertEqual(FileEncoding.utf8WithBOM.decode(encoded), "A")
    }

    func testSingleByteCannotRepresentNonLatin1() {
        XCTAssertFalse(FileEncoding.ansiDefault.canRepresent("☃"))
        XCTAssertTrue(FileEncoding.ansiDefault.canRepresent("café"))
    }

    // MARK: - Line endings

    func testLineEndingDetection() {
        XCTAssertEqual(LineEnding.detect(in: "a\r\nb\r\nc"), .crlf)
        XCTAssertEqual(LineEnding.detect(in: "a\nb\nc"), .lf)
        XCTAssertEqual(LineEnding.detect(in: "a\rb\rc"), .cr)
    }

    func testLineEndingDetectionPicksTheDominantStyle() {
        XCTAssertEqual(LineEnding.detect(in: "a\r\nb\r\nc\nd"), .crlf)
        XCTAssertEqual(LineEnding.detect(in: "a\nb\nc\r\nd"), .lf)
    }

    func testTextWithNoLineEndingsUsesThePlatformDefault() {
        XCTAssertEqual(LineEnding.detect(in: "single line"), LineEnding.platformDefault)
        XCTAssertEqual(LineEnding.detect(in: ""), LineEnding.platformDefault)
    }

    /// Raw values must stay aligned with Scintilla's SC_EOL_* order, because
    /// they are passed through the bridge unchanged.
    func testRawValuesMatchScintillaEOLOrder() {
        XCTAssertEqual(LineEnding.crlf.rawValue, 0)  // SC_EOL_CRLF
        XCTAssertEqual(LineEnding.cr.rawValue, 1)    // SC_EOL_CR
        XCTAssertEqual(LineEnding.lf.rawValue, 2)    // SC_EOL_LF
    }
}
