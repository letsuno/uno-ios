import Foundation
import Synchronization
import Testing

@testable import UnoClient

@Suite("REST client")
struct RestClientTests {
    @Test("GET requests use the normalized API base")
    func getRequest() async throws {
        let endpoint = try #require(ServerEndpoint(userInput: "https://play.example.com/root"))
        let requests = Mutex<[URLRequest]>([])
        let transport: RestClient.Transport = { request in
            requests.withLock { $0.append(request) }
            let data = Data(
                #"{"name":"Example","version":"0.1.0","motd":"","onlinePlayers":2,"activeRooms":1,"uptime":30}"#
                    .utf8
            )
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (data, response)
        }

        let info = try await RestClient(endpoint: endpoint, transport: transport).serverInfo()

        #expect(info.version == "0.1.0")
        let request = try #require(requests.withLock { $0.first })
        #expect(request.url?.absoluteString == "https://play.example.com/root/api/server/info")
        #expect(request.httpMethod == "GET")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("POST requests encode credentials as JSON")
    func postRequest() async throws {
        let endpoint = try #require(ServerEndpoint(userInput: "https://play.example.com"))
        let requests = Mutex<[URLRequest]>([])
        let transport: RestClient.Transport = { request in
            requests.withLock { $0.append(request) }
            let data = Data(#"{"token":"token","user":{"id":"1","username":"alice","nickname":"Alice"}}"#.utf8)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (data, response)
        }

        _ = try await RestClient(endpoint: endpoint, transport: transport).login(
            username: "alice", password: "secret"
        )

        let request = try #require(requests.withLock { $0.first })
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let payload = try JSONDecoder().decode([String: String].self, from: body)
        #expect(payload == ["username": "alice", "password": "secret"])
    }

    @Test("Server error payloads preserve status and message")
    func serverError() async throws {
        let endpoint = try #require(ServerEndpoint(userInput: "https://play.example.com"))
        let requests = Mutex<[URLRequest]>([])
        let transport: RestClient.Transport = { request in
            requests.withLock { $0.append(request) }
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil))
            return (Data(#"{"error":"Session expired"}"#.utf8), response)
        }

        do {
            let _: User = try await RestClient(endpoint: endpoint, transport: transport).me(token: "expired")
            Issue.record("Expected an API error")
        } catch let error as ApiError {
            #expect(error.status == 401)
            #expect(error.message == "Session expired")
            #expect(error.isUnauthorized)
        }
        let request = try #require(requests.withLock { $0.first })
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer expired")
    }
}

@Suite("Socket.IO packets")
struct SocketPacketTests {
    @Test("Event packets preserve acknowledgement IDs and arguments")
    func eventPacket() throws {
        let packet = try #require(SocketPacket(encoded: #"212["room:update",{"success":true}]"#))

        #expect(packet.kind == .event)
        #expect(packet.acknowledgementID == 12)
        #expect(packet.arguments == ["room:update", ["success": true]])
    }

    @Test("Acknowledgement packets decode response arguments")
    func acknowledgementPacket() throws {
        let packet = try #require(SocketPacket(encoded: #"37[{"success":true}]"#))

        #expect(packet.kind == .acknowledgement)
        #expect(packet.acknowledgementID == 7)
        #expect(packet.arguments == [["success": true]])
    }

    @Test("Disconnect packets have no payload")
    func disconnectPacket() throws {
        let packet = try #require(SocketPacket(encoded: "1"))

        #expect(packet.kind == .disconnect)
        #expect(packet.acknowledgementID == nil)
        #expect(packet.arguments.isEmpty)
    }

    @Test("Malformed packets are rejected")
    func malformedPackets() {
        #expect(SocketPacket(encoded: "") == nil)
        #expect(SocketPacket(encoded: "4[]") == nil)
        #expect(SocketPacket(encoded: "2not-json") == nil)
    }
}
