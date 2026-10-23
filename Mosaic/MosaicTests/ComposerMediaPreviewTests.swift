import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Mosaic

@Suite(.serialized)
@MainActor
struct ComposerMediaPreviewTests {
    private let owner = UUID(uuidString: "00000000-0000-0000-0000-0000000000b1")!
    private let mosaic = UUID(uuidString: "00000000-0000-0000-0000-0000000000b2")!

    private func image(width: Int, height: Int, opaque: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
            if !opaque {
                context.cgContext.clear(CGRect(x: 0, y: 0, width: 10, height: 10))
            }
        }
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func previewKeepsTheShapeAndSurvivesTheRoundTrip() throws {
        let cgImage = try #require(image(width: 300, height: 200, opaque: true).cgImage)
        let preview = try #require(ComposerMediaPreview.make(from: cgImage))
        #expect(preview.width == 8 && preview.height == 5)
        #expect(abs(preview.aspect - 1.5) < 0.001)
        #expect(preview.encoded.count < 250)
        let decoded = try #require(ComposerMediaPreview(encoded: preview.encoded))
        #expect(decoded.width == preview.width && decoded.pixels == preview.pixels)
        #expect(decoded.image != nil)
        // Left half teal, right half orange.
        #expect(decoded.pixels[0] < decoded.pixels[(preview.width - 1) * 3])
    }

    @Test
    func malformedPreviewsAreIgnored() {
        for bad in ["", "1.5|8x5", "x|8x5|AAAA", "1.5|9x5|AAAA", "1.5|8x5|AAAA", "-1|1x1|AAAA", "1|1x1|!!"] {
            #expect(ComposerMediaPreview(encoded: bad) == nil, "\(bad)")
        }
    }

    @Test
    func seeThroughPicturesGetNoPreview() throws {
        let cgImage = try #require(image(width: 40, height: 40, opaque: false).cgImage)
        #expect(ComposerMediaPreview.make(from: cgImage) == nil)
    }

