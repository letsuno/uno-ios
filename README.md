<h1 align="center">UNO for iOS</h1>

<p align="center">
  <a href="https://github.com/letsuno/uno-ios"><img src="https://img.shields.io/github/license/letsuno/uno-ios" alt="License" /></a>
  <a href="https://github.com/letsuno/uno-ios/actions/workflows/ci.yml"><img src="https://github.com/letsuno/uno-ios/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
</p>

A native SwiftUI client for playing on self-hosted [UNO Online](https://github.com/letsuno/uno-online) servers from iPhone and iPad.

## Highlights

- Native SwiftUI interface for rooms, spectating, real-time games, and chat
- Password, API key, development-mode, and Passkey authentication
- Configurable house rules with Classic, Party, and Crazy presets
- Bot players with selectable difficulty levels
- Direct Socket.IO communication over WebSocket without a third-party client dependency
- Secure-by-default server connections with HTTPS/WSS for public hosts and HTTP/WS support for local networks

## Requirements

- Xcode 26 or later
- iOS or iPadOS 26 or later
- A compatible self-hosted [UNO Online](https://github.com/letsuno/uno-online) server

## Quick Start

```bash
git clone https://github.com/letsuno/uno-ios.git
cd uno-ios
open UnoClient.xcodeproj
```

Select the `UnoClient` scheme, choose your development team for device signing, and run the app. Enter the base URL of your server on the connection screen.

To verify a release build without code signing:

```bash
make quality
make build
```

## Server Connections

Public servers must use HTTPS/WSS. Plaintext HTTP/WS is limited to `localhost`, `.local` hosts, unqualified hostnames, and private or link-local IP addresses for self-hosted development.

Passkeys require the app's Associated Domains entitlement and the server's WebAuthn configuration to use the same relying-party domain. Update `UnoClient/UnoClient.entitlements` when deploying against a different domain.

## Development

Debug builds support these launch environment variables:

- `UNO_TEST_SERVER` and `UNO_TEST_TOKEN` preconfigure a server and login credential.
- `UNO_TEST_FLOW=quickgame` creates a room, adds three bots, and starts a game after login.

Never commit real credentials to project files or shared schemes.

Run the test suite with:

```bash
make test TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
```

## Project Layout

```text
UnoClient/
  App/      # application entry point and launch automation
  Core/     # REST, WebSocket, Passkey, and Keychain integration
  Models/   # protocol and game models
  Stores/   # session, room, and game state
  Views/    # SwiftUI screens and components
UnoClientTests/  # endpoint policy, encoding, and game-rule tests
```

## Contributing and Support

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and pull-request expectations, and [RELEASING.md](RELEASING.md) for the automated tag and GitHub Release process. Use [GitHub Issues](https://github.com/letsuno/uno-ios/issues) for reproducible client problems, and follow [SECURITY.md](SECURITY.md) for private vulnerability reports.

## Project Status

This is an unofficial, non-profit community project. It is not affiliated with, sponsored by, or endorsed by Mattel or any other owner of similarly named games. The repository does not include official logos, trademark artwork, or game assets.

## License

[AGPL-3.0](LICENSE)
