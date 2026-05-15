import Foundation

class TestURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private nonisolated(unsafe) static var handlers: [ObjectIdentifier: Handler] = [:]
    private nonisolated(unsafe) static var requestLog: [ObjectIdentifier: [URLRequest]] = [:]

    static var requests: [URLRequest] {
        requestLog[ObjectIdentifier(Self.self)] ?? []
    }

    static func setHandler(_ handler: @escaping Handler) {
        self.handlers[ObjectIdentifier(Self.self)] = handler
    }

    static func reset() {
        let key = ObjectIdentifier(Self.self)
        Self.handlers[key] = nil
        Self.requestLog[key] = []
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return URLSession(configuration: configuration)
    }

    static func makeResponse(
        url: URL,
        body: String,
        statusCode: Int = 200,
        contentType: String = "application/json",
        headerFields: [String: String] = [:]) -> (HTTPURLResponse, Data)
    {
        var headers = headerFields
        headers["Content-Type"] = contentType
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers)!
        return (response, Data(body.utf8))
    }

    override class func canInit(with request: URLRequest) -> Bool {
        false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let key = ObjectIdentifier(type(of: self))
        Self.requestLog[key, default: []].append(self.request)
        guard let handler = Self.handlers[key] else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(self.request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
