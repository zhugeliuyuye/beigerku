# beigerku

个人学习资料库，直接部署 [FileBrowser Quantum](https://github.com/gtsteffaniak/filebrowser) 稳定版 `v1.5.6-stable`，不修改上游程序。

## 日常使用

- 双击 `启动书库.cmd`，浏览器打开 `http://127.0.0.1:8090`。
- 用户名为 `library`。首次生成的随机密码保存在 `.local/credentials.json`，请在本机查看；如果以后在网站中改了密码，以新密码为准。
- 已配置简体中文和六个分类文件夹，可自行新建、重命名和移动分类。
- 支持上传、下载、文件名搜索、PDF/图片预览以及文本编辑。其他文件可以保存；Office 在线编辑不在本次部署范围内。
- 双击 `停止书库.cmd` 关闭服务，文件仍然保留。重启电脑后需要再次启动书库。
- 当前仅本机可访问，不需要公网服务器或域名。电脑关机后无法访问。

## 安卓平板访问（同一 Wi-Fi）

1. 在电脑上把 `.local\config.yaml` 中的 `server.listen` 改为 `0.0.0.0`。
2. 在 Windows 防火墙中允许专用网络的 TCP `8090` 端口。
3. 双击 `启动书库.cmd`，在电脑上运行 `ipconfig`，找到 Wi-Fi 网卡的 IPv4 地址。
4. 平板与电脑连接同一个 Wi-Fi，在浏览器打开 `http://电脑IPv4地址:8090`，例如 `http://192.168.1.23:8090`。

平板上传、移动、重命名和删除的内容会直接保存到电脑的 `BeigerLibrary` 资料目录。电脑关机或书库未启动时，平板无法访问。不要把端口转发到互联网；只在可信的家庭/个人局域网使用。

如果防火墙提示“拒绝访问”，请用“管理员身份”打开 PowerShell，执行：

```powershell
New-NetFirewallRule -DisplayName "BeigerLibrary 8090 LAN" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8090 -Profile Private
```

## 数据与备份

默认资料目录为 Windows「文档」下的 `BeigerLibrary`，不在 Git 仓库内。真实路径可在 `.local/instance.json` 中查看。

双击 `备份书库.cmd`，程序会暂停书库，复制资料（包括隐藏文件）、账号数据库、配置及登录信息到资料目录旁的 `BeigerLibrary-Backups`，然后恢复运行。备份期间请勿上传或编辑文件。每次创建新目录，不覆盖旧备份。只有包含 `backup.json` 且 `complete` 为 `true` 的目录才是完整备份。服务重启后需要重新登录，账号和密码不变。

备份不是定时执行的；请在重要整理后手动备份，并将完整备份目录复制到另一块硬盘。单纯备份 Git 仓库无法恢复学习资料。删除文件需确认，但这个版本没有可靠的回收站，请先做好备份。

同一台电脑恢复时，先停止书库，将当前资料和 `.local/state` 另行保存，再用备份中的 `materials`、`state` 和配置恢复到原位置。换电脑时需要调整配置中的绝对路径。备份含登录信息，仅作个人保管。

## 首次安装

需要 Windows x64 和 PowerShell 5.1 或更高版本，不需要 Docker 或单独安装数据库。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\library.ps1 -Action Install
```

使用 Clash 时，可以按实际代理端口指定：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\library.ps1 -Action Install -Proxy http://127.0.0.1:7897
```

安装脚本会验证官方 Windows 程序的 SHA-256。版本、来源和校验值见 `deployment/release.json`。已存在的账号和资料不会因为再次安装而重建。端口被占用时启动会报错，不会终止其他程序。

```powershell
.\scripts\library.ps1 -Action Status
.\scripts\library.ps1 -Action Backup
```

`deployment/config.template.json` 是可分享的配置模板；安装后实际使用的是 `.local/config.yaml`，以 JSON 形式保存合法 YAML。实际配置、账号、数据库、日志和下载的程序都被 `.gitignore` 排除，不要强制加入 Git。

## 来源

- 上游及许可证：[FileBrowser Quantum / Apache-2.0](https://github.com/gtsteffaniak/filebrowser)
- 固定版本：[v1.5.6-stable](https://github.com/gtsteffaniak/filebrowser/releases/tag/v1.5.6-stable)
- Windows 部署：[官方稳定版说明](https://filebrowserquantum.com/en/docs/getting-started/windows-v1.5.x/)

本仓库只存放个人部署配置、启动脚本和说明。GitHub Pages 不能运行此后端，也不是资料存储服务。

## Cloudflare 云端版

仓库中还提供了一套独立的 Cloudflare 版本，目录在 `cloudflare/`：

- Pages 托管网页
- Workers 提供登录和文件 API
- R2 保存云端资料

这套版本与本机 FileBrowser 的资料不会自动同步。部署步骤见 [`cloudflare/README.md`](cloudflare/README.md)。
