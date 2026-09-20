# vtb-pkgs

Live2D / 虚拟形象相关的**归档仓库**（旧仓库，名字保留）。

## 这个仓库现在存什么

| 内容 | 位置 |
|---|---|
| 模型产出（`shiro-1600`，19 个文件） | [`models/`](models/) |
| 打包记录、踩坑清单（原来的 README 全文） | [`docs/packaging-notes.md`](docs/packaging-notes.md) |
| 模型制作流程 | [`docs/搓模型流程.md`](docs/搓模型流程.md) |
| 补丁与改动说明 | [`docs/PATCHES.md`](docs/PATCHES.md) |
| **Linux 二进制 tar.gz** | 本仓库的 [Releases](../../releases) |

Release 里的 tar.gz 内容就是 pacman 包里的 `usr/` 文件树，任何发行版都能直接解包：

```bash
sudo tar xzf open-vt-bin-*.tar.gz -C /
```

> 这样装**不会**登记到 pacman 数据库，升级和卸载都不受管。Arch 用户请用下面的源。

## Arch 用户：pacman 源已经搬走了

配方和构建好的包都挪到了新仓库 **[tc1911/tc191-pkgs](https://github.com/tc1911/tc191-pkgs)**，
由 GitHub Pages 托管、滚动覆盖（不再往 Release 堆二进制）：

```ini
[tc191]
SigLevel = Optional TrustAll
Server = https://tc1911.github.io/tc191-pkgs/
```

```bash
sudo pacman -Syu
sudo pacman -S open-vt-bin openseeface psd2live-bin
```

（没做 gpg 签名所以是 `Optional TrustAll`；介意的话用仓库里的 `SHA256SUMS` 自己校验。
`github.io` 国内可直连，不需要再套 `gh-proxy.com`。）

## 为什么拆成两个仓库

- **二进制不进 git 历史**：每发一版往仓库里塞几百 MB 是不可持续的，所以产物走「发布通道」，
  源码配方走「git 仓库」。
- 本仓库只做归档：模型产出 + 文档 + 二进制 tar.gz 的 Release。
- 可构建、可维护的配方（PKGBUILD、打包脚本、补丁）全在 `tc191-pkgs`，
  跟它要打包的源码放在一起 —— 避免同一份配方在两个仓库里各改一半。
