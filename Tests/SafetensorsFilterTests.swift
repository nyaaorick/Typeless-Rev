import XCTest

final class SafetensorsFilterTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("safetensors-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Builds a safetensors file from (name, bytes) pairs, laid out in the given order.
    private func makeFile(_ tensors: [(String, [UInt8])], metadata: [String: String]? = ["format": "mlx"]) throws -> URL {
        var header: [String: Any] = [:]
        if let metadata { header["__metadata__"] = metadata }
        var offset = 0
        var body = Data()
        for (name, bytes) in tensors {
            header[name] = ["dtype": "U8", "shape": [bytes.count], "data_offsets": [offset, offset + bytes.count]]
            offset += bytes.count
            body.append(contentsOf: bytes)
        }
        let json = try JSONSerialization.data(withJSONObject: header)
        var length = UInt64(json.count).littleEndian
        var file = Data(bytes: &length, count: 8)
        file.append(json)
        file.append(body)
        let url = dir.appendingPathComponent("in.safetensors")
        try file.write(to: url)
        return url
    }

    /// Reads a safetensors file back into name -> bytes, plus its metadata.
    private func read(_ url: URL) throws -> (tensors: [String: [UInt8]], metadata: [String: String]?) {
        let data = try Data(contentsOf: url)
        let length = Int(data.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian)
        XCTAssertEqual((8 + length) % 8, 0, "data section must stay 8-byte aligned")
        var header = try XCTUnwrap(JSONSerialization.jsonObject(with: data.subdata(in: 8..<8 + length)) as? [String: Any])
        let metadata = header.removeValue(forKey: "__metadata__") as? [String: String]
        var tensors: [String: [UInt8]] = [:]
        for (name, value) in header {
            let offsets = try XCTUnwrap((value as? [String: Any])?["data_offsets"] as? [Int])
            tensors[name] = Array(data.subdata(in: 8 + length + offsets[0]..<8 + length + offsets[1]))
        }
        return (tensors, metadata)
    }

    func testDropsMatchingTensorsAndKeepsTheRestByteForByte() throws {
        let source = try makeFile([
            ("model.a", [1, 2, 3]),
            ("vision_tower.x", [9, 9, 9, 9, 9]),
            ("model.b", [4, 5]),
            ("vision_tower.y", [8]),
            ("model.c", [6, 7, 8, 9]),
        ])
        let out = dir.appendingPathComponent("out.safetensors")
        let result = try SafetensorsFilter.copy(from: source, to: out) { $0.hasPrefix("vision_tower") }
        XCTAssertEqual(result, SafetensorsFilter.Result(kept: 3, dropped: 2))

        let (tensors, metadata) = try read(out)
        XCTAssertEqual(tensors, ["model.a": [1, 2, 3], "model.b": [4, 5], "model.c": [6, 7, 8, 9]])
        XCTAssertEqual(metadata, ["format": "mlx"])
    }

    func testKeepsTheOnDiskOrderEvenWhenNamesSortDifferently() throws {
        let source = try makeFile([("z", [1]), ("a", [2]), ("drop", [3]), ("m", [4])], metadata: nil)
        let out = dir.appendingPathComponent("out.safetensors")
        _ = try SafetensorsFilter.copy(from: source, to: out) { $0 == "drop" }
        let (tensors, metadata) = try read(out)
        XCTAssertEqual(tensors, ["z": [1], "a": [2], "m": [4]])
        XCTAssertNil(metadata)
    }

    func testDroppingNothingReproducesEveryTensor() throws {
        let source = try makeFile([("a", [1, 2]), ("b", [3])])
        let out = dir.appendingPathComponent("out.safetensors")
        let result = try SafetensorsFilter.copy(from: source, to: out) { _ in false }
        XCTAssertEqual(result, SafetensorsFilter.Result(kept: 2, dropped: 0))
        XCTAssertEqual(try read(out).tensors, ["a": [1, 2], "b": [3]])
    }

    func testRejectsAFileThatIsNotSafetensors() throws {
        let junk = dir.appendingPathComponent("junk")
        try Data(repeating: 0x41, count: 64).write(to: junk)
        XCTAssertThrowsError(
            try SafetensorsFilter.copy(from: junk, to: dir.appendingPathComponent("o")) { _ in false })
    }

    func testRejectsATruncatedFile() throws {
        let source = try makeFile([("a", [1, 2, 3, 4, 5, 6, 7, 8])])
        let data = try Data(contentsOf: source)
        let cut = dir.appendingPathComponent("cut.safetensors")
        try data.prefix(data.count - 4).write(to: cut)
        XCTAssertThrowsError(try SafetensorsFilter.copy(from: cut, to: dir.appendingPathComponent("o")) { _ in false }) {
            XCTAssertEqual($0 as? SafetensorsFilter.Failure, .truncated)
        }
    }
}
