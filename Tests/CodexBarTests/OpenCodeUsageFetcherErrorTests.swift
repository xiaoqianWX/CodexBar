import CodexBarCore
import Foundation
import Testing

@Suite(.serialized)
struct OpenCodeUsageFetcherErrorTests {
    private func makeSession() -> URLSession {
        OpenCodeStubURLProtocol.makeSession()
    }

    @Test
    func `extracts api error from uppercase HTML title`() async throws {
        defer {
            OpenCodeStubURLProtocol.reset()
        }

        OpenCodeStubURLProtocol.setHandler { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let body = "<html><head><TITLE>403 Forbidden</TITLE></head><body>denied</body></html>"
            return OpenCodeStubURLProtocol.makeResponse(url: url, body: body, statusCode: 500, contentType: "text/html")
        }

        do {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: "auth=test",
                timeout: 2,
                workspaceIDOverride: "wrk_TEST123",
                session: self.makeSession())
            Issue.record("Expected OpenCodeUsageError.apiError")
        } catch let error as OpenCodeUsageError {
            switch error {
            case let .apiError(message):
                #expect(message.contains("HTTP 500"))
                #expect(message.contains("403 Forbidden"))
            default:
                Issue.record("Expected apiError, got: \(error)")
            }
        }
    }

    @Test
    func `extracts api error from detail field`() async throws {
        defer {
            OpenCodeStubURLProtocol.reset()
        }

        OpenCodeStubURLProtocol.setHandler { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let body = #"{"detail":"Workspace missing"}"#
            return OpenCodeStubURLProtocol.makeResponse(
                url: url,
                body: body,
                statusCode: 500,
                contentType: "application/json")
        }

        do {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: "auth=test",
                timeout: 2,
                workspaceIDOverride: "wrk_TEST123",
                session: self.makeSession())
            Issue.record("Expected OpenCodeUsageError.apiError")
        } catch let error as OpenCodeUsageError {
            switch error {
            case let .apiError(message):
                #expect(message.contains("HTTP 500"))
                #expect(message.contains("Workspace missing"))
            default:
                Issue.record("Expected apiError, got: \(error)")
            }
        }
    }

    @Test
    func `subscription get null skips post and returns graceful error`() async throws {
        defer {
            OpenCodeStubURLProtocol.reset()
        }

        var methods: [String] = []
        var urls: [URL] = []
        var queries: [String] = []
        var contentTypes: [String] = []
        OpenCodeStubURLProtocol.setHandler { request in
            guard let url = request.url else { throw URLError(.badURL) }
            methods.append(request.httpMethod ?? "GET")
            urls.append(url)
            queries.append(url.query ?? "")
            contentTypes.append(request.value(forHTTPHeaderField: "Content-Type") ?? "")

            if request.httpMethod?.uppercased() == "GET" {
                return OpenCodeStubURLProtocol.makeResponse(
                    url: url,
                    body: "null",
                    statusCode: 200,
                    contentType: "application/json")
            }

            let body = #"{"status":500,"unhandled":true,"message":"HTTPError"}"#
            return OpenCodeStubURLProtocol.makeResponse(
                url: url,
                body: body,
                statusCode: 500,
                contentType: "application/json")
        }

        do {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: "auth=test",
                timeout: 2,
                workspaceIDOverride: "wrk_TEST123",
                session: self.makeSession())
            Issue.record("Expected OpenCodeUsageError.apiError")
        } catch let error as OpenCodeUsageError {
            switch error {
            case let .apiError(message):
                #expect(message.contains("No subscription usage data"))
                #expect(message.contains("wrk_TEST123"))
            default:
                Issue.record("Expected apiError, got: \(error)")
            }
        }

        #expect(methods == ["GET"])
        #expect(queries[0].contains("id="))
        #expect(queries[0].contains("wrk_TEST123"))
        #expect(urls[0].path == "/_server")
        #expect(contentTypes[0].isEmpty)
    }

    @Test
    func `subscription get payload does not fallback to post`() async throws {
        defer {
            OpenCodeStubURLProtocol.reset()
        }

        var methods: [String] = []
        OpenCodeStubURLProtocol.setHandler { request in
            guard let url = request.url else { throw URLError(.badURL) }
            methods.append(request.httpMethod ?? "GET")

            let body = """
            {
              "rollingUsage": { "usagePercent": 17, "resetInSec": 600 },
              "weeklyUsage": { "usagePercent": 75, "resetInSec": 7200 }
            }
            """
            return OpenCodeStubURLProtocol.makeResponse(
                url: url,
                body: body,
                statusCode: 200,
                contentType: "application/json")
        }

        let snapshot = try await OpenCodeUsageFetcher.fetchUsage(
            cookieHeader: "auth=test",
            timeout: 2,
            workspaceIDOverride: "wrk_TEST123",
            session: self.makeSession())

        #expect(snapshot.rollingUsagePercent == 17)
        #expect(snapshot.weeklyUsagePercent == 75)
        #expect(methods == ["GET"])
    }

    @Test
    func `workspace get public actor error is treated as invalid credentials without post retry`() async throws {
        defer {
            OpenCodeStubURLProtocol.reset()
        }

        var methods: [String] = []
        OpenCodeStubURLProtocol.setHandler { request in
            guard let url = request.url else { throw URLError(.badURL) }
            methods.append(request.httpMethod ?? "GET")
            let body = [
                #";0x00000263;((self.$R=self.$R||{})["server-fn:test"]=[],"#,
                #"($R=>$R[0]=Object.assign(new Error("actor of type \"public\" is not associated with an account"),"#,
                #"{stack:"Error: actor of type \"public\" is not associated with an account"}))"#,
                #"($R["server-fn:test"]))"#,
            ].joined()
            return OpenCodeStubURLProtocol.makeResponse(
                url: url,
                body: body,
                statusCode: 200,
                contentType: "text/javascript")
        }

        do {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: "auth=test",
                timeout: 2,
                session: self.makeSession())
            Issue.record("Expected OpenCodeUsageError.invalidCredentials")
        } catch let error as OpenCodeUsageError {
            switch error {
            case .invalidCredentials:
                break
            default:
                Issue.record("Expected invalidCredentials, got: \(error)")
            }
        }

        #expect(methods == ["GET"])
    }

    @Test
    func `subscription get missing fields falls back to post`() async throws {
        defer {
            OpenCodeStubURLProtocol.reset()
        }

        var methods: [String] = []
        OpenCodeStubURLProtocol.setHandler { request in
            guard let url = request.url else { throw URLError(.badURL) }
            methods.append(request.httpMethod ?? "GET")

            if request.httpMethod?.uppercased() == "GET" {
                return OpenCodeStubURLProtocol.makeResponse(
                    url: url,
                    body: #"{"ok":true}"#,
                    statusCode: 200,
                    contentType: "application/json")
            }

            let body = """
            {
              "rollingUsage": { "usagePercent": 22, "resetInSec": 300 },
              "weeklyUsage": { "usagePercent": 44, "resetInSec": 3600 }
            }
            """
            return OpenCodeStubURLProtocol.makeResponse(
                url: url,
                body: body,
                statusCode: 200,
                contentType: "application/json")
        }

        let snapshot = try await OpenCodeUsageFetcher.fetchUsage(
            cookieHeader: "auth=test",
            timeout: 2,
            workspaceIDOverride: "wrk_TEST123",
            session: self.makeSession())

        #expect(snapshot.rollingUsagePercent == 22)
        #expect(snapshot.weeklyUsagePercent == 44)
        #expect(methods == ["GET", "POST"])
    }

    @Test
    func `fetcher sends only auth cookie to opencode host`() async throws {
        defer {
            OpenCodeStubURLProtocol.reset()
        }

        var observedCookie: String?
        OpenCodeStubURLProtocol.setHandler { request in
            guard let url = request.url else { throw URLError(.badURL) }
            observedCookie = request.value(forHTTPHeaderField: "Cookie")

            let body = """
            {
              "rollingUsage": { "usagePercent": 17, "resetInSec": 600 },
              "weeklyUsage": { "usagePercent": 75, "resetInSec": 7200 }
            }
            """
            return OpenCodeStubURLProtocol.makeResponse(
                url: url,
                body: body,
                statusCode: 200,
                contentType: "application/json")
        }

        _ = try await OpenCodeUsageFetcher.fetchUsage(
            cookieHeader: "provider=google; auth=test",
            timeout: 2,
            workspaceIDOverride: "wrk_TEST123",
            session: self.makeSession())

        #expect(observedCookie == "auth=test")
    }
}

final class OpenCodeStubURLProtocol: TestURLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "opencode.ai"
    }
}
