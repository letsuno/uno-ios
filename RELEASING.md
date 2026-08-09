# Releasing

`Configuration/Shared.xcconfig` is the source of truth for the public release version. `MARKETING_VERSION` must use `MAJOR.MINOR.PATCH`; `CURRENT_PROJECT_VERSION` is the bundle build number.

## Automatic Release

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in a pull request.
2. Merge the pull request after `Required Checks` succeeds.
3. CI validates the resulting `main` commit.
4. `Auto Tag` creates an annotated `vMAJOR.MINOR.PATCH` tag for the current `main` commit.
5. `Publish` validates the tag and creates the corresponding GitHub Release with generated release notes.

Tags are immutable. If the version tag already exists, automation reuses it only when it belongs to the `main` history; it never moves the tag.

## Recovery

If tagging or release creation is interrupted, run `Auto Tag` manually from `main`. The optional `source_sha` must be the current full `main` SHA. To recover only a missing GitHub Release for an existing tag, run `Publish` manually and provide the tag name.

The workflows are idempotent: an existing valid tag or release is reused rather than recreated.

## TestFlight

`Upload iOS to TestFlight` 工作流会使用 Release 配置构建选定的 Git ref，以 App Store 分发身份完成签名，验证导出的 IPA，并上传到 App Store Connect。

### Run

1. GitHub → **Actions** → **Upload iOS to TestFlight** → **Run workflow**。
2. `Use workflow from` 固定选择 `main`；在 `release_ref` 输入构建目标：`main` 或已存在、位于 `main` 历史且版本匹配的 `vMAJOR.MINOR.PATCH` 标签。
3. 默认使用 GitHub Actions run number 作为 `CFBundleVersion`；若该编号在当前发布版本中已被占用，可通过 `build_number` 输入一个尚未使用的正整数。
4. 构建、签名、上传全自动；结束后在 App Store Connect → TestFlight 确认 `MARKETING_VERSION` 与构建号。

### Validation

上传前工作流会中止不合规的构建，失败原因见 run 日志：

- `build_number` 必须为正整数；
- workflow definition 必须从 `main` 运行；`release_ref` 只能是当前 `main` 或位于 `main` 历史且与源码版本一致的发布标签；
- provisioning profile 的 application-identifier 必须与选定源码解析出的 bundle identifier 一致；
- profile 不得包含 `ProvisionedDevices` 或 `ProvisionsAllDevices`，即必须是 App Store 分发 profile 而非 development、ad hoc 或 enterprise。

### Credentials

凭据保存在 1Password，工作流通过 service account 读取。创建名为 `testflight` 的 GitHub Environment，仅允许 `main` 部署；建议启用 required reviewer 并禁止 self-review。唯一需要配置的 environment secret 是 `OP_SERVICE_ACCOUNT_TOKEN`，该 token 需对下述 vault 具备读权限。不要在 repository 或 organization secrets 中保留同名 token。

```
Letsuno CI
├── Apple Distribution
│   ├── Cert_Ethan.p12                 file    Apple Distribution 证书与私钥（PKCS #12）
│   └── password                       field   PKCS #12 密码
├── UnoClient App Store Profile
│   └── UnoClient.mobileprovision      file    App Store provisioning profile
└── App Store Connect
    ├── AuthKey.p8                     file    App Store Connect API 私钥
    ├── key_id                         field   API Key ID
    └── issuer_id                      field   API Issuer ID
```

vault 布局变化时同步修改 `.github/workflows/testflight.yml` 顶部的 `OP_*` item 引用。Environment branch policy 与 reviewer 属于 GitHub 仓库设置，不由 workflow 文件自动创建。

### Version and signing

工作流从选定源码解析 bundle identifier 与发布版本，并从 provisioning profile 解析 Apple Team ID 与 profile 名称。发布工具固定使用 workflow definition 所在 `main` 的 Makefile，并在目标源码目录执行 `make archive` 与 `make export`，因此历史标签无需包含新版发布 target。签名参数不写死在 Makefile 里，`CODE_SIGN_STYLE`、`CODE_SIGN_IDENTITY`、`DEVELOPMENT_TEAM`、`PROVISIONING_PROFILE_SPECIFIER`、`CURRENT_PROJECT_VERSION` 默认为空，本地 `make archive` 仍使用工程的自动签名。上传包含 dSYM（`uploadSymbols: true`），`manageAppVersionAndBuildNumber: false` 防止 App Store Connect 自动改写构建号。
