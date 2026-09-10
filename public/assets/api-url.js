// Settings/storage contain real API URLs; only the request boundary adds a proxy.
const GLM_BASE_URL = "https://open.bigmodel.cn/api/paas/v4/";
const LOOPBACK_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]"]);

export function defaultApiBaseUrl(provider) {
  switch (provider) {
    case "GLM": return GLM_BASE_URL;
    case "openai": return "https://api.openai.com/v1";
    case "anthropic": return "https://api.anthropic.com";
    default: return "";
  }
}

function parseBaseUrl(value) {
  if (!value) throw new Error("请填写接口地址，例如 http://127.0.0.1:8080 或 https://api.example.com/v1。");
  if (/[\s\\\x00-\x1f\x7f]/u.test(value)) {
    throw new Error("接口地址不能包含空格、换行或反斜杠。");
  }
  if (!/^https?:\/\/[^/]/i.test(value)) {
    throw new Error("接口地址必须是完整的 HTTP 或 HTTPS 地址，以 http:// 或 https:// 开头。");
  }
  let url;
  try { url = new URL(value); }
  catch { throw new Error("接口地址格式不正确，请检查域名、IP 和端口。"); }
  if (url.username || url.password || value.slice(value.indexOf("://") + 3).split("/")[0].includes("@")) {
    throw new Error("接口地址不能包含用户名或密码，请在 API 密钥栏填写密钥。");
  }
  if (value.includes("?") || value.includes("#")) {
    throw new Error("接口地址不能包含查询参数（?）或片段（#），请只填写 API 根地址。");
  }
  return url;
}

export function normalizeApiBaseUrl(value) {
  let real = typeof value === "string" ? value.trim() : "";
  // Unwrap only our old local proxy format, never a third-party /proxy/ path.
  // A bound also rejects pathological nested legacy proxy configurations.
  for (let depth = 0; depth < 8; depth++) {
    let rest;
    if (real.startsWith("/proxy/")) {
      rest = real.slice(7);
    } else {
      const url = parseBaseUrl(real);
      if (LOOPBACK_HOSTS.has(url.hostname) && url.pathname.startsWith("/proxy/")) {
        rest = url.pathname.slice(7);
      } else {
        const path = real.slice(real.indexOf("://") + 3).includes("/") ? url.pathname : "";
        return `${url.protocol}//${url.host}${path}`;
      }
    }
    if (!rest) throw new Error("请填写真实 API 接口地址，不能只有代理前缀。");
    real = rest.startsWith("http:/")
      ? "http://" + rest.slice(6).replace(/^\/+/, "")
      : "https://" + rest;
  }
  throw new Error("接口地址包含多层代理，请改填真实 API 地址。");
}

export function apiBaseUrlError(value) {
  try { normalizeApiBaseUrl(value); return ""; }
  catch (error) { return error.message; }
}

export function displayApiBaseUrl(value) {
  try { return normalizeApiBaseUrl(value); }
  catch { return typeof value === "string" ? value.trim() : ""; }
}

export function migrateProviderConfig(config) {
  return config ? { ...config, customPrefixUrl: displayApiBaseUrl(config.customPrefixUrl) } : config;
}

// Persist incomplete settings without losing credentials or reviving an old URL.
// Invalid URL text stays in the live field for correction, never in saved config.
export function providerConfigDraft(config) {
  return { ...config, customPrefixUrl: apiBaseUrlError(config.customPrefixUrl)
    ? "" : normalizeApiBaseUrl(config.customPrefixUrl) };
}

export function isProviderConfigured(config) {
  return Boolean(config && config.provider && config.apiKey?.trim() && config.model?.trim()
    && !apiBaseUrlError(config.customPrefixUrl));
}

export function requestApiBaseUrl(value, provider, origin) {
  let real = normalizeApiBaseUrl(value);
  // Anthropic's SDK appends /v1/messages; remove exactly one terminal /v1.
  // Keep the entered path in settings/storage so normalization is idempotent.
  if (provider === "anthropic") real = real.replace(/\/v1\/?$/, "");
  const url = new URL(real);
  if (provider === "GLM" && url.origin === "https://open.bigmodel.cn"
    && /^\/api\/(?:coding\/)?paas\/v4\/?$/.test(url.pathname)) return real;
  const target = real.slice(real.indexOf("://") + 3);
  return `${new URL(origin).origin}/proxy/${url.protocol === "http:" ? "http:/" : ""}${target}`;
}
