import Foundation

enum TextOffsets {
    /// librime reports cursor and selection positions as UTF-8 byte offsets; AppKit
    /// text APIs count UTF-16 code units. An offset that lands inside a multi-byte
    /// character is rounded down to that character's start.
    static func utf16Offset(forUTF8Offset byteOffset: Int, in string: String) -> Int {
        let bytes = Array(string.utf8)
        var end = max(0, min(byteOffset, bytes.count))
        while end > 0, end < bytes.count, bytes[end] & 0xC0 == 0x80 { end -= 1 }
        return String(decoding: bytes[..<end], as: UTF8.self).utf16.count
    }
}
