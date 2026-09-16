import Foundation
import Testing

@testable import CliampCore

/// A reader over an in-memory blob, with optional truncation limits.
private struct BlobReader: ByteRangeReader {
    let data: Data
    let maxRead: Int?

    init(_ data: Data, maxRead: Int? = nil) {
        self.data = data
        self.maxRead = maxRead
    }

    func readRange(offset: Int64, length: Int) async throws -> Data {
        guard offset >= 0, offset < Int64(data.count) else { return Data() }
        let wanted = maxRead.map { min(length, $0) } ?? length
        let end = min(Int(offset) + wanted, data.count)
        // Zero-based, like the readers the app actually uses.
        return Data(data[Int(offset)..<end])
    }

    func fileSize() async throws -> Int64 {
        Int64(data.count)
    }
}

private let pngBytes = Data((0..<256).map { UInt8($0 % 251) })

private func be32(_ value: Int) -> Data {
    Data([
        UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
    ])
}

private func syncSafe(_ value: Int) -> Data {
    Data([
        UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F),
        UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F),
    ])
}

private func atom(_ type: String, _ payload: Data) -> Data {
    be32(payload.count + 8) + Data(type.utf8) + payload
}

/// An ID3v2.3 tag holding one APIC frame with a PNG cover.
private func id3Fixture(image: Data = pngBytes, version: UInt8 = 3) -> Data {
    var frame = Data([0]) // latin1
    frame.append(contentsOf: Array("image/png".utf8))
    frame.append(0)
    frame.append(3) // front cover
    frame.append(contentsOf: Array("cover".utf8))
    frame.append(0)
    frame.append(image)
    var tag = Data([UInt8(ascii: "A"), UInt8(ascii: "P"), UInt8(ascii: "I"), UInt8(ascii: "C")])
    tag.append(version == 4 ? syncSafe(frame.count) : be32(frame.count))
    tag.append(contentsOf: [0, 0]) // frame flags
    tag.append(frame)
    var header = Data([UInt8(ascii: "I"), UInt8(ascii: "D"), UInt8(ascii: "3"), version, 0, 0])
    header.append(syncSafe(tag.count))
    return header + tag
}

/// An APIC frame whose description is UTF-16 with a BOM — the shape iTunes
/// and most taggers write, where a byte-wise terminator scan goes wrong.
private func id3UnicodeDescriptionFixture(image: Data) -> Data {
    var frame = Data([1]) // UTF-16 with BOM
    frame.append(contentsOf: Array("image/jpeg".utf8))
    frame.append(0)
    frame.append(3) // front cover
    frame.append(contentsOf: [0xFF, 0xFE]) // BOM
    for unit in Array("Cover".utf16) {
        frame.append(UInt8(unit & 0xFF))
        frame.append(UInt8(unit >> 8))
    }
    frame.append(contentsOf: [0, 0]) // terminator
    frame.append(image)
    var tag = Data([UInt8(ascii: "A"), UInt8(ascii: "P"), UInt8(ascii: "I"), UInt8(ascii: "C")])
    tag.append(be32(frame.count))
    tag.append(contentsOf: [0, 0])
    tag.append(frame)
    var header = Data([UInt8(ascii: "I"), UInt8(ascii: "D"), UInt8(ascii: "3"), 3, 0, 0])
    header.append(syncSafe(tag.count))
    return header + tag
}

/// An MP4 with ftyp, a large mdat to skip, then moov > udta > meta > ilst >
/// covr > data around the cover.
private func m4aFixture(image: Data = pngBytes) -> Data {
    let ftyp = atom("ftyp", Data("M4A isom".utf8))
    let mdat = atom("mdat", Data(count: 4096))
    var data = Data([0, 0, 0, 13, 0, 0, 0, 0]) // type flag 13 (jpeg), locale 0
    data.append(image)
    let covr = atom("covr", atom("data", data))
    let ilst = atom("ilst", covr)
    let meta = atom("meta", Data([0, 0, 0, 0]) + ilst)
    let udta = atom("udta", meta)
    let moov = atom("moov", udta)
    return ftyp + mdat + moov
}

/// A FLAC stream with one PICTURE block.
private func flacFixture(image: Data = pngBytes) -> Data {
    let streamInfo = Data([0x00]) + Data([0, 0, 34]) + Data(count: 34)
    var picture = Data()
    picture.append(be32(3)) // front cover
    let mime = Data("image/png".utf8)
    picture.append(be32(mime.count))
    picture.append(mime)
    picture.append(be32(0)) // description
    picture.append(be32(0)) // width
    picture.append(be32(0)) // height
    picture.append(be32(0)) // depth
    picture.append(be32(0)) // colors
    picture.append(be32(image.count))
    picture.append(image)
    var pictureBlock = Data([0x86]) // last block, type 6
    pictureBlock.append(Data([
        UInt8((picture.count >> 16) & 0xFF),
        UInt8((picture.count >> 8) & 0xFF),
        UInt8(picture.count & 0xFF),
    ]))
    pictureBlock.append(picture)
    return Data("fLaC".utf8) + streamInfo + pictureBlock
}

