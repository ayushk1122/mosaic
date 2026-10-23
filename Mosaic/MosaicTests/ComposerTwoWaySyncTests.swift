import Foundation
import Testing
@testable import Mosaic

/// Two devices on one account, talking to an in-memory stand-in for Supabase.
@Suite(.serialized)
@MainActor
struct ComposerTwoWaySyncTests {
    private let owner = UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!
    private let token = "test-token"

    private struct Device {
        var location: ComposerStorageLocation
        var store: ComposerStore
        var sync: ComposerRemoteSync
    }

    private func makeClient() -> SupabaseDocumentSync {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeSupabaseProtocol.self]
        return SupabaseDocumentSync(
            config: SupabaseSyncConfig(url: URL(string: "https://two-way.invalid")!, anonKey: "test-key"),
            session: URLSession(configuration: config)
        )
    }

    private func newLocation() throws -> ComposerStorageLocation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ComposerStorageLocation(root: root.appendingPathComponent("account"))
    }

    private func device(at location: ComposerStorageLocation) -> Device {
        let store = ComposerStore(location: location)
        let sync = ComposerRemoteSync(location: location)
        sync.store = store
        return Device(location: location, store: store, sync: sync)
    }

    /// A first device that has pushed its Mosaic with one Pursuit, and a second device that has
    /// the same boards and sync record, as after both were in sync.
    private func twoDevicesInSync(_ client: SupabaseDocumentSync) async throws -> (Device, Device, ComposerDocumentID) {
        let first = device(at: try newLocation())
        first.store.placeMosaicTitleIfNeeded()
        let block = first.store.addBlock(.pursuit, to: nil)
        let pursuit = try #require(first.store.block(with: block, in: nil)?.pursuitID)
        first.store.addBlock(.text, to: pursuit)
        #expect(await push(first, client))

        let location = try newLocation()
        try FileManager.default.createDirectory(at: location.root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: first.location.snapshotURL, to: location.snapshotURL)
        try FileManager.default.copyItem(at: first.location.syncStateURL, to: location.syncStateURL)
        return (first, device(at: location), pursuit)
    }

    private func push(_ device: Device, _ client: SupabaseDocumentSync) async -> Bool {
        await device.sync.push(device.store.snapshot, protecting: [], client: client, userID: owner, accessToken: token)
    }

    private func pull(_ device: Device, _ client: SupabaseDocumentSync) async {
        await device.sync.pull(client: client, userID: owner, accessToken: token)
    }

    private func cleanUp(_ devices: Device...) {
        for device in devices {
            try? FileManager.default.removeItem(at: device.location.root.deletingLastPathComponent())
        }
    }

    private func texts(_ store: ComposerStore, in documentID: ComposerDocumentID?) -> Int {
        store.blocks(for: documentID).filter { $0.kind == .text }.count
    }

    @Test func anEditOnOneDeviceAppearsOnTheOtherWithoutBeingPushedBack() async throws {
        FakeSupabaseProtocol.server.reset(owner: owner)
        let client = makeClient()
        defer { client.session.invalidateAndCancel() }
        let (first, second, pursuit) = try await twoDevicesInSync(client)
        defer { cleanUp(first, second) }

        first.store.addBlock(.text, to: pursuit)
        #expect(await push(first, client))

        await pull(second, client)
        #expect(texts(second.store, in: pursuit) == 2)
        #expect(second.sync.pullCount == 1)

        // What just arrived matches the server, so pushing sends nothing.
        let saves = FakeSupabaseProtocol.server.saveCount
        #expect(await push(second, client))
        #expect(FakeSupabaseProtocol.server.saveCount == saves)
        // Nothing new on the server: the next pull is just the revision check.
        await pull(second, client)
        #expect(second.sync.pullCount == 1)
    }

    @Test func replacingABoardClearsItsUndoSoOldContentCantBePushedBack() async throws {
        FakeSupabaseProtocol.server.reset(owner: owner)
        let client = makeClient()
        defer { client.session.invalidateAndCancel() }
        let (first, second, pursuit) = try await twoDevicesInSync(client)
        defer { cleanUp(first, second) }

        // Edited and pushed on the second device, so it has undo history but nothing unsynced.
        second.store.addBlock(.text, to: pursuit)
        #expect(await push(second, client))
        #expect(second.store.canUndo(in: pursuit))
        await pull(first, client)
        first.store.addBlock(.text, to: pursuit)
        #expect(await push(first, client))

        await pull(second, client)
        #expect(texts(second.store, in: pursuit) == 3)
        #expect(!second.store.canUndo(in: pursuit))
    }

    @Test func newAndDeletedBoardsFollowTheOtherDevice() async throws {
        FakeSupabaseProtocol.server.reset(owner: owner)
        let client = makeClient()
        defer { client.session.invalidateAndCancel() }
        let (first, second, _) = try await twoDevicesInSync(client)
        defer { cleanUp(first, second) }

        let added = first.store.addBlock(.pursuit, to: nil)
        let newPursuit = try #require(first.store.block(with: added, in: nil)?.pursuitID)
        first.store.addBlock(.text, to: newPursuit)
        #expect(await push(first, client))
        await pull(second, client)
        #expect(second.store.snapshot.pursuits.contains { $0.id == newPursuit })
        #expect(texts(second.store, in: newPursuit) == 1)

        first.store.deleteBlock(added, in: nil)
        #expect(await push(first, client))
        await pull(second, client)
        #expect(!second.store.snapshot.pursuits.contains { $0.id == newPursuit })
        #expect(!second.store.blocks(for: nil).contains { $0.pursuitID == newPursuit })
    }

    /// Files this device kept after a newer edit or a deletion replaced its version.
    private func replacedCopies(_ device: Device) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: device.sync.replacedFolder.path))?.count ?? 0
    }

    @Test func theOtherDevicesNewerEditReplacesAnOlderOneHere() async throws {
        FakeSupabaseProtocol.server.reset(owner: owner)
        let client = makeClient()
        defer { client.session.invalidateAndCancel() }
        let (first, second, pursuit) = try await twoDevicesInSync(client)
        defer { cleanUp(first, second) }

        // Edited here a minute before the other device saved its edit.
        let mine = second.store.addBlock(.drawing, to: pursuit)
        second.sync.recordEdits(in: second.store.snapshot, at: Date().addingTimeInterval(-60))
        first.store.addBlock(.text, to: pursuit)
        #expect(await push(first, client))

        await pull(second, client)
        #expect(texts(second.store, in: pursuit) == 2)
        #expect(second.store.block(with: mine, in: pursuit) == nil)
        #expect(replacedCopies(second) == 1, "the older version is kept quietly on the phone")
        // Nothing left to send: the board is the server's.
        let saves = FakeSupabaseProtocol.server.saveCount
        #expect(await push(second, client))
        #expect(FakeSupabaseProtocol.server.saveCount == saves)
    }

    @Test func aNewerEditHereReplacesTheOtherDevicesOlderOne() async throws {
        FakeSupabaseProtocol.server.reset(owner: owner)
        let client = makeClient()
        defer { client.session.invalidateAndCancel() }
        let (first, second, pursuit) = try await twoDevicesInSync(client)
        defer { cleanUp(first, second) }

        let theirs = first.store.addBlock(.text, to: pursuit)
        #expect(await push(first, client))
        // Edited here after the other device saved.
        let mine = second.store.addBlock(.drawing, to: pursuit)
        second.sync.recordEdits(in: second.store.snapshot, at: Date().addingTimeInterval(60))

        await pull(second, client)
        #expect(second.store.block(with: mine, in: pursuit) != nil)
        #expect(second.store.block(with: theirs, in: pursuit) == nil, "whole boards: the newer one stays as it is")
        #expect(await push(second, client))
        await pull(first, client)
        #expect(first.store.block(with: mine, in: pursuit) != nil)
        #expect(first.store.block(with: theirs, in: pursuit) == nil)
    }

    @Test func aPushOlderThanTheServersVersionDoesNotReplaceIt() async throws {
        FakeSupabaseProtocol.server.reset(owner: owner)
        let client = makeClient()
        defer { client.session.invalidateAndCancel() }
        let (first, second, pursuit) = try await twoDevicesInSync(client)
        defer { cleanUp(first, second) }

        // Edited here first, but pushed only after the other device's later edit, without pulling.
        let mine = second.store.addBlock(.drawing, to: pursuit)
        second.sync.recordEdits(in: second.store.snapshot, at: Date().addingTimeInterval(-60))
        let theirs = first.store.addBlock(.text, to: pursuit)
        #expect(await push(first, client))
        _ = await push(second, client)

        let pursuitUUID = try #require(ComposerBoardSync.uuid(pursuit))
        let server = try #require(FakeSupabaseProtocol.server.bodyText(of: pursuitUUID))
        #expect(server.contains(theirs.rawValue.lowercased()))
        #expect(!server.contains(mine.rawValue.lowercased()))
        #expect(second.store.block(with: theirs, in: pursuit) != nil)
        #expect(replacedCopies(second) == 1)
    }

    @Test func aPushNewerThanTheServersVersionReplacesIt() async throws {
        FakeSupabaseProtocol.server.reset(owner: owner)
        let client = makeClient()
        defer { client.session.invalidateAndCancel() }
        let (first, second, pursuit) = try await twoDevicesInSync(client)
        defer { cleanUp(first, second) }

        let theirs = first.store.addBlock(.text, to: pursuit)
        #expect(await push(first, client))
        // Edited here after that, and pushed without pulling first.
        let mine = second.store.addBlock(.drawing, to: pursuit)
        second.sync.recordEdits(in: second.store.snapshot, at: Date().addingTimeInterval(60))
        #expect(await push(second, client))

        let pursuitUUID = try #require(ComposerBoardSync.uuid(pursuit))
        let server = try #require(FakeSupabaseProtocol.server.bodyText(of: pursuitUUID))
        #expect(server.contains(mine.rawValue.lowercased()))
        #expect(!server.contains(theirs.rawValue.lowercased()))
    }

    @Test func deletingOnAnotherDeviceWinsOverAnEditHere() async throws {
        FakeSupabaseProtocol.server.reset(owner: owner)
        let client = makeClient()
        defer { client.session.invalidateAndCancel() }
        let (first, second, _) = try await twoDevicesInSync(client)
        defer { cleanUp(first, second) }

        let added = first.store.addBlock(.pursuit, to: nil)
        let newPursuit = try #require(first.store.block(with: added, in: nil)?.pursuitID)
        let scrapbook = first.store.addBlock(.scrapbook, to: newPursuit)
        let page = try #require(first.store.block(with: scrapbook, in: newPursuit)?.scrapbookPageIDs.first)
        #expect(await push(first, client))
        await pull(second, client)
        first.store.deleteBlock(added, in: nil)
        #expect(await push(first, client))
        // Edited inside a page of the deleted Pursuit, even after the deletion.
        second.store.addBlock(.text, to: page)
        second.sync.recordEdits(in: second.store.snapshot, at: Date().addingTimeInterval(60))

        await pull(second, client)
        #expect(!second.store.snapshot.pursuits.contains { $0.id == newPursuit })
        #expect(!second.store.blocks(for: nil).contains { $0.id == added })
        #expect(replacedCopies(second) == 1, "the edited page is kept quietly")
    }

    @Test func pushingABoardDeletedElsewhereDoesNotBringItBack() async throws {
        FakeSupabaseProtocol.server.reset(owner: owner)
        let client = makeClient()
        defer { client.session.invalidateAndCancel() }
        let (first, second, _) = try await twoDevicesInSync(client)
        defer { cleanUp(first, second) }

        let added = first.store.addBlock(.pursuit, to: nil)
        let newPursuit = try #require(first.store.block(with: added, in: nil)?.pursuitID)
        #expect(await push(first, client))
        await pull(second, client)
        first.store.deleteBlock(added, in: nil)
        #expect(await push(first, client))
        // The second device edits the deleted Pursuit and pushes before it has pulled.
        second.store.addBlock(.text, to: newPursuit)
        _ = await push(second, client)

        let pursuitUUID = try #require(ComposerBoardSync.uuid(newPursuit))
        #expect(FakeSupabaseProtocol.server.bodyText(of: pursuitUUID) == nil, "the deletion stands on the server")
        #expect(!second.store.snapshot.pursuits.contains { $0.id == newPursuit })
        #expect(replacedCopies(second) == 1)
    }

    @Test func aBoardDeletedElsewhereAndUntouchedHereIsRemovedQuietly() async throws {
        FakeSupabaseProtocol.server.reset(owner: owner)
        let client = makeClient()
        defer { client.session.invalidateAndCancel() }
        let (first, second, pursuit) = try await twoDevicesInSync(client)
        defer { cleanUp(first, second) }

        let block = try #require(first.store.blocks(for: nil).first { $0.pursuitID == pursuit }?.id)
        first.store.deleteBlock(block, in: nil)
        #expect(await push(first, client))
        await pull(second, client)
        #expect(!second.store.snapshot.pursuits.contains { $0.id == pursuit })
        #expect(replacedCopies(second) == 0)
    }

    @Test func conflictCopiesFromEarlierBuildsBecomeReplacedCopies() throws {
        let location = try newLocation()
        let folder = location.root.appendingPathComponent("conflicts", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let board = ComposerSyncDocument(
            id: UUID(), parentID: nil, role: .pursuit, title: "Golf", visibility: "private",
            body: ComposerBoardBody(blocks: [], layoutHeight: nil, background: nil, mosaicTitlePlaced: nil, pursuitPagesBlanked: nil)
        )
        let old: [[String: Any]] = [[
            "id": board.id.uuidString, "title": "Golf", "savedAt": 0,
            "local": try JSONSerialization.jsonObject(with: JSONEncoder().encode(board)),
        ]]
        try JSONSerialization.data(withJSONObject: old).write(to: folder.appendingPathComponent("pending.json"))
        defer { try? FileManager.default.removeItem(at: location.root.deletingLastPathComponent()) }

        let sync = ComposerRemoteSync(location: location)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("pending.json").path))
        #expect((try? FileManager.default.contentsOfDirectory(atPath: sync.replacedFolder.path))?.count == 1)
    }

    @Test func editTimesMoveOnlyWhenABoardChanges() {
        let board = ComposerSyncDocument(
            id: UUID(), parentID: nil, role: .pursuit, title: "Golf", visibility: "private",
            body: ComposerBoardBody(blocks: [], layoutHeight: nil, background: nil, mosaicTitlePlaced: nil, pursuitPagesBlanked: nil)
        )
        let early = Date(timeIntervalSince1970: 1_000), late = Date(timeIntervalSince1970: 2_000)
        let times = ComposerEditTimes().recording([board], at: early)
        #expect(times.recording([board], at: late) == times, "unchanged keeps its time")
        var uploaded = board
        uploaded.body.mediaAssets = ["a.jpg": "asset"]
        #expect(times.editTime(of: uploaded, now: late) == early, "a finished upload isn't an edit")
        var renamed = board
        renamed.title = "Golf 2026"
        #expect(times.editTime(of: renamed, now: late) == late, "an edit not recorded yet happened just now")
        #expect(times.recording([renamed], at: late).editTime(of: renamed, now: .distantFuture) == late)
    }

    @Test func serverSaveTimesReadAsPostgresWritesThem() throws {
        let micro = try #require(ComposerServerTime.date(from: "2026-10-22T21:49:12.123456+00:00"))
        #expect(abs(micro.timeIntervalSince1970 - 1_792_705_752.123) < 0.001)
        #expect(ComposerServerTime.date(from: "2026-10-22T21:49:12+00:00") == Date(timeIntervalSince1970: 1_792_705_752))
        #expect(ComposerServerTime.date(from: "2026-10-22T21:49:12.5Z") == Date(timeIntervalSince1970: 1_792_705_752.5))
        #expect(ComposerServerTime.date(from: "yesterday") == nil)
    }

    @Test func stickersSavedOnBothDevicesAreAllKept() async throws {
        FakeSupabaseProtocol.server.reset(owner: owner)
        let client = makeClient()
        defer { client.session.invalidateAndCancel() }
        let (first, second, _) = try await twoDevicesInSync(client)
        defer { cleanUp(first, second) }

        first.store.saveToStickerLibrary(fileName: "theirs.png", size: CGSize(width: 10, height: 10))
        #expect(await push(first, client))
        second.store.saveToStickerLibrary(fileName: "mine.png", size: CGSize(width: 10, height: 10))

        await pull(second, client)
        #expect(Set(second.store.snapshot.stickerLibrary.map(\.fileName)) == ["theirs.png", "mine.png"])
        #expect(await push(second, client))
        await pull(first, client)
        #expect(Set(first.store.snapshot.stickerLibrary.map(\.fileName)) == ["theirs.png", "mine.png"])
    }

    @Test func onlyNewerAndUnknownBoardsAreFetched() {
        let known = UUID()
        let changed = UUID()
        let unknown = UUID()
        let mosaicID = UUID()
        let gone = UUID()
        var state = ComposerSyncState(mosaicID: mosaicID)
        state.revisions = [
            known.uuidString.lowercased(): 3,
            changed.uuidString.lowercased(): 3,
            mosaicID.uuidString.lowercased(): 1,
            gone.uuidString.lowercased(): 2,
        ]
        let remote: [UUID: Int64] = [known: 3, changed: 4, unknown: 1, mosaicID: 1]
        #expect(Set(ComposerPull.changedIDs(remote: remote, state: state)) == [changed, unknown])
        #expect(ComposerPull.removedIDs(remote: remote, state: state) == [gone])
        // The Mosaic itself is never treated as deleted.
        #expect(ComposerPull.removedIDs(remote: [:], state: state).contains(mosaicID) == false)
    }
}

