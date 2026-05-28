import Foundation
import Testing

@testable import BetterAuth

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var responseData: Data?
  nonisolated(unsafe) static var statusCode: Int = 200

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: MockURLProtocol.statusCode,
      httpVersion: nil,
      headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    if let data = MockURLProtocol.responseData {
      client?.urlProtocol(self, didLoad: data)
    }
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

// MARK: - Helpers

private func makeHTTPClient(responseJSON: String) async -> HTTPClient {
  MockURLProtocol.responseData = responseJSON.data(using: .utf8)
  MockURLProtocol.statusCode = 200
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [MockURLProtocol.self]
  let registry = await MainActor.run { PluginRegistry(factories: []) }
  return HTTPClient(
    baseURL: URL(string: "http://localhost")!,
    scheme: "test://",
    pluginRegistry: registry,
    cookieStorage: CookieStorage(storage: InMemoryStorage()),
    session: URLSession(configuration: config)
  )
}

private func sessionJSON(date: String) -> String {
  """
  {
    "session": {
      "id": "s1", "userId": "u1", "token": "tok",
      "ipAddress": "127.0.0.1", "userAgent": "test",
      "expiresAt": "\(date)", "createdAt": "\(date)", "updatedAt": "\(date)"
    },
    "user": {
      "id": "u1", "email": "test@example.com", "name": "Test",
      "emailVerified": true, "createdAt": "\(date)", "updatedAt": "\(date)"
    }
  }
  """
}

private func signUpJSON(date: String) -> String {
  """
  {
    "token": "tok",
    "user": {
      "id": "u1", "email": "test@example.com", "name": "Test",
      "emailVerified": true, "createdAt": "\(date)", "updatedAt": "\(date)"
    }
  }
  """
}

private func signInJSON(date: String) -> String {
  """
  {
    "token": "tok", "redirect": false,
    "user": {
      "id": "u1", "email": "test@example.com", "name": "Test",
      "emailVerified": true, "createdAt": "\(date)", "updatedAt": "\(date)"
    }
  }
  """
}

// MARK: - Tests

@Suite(.serialized)
struct DateDecodingTests {

  @Test func getSessionDecodesFractionalSecondsDate() async throws {
    let client = await makeHTTPClient(responseJSON: sessionJSON(date: "2026-05-20T09:06:25.513Z"))
    let result: APIResource<Session, BetterAuthContext<AnyCodable>> =
      try await client.perform(route: BetterAuthRoute.getSession, responseType: Session.self)
    #expect(result.data.session.createdAt.timeIntervalSince1970 > 0)
    #expect(result.data.user.createdAt.timeIntervalSince1970 > 0)
  }

  @Test func getSessionDecodesPlainISO8601Date() async throws {
    let client = await makeHTTPClient(responseJSON: sessionJSON(date: "2026-05-20T09:06:25Z"))
    let result: APIResource<Session, BetterAuthContext<AnyCodable>> =
      try await client.perform(route: BetterAuthRoute.getSession, responseType: Session.self)
    #expect(result.data.session.createdAt.timeIntervalSince1970 > 0)
    #expect(result.data.user.createdAt.timeIntervalSince1970 > 0)
  }

  @Test func getSessionDecodesMatchingDates() async throws {
    let withFractional = await makeHTTPClient(
      responseJSON: sessionJSON(date: "2026-05-20T09:06:25.000Z"))
    let r1: APIResource<Session, BetterAuthContext<AnyCodable>> =
      try await withFractional.perform(
        route: BetterAuthRoute.getSession, responseType: Session.self)

    let withoutFractional = await makeHTTPClient(
      responseJSON: sessionJSON(date: "2026-05-20T09:06:25Z"))
    let r2: APIResource<Session, BetterAuthContext<AnyCodable>> =
      try await withoutFractional.perform(
        route: BetterAuthRoute.getSession, responseType: Session.self)

    #expect(
      r1.data.session.createdAt.timeIntervalSince1970
        == r2.data.session.createdAt.timeIntervalSince1970,
      "Fractional .000Z and plain Z should resolve to the same timestamp"
    )
  }

  @Test func signUpDecodesFractionalSecondsDate() async throws {
    let client = await makeHTTPClient(
      responseJSON: signUpJSON(date: "2026-05-20T09:06:25.513Z"))
    let result: APIResource<SignUpEmailResponse, BetterAuthContext<AnyCodable>> =
      try await client.perform(
        route: BetterAuthRoute.signUpEmail, responseType: SignUpEmailResponse.self)
    #expect(result.data.user.createdAt.timeIntervalSince1970 > 0)
  }

  @Test func signUpDecodesPlainISO8601Date() async throws {
    let client = await makeHTTPClient(responseJSON: signUpJSON(date: "2026-05-20T09:06:25Z"))
    let result: APIResource<SignUpEmailResponse, BetterAuthContext<AnyCodable>> =
      try await client.perform(
        route: BetterAuthRoute.signUpEmail, responseType: SignUpEmailResponse.self)
    #expect(result.data.user.createdAt.timeIntervalSince1970 > 0)
  }

  @Test func signInDecodesFractionalSecondsDate() async throws {
    let client = await makeHTTPClient(
      responseJSON: signInJSON(date: "2026-05-20T09:06:25.513Z"))
    let result: APIResource<SignInEmailResponse, BetterAuthContext<AnyCodable>> =
      try await client.perform(
        route: BetterAuthRoute.signInEmail, responseType: SignInEmailResponse.self)
    #expect(result.data.user.createdAt.timeIntervalSince1970 > 0)
  }

  @Test func signInDecodesPlainISO8601Date() async throws {
    let client = await makeHTTPClient(responseJSON: signInJSON(date: "2026-05-20T09:06:25Z"))
    let result: APIResource<SignInEmailResponse, BetterAuthContext<AnyCodable>> =
      try await client.perform(
        route: BetterAuthRoute.signInEmail, responseType: SignInEmailResponse.self)
    #expect(result.data.user.createdAt.timeIntervalSince1970 > 0)
  }

  @Test func invalidDateFormatThrows() async throws {
    let client = await makeHTTPClient(responseJSON: sessionJSON(date: "not-a-date"))
    await #expect(throws: (any Error).self) {
      let _: APIResource<Session, BetterAuthContext<AnyCodable>> =
        try await client.perform(route: BetterAuthRoute.getSession, responseType: Session.self)
    }
  }
}
