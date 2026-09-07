# Cloudflare 版部署说明

这是一套适合个人使用的最小版本：

- `Pages`：网页前端
- `Workers`：登录、分类、上传、下载、删除 API
- `R2`：实际资料文件

现有的 FileBrowser 本地版继续保留；Cloudflare 版是另一套独立存储。两边不会自动同步。

## 已实现

- 管理口令登录
- 六个学习资料分类
- 上传文件到 R2
- 列出当前分类文件
- 下载文件
- 删除文件
- 7 天登录令牌

## 部署前准备

需要一个 Cloudflare 账号，并安装 Node.js。进入项目目录：

```powershell
cd C:\Users\24291\Documents\ChatGPT\A\cloudflare\worker
npm install
npx wrangler login
```

创建 R2 存储桶：

```powershell
npx wrangler r2 bucket create beiger-library
```

设置登录口令和会话密钥。口令不要写进 GitHub：

```powershell
npx wrangler secret put ADMIN_PASSWORD
npx wrangler secret put SESSION_SECRET
```

`ADMIN_PASSWORD` 是登录书库的口令；`SESSION_SECRET` 可以设置成一串随机长字符串。

## 部署 Worker

```powershell
npx wrangler deploy
```

部署成功后会得到一个类似下面的 Worker 地址：

```text
https://beiger-library-worker.<你的账户>.workers.dev
```

把这个地址写入 `cloudflare/pages/config.js`：

```javascript
window.LIBRARY_API_BASE = "https://beiger-library-worker.<你的账户>.workers.dev";
```

## 部署 Pages

在 Cloudflare Dashboard 中创建 Pages 项目，连接 GitHub 仓库：

- 生产分支：`main`
- 构建命令：留空
- 输出目录：`cloudflare/pages`

部署完成后，打开 Pages 分配的地址，输入刚才设置的 `ADMIN_PASSWORD` 即可使用。

第一次部署时，`wrangler.toml` 的 `ALLOWED_ORIGIN` 暂时是 `*`，功能可以直接运行。上线后建议把它改成你的 Pages 地址，例如：

```toml
ALLOWED_ORIGIN = "https://beiger-library.pages.dev"
```

改完后重新部署 Worker：

```powershell
npx wrangler deploy
```

## 数据位置和费用提醒

文件保存在 R2，不再保存在电脑的 `BeigerLibrary` 文件夹。原来的本地版和 Cloudflare 版是两套资料库。使用前先上传少量测试文件确认流程。

Cloudflare 资源通常按使用量计费，具体费用以 Cloudflare 控制台当前显示为准。不要把登录口令、`SESSION_SECRET` 或 Cloudflare API Token 提交到 GitHub。

## 本地检查

```powershell
npm run typecheck
```
