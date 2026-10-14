import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Mosaic

@MainActor
struct ComposerBoardSyncTests {
    @Test
    func splitParentsPagesToThePursuitAndLeavesTopLevelPursuitsUnparented() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let pursuitBlockID = store.addBlock(.pursuit, to: nil)
        let pursuitID = store.block(with: pursuitBlockID, in: nil)?.pursuitID
        store.addBlock(.text, to: pursuitID)
        let scrapbookID = store.addBlock(.scrapbook, to: pursuitID)
        let pageIDs = store.block(with: scrapbookID, in: pursuitID)?.scrapbookPageIDs ?? []
        #expect(pageIDs.count == 2)

        let mosaicID = UUID()
        let documents = ComposerBoardSync.split(snapshot: store.snapshot, mosaicID: mosaicID)
        let mosaic = documents.first { $0.role == .mosaic }
        let pursuit = documents.first { $0.role == .pursuit }
        let pages = documents.filter { $0.role == .page }

        #expect(mosaic?.id == mosaicID)
        #expect(mosaic?.parentID == nil)
        #expect(mosaic?.visibility == "private")
        #expect(pursuit?.parentID == nil)
        #expect(pursuit?.visibility == "private")
        #expect(pursuit?.body.blocks.contains { $0.kind == .text } == true)
        #expect(pages.count == 2)
        #expect(pages.allSatisfy { $0.parentID == pursuit?.id } == true)
        #expect(documents.allSatisfy { $0.visibility == "private" })
    }

    @Test
    func pruneAndDeadIDsDropBoardsNothingPointsAt() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let pursuitBlockID = store.addBlock(.pursuit, to: nil)
        let pursuitID = store.block(with: pursuitBlockID, in: nil)?.pursuitID
        let scrapbookID = store.addBlock(.scrapbook, to: pursuitID)
        let pageIDs = store.block(with: scrapbookID, in: pursuitID)?.scrapbookPageIDs ?? []
        #expect(pageIDs.count == 2)

        store.deleteBlock(pursuitBlockID, in: nil)
        #expect(store.snapshot.pursuits.isEmpty)
        #expect(pageIDs.allSatisfy { store.pursuit(for: $0) == nil })

        var orphaned = ComposerSnapshot.empty
        let live = ComposerDocumentID()
        let deadPage = ComposerDocumentID()
        orphaned.pursuits = [
            ComposerPursuit(id: live, title: "Gym", blocks: [], role: .pursuit),
            ComposerPursuit(id: deadPage, title: "Page 7", blocks: [], role: .page)
        ]
        orphaned.mosaicBlocks = [
            {
                var block = ComposerBlock.make(kind: .pursuit, position: BlockPosition(x: 0.2, y: 0.2))
                block.pursuitID = live
                return block
            }()
        ]
        let removed = ComposerBoardSync.pruneUnreferenced(&orphaned)
        #expect(removed == [deadPage])
        #expect(orphaned.pursuits.map(\.id) == [live])

        let mosaicID = UUID()
        let liveUUID = UUID(uuidString: live.rawValue) ?? UUID()
        let deadUUID = UUID(uuidString: deadPage.rawValue) ?? UUID()
        let dead = ComposerBoardSync.deadIDs(
            live: [mosaicID, liveUUID],
            remote: [mosaicID, liveUUID, deadUUID],
            mosaicID: mosaicID
        )
        #expect(dead == [deadUUID])

        let base = URL(string: "https://example.supabase.co")!
        let owner = UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!
        let listed = SupabaseDocumentSync.ownDocumentsURL(base: base, ownerID: owner)
        #expect(listed.absoluteString.contains("owner_id=eq.00000000-0000-0000-0000-00000000000a"))
        let deleteURL = SupabaseDocumentSync.deleteDocumentsURL(base: base, ids: [deadUUID])
        #expect(deleteURL.absoluteString.contains("id=in.(\(deadUUID.uuidString.lowercased()))"))
    }

    @Test
    func eachAccountKeepsItsOwnBoards() throws {
        let synced = UUID()
        #expect(ComposerLegacyStorage.shouldClaim(legacyMosaicID: synced, serverMosaicID: synced))
        #expect(!ComposerLegacyStorage.shouldClaim(legacyMosaicID: synced, serverMosaicID: nil))
        #expect(!ComposerLegacyStorage.shouldClaim(legacyMosaicID: synced, serverMosaicID: UUID()))
        #expect(ComposerLegacyStorage.shouldClaim(legacyMosaicID: nil, serverMosaicID: nil))
        #expect(!ComposerLegacyStorage.shouldClaim(legacyMosaicID: nil, serverMosaicID: UUID()))

        #expect(ComposerSyncState.mayPush(local: nil, remote: nil))
        #expect(ComposerSyncState.mayPush(local: synced, remote: synced))
        #expect(!ComposerSyncState.mayPush(local: nil, remote: synced))
        #expect(!ComposerSyncState.mayPush(local: UUID(), remote: synced))

        let first = UUID()
        let second = UUID()
        #expect(ComposerStorageLocation.account(first).root != ComposerStorageLocation.account(second).root)
        #expect(ComposerStorageLocation.account(first).root.path.hasSuffix("Accounts/\(first.uuidString.lowercased())"))

        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: temp) }
        let legacy = ComposerStorageLocation(root: temp)
        let target = ComposerStorageLocation(root: temp.appendingPathComponent("Accounts/a", isDirectory: true))
        try fileManager.createDirectory(at: legacy.mediaDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.snapshotURL)
        try fileManager.createDirectory(at: target.root, withIntermediateDirectories: true)
        try JSONEncoder().encode(ComposerSnapshot.empty).write(to: target.snapshotURL)
        #expect(ComposerLegacyStorage.isBlank(target, fileManager: fileManager))
        try Data("jpg".utf8).write(to: legacy.mediaDirectory.appendingPathComponent("day.jpg"))
        let state = ComposerSyncState(mosaicID: synced)
        try JSONEncoder().encode(state).write(to: legacy.syncStateURL)
        #expect(ComposerLegacyStorage.legacyMosaicID(in: legacy) == synced)

        #expect(try ComposerLegacyStorage.claim(from: legacy, to: target, fileManager: fileManager))
        #expect(fileManager.fileExists(atPath: target.snapshotURL.path))
        #expect(fileManager.fileExists(atPath: target.mediaDirectory.appendingPathComponent("day.jpg").path))
        #expect(fileManager.fileExists(atPath: target.syncStateURL.path))
        #expect(!fileManager.fileExists(atPath: legacy.snapshotURL.path))
        #expect(try !ComposerLegacyStorage.claim(from: legacy, to: target, fileManager: fileManager))

        let store = ComposerStore(fileManager: fileManager, persistToDisk: true, location: target)
        #expect(store.mediaURL(for: "day.jpg") == target.mediaDirectory.appendingPathComponent("day.jpg"))
    }

    @Test
    func avatarIsASquareJPEGInTheOwnersFolder() throws {
        let user = UUID()
        let picture = UUID()
        #expect(MosaicAvatar.path(userID: user, pictureID: picture)
            == "\(user.uuidString.lowercased())/\(picture.uuidString.lowercased()).jpg")

        let wide = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        let jpeg = try #require(MosaicAvatar.jpeg(from: wide))
        let decoded = try #require(UIImage(data: jpeg))
        #expect(decoded.size.width * decoded.scale == 512)
        #expect(decoded.size.height * decoded.scale == 512)

        let base = URL(string: "https://example.supabase.co")!
        #expect(MosaicSettingsClient.avatarObjectURL(base: base, path: "a/b.jpg").absoluteString
            == "https://example.supabase.co/storage/v1/object/avatars/a/b.jpg")
        #expect(MosaicSettingsClient.avatarReadURL(base: base, path: "a/b.jpg").absoluteString
            == "https://example.supabase.co/storage/v1/object/authenticated/avatars/a/b.jpg")

        let framed = try #require(MosaicAvatar.jpeg(from: wide, zoom: 2, pan: CGSize(width: 0.3, height: -0.1)))
        #expect(try #require(UIImage(data: framed)).size.width == 512)
    }

    @Test
    func avatarFramingKeepsTheCircleCovered() {
        let wide = CGSize(width: 1200, height: 800)
        #expect(MosaicAvatar.cropRect(imageSize: wide, zoom: 1, pan: .zero) == CGRect(x: 200, y: 0, width: 800, height: 800))
        // Moving the photo right shows more of its left edge, and stops at that edge.
        #expect(MosaicAvatar.cropRect(imageSize: wide, zoom: 1, pan: CGSize(width: 0.25, height: 0)).minX == 0)
        #expect(MosaicAvatar.cropRect(imageSize: wide, zoom: 1, pan: CGSize(width: 5, height: 5))
            == CGRect(x: 0, y: 0, width: 800, height: 800))
        #expect(MosaicAvatar.cropRect(imageSize: wide, zoom: 2, pan: .zero) == CGRect(x: 400, y: 200, width: 400, height: 400))
        #expect(MosaicAvatar.cropRect(imageSize: wide, zoom: 2, pan: CGSize(width: -9, height: 9))
            == CGRect(x: 800, y: 0, width: 400, height: 400))
        #expect(MosaicAvatar.cropRect(imageSize: wide, zoom: 10, pan: .zero).width == 200)
        #expect(MosaicAvatar.clampedPan(CGSize(width: 1, height: 1), imageSize: wide, zoom: 1) == CGSize(width: 0.25, height: 0))
    }

    @Test
    func avatarCropperStaysScreenWideForAPanorama() {
        let panorama = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 500)).image { _ in }
        let host = UIHostingController(rootView: MosaicAvatarCropper(image: panorama, onCancel: {}, onSave: { _ in }))
        #expect(host.sizeThatFits(in: CGSize(width: 402, height: 874)).width <= 402)
    }

    @Test
    func mosaicLinksNameAUsername() throws {
        #expect(MosaicLink.url(username: "@Ayush")?.absoluteString == "mosaic://@ayush")
        #expect(MosaicLink.url(username: "") == nil)
        #expect(MosaicLink.username(from: try #require(URL(string: "mosaic://@ayush"))) == "ayush")
        #expect(MosaicLink.username(from: try #require(URL(string: "mosaic://@Ayush_2/"))) == "ayush_2")
        #expect(MosaicLink.username(from: try #require(URL(string: "mosaic://@ayush?ref=copy"))) == "ayush")
        #expect(MosaicLink.username(from: try #require(URL(string: "mosaic://login-callback?code=x"))) == nil)
        #expect(MosaicLink.username(from: try #require(URL(string: "mosaic://@a"))) == nil)
        #expect(MosaicLink.username(from: try #require(URL(string: "https://example.com/@ayush"))) == nil)
    }

    @Test
    func searchReadsUsernamesAndDisplayNames() throws {
        let id = UUID()
        let data = Data("""
        [{"id":"\(id.uuidString.lowercased())","username":"ayush","display_name":"  Ayush K ","avatar_path":"a/b.jpg"},
         {"id":"\(UUID().uuidString)","username":"ayush2","display_name":null},
         {"id":"not-a-uuid","username":"broken"}]
        """.utf8)
        let people = try MosaicSearchClient.results(from: data)
        #expect(people.map(\.username) == ["ayush", "ayush2"])
        #expect(people.first?.id == id)
        #expect(people.first?.displayName == "Ayush K")
        #expect(people.last?.displayName == "")
        #expect(people.first?.avatarPath == "a/b.jpg")
        #expect(people.last?.avatarPath == nil)
    }

    @Test
    func circleRingsGrowOutwardAroundTheMosaic() {
        #expect(MosaicCircleLayout.plan(count: 0, width: 402).bubbles.isEmpty)
        #expect(MosaicCircleLayout.ringCount(for: 10) == 1)
        #expect(MosaicCircleLayout.ringCount(for: 11) == 2)
        #expect(MosaicCircleLayout.ringCount(for: 26) == 2)
        #expect(MosaicCircleLayout.ringCount(for: 27) == 3)

        func distance(_ point: CGPoint) -> CGFloat { (point.x * point.x + point.y * point.y).squareRoot() }

        let one = MosaicCircleLayout.plan(count: 8, width: 402)
        #expect(one.ringRadii.count == 1)
        #expect(one.bubbles.allSatisfy { abs(distance($0.center) - one.ringRadii[0]) < 0.001 })
        #expect(abs(one.bubbles[0].center.x) < 0.001 && one.bubbles[0].center.y < 0)
        #expect(one.size.width <= 402.001)
        #expect(one.size.width > 400)
        #expect(one.bubbles[0].size > MosaicCircleLayout.firstSize)
        let few = MosaicCircleLayout.plan(count: 3, width: 402, height: 700)
        #expect(abs(few.ringRadii[0] - one.ringRadii[0]) < 0.001)

        let two = MosaicCircleLayout.plan(count: 14, width: 402)
        #expect(two.ringRadii.count == 2)
        #expect(two.bubbles.prefix(10).allSatisfy { abs(distance($0.center) - two.ringRadii[0]) < 0.001 })
        #expect(two.bubbles.suffix(4).allSatisfy { abs(distance($0.center) - two.ringRadii[1]) < 0.001 })
        #expect(two.bubbles[13].size < two.bubbles[0].size)
        #expect(two.size.width <= 402.001)
        #expect(two.size.width > 400)
        #expect(two.mosaicSize < one.mosaicSize)

        let wide = MosaicCircleLayout.plan(count: 14, width: 1000)
        func step(_ plan: MosaicCircleLayout.Plan) -> CGFloat {
            (plan.ringRadii[1] - plan.ringRadii[0]) / plan.bubbles[0].size
        }
        #expect(step(two) < step(wide))

        let short = MosaicCircleLayout.plan(count: 8, width: 402, height: 300)
        #expect(short.size.height <= 300.001)
    }

    @Test
    func circleCoversAreSmallThumbnails() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try #require(big.jpegData(compressionQuality: 0.8)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let thumb = try #require(MosaicThumbnail.image(at: url, maxPixelSize: MosaicThumbnail.bubblePixelSize))
        let pixels = thumb.cgImage.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        #expect(max(pixels.width, pixels.height) <= CGFloat(MosaicThumbnail.bubblePixelSize))
        #expect(pixels.width > pixels.height)
        #expect(MosaicThumbnail.isVideo("clip.MOV"))
        #expect(!MosaicThumbnail.isVideo("cover.jpg"))
    }

    @Test
    func circleReadsBubblesAndPeople() throws {
        let mosaic = UUID()
        let golf = UUID()
        let bubbles = try MosaicCircleClient.bubbles(from: Data("""
        [{"document_id":"\(mosaic.uuidString.lowercased())","role":"mosaic","title":"Mosaic","visibility":"public","follower_count":3,"pending_count":1,"badge_count":2},
         {"document_id":"\(golf.uuidString.lowercased())","role":"pursuit","title":" Golf ","visibility":"private","follower_count":0,"pending_count":0,"badge_count":0},
         {"document_id":"nope","role":"pursuit"}]
        """.utf8))
        #expect(bubbles.map(\.id) == [mosaic, golf])
        #expect(bubbles.first?.isMosaic == true)
        #expect(bubbles.first?.badgeCount == 2)
        #expect(bubbles.first?.followerCount == 3)
        #expect(bubbles.last?.title == "Golf")
        #expect(bubbles.last?.level == .private)

        let request = UUID()
        let person = UUID()
        let people = try MosaicCircleClient.people(from: Data("""
        [{"kind":"request","request_id":"\(request.uuidString.lowercased())","person_id":"\(person.uuidString.lowercased())","username":"ayush2","display_name":"","avatar_path":null},
         {"kind":"follower","request_id":null,"person_id":"\(person.uuidString.lowercased())","username":"ayush2","display_name":"Ayush Two"}]
        """.utf8))
        #expect(people.map(\.kind) == [.request, .follower])
        #expect(people.first?.requestID == request)
        #expect(people.first?.name == "ayush2")
        #expect(people.last?.name == "Ayush Two")
        #expect(people.first?.id != people.last?.id)
    }

    @Test
    func visitReadsProfilePursuitsAndBoards() throws {
        let owner = UUID()
        let mosaic = UUID()
        let profile = try MosaicVisitClient.profile(from: Data("""
        [{"user_id":"\(owner.uuidString.lowercased())","username":"ayush","display_name":"","avatar_path":null,"mosaic_id":"\(mosaic.uuidString.lowercased())","mosaic_visibility":"private","can_view":false,"request_status":"pending","follows_mosaic":false}]
        """.utf8))
        #expect(profile?.userID == owner)
        #expect(profile?.mosaicID == mosaic)
        #expect(profile?.name == "ayush")
        #expect(profile?.isPublic == false)
        #expect(profile?.canView == false)
        #expect(profile?.isRequested == true)
        #expect(try MosaicVisitClient.profile(from: Data("[]".utf8)) == nil)

        let golf = UUID()
        let family = UUID()
        let pursuits = try MosaicVisitClient.pursuits(from: Data("""
        [{"pursuit_id":"\(golf.uuidString.lowercased())","title":" Golf ","visibility":"public","can_open":true,"request_status":null,"following":true},
         {"pursuit_id":"\(family.uuidString.lowercased())","title":"","visibility":"private","can_open":false,"request_status":"declined","following":false}]
        """.utf8))
        #expect(pursuits.map(\.id) == [golf, family])
        #expect(pursuits.first?.title == "Golf")
        #expect(pursuits.first?.following == true)
        #expect(pursuits.last?.level == .private)
        #expect(pursuits.last?.isRequested == false)
        #expect(pursuits.last?.displayTitle == "Pursuit")

        let boards = try MosaicVisitClient.boards(from: Data("""
        [{"id":"\(mosaic.uuidString.lowercased())","parent_id":null,"role":"mosaic","title":"Mosaic","body":{"blocks":[],"mediaAssets":{"a.jpg":"x"}}},
         {"id":"\(golf.uuidString.lowercased())","parent_id":"\(mosaic.uuidString.lowercased())","role":"pursuit","title":"Golf","body":{"blocks":[]}},
         {"id":"nope","role":"pursuit","body":{"blocks":[]}}]
        """.utf8))
        #expect(boards.map(\.id) == [mosaic, golf])
        #expect(boards.first?.body.mediaAssets == ["a.jpg": "x"])
        #expect(boards.last?.parentID == mosaic)
    }

    @Test
    func visitLocksPrivatePursuitsAndDropsTheirBoards() throws {
        let mosaic = UUID(), golf = UUID(), family = UUID(), travel = UUID(), unlisted = UUID()
        let me = UUID(), journal = UUID()
        let node = UUID(), page = UUID(), golfNode = UUID(), journalNode = UUID()
        func id(_ value: UUID) -> String { value.uuidString.lowercased() }
        let pursuits = try MosaicVisitClient.pursuits(from: Data("""
        [{"pursuit_id":"\(id(golf))","title":"Golf","visibility":"public","can_open":true,"request_status":null,"following":false},
         {"pursuit_id":"\(id(family))","title":"Family","visibility":"private","can_open":false,"request_status":"pending","following":false},
         {"pursuit_id":"\(id(travel))","title":"Travel","visibility":"private","can_open":false,"request_status":"declined","following":false},
         {"pursuit_id":"\(id(me))","title":"Me","visibility":"private","can_open":true,"request_status":"accepted","following":false},
         {"pursuit_id":"\(id(journal))","title":"Journal","visibility":"private","can_open":true,"request_status":"accepted","following":true}]
        """.utf8))
        let byID = Dictionary(uniqueKeysWithValues: pursuits.map { ($0.id, $0) })
        #expect(MosaicVisit.access(byID[golf]) == .open)
        #expect(MosaicVisit.access(byID[family]) == .pending)
        #expect(MosaicVisit.access(byID[travel]) == .locked)
        #expect(MosaicVisit.access(byID[unlisted]) == .locked)
        #expect(MosaicVisit.access(byID[me]) == .locked)
        #expect(MosaicVisit.access(byID[journal]) == .open)
        #expect(MosaicVisit.requestProblem(byID[family]) == nil)
        #expect(MosaicVisit.requestProblem(byID[journal]) == nil)
        #expect(MosaicVisit.requestProblem(byID[travel]) != nil)
        #expect(MosaicVisit.requestProblem(byID[me]) != nil)
        #expect(MosaicVisit.status(afterRequestReply: nil) == "pending")
        #expect(MosaicVisit.status(afterRequestReply: "requested") == "pending")
        #expect(MosaicVisit.status(afterRequestReply: "declined") == "declined")
        #expect(MosaicVisit.status(afterRequestReply: "accepted") == "accepted")

        let boards = try MosaicVisitClient.boards(from: Data("""
        [{"id":"\(id(mosaic))","parent_id":null,"role":"mosaic","title":"Mosaic","body":{"blocks":[]}},
         {"id":"\(id(golf))","parent_id":"\(id(mosaic))","role":"pursuit","title":"Golf","body":{"blocks":[]}},
         {"id":"\(id(golfNode))","parent_id":"\(id(golf))","role":"node","title":"Range","body":{"blocks":[]}},
         {"id":"\(id(family))","parent_id":"\(id(mosaic))","role":"pursuit","title":"Family","body":{"blocks":[]}},
         {"id":"\(id(node))","parent_id":"\(id(family))","role":"node","title":"Trip","body":{"blocks":[]}},
         {"id":"\(id(page))","parent_id":"\(id(node))","role":"page","title":"Day one","body":{"blocks":[]}},
         {"id":"\(id(unlisted))","parent_id":"\(id(mosaic))","role":"pursuit","title":"Unlisted","body":{"blocks":[]}},
         {"id":"\(id(me))","parent_id":"\(id(mosaic))","role":"pursuit","title":"Me","body":{"blocks":[]}},
         {"id":"\(id(journal))","parent_id":"\(id(mosaic))","role":"pursuit","title":"Journal","body":{"blocks":[]}},
         {"id":"\(id(journalNode))","parent_id":"\(id(journal))","role":"node","title":"Entry","body":{"blocks":[]}}]
        """.utf8))
        let visible = MosaicVisit.authorizedDocuments(boards, pursuits: pursuits)
        #expect(visible.map(\.id) == [mosaic, golf, golfNode, journal, journalNode])
    }

    @Test
    func acceptingARequestMovesThePersonToFollowers() throws {
        let request = UUID(), asker = UUID(), follower = UUID(), other = UUID(), otherRequest = UUID()
        func id(_ value: UUID) -> String { value.uuidString.lowercased() }
        let people = try MosaicCircleClient.people(from: Data("""
        [{"kind":"request","request_id":"\(id(request))","person_id":"\(id(asker))","username":"asker","display_name":""},
         {"kind":"request","request_id":"\(id(otherRequest))","person_id":"\(id(follower))","username":"already","display_name":""},
         {"kind":"follower","request_id":null,"person_id":"\(id(follower))","username":"already","display_name":""},
         {"kind":"follower","request_id":null,"person_id":"\(id(other))","username":"other","display_name":""}]
        """.utf8))

        let accepted = MosaicCirclePerson.accepting(people[0], in: people)
        #expect(accepted.map(\.kind) == [.request, .follower, .follower, .follower])
        #expect(accepted[1].personID == asker)
        #expect(accepted[1].requestID == nil)
        #expect(accepted[1].username == "asker")

        let duplicate = MosaicCirclePerson.accepting(people[1], in: people)
        #expect(duplicate.map(\.personID) == [asker, follower, other])
        #expect(duplicate.filter { $0.personID == follower }.count == 1)
    }

    @Test
    func visitDownloadsDisplayCopiesOfPhotosAndOriginalVideos() {
        let owner = UUID(uuidString: "A05FD464-A05E-4F13-8EE3-52CDC4CC6A21")!
        let prefix = "a05fd464-a05e-4f13-8ee3-52cdc4cc6a21/abc"
        #expect(MosaicVisitClient.objectPaths(ownerID: owner, assetID: "ABC", fileName: "p.jpg") == ["\(prefix)/display", "\(prefix)/original"])
        #expect(MosaicVisitClient.objectPaths(ownerID: owner, assetID: "abc", fileName: "v.MOV") == ["\(prefix)/original"])
        #expect(MosaicVisitClient.objectPaths(ownerID: owner, assetID: "abc", fileName: "a.gif") == ["\(prefix)/original"])
    }

    @Test
    func discoverReadsFollowsAndFiltersThem() throws {
        let owner = UUID()
        let mosaic = UUID()
        let golf = UUID()
        let items = try MosaicFollowingClient.items(from: Data("""
        [{"target_type":"mosaic","target_id":"\(mosaic.uuidString.lowercased())","owner_id":"\(owner.uuidString.lowercased())","username":"ayush","display_name":" Ayush K ","avatar_path":null,"title":null,"cover_file":null,"cover_asset":null},
         {"target_type":"pursuit","target_id":"\(golf.uuidString.lowercased())","owner_id":"\(owner.uuidString.lowercased())","username":"ayush","display_name":"","title":"Golf","cover_file":"a.jpg","cover_asset":"x"},
         {"target_type":"board","target_id":"\(golf.uuidString.lowercased())","owner_id":"\(owner.uuidString.lowercased())","username":"ayush"}]
        """.utf8))
        #expect(items.map(\.kind) == [.mosaic, .pursuit])
        #expect(items.first?.ownerName == "Ayush K")
        #expect(items.last?.ownerName == "ayush")
        #expect(items.last?.coverAsset == "x")
        #expect(items.first?.id != items.last?.id)
        #expect(items.last?.matches("gol") == true)
        #expect(items.last?.matches("AYU") == true)
        #expect(items.last?.matches("tennis") == false)
        #expect(items.first?.matches("golf") == false)
        #expect(items.first?.matches("  ") == true)

        var other = items[1]
        other.owner.id = UUID()
        other.targetID = UUID()
        let list = items + [other]
        #expect(MosaicFollowingClient.remaining(list, after: items[0]).map(\.id) == [other.id])
        #expect(MosaicFollowingClient.remaining(list, after: items[1]).map(\.id) == [items[0].id, other.id])
    }

    @Test
    func visitingStaysInViewMode() {
        let chrome = MosaicChrome(isVisiting: true)
        #expect(chrome.isViewing)
        chrome.isViewing.toggle()
        #expect(chrome.isViewing)

        let own = MosaicChrome()
        own.isViewing.toggle()
        #expect(own.isViewing)
        own.isViewing.toggle()
        #expect(!own.isViewing)
    }

    @Test
    func visitsReportTheMosaicAndOpenPursuitsOnce() {
        let mosaic = UUID(), open = UUID(), locked = UUID(), page = UUID()
        func pursuit(_ id: UUID, canOpen: Bool) -> MosaicVisitPursuit {
            MosaicVisitPursuit(id: id, title: "", level: .public, canOpen: canOpen, requestStatus: nil, following: false)
        }
        let pursuits = [open: pursuit(open, canOpen: true), locked: pursuit(locked, canOpen: false)]

        #expect(MosaicVisit.visitTarget(nil, mosaicID: mosaic, pursuits: pursuits, reported: []) == mosaic)
        #expect(MosaicVisit.visitTarget(nil, mosaicID: mosaic, pursuits: pursuits, reported: [mosaic]) == nil)
        #expect(MosaicVisit.visitTarget(nil, mosaicID: nil, pursuits: pursuits, reported: []) == nil)
        #expect(MosaicVisit.visitTarget(open, mosaicID: mosaic, pursuits: pursuits, reported: [mosaic]) == open)
        #expect(MosaicVisit.visitTarget(open, mosaicID: mosaic, pursuits: pursuits, reported: [open]) == nil)
        #expect(MosaicVisit.visitTarget(locked, mosaicID: mosaic, pursuits: pursuits, reported: []) == nil)
        #expect(MosaicVisit.visitTarget(page, mosaicID: mosaic, pursuits: pursuits, reported: []) == nil)
    }

    @Test
    func dailyVisitCountsDecodeByBoard() throws {
        let mosaic = UUID(), golf = UUID()
        let json = """
        [{"document_id": "\(mosaic.uuidString.lowercased())", "visit_count": 3},
         {"document_id": "\(golf.uuidString.lowercased())", "visit_count": 1},
         {"document_id": "not-a-uuid", "visit_count": 9},
         {"document_id": "\(UUID().uuidString)"}]
        """
        let counts = try MosaicCircleClient.visitCounts(from: Data(json.utf8))
        #expect(counts == [mosaic: 3, golf: 1])
        #expect(try MosaicCircleClient.visitCounts(from: Data("[]".utf8)).isEmpty)
        #expect(throws: (any Error).self) { try MosaicCircleClient.visitCounts(from: Data("{}".utf8)) }
    }

    @Test
    func pursuitTitleFallsBackToItsTextWhenTheNameIsCleared() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let blockID = store.addBlock(.pursuit, to: nil)
        guard var block = store.block(with: blockID, in: nil), let pursuitID = block.pursuitID else {
            Issue.record("No pursuit widget")
            return
        }
        block.text = ""
        block.pursuitTexts = [
            PursuitTextItem(text: "  ", y: 0.1),
            PursuitTextItem(text: "Notes", y: 0.8),
            PursuitTextItem(text: "Baseball", y: 0.2)
        ]
        store.updateBlock(block, in: nil)
        #expect(store.pursuit(for: pursuitID)?.title == "Baseball")

        block.text = "Leia"
        store.updateBlock(block, in: nil)
        #expect(store.pursuit(for: pursuitID)?.title == "Leia")

        var snapshot = store.snapshot
        if let index = snapshot.pursuits.firstIndex(where: { $0.id == pursuitID }) {
            snapshot.pursuits[index].title = ""
        }
        #expect(ComposerStore.refreshPursuitTitles(&snapshot))
        #expect(snapshot.pursuits.first(where: { $0.id == pursuitID })?.title == "Leia")
        #expect(!ComposerStore.refreshPursuitTitles(&snapshot))
    }

    @Test
    func assembleRestoresTheBoards() {
        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        store.addBlock(.text, to: nil)
        let pursuitBlockID = store.addBlock(.pursuit, to: nil)
        let pursuitID = store.block(with: pursuitBlockID, in: nil)?.pursuitID
        store.addBlock(.heading, to: pursuitID)

        let mosaicID = UUID()
        let documents = ComposerBoardSync.split(snapshot: store.snapshot, mosaicID: mosaicID)
        let restored = ComposerBoardSync.assemble(mosaicID: mosaicID, documents: documents)

        #expect(restored?.mosaicTitle == store.snapshot.mosaicTitle)
        #expect(restored?.mosaicBlocks.map(\.kind) == store.snapshot.mosaicBlocks.map(\.kind))
        #expect(restored?.pursuits.count == 1)
        #expect(restored?.pursuits.first?.blocks.map(\.kind) == [.heading])
    }

    @Test
    func saveBodyCarriesTheExpectedRevision() throws {
        let mosaicID = UUID()
        let document = ComposerSyncDocument(
            id: mosaicID,
            parentID: nil,
            role: .mosaic,
            title: "Mosaic",
            visibility: "private",
            body: ComposerBoardBody(
                blocks: [],
                layoutHeight: nil,
                background: nil,
                mosaicTitlePlaced: false,
                pursuitPagesBlanked: false
            )
        )
        let body = try SupabaseDocumentSync.saveBody(
            ComposerDocumentPush(document: document, expectedRevision: 4)
        )
        #expect((body["p_expected_revision"] as? NSNumber)?.int64Value == 4)
        #expect(body["p_role"] as? String == "mosaic")
        #expect(body["p_id"] as? String == mosaicID.uuidString.lowercased())
        #expect(body["p_parent_id"] is NSNull)
    }

    @Test
    func revisionParserReadsTheRpcRow() throws {
        let data = Data(#"[{"revision": 3}]"#.utf8)
        #expect(try SupabaseDocumentSync.revision(from: data) == 3)
        #expect(SupabaseDocumentSync.error(from: Data("revision conflict".utf8), status: 400) == .revisionConflict)
        #expect(SupabaseDocumentSync.mosaicID(from: Data("null".utf8)) == nil)
        #expect(
            SupabaseDocumentSync.mosaicID(from: Data(#""65c2a70f-dfb3-40a0-a76c-96a6e721fd22""#.utf8))
                == UUID(uuidString: "65C2A70F-DFB3-40A0-A76C-96A6E721FD22")
        )
    }

    @Test
    func authSessionReadsTheTokenPayload() throws {
        let userID = UUID()
        let json = """
        {"access_token":"access","refresh_token":"refresh","expires_in":3600,"user":{"id":"\(userID.uuidString)"}}
        """
        let now = Date(timeIntervalSince1970: 1_000)
        let session = try MosaicAuthResponse.session(from: Data(json.utf8), now: now)
        #expect(session.accessToken == "access")
        #expect(session.userID == userID)
        #expect(session.expiresAt == now.addingTimeInterval(3600))
        #expect(MosaicPKCE.challenge(for: "hello-verifier-hello-verifier-hello-verif") == "My6Ou2QRvR7J1v2W65mBNajT_v3bz6dH3B4oolrqrKQ")
    }

    @Test
    func remoteMosaicIDWinsWhenTheServerAlreadyHasOne() {
        let remote = UUID()
        #expect(ComposerSyncState.choosingMosaicID(local: UUID(), remote: remote) == remote)
        let local = UUID()
        #expect(ComposerSyncState.choosingMosaicID(local: local, remote: nil) == local)
    }

    @Test
    func mediaUploadKeepsADisplayCopyAndCapsVideoLength() throws {
        let wide = ComposerMediaScale.fitted(width: 4000, height: 2000, longEdge: ComposerMediaScale.displayLongEdge)
        #expect(wide.width == 2560)
        #expect(wide.height == 1280)
        let small = ComposerMediaScale.fitted(width: 300, height: 200, longEdge: ComposerMediaScale.thumbLongEdge)
        #expect(small == (width: 300, height: 200))
        #expect(ComposerMediaScale.videoMilliseconds(seconds: 3.2) == 3200)
        #expect(ComposerMediaScale.videoMilliseconds(seconds: 15) == nil)

        let store = ComposerStore(seedSnapshot: .empty, persistToDisk: false)
        let mediaID = store.addBlock(.media, to: nil)
        var media = try #require(store.block(with: mediaID, in: nil))
        media.mediaFileName = "day.jpg"
        store.updateBlock(media, in: nil)
        let groupID = store.addBlock(.group, to: nil)
        var grouped = try #require(store.block(with: groupID, in: nil))
        var inside = ComposerBlock.make(kind: .media, position: BlockPosition(x: 0.1, y: 0.1))
        inside.mediaFileName = "inside.jpg"
        grouped.groupMembers = [inside]
        store.updateBlock(grouped, in: nil)

        let mosaicID = UUID()
        let found = ComposerMediaCatalog.references(snapshot: store.snapshot, mosaicID: mosaicID)
        #expect(found.map(\.fileName) == ["day.jpg", "inside.jpg"])
        #expect(found.allSatisfy { $0.documentID == mosaicID })

        let owner = UUID()
        let asset = UUID()
        let path = ComposerMediaCatalog.objectPath(ownerID: owner, assetID: asset, name: "original")
        #expect(path == "\(owner.uuidString.lowercased())/\(asset.uuidString.lowercased())/original")

        let documents = ComposerBoardSync.split(snapshot: store.snapshot, mosaicID: mosaicID)
        let stamped = ComposerMediaCatalog.stamped(documents, assets: ["day.jpg": asset.uuidString, "other.png": UUID().uuidString])
        #expect(stamped.first?.body.mediaAssets?.keys.contains("day.jpg") == true)
        #expect(stamped.first?.body.mediaAssets?["other.png"] == nil)

        let state = try JSONDecoder().decode(
            ComposerSyncState.self,
            from: Data(#"{"mosaicID":"00000000-0000-0000-0000-000000000001","revisions":{"a":1}}"#.utf8)
        )
        #expect(state.mediaAssets.isEmpty)
        #expect(state.revisions["a"] == 1)
    }

    @Test
    func settingsListUsesLocalTitlesAndServerPrivacy() {
        let mosaicID = UUID()
        let synced = UUID()
        let waiting = UUID()
        var snapshot = ComposerSnapshot.empty
        snapshot.mosaicTitle = "  Studio  "
        snapshot.pursuits = [
            ComposerPursuit(id: ComposerDocumentID(rawValue: synced.uuidString), title: "Golf", blocks: []),
            ComposerPursuit(id: ComposerDocumentID(rawValue: waiting.uuidString), title: "", blocks: [])
        ]
        let listed = MosaicSettingsList.rows(
            snapshot: snapshot,
            remote: [
                MosaicRemoteBoard(id: mosaicID, role: "mosaic", title: "Server", level: .public),
                MosaicRemoteBoard(id: synced, role: "pursuit", title: "Old", level: .private)
            ]
        )
        #expect(listed.mosaic?.title == "Studio")
        #expect(listed.mosaic?.level == .public)
        #expect(listed.pursuits.map(\.level) == [.private, .hidden])
        #expect(MosaicVisibilityLevel.parse("hidden", role: "pursuit") == .hidden)
        #expect(MosaicVisibilityLevel.parse(nil, role: "pursuit") == .hidden)
        #expect(MosaicVisibilityLevel.parse(nil, role: "mosaic") == .private)
        #expect(listed.mosaic?.canChange == true)
        #expect(listed.pursuits.map(\.title) == ["Golf", "Pursuit"])
        #expect(listed.pursuits.map(\.canChange) == [true, false])
        #expect(MosaicSettingsList.displayName(from: "  Ada Lovelace  ") == "Ada Lovelace")
    }

    @Test
    func usernameFollowsTheServerRule() {
        #expect(MosaicSettingsList.username(from: "  @Ada_Golf ") == "ada_golf")
        #expect(MosaicSettingsList.typedUsername("@@Ada_Golf") == "ada_golf")
        #expect(MosaicSettingsList.usernameProblems("ada_golf").isEmpty)
        #expect(MosaicSettingsList.usernameProblems("ab") == ["Use at least 3 characters."])
        #expect(MosaicSettingsList.usernameProblems(String(repeating: "a", count: 21)) == ["Use 20 characters or fewer."])
        #expect(MosaicSettingsList.usernameProblems("a-") == [
            "Use at least 3 characters.",
            "Use only letters, numbers, and underscores."
        ])
        #expect(MosaicSettingsList.usernameProblems("ada golf") == ["Use only letters, numbers, and underscores."])
        let lookup = MosaicSettingsClient.usernameURL(base: URL(string: "https://example.supabase.co")!, username: "ada_golf")
        #expect(lookup.absoluteString == "https://example.supabase.co/rest/v1/profiles?username=eq.ada_golf&select=id")
        #expect(MosaicSettingsClient.usernameError(status: 409, body: Data()) == .taken)
        #expect(MosaicSettingsClient.usernameError(status: 400, body: Data(#"{"code":"23505"}"#.utf8)) == .taken)
        #expect(MosaicSettingsClient.usernameError(status: 400, body: Data(#"{"code":"23514"}"#.utf8)) == .failed)
    }

    @Test
    func configIgnoresEmptyKeys() {
        #expect(SupabaseSyncConfig.current(bundle: Bundle(for: EmptyBundleToken.self), environment: [:]) == nil)
        let config = SupabaseSyncConfig.current(
            bundle: Bundle(for: EmptyBundleToken.self),
            environment: [
                "SUPABASE_URL": "https://example.supabase.co",
                "SUPABASE_ANON_KEY": "anon"
            ]
        )
        #expect(config?.anonKey == "anon")
        #expect(config?.url.absoluteString == "https://example.supabase.co")
    }
}

private final class EmptyBundleToken: NSObject {}
