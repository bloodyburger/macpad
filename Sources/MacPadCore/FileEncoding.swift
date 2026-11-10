//
//  FileEncoding.swift
//  MacPad
//
//  Encoding detection and conversion.
//
//  Scope note: this is the UTF-8/UTF-16/single-byte subset needed to open and
//  save ordinary files correctly. Milestone M2 extends it to a full
//  code-page menu and adds the byte-for-byte round-trip corpus.
//
//  On "ANSI": on Windows, ANSI means "the system locale code page", which
//  has no macOS equivalent. MacPad treats it as an explicit choice of
//  8-bit code page, defaulting to Windows-1252. This is a deliberate
//  divergence and belongs in docs/DIVERGENCES.md.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum FileEncoding: Equatable {
    case utf8
    case utf8WithBOM
    case utf16LittleEndianWithBOM
    case utf16BigEndianWithBOM
    /// An 8-bit code page, what Windows editors label "ANSI".
    ///
    /// Carries a Foundation String.Encoding rather than a CFStringEncodings
    /// case: Foundation names these directly (.windowsCP1252 and friends) and
    /// needs no CF bridging. M2, which adds the full code-page menu,
    /// will need CFStringEncoding for the pages Foundation does not name.
    case singleByte(String.Encoding)

    static let ansiDefault: FileEncoding = .singleByte(.windowsCP1252)

    var displayName: String {
        switch self {
        case .utf8:                       return "UTF-8"
        case .utf8WithBOM:                return "UTF-8-BOM"
        case .utf16LittleEndianWithBOM:   return "UTF-16 LE BOM"
        case .utf16BigEndianWithBOM:      return "UTF-16 BE BOM"
        case .singleByte(let encoding):
            return "ANSI (\(Self.name(of: encoding)))"
        }
    }

    // MARK: - Storage

    /// A stable name for the session file: the IANA charset name, with the
    /// BOM variants spelled out. Round-trips through init(storageName:).
    var storageName: String {
        switch self {
        case .utf8:                       return "UTF-8"
        case .utf8WithBOM:                return "UTF-8-BOM"
        case .utf16LittleEndianWithBOM:   return "UTF-16LE-BOM"
        case .utf16BigEndianWithBOM:      return "UTF-16BE-BOM"
        case .singleByte(let encoding):
            let cfEncoding = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
            if let name = CFStringConvertEncodingToIANACharSetName(cfEncoding) {
                return name as String
            }
            return "nsencoding-\(encoding.rawValue)"
        }
    }

    init?(storageName: String) {
        switch storageName {
        case "UTF-8":        self = .utf8
        case "UTF-8-BOM":    self = .utf8WithBOM
        case "UTF-16LE-BOM": self = .utf16LittleEndianWithBOM
        case "UTF-16BE-BOM": self = .utf16BigEndianWithBOM
        default:
            if storageName.hasPrefix("nsencoding-"),
               let raw = UInt(storageName.dropFirst("nsencoding-".count)) {
                self = .singleByte(String.Encoding(rawValue: raw))
                return
            }
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(storageName as CFString)
            guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
            self = .singleByte(String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding)))
        }
    }

    private static func name(of encoding: String.Encoding) -> String {
        switch encoding {
        case .windowsCP1250: return "Windows-1250, Central European"
        case .windowsCP1251: return "Windows-1251, Cyrillic"
        case .windowsCP1252: return "Windows-1252"
        case .windowsCP1253: return "Windows-1253, Greek"
        case .windowsCP1254: return "Windows-1254, Turkish"
        case .isoLatin1:     return "ISO-8859-1"
        case .isoLatin2:     return "ISO-8859-2"
        case .macOSRoman:    return "Mac OS Roman"
        default:
            let cfEncoding = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
            if let name = CFStringConvertEncodingToIANACharSetName(cfEncoding) {
                return name as String
            }
            return "encoding \(encoding.rawValue)"
        }
    }

    private var stringEncoding: String.Encoding {
        switch self {
        case .utf8, .utf8WithBOM:
            return .utf8
        case .utf16LittleEndianWithBOM:
            return .utf16LittleEndian
        case .utf16BigEndianWithBOM:
            return .utf16BigEndian
        case .singleByte(let encoding):
            return encoding
        }
    }

    private var byteOrderMark: Data {
        switch self {
        case .utf8WithBOM:              return Data([0xEF, 0xBB, 0xBF])
        case .utf16LittleEndianWithBOM: return Data([0xFF, 0xFE])
        case .utf16BigEndianWithBOM:    return Data([0xFE, 0xFF])
        case .utf8, .singleByte:        return Data()
        }
    }

    // MARK: - Detection

    /// Determine a file's encoding: trust a byte order mark if there
    /// is one, otherwise accept UTF-8 if the bytes are valid UTF-8, otherwise
    /// fall back to the configured 8-bit code page.
    static func detect(in data: Data, singleByteFallback: FileEncoding = .ansiDefault) -> FileEncoding {
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return .utf8WithBOM
        }
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xFE {
            return .utf16LittleEndianWithBOM
        }
        if data.count >= 2, data[0] == 0xFE, data[1] == 0xFF {
            return .utf16BigEndianWithBOM
        }
        // No BOM. Valid UTF-8 (which includes pure ASCII) is treated as UTF-8.
        if String(data: data, encoding: .utf8) != nil {
            return .utf8
        }
        return singleByteFallback
    }

    // MARK: - Conversion

    /// Decode file bytes to a string, stripping any byte order mark.
    func decode(_ data: Data) -> String? {
        let bom = byteOrderMark
        let body = data.count >= bom.count && data.prefix(bom.count) == bom
            ? data.dropFirst(bom.count)
            : data
        return String(data: body, encoding: stringEncoding)
    }

    /// Encode a string to file bytes, adding any byte order mark.
    func encode(_ string: String) -> Data? {
        guard let body = string.data(using: stringEncoding, allowLossyConversion: false) else {
            return nil
        }
        return byteOrderMark + body
    }

    /// Whether every character in `string` survives this encoding. Used to warn
    /// before a save would silently mangle the file.
    func canRepresent(_ string: String) -> Bool {
        string.data(using: stringEncoding, allowLossyConversion: false) != nil
    }
}

