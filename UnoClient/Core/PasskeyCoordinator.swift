import AuthenticationServices
import UIKit

/// Errors surfaced by the passkey flow. `canceled` is treated as a silent
/// dismissal by callers (no toast).
enum PasskeyError: Error, LocalizedError {
    case canceled
    case unexpectedCredential
    case malformedChallenge
    case notSupported
    case requestInProgress

    var errorDescription: String? {
        switch self {
        case .canceled: return "Passkey request canceled"
        case .unexpectedCredential: return "Unexpected passkey credential"
        case .malformedChallenge: return "Server sent a malformed passkey challenge"
        case .notSupported: return "Passkeys are not available on this device"
        case .requestInProgress: return "Another passkey request is already in progress"
        }
    }
}

/// Bridges `ASAuthorizationController`'s delegate callbacks to async/await for
/// platform (Face/Touch ID) passkeys. One request in flight at a time.
@MainActor
final class PasskeyCoordinator: NSObject {
    static let shared = PasskeyCoordinator()

    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var presentationAnchor: ASPresentationAnchor?

    /// Usernameless assertion using a discoverable credential.
    func assertion(
        rpId: String, challenge: Data
    ) async throws -> ASAuthorizationPlatformPublicKeyCredentialAssertion {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: rpId
        )
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        let authorization = try await perform(request)
        guard
            let assertion = authorization.credential
                as? ASAuthorizationPlatformPublicKeyCredentialAssertion
        else { throw PasskeyError.unexpectedCredential }
        return assertion
    }

    /// Register a new platform passkey for the signed-in user.
    func registration(
        rpId: String, name: String, userID: Data, challenge: Data
    ) async throws -> ASAuthorizationPlatformPublicKeyCredentialRegistration {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: rpId
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge, name: name, userID: userID
        )
        let authorization = try await perform(request)
        guard
            let registration = authorization.credential
                as? ASAuthorizationPlatformPublicKeyCredentialRegistration
        else { throw PasskeyError.unexpectedCredential }
        return registration
    }

    private func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        guard continuation == nil else { throw PasskeyError.requestInProgress }
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
        else { throw PasskeyError.notSupported }

        presentationAnchor = ASPresentationAnchor(windowScene: windowScene)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Wire encoding

    /// Assemble the `AuthenticationResponseJSON` shape `@simplewebauthn/server` expects.
    static func assertionJSON(
        _ assertion: ASAuthorizationPlatformPublicKeyCredentialAssertion
    ) -> JSONValue {
        var response: [String: JSONValue] = [
            "clientDataJSON": .string(assertion.rawClientDataJSON.base64URLEncoded),
            "authenticatorData": .string(assertion.rawAuthenticatorData.base64URLEncoded),
            "signature": .string(assertion.signature.base64URLEncoded),
        ]
        if !assertion.userID.isEmpty {
            response["userHandle"] = .string(assertion.userID.base64URLEncoded)
        }
        let id = assertion.credentialID.base64URLEncoded
        return .object([
            "id": .string(id),
            "rawId": .string(id),
            "type": .string("public-key"),
            "clientExtensionResults": .object([:]),
            "response": .object(response),
        ])
    }

    /// Assemble the `RegistrationResponseJSON` shape the server expects.
    static func registrationJSON(
        _ registration: ASAuthorizationPlatformPublicKeyCredentialRegistration
    ) -> JSONValue {
        var response: [String: JSONValue] = [
            "clientDataJSON": .string(registration.rawClientDataJSON.base64URLEncoded)
        ]
        if let attestation = registration.rawAttestationObject {
            response["attestationObject"] = .string(attestation.base64URLEncoded)
        }
        let id = registration.credentialID.base64URLEncoded
        return .object([
            "id": .string(id),
            "rawId": .string(id),
            "type": .string("public-key"),
            "clientExtensionResults": .object([:]),
            "response": .object(response),
        ])
    }
}

extension PasskeyCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        continuation?.resume(returning: authorization)
        continuation = nil
        presentationAnchor = nil
    }

    func authorizationController(
        controller: ASAuthorizationController, didCompleteWithError error: Error
    ) {
        let mapped: Error
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            mapped = PasskeyError.canceled
        } else {
            mapped = error
        }
        continuation?.resume(throwing: mapped)
        continuation = nil
        presentationAnchor = nil
    }
}

extension PasskeyCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let presentationAnchor else {
            preconditionFailure("Passkey presentation requested without an active authorization")
        }
        return presentationAnchor
    }
}

extension Data {
    /// RFC 4648 base64url without padding — the WebAuthn wire encoding.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var padded =
            string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }
        self.init(base64Encoded: padded)
    }
}
