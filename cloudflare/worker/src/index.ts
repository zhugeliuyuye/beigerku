export interface Env {
  LIBRARY_BUCKET: R2Bucket;
  APP_NAME: string;
  ADMIN_PASSWORD: string;
  SESSION_SECRET: string;
  ALLOWED_ORIGIN: string;
}

const TOKEN_TTL_SECONDS = 60 * 60 * 24 * 7;
const CATEGORY_NAMES = [
  "01 编程与技术",
  "02 英语与语言",
  "03 考试与课程",
  "04 阅读与论文",
  "05 笔记与总结",
  "99 待整理",
];
const encoder = new TextEncoder();
const decoder = new TextDecoder();

function json(data: unknown, init: ResponseInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("content-type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(data, null, 2), {
    ...init,
    headers,
  });
}

function base64UrlEncode(value: Uint8Array) {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlDecode(value: string) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(padded);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

async function sign(value: string, secret: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(value));
  return base64UrlEncode(new Uint8Array(signature));
}

async function issueToken(env: Env) {
  const expiresAt = Math.floor(Date.now() / 1000) + TOKEN_TTL_SECONDS;
  const payload = `${expiresAt}.${crypto.randomUUID()}`;
  return `${base64UrlEncode(encoder.encode(payload))}.${await sign(payload, env.SESSION_SECRET)}`;
}

async function isAuthorized(request: Request, env: Env) {
  const header = request.headers.get("x-library-token") || request.headers.get("authorization") || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : header;
  const [encodedPayload, signature] = token.split(".");
  if (!encodedPayload || !signature || !env.SESSION_SECRET) return false;

  try {
    const payload = decoder.decode(base64UrlDecode(encodedPayload));
    const expiresAt = Number(payload.split(".")[0]);
    if (!Number.isFinite(expiresAt) || expiresAt < Math.floor(Date.now() / 1000)) return false;
    const expected = await sign(payload, env.SESSION_SECRET);
    return signature === expected;
  } catch {
    return false;
  }
}

function allowedOrigin(request: Request, env: Env) {
  const origin = request.headers.get("Origin");
  if (!origin) return "";
  const allowed = (env.ALLOWED_ORIGIN || "*")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  return allowed.includes("*") || allowed.includes(origin) ? (allowed.includes("*") ? "*" : origin) : "";
}

function corsHeaders(request: Request, env: Env) {
  const origin = allowedOrigin(request, env);
  return {
    ...(origin ? { "access-control-allow-origin": origin } : {}),
    "access-control-allow-headers": "content-type, x-library-token, authorization",
    "access-control-allow-methods": "GET, POST, DELETE, OPTIONS",
    "access-control-max-age": "86400",
    vary: "Origin",
  };
}

function withCors(request: Request, env: Env, init: ResponseInit = {}) {
  const headers = new Headers(init.headers);
  for (const [key, value] of Object.entries(corsHeaders(request, env))) {
    headers.set(key, value);
  }
  return {
    ...init,
    headers,
  };
}

function safeKey(value: string) {
  const key = value.replace(/\\/g, "/").replace(/^\/+/, "");
  if (!key || key.length > 1024 || key.includes("\0")) return null;
  if (key.split("/").some((segment) => segment === ".." || segment === ".")) return null;
  return key;
}

function downloadName(key: string) {
  const raw = key.split("/").pop() || "download";
  return raw.replace(/[\r\n"]/g, "_").slice(0, 180) || "download";
}

function unauthorized(request: Request, env: Env) {
  return json({ error: "unauthorized" }, withCors(request, env, { status: 401 }));
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(request, env) });
    }

    if (url.pathname === "/api/health" && request.method === "GET") {
      return json({ ok: true, app: env.APP_NAME }, withCors(request, env));
    }

    if (url.pathname === "/api/login" && request.method === "POST") {
      const body = await request.json().catch(() => ({} as Record<string, unknown>));
      const password = String(body.password || "");
      if (!env.ADMIN_PASSWORD || !env.SESSION_SECRET || password !== env.ADMIN_PASSWORD) {
        return json({ ok: false, error: "invalid password" }, withCors(request, env, { status: 401 }));
      }
      return json(
        { ok: true, token: await issueToken(env), expiresIn: TOKEN_TTL_SECONDS },
        withCors(request, env),
      );
    }

    if (url.pathname === "/api/categories" && request.method === "GET") {
      if (!(await isAuthorized(request, env))) return unauthorized(request, env);
      return json(
        { categories: CATEGORY_NAMES.map((name) => ({ name, path: `${name}/` })) },
        withCors(request, env),
      );
    }

    if (url.pathname === "/api/files" && request.method === "GET") {
      if (!(await isAuthorized(request, env))) return unauthorized(request, env);
      const prefix = safeKey(url.searchParams.get("prefix") || "") || "";
      const cursor = url.searchParams.get("cursor") || undefined;
      const listed = await env.LIBRARY_BUCKET.list({ prefix, cursor, limit: 1000 });
      return json(
        {
          prefix,
          files: listed.objects.map((item) => ({
            key: item.key,
            size: item.size,
            uploaded: item.uploaded?.toISOString?.() ?? null,
          })),
          truncated: listed.truncated,
          cursor: listed.truncated ? listed.cursor : null,
        },
        withCors(request, env),
      );
    }

    if (url.pathname === "/api/upload" && request.method === "POST") {
      if (!(await isAuthorized(request, env))) return unauthorized(request, env);
      const form = await request.formData();
      const file = form.get("file");
      const key = safeKey(String(form.get("key") || ""));

      if (!(file instanceof File)) {
        return json({ error: "missing file" }, withCors(request, env, { status: 400 }));
      }
      if (!key || !key.includes("/")) {
        return json({ error: "invalid key" }, withCors(request, env, { status: 400 }));
      }

      await env.LIBRARY_BUCKET.put(key, file.stream(), {
        httpMetadata: { contentType: file.type || "application/octet-stream" },
      });
      return json({ ok: true, key }, withCors(request, env));
    }

    if (url.pathname === "/api/download" && request.method === "GET") {
      if (!(await isAuthorized(request, env))) return unauthorized(request, env);
      const key = safeKey(url.searchParams.get("key") || "");
      if (!key) return json({ error: "invalid key" }, withCors(request, env, { status: 400 }));

      const object = await env.LIBRARY_BUCKET.get(key);
      if (!object) return json({ error: "not found" }, withCors(request, env, { status: 404 }));

      return new Response(object.body, {
        headers: {
          ...(object.httpMetadata?.contentType
            ? { "content-type": object.httpMetadata.contentType }
            : { "content-type": "application/octet-stream" }),
          "content-length": String(object.size),
          "content-disposition": `attachment; filename="${downloadName(key)}"; filename*=UTF-8''${encodeURIComponent(downloadName(key))}`,
          etag: object.httpEtag,
          ...corsHeaders(request, env),
        },
      });
    }

    if (url.pathname === "/api/delete" && request.method === "DELETE") {
      if (!(await isAuthorized(request, env))) return unauthorized(request, env);
      const key = safeKey(url.searchParams.get("key") || "");
      if (!key) return json({ error: "invalid key" }, withCors(request, env, { status: 400 }));
      await env.LIBRARY_BUCKET.delete(key);
      return json({ ok: true, key }, withCors(request, env));
    }

    return json({ error: "not found" }, withCors(request, env, { status: 404 }));
  },
};
