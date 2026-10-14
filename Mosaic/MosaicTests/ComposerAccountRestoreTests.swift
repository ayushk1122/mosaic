import Foundation
import Testing
@testable import Mosaic

@Suite(.serialized)
@MainActor
struct ComposerAccountRestoreTests {
    private let owner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let mosaic = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let asset = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    private func location() throws -> ComposerStorageLocation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ComposerStorageLocation(root: root.appendingPathComponent("account"))
    }

    private func rows() -> [ComposerRestoredDocument] {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        store.placeMosaicTitleIfNeeded()
        let block = store.addBlock(.pursuit, to: nil)
        let pursuit = store.block(with: block, in: nil)?.pursuitID
        store.addBlock(.text, to: pursuit)
        store.addBlock(.scrapbook, to: pursuit)
        return ComposerBoardSync.split(snapshot: store.snapshot, mosaicID: mosaic).enumerated().map { index, doc in
            ComposerRestoredDocument(id: doc.id, ownerID: owner, parentID: doc.parentID,
                                     role: doc.role, title: doc.title, body: doc.body, revision: Int64(index + 7))
        }
    }

    private func client(_ replies: [(Int, Data)]) -> SupabaseDocumentSync {
        RestoreURLProtocol.state.reset(replies)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RestoreURLProtocol.self]
        return SupabaseDocumentSync(config: SupabaseSyncConfig(url: URL(string: "https://restore.invalid")!, anonKey: "test-key"),
                                    session: URLSession(configuration: config))
    }

    private var mosaicResponse: Data { Data("\"\(mosaic.uuidString.lowercased())\"".utf8) }

    @Test func opensLandingBoardBeforeChildrenAndMediaAndPreservesEdits() async throws {
        let location = try location()
        defer { try? FileManager.default.removeItem(at: location.root.deletingLastPathComponent()) }
        let starter = ComposerStore(location: location)
        starter.placeMosaicTitleIfNeeded()
        starter.lockLayoutHeight(800, for: nil)
        var rows = rows()
        rows[0].body.mediaAssets = ["photo.jpg": asset.uuidString]
        var photo = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0.2, y: 0.3))
        photo.mediaFileName = "photo.jpg"
        rows[0].body.blocks.append(photo)
        let image = Data([1, 2, 3, 4])
        let client = client([(200, mosaicResponse), (200, try JSONEncoder().encode([rows[0]])),
                             (200, try JSONEncoder().encode(rows)), (200, Data("[]".utf8)), (200, image)])
        defer { client.session.invalidateAndCancel() }
        try await ComposerAccountRestore(client: client).prepare(ownerID: owner, accessToken: "test-token", location: location)
        #expect(RestoreURLProtocol.state.requests.count == 2)
        let store = ComposerStore(location: location)
        #expect(store.isRestoringDocuments)
        #expect(store.snapshot.pursuits.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.mediaURL(for: "photo.jpg").path))
        let pursuitID = try #require(rows[0].body.blocks.first { $0.kind == .pursuit }?.pursuitID)
        #expect(store.isWaitingForDocument(pursuitID))
        let edit = store.addBlock(.text, to: nil)
        let downloader = ComposerBackgroundRestore()
        try await downloader.run(store: store, client: client, ownerID: owner, accessToken: "test-token")
        #expect(!store.isRestoringDocuments)
        #expect(!store.isWaitingForDocument(pursuitID))
        #expect(store.block(with: edit, in: nil) != nil)
        #expect(store.snapshot.pursuits.count == rows.count - 1)
        #expect(store.snapshot.pursuits.contains { $0.blocks.contains { $0.kind == .text } })
        let state = try JSONDecoder().decode(ComposerSyncState.self, from: Data(contentsOf: location.syncStateURL))
        #expect(!state.pendingRestore)
        #expect(state.revisions.count == rows.count)
        #expect(state.revisions[mosaic.uuidString.lowercased()] == 7)
        #expect(try Data(contentsOf: store.mediaURL(for: "photo.jpg")) == image)
        #expect(store.mediaVersions["photo.jpg"] == 1)
        #expect(!ComposerBackgroundRestore.needsWork(store: store))
        #expect(RestoreURLProtocol.state.requests.allSatisfy {
            $0.httpMethod == "GET" || $0.url?.path == "/rest/v1/rpc/own_mosaic_id"
        })
        #expect(RestoreURLProtocol.state.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token"
        })
    }

    @Test func paginationContinuesAfterShortPageAndKeepsOwnerFilter() async throws {
        let rows = rows()
        let client = client([(200, try JSONEncoder().encode(Array(rows.prefix(1)))),
                             (200, try JSONEncoder().encode(Array(rows.dropFirst()))), (200, Data("[]".utf8))])
        defer { client.session.invalidateAndCancel() }
        let loaded = try await client.ownDocuments(ownerID: owner, accessToken: "test-token")
        #expect(loaded.count == rows.count)
        let queries = RestoreURLProtocol.state.requests.map {
            URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)!.queryItems!
        }
        #expect(queries.map { $0.first { $0.name == "offset" }?.value } == ["0", "1", String(rows.count)])
        #expect(queries.allSatisfy { $0.contains(URLQueryItem(name: "owner_id", value: "eq.\(owner.uuidString.lowercased())")) })
    }

    @Test func failedMediaDoesNotBlockBoardsAndRelaunchRetriesOnlyMissingFiles() async throws {
        let location = try location()
        defer { try? FileManager.default.removeItem(at: location.root.deletingLastPathComponent()) }
        var rows = rows()
        rows[0].body.mediaAssets = ["photo.jpg": asset.uuidString]
        var photo = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0.2, y: 0.3))
        photo.mediaFileName = "photo.jpg"
        rows[0].body.blocks.append(photo)
        let client = client([(200, mosaicResponse), (200, try JSONEncoder().encode([rows[0]])),
                             (200, try JSONEncoder().encode(rows)), (200, Data("[]".utf8)), (503, Data()), (200, Data([1]))])
        defer { client.session.invalidateAndCancel() }
        try await ComposerAccountRestore(client: client).prepare(ownerID: owner, accessToken: "token", location: location)
        let store = ComposerStore(location: location)
        let downloads = ComposerBackgroundRestore()
        try await downloads.run(store: store, client: client, ownerID: owner, accessToken: "token")
        #expect(downloads.failure != nil)
        #expect(!store.isRestoringDocuments)
        #expect(store.snapshot.pursuits.count == rows.count - 1)
        let count = RestoreURLProtocol.state.requests.count
        // Cached reopening needs no root or board downloads, only the missing file.
        try await ComposerAccountRestore(client: client).prepare(ownerID: owner, accessToken: "token", location: location)
        let reopened = ComposerStore(location: location)
        try await downloads.run(store: reopened, client: client, ownerID: owner, accessToken: "token")
        #expect(RestoreURLProtocol.state.requests.count == count + 1)
        #expect(downloads.failure == nil)
        #expect(!ComposerBackgroundRestore.needsWork(store: reopened))
    }

    @Test func failedChildrenResumeAfterRelaunchWithoutReplacingLocalEdits() async throws {
        let location = try location()
        defer { try? FileManager.default.removeItem(at: location.root.deletingLastPathComponent()) }
        let rows = rows()
        let client = client([(200, mosaicResponse), (200, try JSONEncoder().encode([rows[0]])),
                             (503, Data()), (200, try JSONEncoder().encode(rows)), (200, Data("[]".utf8))])
        defer { client.session.invalidateAndCancel() }
        try await ComposerAccountRestore(client: client).prepare(ownerID: owner, accessToken: "token", location: location)
        let store = ComposerStore(location: location)
        let edit = store.addBlock(.text, to: nil)
        do {
            try await ComposerBackgroundRestore().run(store: store, client: client, ownerID: owner, accessToken: "token")
            Issue.record("An incomplete board download must fail")
        } catch {}
        #expect(ComposerBackgroundRestore.state(at: location)?.pendingRestore == true)
        let reopened = ComposerStore(location: location)
        #expect(reopened.block(with: edit, in: nil) != nil)
        #expect(reopened.isRestoringDocuments)
        try await ComposerBackgroundRestore().run(store: reopened, client: client, ownerID: owner, accessToken: "token")
        #expect(reopened.block(with: edit, in: nil) != nil)
        #expect(!reopened.isRestoringDocuments)
    }

    @Test func deletionAndUndoDuringDownloadDoNotLosePursuitContents() async throws {
        let location = try location()
        defer { try? FileManager.default.removeItem(at: location.root.deletingLastPathComponent()) }
        let rows = rows()
        let client = client([(200, mosaicResponse), (200, try JSONEncoder().encode([rows[0]])),
                             (200, try JSONEncoder().encode(rows)), (200, Data("[]".utf8))])
        defer { client.session.invalidateAndCancel() }
        try await ComposerAccountRestore(client: client).prepare(ownerID: owner, accessToken: "token", location: location)
        let store = ComposerStore(location: location)
        let block = try #require(store.snapshot.mosaicBlocks.first { $0.kind == .pursuit })
        store.deleteBlock(block.id, in: nil)
        try await ComposerBackgroundRestore().run(store: store, client: client, ownerID: owner, accessToken: "token")
        #expect(store.snapshot.pursuits.isEmpty)
        store.undo(in: nil)
        #expect(store.block(with: block.id, in: nil) != nil)
        #expect(store.snapshot.pursuits.count == rows.count - 1)
        #expect(store.snapshot.pursuits.contains { $0.blocks.contains { $0.kind == .text } })
    }

    @Test func partialRestorationBlocksUploadScheduling() throws {
        let location = try location()
        defer { try? FileManager.default.removeItem(at: location.root.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: location.root, withIntermediateDirectories: true)
        try JSONEncoder().encode(ComposerSyncState(mosaicID: mosaic, pendingRestore: true)).write(to: location.syncStateURL)
        let sync = ComposerRemoteSync(location: location)
        #expect(!sync.canUpload)
        try JSONEncoder().encode(ComposerSyncState(mosaicID: mosaic)).write(to: location.syncStateURL)
        #expect(sync.canUpload)
    }

    @Test func mediaRefreshTargetsOnlyTheDownloadedFile() {
        let photo = URL(fileURLWithPath: "/tmp/photo.jpg")
        let other = URL(fileURLWithPath: "/tmp/other.jpg")
        #expect(ComposerMediaLoadKey(photo, versions: [:]) != ComposerMediaLoadKey(photo, versions: ["photo.jpg": 1]))
        #expect(ComposerMediaLoadKey(other, versions: [:]) == ComposerMediaLoadKey(other, versions: ["photo.jpg": 1]))
    }

    @Test func establishedLocalEditsArePreservedWithoutNetwork() async throws {
        let location = try location()
        defer { try? FileManager.default.removeItem(at: location.root.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: location.root, withIntermediateDirectories: true)
        let store = ComposerStore(location: location)
        store.addBlock(.text, to: nil)
        let before = try Data(contentsOf: location.snapshotURL)
        try JSONEncoder().encode(ComposerSyncState(mosaicID: mosaic)).write(to: location.syncStateURL)
        let client = client([])
        defer { client.session.invalidateAndCancel() }
        try await ComposerAccountRestore(client: client).prepare(ownerID: owner, accessToken: "token", location: location)
        #expect(RestoreURLProtocol.state.requests.isEmpty)
        #expect(try Data(contentsOf: location.snapshotURL) == before)
    }

    @Test func unsyncedEditsDoNotGetOverwrittenByCloudBoard() async throws {
        let location = try location()
        defer { try? FileManager.default.removeItem(at: location.root.deletingLastPathComponent()) }
        let store = ComposerStore(location: location)
        store.addBlock(.text, to: nil)
        let before = try Data(contentsOf: location.snapshotURL)
        let client = client([(200, mosaicResponse)])
        defer { client.session.invalidateAndCancel() }
        do {
            try await ComposerAccountRestore(client: client).prepare(ownerID: owner, accessToken: "token", location: location)
            Issue.record("Unsynced local edits need reconciliation")
        } catch ComposerRestoreError.localChanges {} catch { throw error }
        #expect(try Data(contentsOf: location.snapshotURL) == before)
        #expect(!FileManager.default.fileExists(atPath: location.syncStateURL.path))
    }

    @Test func starterHeadingIsRecognizedButAnEditedHeadingIsNot() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        store.placeMosaicTitleIfNeeded()
        store.blankPursuitPagesIfNeeded() // Previous versions wrote this flag even on a blank board.
        store.lockLayoutHeight(800, for: nil) // The canvas records its size without user edits.
        #expect(ComposerAccountRestore.isStarterBoard(store.snapshot))
        var edited = store.snapshot
        edited.mosaicBlocks[0].text = "My edited heading"
        #expect(!ComposerAccountRestore.isStarterBoard(edited))
    }

    @Test func rejectsIncompleteForeignAndUnsafeData() throws {
        let good = rows()
        #expect(throws: (any Error).self) {
            _ = try ComposerAccountRestore.assemble(rows: Array(good.prefix(1)), ownerID: owner, mosaicID: mosaic)
        }
        var foreign = good
        foreign[0].ownerID = UUID()
        #expect(throws: (any Error).self) {
            _ = try ComposerAccountRestore.assemble(rows: foreign, ownerID: owner, mosaicID: mosaic)
        }
        var unsafe = good
        unsafe[0].body.mediaAssets = ["../composer.json": asset.uuidString]
        #expect(throws: (any Error).self) {
            _ = try ComposerAccountRestore.assemble(rows: unsafe, ownerID: owner, mosaicID: mosaic)
        }
        #expect(throws: (any Error).self) {
            _ = try ComposerAccountRestore.assemble(rows: good + [good[0]], ownerID: owner, mosaicID: mosaic)
        }
    }

    @Test func lowercaseBoardReferencesSurviveStorePruning() throws {
        var rows = rows()
        for index in rows[0].body.blocks.indices {
            if let id = rows[0].body.blocks[index].pursuitID {
                rows[0].body.blocks[index].pursuitID = ComposerDocumentID(rawValue: id.rawValue.lowercased())
            }
        }
        var (snapshot, _) = try ComposerAccountRestore.assemble(rows: rows, ownerID: owner, mosaicID: mosaic)
        #expect(ComposerBoardSync.pruneUnreferenced(&snapshot).isEmpty)
        #expect(snapshot.pursuits.count == rows.count - 1)
    }

    @Test func malformedResponseIsNotTreatedAsNewAccount() async throws {
        let client = client([(200, Data("{}".utf8))])
        defer { client.session.invalidateAndCancel() }
        do {
            _ = try await client.ownMosaicID(accessToken: "token")
            Issue.record("Malformed data must fail rather than creating a new Mosaic")
        } catch SupabaseDocumentSyncError.unexpectedResponse {} catch { throw error }
    }

    @Test func visitLoadsOnlyOpenedBoardAndReusesCachedMedia() async throws {
        let location = try location()
        defer { try? FileManager.default.removeItem(at: location.root.deletingLastPathComponent()) }
        var documents = rows().map(\.document)
        let child = try #require(documents.firstIndex { $0.role == .pursuit })
        documents[0].body.mediaAssets = ["cover.jpg": asset.uuidString]
        documents[child].body.mediaAssets = ["inside.jpg": UUID().uuidString]
        let network = client([(200, Data([1])), (200, Data([2]))])
        defer { network.session.invalidateAndCancel() }
        let visitor = MosaicVisitClient(config: network.config, session: network.session)
        let media = try MosaicVisitMedia(documents: documents, mosaicID: mosaic, ownerID: owner,
                                        location: location, client: visitor)
        let snapshot = try #require(ComposerBoardSync.assemble(mosaicID: mosaic, documents: documents))
        let store = ComposerStore(seedSnapshot: snapshot, persistToDisk: false, location: location)
        #expect(RestoreURLProtocol.state.requests.isEmpty)
        await media.load(documentID: nil, store: store, token: "visitor")
        #expect(RestoreURLProtocol.state.requests.count == 1)
        #expect(RestoreURLProtocol.state.requests[0].url?.lastPathComponent == "display")
        #expect(store.mediaVersions["cover.jpg"] == 1)
        #expect(!FileManager.default.fileExists(atPath: store.mediaURL(for: "inside.jpg").path))
        await media.load(documentID: ComposerDocumentID(rawValue: documents[child].id.uuidString), store: store, token: "visitor")
        #expect(RestoreURLProtocol.state.requests.count == 2)
        #expect(store.mediaVersions["inside.jpg"] == 1)
        let revisit = try MosaicVisitMedia(documents: documents, mosaicID: mosaic, ownerID: owner,
                                          location: location, client: visitor)
        await revisit.load(documentID: nil, store: store, token: "visitor")
        #expect(RestoreURLProtocol.state.requests.count == 2)
    }

    @Test func visitMediaFailureCanRetryWithoutReplacingBoard() async throws {
        let location = try location()
        defer { try? FileManager.default.removeItem(at: location.root.deletingLastPathComponent()) }
        var documents = rows().map(\.document)
        documents[0].body.mediaAssets = ["photo.jpg": asset.uuidString]
        let network = client([(503, Data()), (503, Data()), (200, Data([7]))])
        defer { network.session.invalidateAndCancel() }
        let media = try MosaicVisitMedia(documents: documents, mosaicID: mosaic, ownerID: owner,
            location: location, client: MosaicVisitClient(config: network.config, session: network.session))
        let snapshot = try #require(ComposerBoardSync.assemble(mosaicID: mosaic, documents: documents))
        let store = ComposerStore(seedSnapshot: snapshot, persistToDisk: false, location: location)
        await media.load(documentID: nil, store: store, token: "visitor")
        #expect(media.failed.contains(mosaic))
        #expect(media.loading.isEmpty)
        #expect(store.snapshot == snapshot)
        await media.load(documentID: nil, store: store, token: "visitor")
        #expect(media.failed.isEmpty)
        #expect(store.mediaVersions["photo.jpg"] == 1)
        #expect(store.snapshot == snapshot)
    }

    @Test func cancelledVisitDoesNotStartMediaRequests() async throws {
        let location = try location()
        defer { try? FileManager.default.removeItem(at: location.root.deletingLastPathComponent()) }
        var documents = rows().map(\.document)
        documents[0].body.mediaAssets = ["photo.jpg": asset.uuidString]
        let network = client([(200, Data([1]))])
        defer { network.session.invalidateAndCancel() }
        let media = try MosaicVisitMedia(documents: documents, mosaicID: mosaic, ownerID: owner,
            location: location, client: MosaicVisitClient(config: network.config, session: network.session))
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false, location: location)
        let task = Task { await media.load(documentID: nil, store: store, token: "visitor") }
        task.cancel()
        await task.value
        #expect(RestoreURLProtocol.state.requests.isEmpty)
        #expect(media.loading.isEmpty)
        #expect(store.mediaVersions.isEmpty)
    }

    @Test func visitCacheInvalidatesChangedAndRemovedAssetsAndRejectsUnsafeNames() throws {
        let location = try location()
        defer { try? FileManager.default.removeItem(at: location.root.deletingLastPathComponent()) }
        var documents = rows().map(\.document)
        documents[0].body.mediaAssets = ["changed.jpg": asset.uuidString, "removed.jpg": UUID().uuidString,
                                        "kept.jpg": UUID().uuidString]
        try MosaicVisitMedia.prepareCache(documents: documents, location: location)
        for name in ["changed.jpg", "removed.jpg", "kept.jpg"] {
            try Data([1]).write(to: location.mediaDirectory.appendingPathComponent(name))
        }
        documents[0].body.mediaAssets?["changed.jpg"] = UUID().uuidString
        documents[0].body.mediaAssets?.removeValue(forKey: "removed.jpg")
        try MosaicVisitMedia.prepareCache(documents: documents, location: location)
        #expect(!FileManager.default.fileExists(atPath: location.mediaDirectory.appendingPathComponent("changed.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: location.mediaDirectory.appendingPathComponent("removed.jpg").path))
        #expect(FileManager.default.fileExists(atPath: location.mediaDirectory.appendingPathComponent("kept.jpg").path))
        documents[0].body.mediaAssets = ["../outside.jpg": asset.uuidString]
        #expect(throws: (any Error).self) {
            try MosaicVisitMedia.prepareCache(documents: documents, location: location)
        }
        #expect(MosaicVisitMedia.location(viewerID: UUID(), ownerID: owner) != MosaicVisitMedia.location(viewerID: UUID(), ownerID: owner))
    }

    @Test func newAccountCanStartWithLocalBoard() async throws {
        let location = try location()
        defer { try? FileManager.default.removeItem(at: location.root.deletingLastPathComponent()) }
        let client = client([(200, Data("null".utf8))])
        defer { client.session.invalidateAndCancel() }
        try await ComposerAccountRestore(client: client).prepare(ownerID: owner, accessToken: "token", location: location)
        #expect(!FileManager.default.fileExists(atPath: location.snapshotURL.path))
        #expect(RestoreURLProtocol.state.requests.count == 1)
    }
}

private final class RestoreURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = RestoreResponses()
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

private final class RestoreResponses: @unchecked Sendable {
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
