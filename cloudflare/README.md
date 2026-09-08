# Cloudflare Pages + Supabase 部署说明

这是一套不依赖 Cloudflare R2 的个人资料库方案：

- `Cloudflare Pages`：托管网页
- `Supabase Auth`：邮箱密码登录
- `Supabase Storage`：保存资料文件

现有的 FileBrowser 本地版继续保留；这个云端版使用 Supabase 存储，两边不会自动同步。

## 已实现

- 邮箱密码登录
- 六个学习资料分类
- 上传文件到 Supabase Storage
- 按分类列出文件
- 下载文件
- 删除文件

## Supabase 设置

项目地址已经写入 `cloudflare/pages/config.js`：

```text
https://wcyozlrzwcgieinbdocw.supabase.co
```

公开 publishable key 也已经写入前端配置。不要把 `service_role` key 放进网页或 GitHub。

在 Supabase 控制台打开 SQL Editor，执行：

```sql
-- 文件位置：supabase/setup-library-storage.sql
```

也就是把仓库里的 `supabase/setup-library-storage.sql` 全部复制到 SQL Editor 后运行。它会创建私有 `library` bucket，并设置只允许登录用户访问自己文件夹的 Storage policies。

然后在 Supabase 控制台创建你的登录用户：

1. 打开 Authentication
2. 进入 Users
3. 点击 Add user
4. 填写你的邮箱和密码

建议只创建你自己的账号，并关闭公开注册。

## 部署 Pages

在 Cloudflare Dashboard 创建 Pages 项目，连接 GitHub 仓库：

- 生产分支：`main`
- 构建命令：留空
- 输出目录：`cloudflare/pages`

部署完成后，打开 Pages 分配的网址，用刚才在 Supabase 创建的邮箱和密码登录。

当前已经创建的 Pages 项目：

```text
https://beiger-library.pages.dev/
```

本次直接部署生成的预览地址：

```text
https://d307013c.beiger-library.pages.dev
```

## 使用限制

Supabase 免费版适合个人小资料库。请先上传少量测试文件确认流程，再逐步迁移资料。免费项目可能因长时间不用而暂停；如果网站突然无法访问，先去 Supabase 控制台检查项目状态。
