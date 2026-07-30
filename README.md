# UnoClient

UnoClient 是一个面向自托管服务端的开源 iOS 在线卡牌客户端。它提供原生 SwiftUI 界面、房间与观战流程、实时对局、聊天、机器人玩家，以及密码、API Key 和 Passkey 登录。

> [!IMPORTANT]
> 本项目是非官方、非营利的社区项目，与 Mattel 或其他同名商业游戏及其权利人不存在隶属、赞助或背书关系。仓库不包含其官方图标、商标图形或美术资源。

## 环境要求

- Xcode 26 或更高版本
- iOS / iPadOS 26 或更高版本
- 与客户端协议兼容的自托管服务端

## 构建

在 Xcode 中打开 `UnoClient.xcodeproj`，选择 `UnoClient` scheme 与任意 iOS 模拟器后运行。

也可以通过命令行验证：

```bash
xcodebuild build \
  -project UnoClient.xcodeproj \
  -scheme UnoClient \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

单元测试需要一个可用的 iOS 模拟器：

```bash
xcodebuild test \
  -project UnoClient.xcodeproj \
  -scheme UnoClient \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

真机运行时请在本地选择自己的 Development Team；工程不会把维护者的签名身份提交到仓库。

## 网络模型

客户端默认使用 HTTPS/WSS。为方便本地自托管开发，它也允许连接 `localhost`、`.local`、局域网 IPv4/IPv6 地址及无限定主机名上的 HTTP/WS 服务。公共主机必须使用 HTTPS。

Passkey 依赖服务端域名与应用的 Associated Domains 配置。若部署到其他域名，需要同步调整 `UnoClient/UnoClient.entitlements` 与服务端的 WebAuthn 配置。

## 调试自动化

Debug 构建支持以下启动环境变量：

- `UNO_TEST_SERVER` 与 `UNO_TEST_TOKEN`：预置服务端地址和登录凭据。
- `UNO_TEST_FLOW=quickgame`：登录后自动创建房间、加入机器人并启动对局。

不要把真实 Token 写入工程文件、scheme 或提交记录。

## 许可证

本项目依据 [GNU Affero General Public License v3.0](LICENSE) 发布。
