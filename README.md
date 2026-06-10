# GLM Excel Custom — Multi-Provider Add-in

A local patch of the official “GLM in Excel” Office add-in that unlocks
OpenAI / Anthropic Claude / any OpenAI-compatible endpoint, served from a
local HTTPS server instead of the official CDN. GLM (ZhipuAI) is retained
as an optional backend.

## How it works

The official add-in loads its frontend from `office-addin.bigmodel.cn` on
every use — it can't be modified in place. This project:

1. Saves the frontend bundle locally under `public/`
2. Patches it (`patch.py`) — unlocks the settings UI, adds multi-provider
   support and per-field `?` tooltips
3. Serves it over a local HTTPS server (`server.cjs`, default port 3000)
4. Registers a custom manifest (`manifest/manifest.xml`) that points Excel
   to `https://localhost:PORT` instead of the official CDN

A built-in CORS reverse proxy at `/proxy/<domain>/...` lets you call APIs
that block browser cross-origin requests.

## Quick start (developer)

**Prerequisites:** Node.js 22+, Windows with Microsoft Excel installed.

```cmd
:: 1. Generate a self-signed localhost cert (one-time)
cd installer
powershell -ExecutionPolicy Bypass -File gen-cert.ps1
cd ..

:: 2. Register the sideload manifest
npx office-addin-dev-settings register manifest/manifest.xml

:: 3. Start the local server (keep this window open while using the add-in)
start-server.cmd
```

Open Excel → **Home** tab → **AI in Excel** → **Settings** → enter your API key.

## Providers & CORS proxy

Switching the provider in Settings auto-fills the base URL via the local proxy:

| Provider | Auto-filled base URL |
|---|---|
| GLM (ZhipuAI) | official endpoint (CORS-enabled, direct) |
| OpenAI | `https://localhost:PORT/proxy/api.openai.com/v1` |
| Anthropic Claude | `https://localhost:PORT/proxy/api.anthropic.com` |
| OpenAI-compatible | `https://localhost:PORT/proxy/<your-relay-domain>` |

The proxy at `/proxy/<domain>/<path>` forwards server-side (no CORS
restrictions) and adds the necessary CORS response headers.

Example — using an OpenRouter relay:
```
Provider:  OpenAI-compatible
Base URL:  https://localhost:3000/proxy/openrouter.ai/api/v1
Model:     openai/gpt-4o
API key:   your-key
```

## What the patch does

- **P1** — model-resolution fallback: unknown model names auto-construct a
  default model object so any third-party model name works
- **P2** — settings UI: replaces the locked GLM dropdown with a free-form
  provider selector + base URL + model field, each with a `?` help tooltip
- **P3** — API-key field tooltip
- **P4–P8** — removes upstream GLM/ZhipuAI branding; customize these in
  `patch.py` to add your own
- **P9** — copyright line
- **P10** — removes the upstream “beta” badge
- **P11** — default config (shown on first launch before any settings are saved)

Re-run `python patch.py` at any time to rebuild `taskpane-DG2CZyG2.js` from
the pristine `.orig` backup.

## Customize the branding

1. Edit the strings in `patch.py` sections P4–P9 (app title, about text,
   contact info).
2. Edit `manifest/manifest.xml` — `ProviderName`, `DisplayName`,
   `Description`, `SupportUrl`.
3. Replace the placeholder icons in `public/assets/` and `installer/`:
   - Edit `SRC` / `HEADER_SRC` paths at the top of `make-icons.py`
   - Run `python make-icons.py` (requires `pip install pillow`)

## One-click installer for end users

For users who don't have Node installed (no admin rights required):

```cmd
cd installer
build.cmd
```

Produces `installer/dist/AI-Excel-Setup.exe`. When run it:

- Picks a free port in 3000–3099
- Installs a self-signed localhost cert into the current user's trust store
- Embeds the entire frontend into a Node SEA binary (`AIExcelServer.exe`)
- Creates desktop and Start Menu shortcuts

To uninstall: **Start Menu → AI in Excel → 卸载 AI in Excel**

Key design choices:
- **No admin**: cert goes into `CurrentUser\Root`, files into
  `%LOCALAPPDATA%\AIExcelCustom`, sideload into `HKCU` — no UAC prompt
- **Auto port**: installer scans 3000–3099 for a free port; the frontend
  uses `location.origin` so it follows the port automatically; if the port
  is taken at runtime, the server picks a new one and re-registers the manifest
- **Self-contained**: the frontend JS is embedded in the exe via Node SEA

## Notes

- Cert passphrase for `localhost.pfx`: `localdev` (set in `gen-cert.ps1` and
  `server.cjs`)
- Remove sideload: `npx office-addin-dev-settings unregister manifest/manifest.xml`
- Restore original JS: `copy public\assets\taskpane-DG2CZyG2.js.orig public\assets\taskpane-DG2CZyG2.js`
- The proxy uses direct connections (bypasses system proxy). To route through
  a local proxy (e.g. Clash on 127.0.0.1:7897), add an `undici` `ProxyAgent`
  in `server.cjs`.

## License

The patch scripts, server, and installer code in this repository are released
under the **MIT License**. The original GLM in Excel frontend bundle
(`taskpane-DG2CZyG2.js.orig`) is copyright ZhipuAI and is included here
solely for patching purposes under fair use / personal modification.

