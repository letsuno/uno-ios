import Foundation
import Testing

@testable import UnoClient

@Suite("Server endpoint")
struct ServerEndpointTests {
    @Test("Bare public hosts default to HTTPS")
    func publicHostDefaultsToHTTPS() throws {
        let endpoint = try #require(ServerEndpoint(userInput: "play.example.com/"))

        #expect(endpoint.baseURL.absoluteString == "https://play.example.com")
        #expect(endpoint.storageKey == "https://play.example.com")
        #expect(endpoint.insecureVariant == nil)
    }

    @Test(
        "Plain HTTP is restricted to local networks",
        arguments: [
            "http://localhost:3001",
            "http://uno.local:3001",
            "http://10.0.0.8:3001",
            "http://172.16.0.8:3001",
            "http://192.168.1.8:3001",
            "http://[::1]:3001",
            "http://[fd00::8]:3001",
        ])
    func acceptsLocalHTTP(address: String) {
        #expect(ServerEndpoint(userInput: address) != nil)
    }

    @Test("Plain HTTP public hosts are rejected")
    func rejectsPublicHTTP() {
        #expect(ServerEndpoint(userInput: "http://example.com") == nil)
        #expect(ServerEndpoint(userInput: "ftp://192.168.1.8") == nil)
        #expect(ServerEndpoint(userInput: "https://user:password@example.com") == nil)
        #expect(ServerEndpoint(userInput: "https://example.com#fragment") == nil)
    }

    @Test("Bare local addresses expose an HTTP fallback")
    func localFallback() throws {
        let endpoint = try #require(ServerEndpoint(userInput: "192.168.1.8:3001"))

        #expect(endpoint.insecureVariant?.baseURL.absoluteString == "http://192.168.1.8:3001")
    }

    @Test("API paths are rooted below the selected server")
    func apiPath() throws {
        let endpoint = try #require(ServerEndpoint(userInput: "https://example.com"))

        #expect(endpoint.api("/server/info").absoluteString == "https://example.com/api/server/info")
    }
}