/// Behaves like the parts of Supabase sync uses: `documents` rows, `save_document` with revision
/// checks, `own_mosaic_id`, and `delete_documents` with child rows cascading.
private final class FakeSupabaseProtocol: URLProtocol, @unchecked Sendable {
    static let server = FakeSupabaseServer()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.server.handle(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class FakeSupabaseServer: @unchecked Sendable {
    private let lock = NSLock()
    private var owner = UUID()
    /// Rows keyed by lowercased id, shaped like PostgREST's JSON.
    private var rows: [String: [String: Any]] = [:]
    private var saves = 0

    var saveCount: Int { lock.withLock { saves } }

    func reset(owner: UUID) {
        lock.withLock {
            self.owner = owner
            rows = [:]
            saves = 0
        }
    }

    /// The saved body as lowercased JSON text, for checking which pieces the server has.
    func bodyText(of id: UUID) -> String? {
        lock.withLock {
            guard let body = rows[id.uuidString.lowercased()]?["body"],
                  let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
            return String(data: data, encoding: .utf8)?.lowercased()
        }
    }

    func handle(_ request: URLRequest) -> (Int, Data) {
        lock.withLock {
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
            switch (request.httpMethod ?? "GET", components.path) {
            case ("POST", "/rest/v1/rpc/own_mosaic_id"):
                let mosaic = rows.values.first { $0["role"] as? String == "mosaic" }?["id"] as? String
                return (200, Data((mosaic.map { "\"\($0)\"" } ?? "null").utf8))
            case ("POST", "/rest/v1/rpc/save_document"):
                return save(Self.json(body(of: request)) as? [String: Any] ?? [:])
            case ("POST", "/rest/v1/rpc/delete_documents"):
                let ids = (Self.json(body(of: request)) as? [String: Any])?["p_ids"] as? [String] ?? []
                for id in ids { delete(id) }
                return (200, Data("null".utf8))
            case ("DELETE", "/rest/v1/media_assets"):
                return (204, Data())
            case ("GET", "/rest/v1/documents"):
                return (200, documents(query))
            default:
                return (404, Data())
            }
        }
    }

    private func save(_ call: [String: Any]) -> (Int, Data) {
        guard let id = (call["p_id"] as? String)?.lowercased() else { return (400, Data()) }
        let expected = (call["p_expected_revision"] as? NSNumber)?.int64Value ?? 0
        let current = (rows[id]?["revision"] as? NSNumber)?.int64Value ?? 0
        if rows[id] == nil, expected > 0 {
            return (409, Data(#"{"code":"MS404","message":"document deleted"}"#.utf8))
        }
        guard expected == current else {
            return (409, Data(#"{"code":"P0001","message":"revision conflict"}"#.utf8))
        }
        saves += 1
        rows[id] = [
            "id": id,
            "owner_id": owner.uuidString.lowercased(),
            "parent_id": call["p_parent_id"] ?? NSNull(),
            "role": call["p_role"] ?? "pursuit",
            "title": call["p_title"] ?? "",
            "body": call["p_body"] ?? [:],
            "revision": current + 1,
            "updated_at": Self.timestamp.string(from: Date()),
        ]
        return (200, Data("\(current + 1)".utf8))
    }

    private func delete(_ id: String) {
        rows[id.lowercased()] = nil
        let children = rows.values.filter { ($0["parent_id"] as? String)?.lowercased() == id.lowercased() }
        for child in children {
            if let childID = child["id"] as? String { delete(childID) }
        }
    }

    private func documents(_ query: [String: String]) -> Data {
        var matching = rows.values.sorted { ($0["id"] as! String) < ($1["id"] as! String) }
        if let id = query["id"] {
            if id.hasPrefix("eq.") {
                matching = matching.filter { $0["id"] as? String == String(id.dropFirst(3)) }
            } else if id.hasPrefix("in.(") {
                let list = Set(id.dropFirst(4).dropLast().split(separator: ",").map(String.init))
                matching = matching.filter { list.contains($0["id"] as? String ?? "") }
            }
        }
        let offset = Int(query["offset"] ?? "0") ?? 0
        let limit = Int(query["limit"] ?? "") ?? matching.count
        matching = Array(matching.dropFirst(offset).prefix(limit))
        let fields = (query["select"] ?? "").split(separator: ",").map(String.init)
        let selected = matching.map { row in row.filter { fields.contains($0.key) } }
        return (try? JSONSerialization.data(withJSONObject: selected)) ?? Data("[]".utf8)
    }

    private func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func json(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }
}