    @Test
    func previewsAreMadeOncePerFileAndMissingFilesWait() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try #require(image(width: 120, height: 160, opaque: true).jpegData(compressionQuality: 0.8))
            .write(to: folder.appendingPathComponent("photo.jpg"))
        try #require(image(width: 40, height: 40, opaque: false).pngData())
            .write(to: folder.appendingPathComponent("sticker.png"))
        let previews = await ComposerRemoteSync.addingPreviews(
            to: [:],
            for: ["photo.jpg", "sticker.png", "missing.jpg"],
            mediaFile: { folder.appendingPathComponent($0) }
        )
        #expect(ComposerMediaPreview(encoded: previews["photo.jpg"] ?? "")?.height == 8)
        #expect(previews["sticker.png"] == "", "Remembered as having none, so it isn't tried again")
        #expect(previews["missing.jpg"] == nil, "Tried again once the file is on this phone")
    }

    @Test
    func boardsCarryPreviewsOnlyForUploadedFiles() {
        var photo = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0.2, y: 0.2))
        photo.mediaFileName = "photo.jpg"
        var waiting = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0.4, y: 0.4))
        waiting.mediaFileName = "waiting.jpg"
        var snapshot = ComposerSnapshot.empty
        snapshot.mosaicBlocks = [photo, waiting]
        let stamped = ComposerMediaCatalog.stamped(
            ComposerBoardSync.split(snapshot: snapshot, mosaicID: mosaic),
            assets: ["photo.jpg": UUID().uuidString],
            previews: ["photo.jpg": "1.500|8x5|AAAA", "waiting.jpg": "1.000|1x1|AAAA", "other.jpg": "1|1x1|AAAA"]
        )
        #expect(stamped[0].body.mediaPreviews == ["photo.jpg": "1.500|8x5|AAAA"])
    }

    @Test
    func syncStateKeepsPreviewsAndReadsOlderStates() throws {
        var state = ComposerSyncState(mosaicID: mosaic)
        state.mediaPreviews = ["photo.jpg": "1.500|8x5|AAAA", "sticker.png": ""]
        let decoded = try JSONDecoder().decode(ComposerSyncState.self, from: JSONEncoder().encode(state))
        #expect(decoded.mediaPreviews == state.mediaPreviews)
        let older = try JSONDecoder().decode(
            ComposerSyncState.self,
            from: Data(#"{"mosaicID":"\#(mosaic.uuidString)","revisions":{},"mediaAssets":{},"pendingRestore":false,"pushedHashes":{}}"#.utf8)
        )
        #expect(older.mediaPreviews.isEmpty)
    }

    @Test
    func aVisitQuietlyFetchesOtherBoardsPhotosButNotVideos() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = ComposerStorageLocation(root: root.appendingPathComponent("visit"))
        let pursuit = UUID()
        let mosaicDoc = ComposerSyncDocument(
            id: mosaic, parentID: nil, role: .mosaic, title: "", visibility: "public",
            body: ComposerBoardBody(blocks: [], layoutHeight: nil, background: nil, mosaicTitlePlaced: nil, pursuitPagesBlanked: nil)
        )
        var photo = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0.2, y: 0.2))
        photo.mediaFileName = "inside.jpg"
        var video = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0.4, y: 0.4))
        video.mediaFileName = "clip.mov"
        let pursuitDoc = ComposerSyncDocument(
            id: pursuit, parentID: nil, role: .pursuit, title: "Golf", visibility: "public",
            body: ComposerBoardBody(
                blocks: [photo, video], layoutHeight: nil, background: nil, mosaicTitlePlaced: nil, pursuitPagesBlanked: nil,
                mediaAssets: ["inside.jpg": UUID().uuidString, "clip.mov": UUID().uuidString],
                mediaPreviews: ["inside.jpg": "1.500|1x1|AAAA"]
            )
        )
        PrefetchURLProtocol.state.reset([(200, Data([9, 9, 9]))])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PrefetchURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = MosaicVisitClient(config: SupabaseSyncConfig(url: URL(string: "https://visit.invalid")!, anonKey: "key"),
                                       session: session)
        let media = try MosaicVisitMedia(documents: [mosaicDoc, pursuitDoc], mosaicID: mosaic, ownerID: owner,
                                         location: location, client: client)
        #expect(media.previews["inside.jpg"]?.aspect == 1.5)
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false, location: location)

        await media.load(documentID: nil, store: store, token: "visitor")
        await media.prefetchFinished()

        let requested = PrefetchURLProtocol.state.requests.compactMap { $0.url?.path }
        #expect(requested.count == 1)
        #expect(requested.first?.hasSuffix("/display") == true)
        #expect(try Data(contentsOf: location.mediaDirectory.appendingPathComponent("inside.jpg")) == Data([9, 9, 9]))
        #expect(store.mediaVersions["inside.jpg"] == 1)
        #expect(PrefetchURLProtocol.state.requests.first?.allowsConstrainedNetworkAccess == false)

        // Opening the Pursuit now needs only its video.
        PrefetchURLProtocol.state.reset([(200, Data([1]))])
        await media.load(documentID: ComposerDocumentID(rawValue: pursuit.uuidString), store: store, token: "visitor")
        #expect(PrefetchURLProtocol.state.requests.compactMap { $0.url?.path }.allSatisfy { $0.hasSuffix("/original") })
        #expect(PrefetchURLProtocol.state.requests.count == 1)
    }
}

private final class PrefetchURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = PrefetchReplies()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.state.next(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class PrefetchReplies: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [(Int, Data)] = []
    private var received: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { received } }
    func reset(_ replies: [(Int, Data)]) {
        lock.withLock { self.replies = replies; received = [] }
    }
    func next(_ request: URLRequest) -> (Int, Data) {
        lock.withLock {
            received.append(request)
            return replies.isEmpty ? (500, Data()) : replies.removeFirst()
        }
    }
}
