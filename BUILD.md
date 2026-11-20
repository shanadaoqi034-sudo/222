# 用 GitHub Actions 构建 NeoStatus

## 为什么需要这个

NeoStatus 注入的是 **SpringBoard**，它是 arm64e 进程。
dylib 必须包含 **arm64e 切片**才能被注入。

Linux 的 lld 链接器产不出 arm64e（`-fixup_chains` 不支持），
所以必须在 macOS 上编译。GitHub Actions 免费提供 macOS runner。

## 用法

1. 在 GitHub 上建一个空仓库（private 也可以）
2. 把本目录所有文件推上去：

```bash
git init
git add .
git commit -m "NeoStatus 1.0.0"
git branch -M main
git remote add origin https://github.com/你的用户名/仓库名.git
git push -u origin main
```

3. 打开仓库的 **Actions** 标签页
4. 等 "Build NeoStatus" 跑完（约 5-8 分钟）
5. 点进去，页面底部 **Artifacts** 下载 `NeoStatus-deb`
6. 解压得到 `.deb`，传到手机安装

## workflow 会做什么

- 装 Theos + iOS SDK
- `make package FINALPACKAGE=1`
- **自动验证 dylib 是否含 arm64e 切片**，没有就直接失败
- 上传 deb

## 如果失败

看 Actions 里的日志。常见原因：

- SDK 版本不匹配 → 改 workflow 里 `Install iOS SDK` 那步的版本号
- 依赖缺失 → `NeoStatus_FRAMEWORKS` 里加对应框架

把报错贴给我。
