# SwiftWaveform (extractWave) ⚡️

**轻量的音频波形提取库（Swift + FFmpeg）**

从音频文件中解码并生成波形数据（等分点的幅值数组），适用于可视化或预览场景。

---

## 功能 ✅

- 使用 FFmpeg 进行准确解码
- 输出可编码为 JSON 的 `WaveformData`（包含时长、采样率、总采样点、每点采样数与幅值数组）
- 支持自定义输出点数（默认 120）

---

## 要求 🔧

- macOS
- Swift（推荐使用最新稳定版本）
- 使用 Swift Package Manager（SPM）管理依赖
- 依赖：`FFmpegKitSPM`（已在源码中使用）

---

## 安装 📦

在你的 `Package.swift` 中添加依赖（或通过 Xcode 的 Swift Packages 添加）：

```swift
.package(url: "https://github.com/your/repo.git", from: "0.0.0")
```

然后在 target 的 dependencies 中引用 `SwiftWaveform`。

---

## 快速开始 （使用示例） 💡

```swift
import SwiftWaveform
import Foundation

let extractor = WaveformExtractor()
let fileURL = URL(fileURLWithPath: "/path/to/audio.m4a")

do {
    // duration 参数可传 -1 表示自动估算，points 为输出波形点数
    let waveform = try extractor.extract(url: fileURL, duration: -1, points: 120)

    // `WaveformData` 可被编码为 JSON
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let jsonData = try encoder.encode(waveform)
    print(String(data: jsonData, encoding: .utf8)!)
} catch {
    print("Waveform extraction failed: \(error)")
}
```

`WaveformData` 字段说明:
- `duration`：音频时长（秒）
- `sample_rate`：输出采样率（库内部使用 4000 Hz）
- `total_samples`：总采样点数
- `samples_per_point`：每个波形点平均对应的采样数
- `data`：幅值数组（Double[]）

---

## 构建与测试 🧪

使用 SPM 命令：

```bash
swift build
swift test
```

---

## 仓库清理说明 ⚠️

> 注意：仓库历史中曾包含大型音频文件（`assets/large.m4a`、`assets/adele.m4a`）。这些文件已使用 `git-filter-repo` 从历史中移除，并将相关规则加入到 `.gitignore`（例如 `*.m4a`）。

如果你需要把本地的历史重写推送到远程仓库：

```bash
# 1) (可选) 重新添加远程
git remote add origin <remote-repo-url>

# 2) 强制推送（会重写远程历史，请在团队中协同）
git push --force --tags origin main
```

---

## 贡献 🤝

欢迎提交 Issue 或 Pull Request：

- 保持 PR 小而专注
- 添加或更新单元测试
- 遵循现有代码风格

---

## 许可 📝

本仓库使用 **MIT 许可证**，详见项目根目录的 `LICENSE` 文件。

---

## 致谢

基于 FFmpeg 通过 `FFmpegKitSPM` 实现音频解码，感谢相应开源社区的贡献。

---

> 如需我把 README 翻译为英文或补充更详细的 API 文档（自动生成示例、更多用法、Benchmarks 等），告诉我需要的内容即可。