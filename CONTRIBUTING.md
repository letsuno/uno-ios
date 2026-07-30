# Contributing

Contributions are welcome through GitHub issues and pull requests.

## Development Setup

Requirements:

- Xcode 26 or later
- iOS or iPadOS 26 SDK
- GNU Make

Clone the repository and open `UnoClient.xcodeproj` for interactive development. Select your own development team when running on a device; signing identities must not be committed.

Run the repository checks before opening a pull request:

```bash
make quality
make build
make test TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
```

The simulator name can be replaced with any available iPhone simulator.

## Change Guidelines

- Keep user-facing behavior compatible with the supported UNO Online server protocol.
- Add regression tests for fixes and tests for new protocol or game-rule behavior.
- Use `swift-format`; avoid unrelated formatting or generated project changes.
- Never commit credentials, signing identities, provisioning profiles, or real server tokens.
- Update README or security documentation when behavior, requirements, or trust boundaries change.

## Pull Requests

Keep each pull request focused and describe the resulting behavior. Include the commands actually used for validation. CI must pass before merge.

Security vulnerabilities must follow [SECURITY.md](SECURITY.md) instead of the public pull-request workflow.
