# 棋境 Qijing

七种棋 × 五档 AI 的 iOS 对弈合集。

## 棋种

围棋 · 将棋 · 中国象棋 · 国际象棋 · 国际跳棋（10×10 FMJD）· 五子棋 · 黑白棋

## AI

- 全部引擎为 Swift 自写，采用公开经典算法机制（不使用 GPL 代码，规避 App Store 许可证问题）
- 棋子类棋（象棋/国象/将棋/跳棋/五子/黑白棋）：negamax + α-β 剪枝 + 迭代加深 + 置换表 + 静态搜索
- 围棋：MCTS（UCB1）+ 死活启发
- 难度五档：低 / 中 / 高 / 超高 / 天人（搜索深度、思考时限、容差放水分层）

## 结构

```
App/            SwiftUI 界面（iOS 26 液态玻璃，兼容 iOS 17+）
BoardCore/      纯 Swift 引擎包（SwiftPM，可独立测试）
project.yml     XcodeGen 工程定义（CI 里生成 .xcodeproj）
.github/        GitHub Actions：单测（Linux）+ 未签名 IPA 构建（macOS）
```

## 构建

本地（需 macOS + Xcode 26）：

```bash
brew install xcodegen
xcodegen generate
open Qijing.xcodeproj
```

CI：推送到 GitHub 后，Actions 产出 `Qijing-unsigned.ipa` 工件，用
[Sideloadly](https://sideloadly.io) 或 AltStore + 自有 Apple ID 签名侧载。

## 测试

```bash
cd BoardCore && swift test
```
