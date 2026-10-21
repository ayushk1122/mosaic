import Foundation
import Testing
@testable import Mosaic

@Suite(.serialized)
@MainActor
struct MosaicAuthReliabilityTests {
    private func session(_ replies: [FlakyReply]) -> URLSession {
        FlakyURLProtocol.state.reset(replies)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FlakyURLProtocol.self]
        return URLSession(configuration: config)
    }

    private var request: URLRequest {
        URLRequest(url: URL(string: "https://auth.invalid/auth/v1/token")!)
    }

    @Test
    func aDroppedConnectionIsTriedOnceMore() async throws {
        let session = session([.fail(.networkConnectionLost), .reply(200, Data("{}".utf8))])
        defer { session.invalidateAndCancel() }
        let (data, response) = try await MosaicAccount.send(request, session: session)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == Data("{}".utf8))
        #expect(FlakyURLProtocol.state.count == 2)
    }

    @Test
    func otherFailuresAreNotRetried() async {
        let session = session([.fail(.notConnectedToInternet), .reply(200, Data())])
        defer { session.invalidateAndCancel() }
        await #expect(throws: URLError.self) {
            _ = try await MosaicAccount.send(self.request, session: session)
        }
        #expect(FlakyURLProtocol.state.count == 1)
    }

    @Test
    func aServerAnswerIsNeverRetried() async throws {
        // A wrong password is an answer, not a dropped connection.
        let session = session([.reply(400, Data(#"{"error":"invalid_grant"}"#.utf8)), .reply(200, Data())])
        defer { session.invalidateAndCancel() }
        let (_, response) = try await MosaicAccount.send(request, session: session)
        #expect((response as? HTTPURLResponse)?.statusCode == 400)
        #expect(FlakyURLProtocol.state.count == 1)
    }

    @Test
    func onlyConnectionDropsAndTimeoutsRetry() {
        #expect(MosaicAccount.retriesOnce(.networkConnectionLost))
        #expect(MosaicAccount.retriesOnce(.timedOut))
        #expect(!MosaicAccount.retriesOnce(.notConnectedToInternet))
        #expect(!MosaicAccount.retriesOnce(.cancelled))
    }
}

private enum FlakyReply {
    case fail(URLError.Code)
    case reply(Int, Data)
}

private final class FlakyURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = FlakyReplies()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        switch Self.state.next() {
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .reply(let status, let data):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private final class FlakyReplies: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [FlakyReply] = []
    private var served = 0
    var count: Int { lock.withLock { served } }
    func reset(_ replies: [FlakyReply]) {
        lock.withLock { self.replies = replies; served = 0 }
    }
    func next() -> FlakyReply {
        lock.withLock {
            served += 1
            return replies.isEmpty ? .fail(.badServerResponse) : replies.removeFirst()
        }
    }
}
