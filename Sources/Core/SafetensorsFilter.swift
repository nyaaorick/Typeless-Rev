import Foundation

/// Copies a `.safetensors` file without some of its tensors.
///
/// The format is an 8-byte little-endian header length, a JSON header mapping each tensor
/// to its dtype, shape and byte range, then the raw data. Kept tensors are copied byte for
/// byte, so their values are exactly the original ones.
enum SafetensorsFilter {
    enum Failure: Error, Equatable {
        case malformedHeader
        case truncated
    }

    struct Result: Equatable {
        var kept: Int
        var dropped: Int
    }

    /// Writes `source` to `destination` minus every tensor whose name `drop` accepts.
    static func copy(
        from source: URL, to destination: URL, dropping drop: (String) -> Bool
    ) throws -> Result {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }

        guard let lengthBytes = try input.read(upToCount: 8), lengthBytes.count == 8 else { throw Failure.truncated }
        let headerLength = Int(lengthBytes.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian)
        guard headerLength > 0, headerLength < 100 << 20,
            let headerData = try input.read(upToCount: headerLength), headerData.count == headerLength,
            var header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any]
        else { throw Failure.malformedHeader }
        let dataStart = UInt64(8 + headerLength)

        let metadata = header.removeValue(forKey: "__metadata__")
        var kept: [(name: String, entry: [String: Any], range: Range<UInt64>)] = []
        for (name, value) in header where !drop(name) {
            guard let entry = value as? [String: Any],
                let offsets = entry["data_offsets"] as? [NSNumber], offsets.count == 2,
                offsets[0].uint64Value <= offsets[1].uint64Value
            else { throw Failure.malformedHeader }
            kept.append((name, entry, offsets[0].uint64Value..<offsets[1].uint64Value))
        }
        kept.sort { $0.range.lowerBound < $1.range.lowerBound }

        // Lay the kept tensors out back to back.
        var newHeader: [String: Any] = [:]
        if let metadata { newHeader["__metadata__"] = metadata }
        var offset: UInt64 = 0
        for item in kept {
            var entry = item.entry
            let length = item.range.upperBound - item.range.lowerBound
            entry["data_offsets"] = [offset, offset + length]
            newHeader[item.name] = entry
            offset += length
        }
        var encoded = try JSONSerialization.data(withJSONObject: newHeader, options: [.sortedKeys])
        encoded.append(Data(repeating: 0x20, count: (8 - encoded.count % 8) % 8))  // keep the data 8-byte aligned

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var length = UInt64(encoded.count).littleEndian
        try output.write(contentsOf: Data(bytes: &length, count: 8))
        try output.write(contentsOf: encoded)

        let chunk = 64 << 20
        for item in kept {
            try input.seek(toOffset: dataStart + item.range.lowerBound)
            var remaining = Int(item.range.upperBound - item.range.lowerBound)
            while remaining > 0 {
                guard let data = try input.read(upToCount: min(chunk, remaining)), !data.isEmpty else {
                    throw Failure.truncated
                }
                try output.write(contentsOf: data)
                remaining -= data.count
            }
        }
        return Result(kept: kept.count, dropped: header.count - kept.count)
    }
}