/// Opt-in check against a real file:
/// `CLIAMP_ART_FILE=/path/to.mp3 swift test --filter RealFileArtworkTests`
@Suite("real file artwork", .enabled(if: ProcessInfo.processInfo.environment["CLIAMP_ART_FILE"] != nil))
struct RealFileArtworkTests {
    @Test("extracts the cover from a real file")
    func realFile() async throws {
        let path = ProcessInfo.processInfo.environment["CLIAMP_ART_FILE"] ?? ""
        let image = await EmbeddedArtwork.extract(
            from: LocalFileByteRangeReader(url: URL(fileURLWithPath: path)),
            fileExtension: (path as NSString).pathExtension
        )
        #expect(image != nil, "no artwork found in \(path)")
        #expect((image?.count ?? 0) > 1024)
        #expect(image?.prefix(3).elementsEqual([0xFF, 0xD8, 0xFF]) == true)
    }
}

@Suite("embedded artwork")
struct EmbeddedArtworkTests {
    @Test("ID3v2.3 APIC is extracted")
    func id3v23() async throws {
        let image = await EmbeddedArtwork.extract(
            from: BlobReader(id3Fixture()), fileExtension: "mp3"
        )
        #expect(image == pngBytes)
    }

    @Test("ID3v2.4 syncsafe frame sizes are extracted")
    func id3v24() async throws {
        let image = await EmbeddedArtwork.extract(
            from: BlobReader(id3Fixture(version: 4)), fileExtension: "mp3"
        )
        #expect(image == pngBytes)
    }

    @Test("a UTF-16 APIC description does not leak a byte into the image")
    func unicodeDescription() async throws {
        // A real JPEG header, so the parser's own magic check applies.
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(count: 252)
        let image = await EmbeddedArtwork.extract(
            from: BlobReader(id3UnicodeDescriptionFixture(image: jpeg)), fileExtension: "mp3"
        )
        #expect(image == jpeg)
    }

    @Test("an MP4 covr atom is found past a large mdat")
    func mp4() async throws {
        let image = await EmbeddedArtwork.extract(
            from: BlobReader(m4aFixture()), fileExtension: "m4a"
        )
        #expect(image == pngBytes)
    }

    @Test("a FLAC PICTURE block is extracted")
    func flac() async throws {
        let image = await EmbeddedArtwork.extract(
            from: BlobReader(flacFixture()), fileExtension: "flac"
        )
        #expect(image == pngBytes)
    }

    @Test("an oversized declared cover is refused, not read")
    func oversized() async throws {
        var huge = Data([0])
        huge.append(contentsOf: Array("image/png".utf8))
        huge.append(0)
        huge.append(3)
        huge.append(0)
        huge.append(Data(count: EmbeddedArtwork.maxImageBytes + 2048))
        var tag = Data([UInt8(ascii: "A"), UInt8(ascii: "P"), UInt8(ascii: "I"), UInt8(ascii: "C")])
        tag.append(be32(huge.count))
        tag.append(contentsOf: [0, 0])
        tag.append(huge)
        var header = Data([UInt8(ascii: "I"), UInt8(ascii: "D"), UInt8(ascii: "3"), 3, 0, 0])
        header.append(syncSafe(tag.count))
        let image = await EmbeddedArtwork.extract(
            from: BlobReader(header + tag), fileExtension: "mp3"
        )
        #expect(image == nil)
    }

    @Test("junk, wrong extensions and truncation all yield nothing")
    func rejects() async throws {
        #expect(await EmbeddedArtwork.extract(from: BlobReader(Data(count: 64)), fileExtension: "mp3") == nil)
        #expect(await EmbeddedArtwork.extract(from: BlobReader(id3Fixture()), fileExtension: "wav") == nil)
        let truncated = BlobReader(id3Fixture(), maxRead: 8)
        #expect(await EmbeddedArtwork.extract(from: truncated, fileExtension: "mp3") == nil)
    }

    @Test("a second APIC is reached when the first frame is something else")
    func skipsOtherFrames() async throws {
        var tag = Data([UInt8(ascii: "T"), UInt8(ascii: "I"), UInt8(ascii: "T"), UInt8(ascii: "2")])
        let title = Data([0]) + Array("Hello".utf8)
        tag.append(be32(title.count))
        tag.append(contentsOf: [0, 0])
        tag.append(title)
        let apic = id3Fixture().dropFirst(10)
        tag.append(apic)
        var header = Data([UInt8(ascii: "I"), UInt8(ascii: "D"), UInt8(ascii: "3"), 3, 0, 0])
        header.append(syncSafe(tag.count))
        let image = await EmbeddedArtwork.extract(
            from: BlobReader(header + tag), fileExtension: "mp3"
        )
        #expect(image == pngBytes)
    }
}