/// End-of-line convention. Raw values are Scintilla's SC_EOL_* order, so they
/// pass straight through to the bridge.
enum LineEnding: Int, CaseIterable {
    case crlf = 0   // Windows
    case cr   = 1   // Classic Mac
    case lf   = 2   // Unix

    var displayName: String {
        switch self {
        case .crlf: return "Windows (CR LF)"
        case .cr:   return "Macintosh (CR)"
        case .lf:   return "Unix (LF)"
        }
    }

    var sequence: String {
        switch self {
        case .crlf: return "\r\n"
        case .cr:   return "\r"
        case .lf:   return "\n"
        }
    }

    /// macOS default for new documents: LF, as every Mac tool expects.
    /// Existing files keep whatever they already had.
    static let platformDefault: LineEnding = .lf

    /// Detect the dominant line ending when a file is loaded.
    static func detect(in text: String) -> LineEnding {
        var crlf = 0, cr = 0, lf = 0
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\r":
                if previousWasCR { cr += 1 }
                previousWasCR = true
            case "\n":
                if previousWasCR { crlf += 1; previousWasCR = false } else { lf += 1 }
            default:
                if previousWasCR { cr += 1; previousWasCR = false }
            }
        }
        if previousWasCR { cr += 1 }

        if crlf == 0 && cr == 0 && lf == 0 { return .platformDefault }
        if crlf >= cr && crlf >= lf { return .crlf }
        if lf >= cr { return .lf }
        return .cr
    }
}
