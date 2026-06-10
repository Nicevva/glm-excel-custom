# GLM Excel Web Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and deploy a bilingual (zh/en) product landing site for glm-excel-public on Vercel.

**Architecture:** Next.js 15 App Router with `[locale]` prefix routing via next-intl. Tailwind CSS for hand-drawn clean style. anime.js v4 for subtle entrance animations. Multi-page: Home, Quick Start, FAQ, Changelog.

**Tech Stack:** Next.js 15, TypeScript, Tailwind CSS, next-intl, anime.js v4, Vercel

---

## File Structure

```
glm-excel-web/
├── src/
│   ├── app/
│   │   ├── [locale]/
│   │   │   ├── layout.tsx          ← locale layout with Navbar + Footer
│   │   │   ├── page.tsx            ← Home (Hero + Features + About)
│   │   │   ├── quick-start/
│   │   │   │   └── page.tsx
│   │   │   ├── faq/
│   │   │   │   └── page.tsx
│   │   │   └── changelog/
│   │   │       └── page.tsx
│   │   ├── layout.tsx              ← root layout (html, body)
│   │   └── globals.css
│   ├── components/
│   │   ├── Navbar.tsx
│   │   ├── Footer.tsx
│   │   ├── LanguageSwitcher.tsx
│   │   ├── FeatureCard.tsx
│   │   ├── FaqAccordion.tsx
│   │   ├── ChangelogTimeline.tsx
│   │   └── AnimateOnScroll.tsx     ← reusable scroll-triggered anime.js wrapper
│   └── i18n/
│       ├── routing.ts
│       └── request.ts
├── messages/
│   ├── zh.json
│   └── en.json
├── public/
│   └── images/                     ← icons, illustrations
├── middleware.ts
├── next.config.ts
├── tailwind.config.ts
├── tsconfig.json
└── package.json
```

---

### Task 1: Create GitHub Repo & Scaffold Next.js Project

**Files:**
- Create: entire `glm-excel-web/` project via `create-next-app`

- [ ] **Step 1: Create GitHub repo**

```bash
gh repo create Nicevva/glm-excel-web --public --description "Product landing site for GLM Excel Custom" --clone
cd glm-excel-web
```

- [ ] **Step 2: Scaffold Next.js 15 with TypeScript + Tailwind**

```bash
npx create-next-app@latest . --typescript --tailwind --eslint --app --src-dir --import-alias "@/*" --use-npm
```

Select: No to Turbopack for dev (stable default).

- [ ] **Step 3: Install dependencies**

```bash
npm install next-intl animejs
npm install -D @types/animejs
```

- [ ] **Step 4: Verify scaffold runs**

```bash
npm run dev
```

Open `http://localhost:3000` — confirm the default Next.js page loads.

- [ ] **Step 5: Clean up scaffold**

Remove default content from `src/app/page.tsx` and `src/app/globals.css` (keep Tailwind directives only).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: scaffold Next.js 15 project with Tailwind and deps"
```

---

### Task 2: Configure next-intl (i18n Routing)

**Files:**
- Create: `src/i18n/routing.ts`
- Create: `src/i18n/request.ts`
- Create: `middleware.ts`
- Create: `messages/zh.json`
- Create: `messages/en.json`
- Modify: `next.config.ts`
- Modify: `src/app/layout.tsx`
- Create: `src/app/[locale]/layout.tsx`
- Create: `src/app/[locale]/page.tsx`

- [ ] **Step 1: Create routing config**

Create `src/i18n/routing.ts`:

```typescript
import { defineRouting } from "next-intl/routing";

export const routing = defineRouting({
  locales: ["zh", "en"],
  defaultLocale: "en",
  localePrefix: "always",
});
```

- [ ] **Step 2: Create request config**

Create `src/i18n/request.ts`:

```typescript
import { getRequestConfig } from "next-intl/server";
import { hasLocale } from "next-intl";
import { routing } from "./routing";

export default getRequestConfig(async ({ requestLocale }) => {
  const requested = await requestLocale;
  const locale = hasLocale(routing.locales, requested)
    ? requested
    : routing.defaultLocale;

  return {
    locale,
    messages: (await import(`../../messages/${locale}.json`)).default,
  };
});
```

- [ ] **Step 3: Create middleware**

Create `middleware.ts` (project root, NOT inside `src/`):

```typescript
import createMiddleware from "next-intl/middleware";
import { routing } from "./src/i18n/routing";

export default createMiddleware(routing);

export const config = {
  matcher: "/((?!api|trpc|_next|_vercel|.*\\..*).*)",
};
```

- [ ] **Step 4: Update next.config.ts**

```typescript
import { NextConfig } from "next";
import createNextIntlPlugin from "next-intl/plugin";

const withNextIntl = createNextIntlPlugin("./src/i18n/request.ts");

const nextConfig: NextConfig = {};

export default withNextIntl(nextConfig);
```

- [ ] **Step 5: Create initial message files**

Create `messages/en.json`:

```json
{
  "metadata": {
    "title": "GLM Excel Custom",
    "description": "Let Excel connect to any AI — OpenAI / Claude / GLM / any compatible endpoint"
  },
  "nav": {
    "home": "Home",
    "quickStart": "Quick Start",
    "faq": "FAQ",
    "changelog": "Changelog"
  },
  "hero": {
    "title": "GLM Excel Custom",
    "slogan": "Let Excel connect to any AI — OpenAI / Claude / GLM / any compatible endpoint",
    "download": "Download Installer",
    "source": "View Source"
  },
  "features": {
    "heading": "Features",
    "multiModel": {
      "title": "Multi-Model Support",
      "description": "Seamlessly switch between OpenAI, Anthropic Claude, GLM (ZhipuAI), and any OpenAI-compatible endpoint."
    },
    "local": {
      "title": "Local-First",
      "description": "Runs entirely on your machine via a local HTTPS server. Your data never leaves your computer."
    },
    "install": {
      "title": "One-Click Install",
      "description": "No admin rights required. Auto certificate generation and port allocation. Just run the installer."
    },
    "proxy": {
      "title": "Built-in CORS Proxy",
      "description": "Integrated reverse proxy handles cross-origin restrictions automatically. No extra configuration needed."
    }
  },
  "about": {
    "heading": "About",
    "description": "GLM Excel Custom is an open-source local patch of the official \"GLM in Excel\" add-in. It unlocks multi-provider AI support while keeping your data private and under your control.",
    "license": "Released under the MIT License."
  },
  "footer": {
    "copyright": "© 2025 GLM Excel Custom. All rights reserved.",
    "license": "MIT License"
  }
}
```

Create `messages/zh.json`:

```json
{
  "metadata": {
    "title": "GLM Excel Custom",
    "description": "让 Excel 连接任意 AI — OpenAI / Claude / GLM / 任何兼容端点"
  },
  "nav": {
    "home": "首页",
    "quickStart": "快速开始",
    "faq": "常见问题",
    "changelog": "更新日志"
  },
  "hero": {
    "title": "GLM Excel Custom",
    "slogan": "让 Excel 连接任意 AI — OpenAI / Claude / GLM / 任何兼容端点",
    "download": "下载安装包",
    "source": "查看源码"
  },
  "features": {
    "heading": "功能特点",
    "multiModel": {
      "title": "多模型支持",
      "description": "在 OpenAI、Anthropic Claude、GLM (智谱AI) 以及任何 OpenAI 兼容端点之间自由切换。"
    },
    "local": {
      "title": "本地运行",
      "description": "通过本地 HTTPS 服务器完全在你的机器上运行。数据永远不会离开你的电脑。"
    },
    "install": {
      "title": "一键安装",
      "description": "无需管理员权限。自动生成证书和分配端口。运行安装程序即可。"
    },
    "proxy": {
      "title": "内置 CORS 代理",
      "description": "集成的反向代理自动处理跨域限制，无需额外配置。"
    }
  },
  "about": {
    "heading": "关于项目",
    "description": "GLM Excel Custom 是官方「GLM in Excel」插件的开源本地补丁。它解锁了多供应商 AI 支持，同时保持你的数据私密且可控。",
    "license": "基于 MIT 许可证发布。"
  },
  "footer": {
    "copyright": "© 2025 GLM Excel Custom. 保留所有权利。",
    "license": "MIT 许可证"
  }
}
```

- [ ] **Step 6: Create root layout**

Modify `src/app/layout.tsx`:

```typescript
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "GLM Excel Custom",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return children;
}
```

- [ ] **Step 7: Create locale layout**

Create `src/app/[locale]/layout.tsx`:

```typescript
import { NextIntlClientProvider, hasLocale } from "next-intl";
import { getMessages } from "next-intl/server";
import { notFound } from "next/navigation";
import { routing } from "@/i18n/routing";
import "../globals.css";

type Props = {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
};

export default async function LocaleLayout({ children, params }: Props) {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) {
    notFound();
  }

  const messages = await getMessages();

  return (
    <html lang={locale}>
      <body className="bg-white text-gray-900 antialiased">
        <NextIntlClientProvider messages={messages}>
          {children}
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
```

- [ ] **Step 8: Create placeholder home page**

Create `src/app/[locale]/page.tsx`:

```typescript
import { useTranslations } from "next-intl";

export default function HomePage() {
  const t = useTranslations("hero");
  return (
    <main className="flex min-h-screen items-center justify-center">
      <h1 className="text-4xl font-bold">{t("title")}</h1>
    </main>
  );
}
```

- [ ] **Step 9: Verify i18n works**

```bash
npm run dev
```

- Visit `http://localhost:3000/en` → shows "GLM Excel Custom" in English
- Visit `http://localhost:3000/zh` → shows "GLM Excel Custom" in Chinese
- Visit `http://localhost:3000` → redirects to `/en`

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: configure next-intl with zh/en locale routing"
```

---

### Task 3: Shared Components (Navbar + Footer + LanguageSwitcher)

**Files:**
- Create: `src/components/Navbar.tsx`
- Create: `src/components/Footer.tsx`
- Create: `src/components/LanguageSwitcher.tsx`
- Modify: `src/app/[locale]/layout.tsx` — add Navbar + Footer

- [ ] **Step 1: Create LanguageSwitcher**

Create `src/components/LanguageSwitcher.tsx`:

```tsx
"use client";

import { useLocale } from "next-intl";
import { usePathname, useRouter } from "next/navigation";

export default function LanguageSwitcher() {
  const locale = useLocale();
  const pathname = usePathname();
  const router = useRouter();

  function switchLocale() {
    const newLocale = locale === "zh" ? "en" : "zh";
    const segments = pathname.split("/");
    segments[1] = newLocale;
    router.push(segments.join("/"));
  }

  return (
    <button
      onClick={switchLocale}
      className="rounded-md border border-gray-300 px-3 py-1 text-sm hover:bg-gray-100 transition-colors"
    >
      {locale === "zh" ? "EN" : "中文"}
    </button>
  );
}
```

- [ ] **Step 2: Create Navbar**

Create `src/components/Navbar.tsx`:

```tsx
"use client";

import Link from "next/link";
import { useLocale, useTranslations } from "next-intl";
import LanguageSwitcher from "./LanguageSwitcher";

export default function Navbar() {
  const t = useTranslations("nav");
  const locale = useLocale();

  const links = [
    { href: `/${locale}`, label: t("home") },
    { href: `/${locale}/quick-start`, label: t("quickStart") },
    { href: `/${locale}/faq`, label: t("faq") },
    { href: `/${locale}/changelog`, label: t("changelog") },
  ];

  return (
    <nav className="sticky top-0 z-50 border-b border-gray-200 bg-white/80 backdrop-blur-sm">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-6 py-4">
        <Link href={`/${locale}`} className="text-lg font-bold">
          GLM Excel
        </Link>
        <div className="flex items-center gap-6">
          {links.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              {link.label}
            </Link>
          ))}
          <LanguageSwitcher />
        </div>
      </div>
    </nav>
  );
}
```

- [ ] **Step 3: Create Footer**

Create `src/components/Footer.tsx`:

```tsx
import { useTranslations } from "next-intl";

export default function Footer() {
  const t = useTranslations("footer");

  return (
    <footer className="border-t border-gray-200 py-8">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-6 text-sm text-gray-500">
        <span>{t("copyright")}</span>
        <div className="flex items-center gap-4">
          <a
            href="https://github.com/Nicevva/glm-excel-custom"
            target="_blank"
            rel="noopener noreferrer"
            className="hover:text-gray-900 transition-colors"
          >
            GitHub
          </a>
          <span>{t("license")}</span>
        </div>
      </div>
    </footer>
  );
}
```

- [ ] **Step 4: Add Navbar + Footer to locale layout**

Modify `src/app/[locale]/layout.tsx` — wrap `{children}` with Navbar and Footer:

```typescript
import { NextIntlClientProvider, hasLocale } from "next-intl";
import { getMessages } from "next-intl/server";
import { notFound } from "next/navigation";
import { routing } from "@/i18n/routing";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import "../globals.css";

type Props = {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
};

export default async function LocaleLayout({ children, params }: Props) {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) {
    notFound();
  }

  const messages = await getMessages();

  return (
    <html lang={locale}>
      <body className="bg-white text-gray-900 antialiased">
        <NextIntlClientProvider messages={messages}>
          <Navbar />
          <main className="min-h-screen">{children}</main>
          <Footer />
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
```

- [ ] **Step 5: Verify navigation and language switching**

```bash
npm run dev
```

- Navbar shows on all pages
- Language toggle switches between `/zh` and `/en` and preserves route
- Footer shows copyright and GitHub link

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Navbar, Footer, and LanguageSwitcher components"
```

---

### Task 4: AnimateOnScroll Wrapper Component

**Files:**
- Create: `src/components/AnimateOnScroll.tsx`

- [ ] **Step 1: Create reusable scroll animation wrapper**

Create `src/components/AnimateOnScroll.tsx`:

```tsx
"use client";

import { useRef, useEffect } from "react";
import anime from "animejs";

type Props = {
  children: React.ReactNode;
  className?: string;
  delay?: number;
  duration?: number;
  translateY?: number;
};

export default function AnimateOnScroll({
  children,
  className = "",
  delay = 0,
  duration = 600,
  translateY = 30,
}: Props) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    el.style.opacity = "0";
    el.style.transform = `translateY(${translateY}px)`;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          anime({
            targets: el,
            opacity: [0, 1],
            translateY: [translateY, 0],
            duration,
            delay,
            easing: "easeOutCubic",
          });
          observer.unobserve(el);
        }
      },
      { threshold: 0.1 }
    );

    observer.observe(el);
    return () => observer.disconnect();
  }, [delay, duration, translateY]);

  return (
    <div ref={ref} className={className}>
      {children}
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add src/components/AnimateOnScroll.tsx
git commit -m "feat: add AnimateOnScroll wrapper using anime.js"
```

---

### Task 5: Home Page (Hero + Features + About)

**Files:**
- Create: `src/components/FeatureCard.tsx`
- Modify: `src/app/[locale]/page.tsx`

- [ ] **Step 1: Create FeatureCard component**

Create `src/components/FeatureCard.tsx`:

```tsx
type Props = {
  icon: string;
  title: string;
  description: string;
};

export default function FeatureCard({ icon, title, description }: Props) {
  return (
    <div className="rounded-xl border border-gray-200 p-6 hover:shadow-md transition-shadow">
      <div className="mb-4 text-3xl">{icon}</div>
      <h3 className="mb-2 text-lg font-semibold">{title}</h3>
      <p className="text-sm leading-relaxed text-gray-600">{description}</p>
    </div>
  );
}
```

- [ ] **Step 2: Build Home page**

Replace `src/app/[locale]/page.tsx`:

```tsx
import { useTranslations } from "next-intl";
import AnimateOnScroll from "@/components/AnimateOnScroll";
import FeatureCard from "@/components/FeatureCard";

export default function HomePage() {
  const t = useTranslations();

  const features = [
    { icon: "🔀", key: "multiModel" },
    { icon: "🔒", key: "local" },
    { icon: "📦", key: "install" },
    { icon: "🌐", key: "proxy" },
  ] as const;

  return (
    <>
      {/* Hero */}
      <section className="flex flex-col items-center justify-center px-6 py-24 text-center">
        <AnimateOnScroll>
          <h1 className="mb-4 text-5xl font-bold tracking-tight">
            {t("hero.title")}
          </h1>
        </AnimateOnScroll>
        <AnimateOnScroll delay={150}>
          <p className="mb-8 max-w-2xl text-lg text-gray-600">
            {t("hero.slogan")}
          </p>
        </AnimateOnScroll>
        <AnimateOnScroll delay={300}>
          <div className="flex gap-4">
            <a
              href="https://github.com/Nicevva/glm-excel-custom/releases"
              target="_blank"
              rel="noopener noreferrer"
              className="rounded-lg bg-gray-900 px-6 py-3 text-sm font-medium text-white hover:bg-gray-700 transition-colors"
            >
              {t("hero.download")}
            </a>
            <a
              href="https://github.com/Nicevva/glm-excel-custom"
              target="_blank"
              rel="noopener noreferrer"
              className="rounded-lg border border-gray-300 px-6 py-3 text-sm font-medium hover:bg-gray-50 transition-colors"
            >
              {t("hero.source")}
            </a>
          </div>
        </AnimateOnScroll>
      </section>

      {/* Features */}
      <section className="mx-auto max-w-5xl px-6 py-16">
        <AnimateOnScroll>
          <h2 className="mb-12 text-center text-3xl font-bold">
            {t("features.heading")}
          </h2>
        </AnimateOnScroll>
        <div className="grid gap-6 sm:grid-cols-2">
          {features.map((f, i) => (
            <AnimateOnScroll key={f.key} delay={i * 100}>
              <FeatureCard
                icon={f.icon}
                title={t(`features.${f.key}.title`)}
                description={t(`features.${f.key}.description`)}
              />
            </AnimateOnScroll>
          ))}
        </div>
      </section>

      {/* About */}
      <section className="mx-auto max-w-3xl px-6 py-16 text-center">
        <AnimateOnScroll>
          <h2 className="mb-6 text-3xl font-bold">{t("about.heading")}</h2>
        </AnimateOnScroll>
        <AnimateOnScroll delay={100}>
          <p className="mb-4 text-gray-600 leading-relaxed">
            {t("about.description")}
          </p>
        </AnimateOnScroll>
        <AnimateOnScroll delay={200}>
          <p className="text-sm text-gray-500">{t("about.license")}</p>
        </AnimateOnScroll>
      </section>
    </>
  );
}
```

- [ ] **Step 3: Verify home page**

```bash
npm run dev
```

- Visit `/en` — Hero with title, slogan, two buttons; four feature cards; about section
- Visit `/zh` — same layout with Chinese text
- Scroll animations trigger correctly

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: build Home page with Hero, Features, and About sections"
```

---

### Task 6: Quick Start Page

**Files:**
- Create: `src/app/[locale]/quick-start/page.tsx`
- Modify: `messages/en.json` — add `quickStart` section
- Modify: `messages/zh.json` — add `quickStart` section

- [ ] **Step 1: Add i18n messages for Quick Start**

Add to `messages/en.json`:

```json
"quickStart": {
  "heading": "Quick Start",
  "tabs": {
    "user": "Regular User",
    "developer": "Developer"
  },
  "user": {
    "step1": { "title": "Download the installer", "detail": "Go to the GitHub Releases page and download AI-Excel-Setup.exe." },
    "step2": { "title": "Run the installer", "detail": "Double-click the exe. No admin rights needed — it installs to your user folder." },
    "step3": { "title": "Open Excel", "detail": "Launch Excel → Home tab → click \"AI in Excel\"." },
    "step4": { "title": "Configure your API key", "detail": "Go to Settings, select your AI provider, and enter your API key." }
  },
  "developer": {
    "step1": { "title": "Generate a self-signed cert", "detail": "cd installer && powershell -ExecutionPolicy Bypass -File gen-cert.ps1" },
    "step2": { "title": "Register the sideload manifest", "detail": "npx office-addin-dev-settings register manifest/manifest.xml" },
    "step3": { "title": "Start the local server", "detail": "start-server.cmd" },
    "step4": { "title": "Open Excel and use the add-in", "detail": "Home tab → AI in Excel → Settings → enter your API key." }
  },
  "providers": {
    "heading": "Provider Configuration",
    "headerProvider": "Provider",
    "headerBaseUrl": "Base URL",
    "glm": { "name": "GLM (ZhipuAI)", "url": "Official endpoint (direct)" },
    "openai": { "name": "OpenAI", "url": "https://localhost:PORT/proxy/api.openai.com/v1" },
    "claude": { "name": "Anthropic Claude", "url": "https://localhost:PORT/proxy/api.anthropic.com" },
    "custom": { "name": "OpenAI-compatible", "url": "https://localhost:PORT/proxy/<your-domain>" }
  }
}
```

Add equivalent keys to `messages/zh.json`:

```json
"quickStart": {
  "heading": "快速开始",
  "tabs": {
    "user": "普通用户",
    "developer": "开发者"
  },
  "user": {
    "step1": { "title": "下载安装包", "detail": "前往 GitHub Releases 页面下载 AI-Excel-Setup.exe。" },
    "step2": { "title": "运行安装程序", "detail": "双击 exe 文件。无需管理员权限，自动安装到用户目录。" },
    "step3": { "title": "打开 Excel", "detail": "启动 Excel → 开始选项卡 → 点击「AI in Excel」。" },
    "step4": { "title": "配置 API 密钥", "detail": "进入设置，选择你的 AI 供应商，输入 API 密钥。" }
  },
  "developer": {
    "step1": { "title": "生成自签名证书", "detail": "cd installer && powershell -ExecutionPolicy Bypass -File gen-cert.ps1" },
    "step2": { "title": "注册 sideload 清单", "detail": "npx office-addin-dev-settings register manifest/manifest.xml" },
    "step3": { "title": "启动本地服务器", "detail": "start-server.cmd" },
    "step4": { "title": "打开 Excel 并使用插件", "detail": "开始选项卡 → AI in Excel → 设置 → 输入 API 密钥。" }
  },
  "providers": {
    "heading": "供应商配置",
    "headerProvider": "供应商",
    "headerBaseUrl": "Base URL",
    "glm": { "name": "GLM (智谱AI)", "url": "官方端点（直连）" },
    "openai": { "name": "OpenAI", "url": "https://localhost:PORT/proxy/api.openai.com/v1" },
    "claude": { "name": "Anthropic Claude", "url": "https://localhost:PORT/proxy/api.anthropic.com" },
    "custom": { "name": "OpenAI 兼容端点", "url": "https://localhost:PORT/proxy/<你的域名>" }
  }
}
```

- [ ] **Step 2: Create Quick Start page**

Create `src/app/[locale]/quick-start/page.tsx`:

```tsx
"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import AnimateOnScroll from "@/components/AnimateOnScroll";

const steps = ["step1", "step2", "step3", "step4"] as const;
const providers = ["glm", "openai", "claude", "custom"] as const;

export default function QuickStartPage() {
  const t = useTranslations("quickStart");
  const [tab, setTab] = useState<"user" | "developer">("user");

  return (
    <div className="mx-auto max-w-3xl px-6 py-16">
      <AnimateOnScroll>
        <h1 className="mb-8 text-center text-4xl font-bold">
          {t("heading")}
        </h1>
      </AnimateOnScroll>

      {/* Tab switcher */}
      <div className="mb-8 flex justify-center gap-2">
        {(["user", "developer"] as const).map((key) => (
          <button
            key={key}
            onClick={() => setTab(key)}
            className={`rounded-lg px-5 py-2 text-sm font-medium transition-colors ${
              tab === key
                ? "bg-gray-900 text-white"
                : "border border-gray-300 hover:bg-gray-50"
            }`}
          >
            {t(`tabs.${key}`)}
          </button>
        ))}
      </div>

      {/* Steps */}
      <div className="space-y-6">
        {steps.map((step, i) => (
          <AnimateOnScroll key={`${tab}-${step}`} delay={i * 80}>
            <div className="flex gap-4 rounded-lg border border-gray-200 p-5">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-gray-900 text-sm font-bold text-white">
                {i + 1}
              </div>
              <div>
                <h3 className="font-semibold">
                  {t(`${tab}.${step}.title`)}
                </h3>
                <p className="mt-1 text-sm text-gray-600">
                  {t(`${tab}.${step}.detail`)}
                </p>
              </div>
            </div>
          </AnimateOnScroll>
        ))}
      </div>

      {/* Provider table */}
      <AnimateOnScroll delay={400}>
        <h2 className="mb-4 mt-16 text-2xl font-bold">
          {t("providers.heading")}
        </h2>
        <div className="overflow-x-auto rounded-lg border border-gray-200">
          <table className="w-full text-left text-sm">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 font-semibold">
                  {t("providers.headerProvider")}
                </th>
                <th className="px-4 py-3 font-semibold">
                  {t("providers.headerBaseUrl")}
                </th>
              </tr>
            </thead>
            <tbody>
              {providers.map((p) => (
                <tr key={p} className="border-t border-gray-100">
                  <td className="px-4 py-3">{t(`providers.${p}.name`)}</td>
                  <td className="px-4 py-3 font-mono text-xs text-gray-600">
                    {t(`providers.${p}.url`)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </AnimateOnScroll>
    </div>
  );
}
```

- [ ] **Step 3: Verify Quick Start page**

```bash
npm run dev
```

- Visit `/en/quick-start` — tab switcher works, steps display, provider table shows
- Visit `/zh/quick-start` — Chinese translations display correctly

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add Quick Start page with user/developer tabs and provider table"
```

---

### Task 7: FAQ Page

**Files:**
- Create: `src/components/FaqAccordion.tsx`
- Create: `src/app/[locale]/faq/page.tsx`
- Modify: `messages/en.json` — add `faq` section
- Modify: `messages/zh.json` — add `faq` section

- [ ] **Step 1: Add i18n messages for FAQ**

Add to `messages/en.json`:

```json
"faq": {
  "heading": "FAQ",
  "items": [
    {
      "question": "Do I need admin rights to install?",
      "answer": "No. The installer places files in your user folder, the certificate goes into CurrentUser\\Root, and the sideload manifest is registered under HKCU. No UAC prompt needed."
    },
    {
      "question": "How does the CORS proxy work?",
      "answer": "The built-in reverse proxy at /proxy/<domain>/... forwards requests server-side, bypassing browser cross-origin restrictions. It adds the necessary CORS response headers automatically."
    },
    {
      "question": "Can I use a custom AI endpoint?",
      "answer": "Yes. Choose \"OpenAI-compatible\" as the provider and set the Base URL to https://localhost:PORT/proxy/<your-relay-domain>. Any endpoint that follows the OpenAI API format will work."
    },
    {
      "question": "What is the default certificate passphrase?",
      "answer": "The default passphrase for localhost.pfx is \"localdev\", configured in gen-cert.ps1 and server.cjs."
    },
    {
      "question": "How do I uninstall?",
      "answer": "Start Menu → AI in Excel → Uninstall AI in Excel. To remove the sideload manifest manually: npx office-addin-dev-settings unregister manifest/manifest.xml"
    }
  ]
}
```

Add equivalent to `messages/zh.json`:

```json
"faq": {
  "heading": "常见问题",
  "items": [
    {
      "question": "安装需要管理员权限吗？",
      "answer": "不需要。安装程序将文件放在用户目录中，证书安装到 CurrentUser\\Root，sideload 清单注册在 HKCU 下。无需 UAC 弹窗。"
    },
    {
      "question": "CORS 代理是如何工作的？",
      "answer": "内置反向代理 /proxy/<domain>/... 在服务器端转发请求，绕过浏览器跨域限制，并自动添加必要的 CORS 响应头。"
    },
    {
      "question": "可以使用自定义的 AI 端点吗？",
      "answer": "可以。选择「OpenAI 兼容」作为供应商，将 Base URL 设置为 https://localhost:PORT/proxy/<你的中继域名>。任何遵循 OpenAI API 格式的端点都可以使用。"
    },
    {
      "question": "默认的证书密码是什么？",
      "answer": "localhost.pfx 的默认密码是 \"localdev\"，在 gen-cert.ps1 和 server.cjs 中配置。"
    },
    {
      "question": "如何卸载？",
      "answer": "开始菜单 → AI in Excel → 卸载 AI in Excel。手动移除 sideload 清单：npx office-addin-dev-settings unregister manifest/manifest.xml"
    }
  ]
}
```

- [ ] **Step 2: Create FaqAccordion component**

Create `src/components/FaqAccordion.tsx`:

```tsx
"use client";

import { useState, useRef, useEffect } from "react";
import anime from "animejs";

type Props = {
  question: string;
  answer: string;
};

export default function FaqAccordion({ question, answer }: Props) {
  const [open, setOpen] = useState(false);
  const contentRef = useRef<HTMLDivElement>(null);
  const innerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const content = contentRef.current;
    if (!content || !innerRef.current) return;

    const height = open ? innerRef.current.scrollHeight : 0;

    anime({
      targets: content,
      height: [content.offsetHeight, height],
      opacity: open ? [0.5, 1] : [1, 0.5],
      duration: 300,
      easing: "easeOutCubic",
    });
  }, [open]);

  return (
    <div className="border-b border-gray-200">
      <button
        onClick={() => setOpen(!open)}
        className="flex w-full items-center justify-between py-5 text-left"
      >
        <span className="font-medium">{question}</span>
        <span className="ml-4 shrink-0 text-gray-400 transition-transform duration-200"
          style={{ transform: open ? "rotate(45deg)" : "rotate(0deg)" }}
        >
          +
        </span>
      </button>
      <div ref={contentRef} className="overflow-hidden" style={{ height: 0 }}>
        <div ref={innerRef} className="pb-5 text-sm leading-relaxed text-gray-600">
          {answer}
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Create FAQ page**

Create `src/app/[locale]/faq/page.tsx`:

```tsx
"use client";

import { useTranslations } from "next-intl";
import AnimateOnScroll from "@/components/AnimateOnScroll";
import FaqAccordion from "@/components/FaqAccordion";

export default function FaqPage() {
  const t = useTranslations("faq");

  const items = [0, 1, 2, 3, 4].map((i) => ({
    question: t(`items.${i}.question`),
    answer: t(`items.${i}.answer`),
  }));

  return (
    <div className="mx-auto max-w-3xl px-6 py-16">
      <AnimateOnScroll>
        <h1 className="mb-8 text-center text-4xl font-bold">
          {t("heading")}
        </h1>
      </AnimateOnScroll>
      <div>
        {items.map((item, i) => (
          <AnimateOnScroll key={i} delay={i * 80}>
            <FaqAccordion question={item.question} answer={item.answer} />
          </AnimateOnScroll>
        ))}
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Verify FAQ page**

```bash
npm run dev
```

- Visit `/en/faq` — 5 FAQ items, click to expand/collapse with smooth animation
- Visit `/zh/faq` — Chinese translations

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add FAQ page with animated accordion"
```

---

### Task 8: Changelog Page

**Files:**
- Create: `src/components/ChangelogTimeline.tsx`
- Create: `src/app/[locale]/changelog/page.tsx`
- Modify: `messages/en.json` — add `changelog` section
- Modify: `messages/zh.json` — add `changelog` section

- [ ] **Step 1: Add i18n messages for Changelog**

Add to `messages/en.json`:

```json
"changelog": {
  "heading": "Changelog",
  "entries": [
    {
      "version": "1.0.0",
      "date": "2025-06-01",
      "changes": [
        "Initial release with multi-provider support (OpenAI, Claude, GLM)",
        "Local HTTPS server with built-in CORS proxy",
        "One-click installer for end users (no admin required)",
        "Settings UI with provider selector, base URL, and model fields",
        "Custom branding support via patch.py"
      ]
    }
  ]
}
```

Add equivalent to `messages/zh.json`:

```json
"changelog": {
  "heading": "更新日志",
  "entries": [
    {
      "version": "1.0.0",
      "date": "2025-06-01",
      "changes": [
        "首次发布，支持多供应商（OpenAI、Claude、GLM）",
        "本地 HTTPS 服务器，内置 CORS 代理",
        "一键安装程序，无需管理员权限",
        "设置界面支持供应商选择、Base URL 和模型字段",
        "通过 patch.py 支持自定义品牌"
      ]
    }
  ]
}
```

- [ ] **Step 2: Create ChangelogTimeline component**

Create `src/components/ChangelogTimeline.tsx`:

```tsx
type Entry = {
  version: string;
  date: string;
  changes: string[];
};

type Props = {
  entry: Entry;
};

export default function ChangelogTimeline({ entry }: Props) {
  return (
    <div className="relative border-l-2 border-gray-200 pl-8 pb-10">
      <div className="absolute -left-[9px] top-0 h-4 w-4 rounded-full border-2 border-gray-300 bg-white" />
      <div className="flex items-baseline gap-3">
        <span className="rounded-md bg-gray-100 px-2 py-1 text-sm font-mono font-semibold">
          v{entry.version}
        </span>
        <span className="text-sm text-gray-500">{entry.date}</span>
      </div>
      <ul className="mt-3 space-y-2">
        {entry.changes.map((change, i) => (
          <li key={i} className="text-sm text-gray-600 leading-relaxed">
            • {change}
          </li>
        ))}
      </ul>
    </div>
  );
}
```

- [ ] **Step 3: Create Changelog page**

Create `src/app/[locale]/changelog/page.tsx`:

```tsx
"use client";

import { useTranslations } from "next-intl";
import AnimateOnScroll from "@/components/AnimateOnScroll";
import ChangelogTimeline from "@/components/ChangelogTimeline";

export default function ChangelogPage() {
  const t = useTranslations("changelog");

  const entries = [0].map((i) => ({
    version: t(`entries.${i}.version`),
    date: t(`entries.${i}.date`),
    changes: [0, 1, 2, 3, 4].map((j) => t(`entries.${i}.changes.${j}`)),
  }));

  return (
    <div className="mx-auto max-w-3xl px-6 py-16">
      <AnimateOnScroll>
        <h1 className="mb-12 text-center text-4xl font-bold">
          {t("heading")}
        </h1>
      </AnimateOnScroll>
      <div>
        {entries.map((entry, i) => (
          <AnimateOnScroll key={i} delay={i * 100}>
            <ChangelogTimeline entry={entry} />
          </AnimateOnScroll>
        ))}
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Verify Changelog page**

```bash
npm run dev
```

- Visit `/en/changelog` — timeline with v1.0.0 entry
- Visit `/zh/changelog` — Chinese translations

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Changelog page with timeline component"
```

---

### Task 9: SEO Metadata & Final Polish

**Files:**
- Modify: `src/app/[locale]/layout.tsx` — add dynamic metadata
- Modify: `src/app/[locale]/page.tsx` — add page metadata
- Modify: `src/app/[locale]/quick-start/page.tsx` — add page metadata
- Modify: `src/app/[locale]/faq/page.tsx` — add page metadata
- Modify: `src/app/[locale]/changelog/page.tsx` — add page metadata

- [ ] **Step 1: Add generateMetadata to locale layout**

Add to `src/app/[locale]/layout.tsx`:

```typescript
import { getTranslations } from "next-intl/server";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "metadata" });

  return {
    title: {
      default: t("title"),
      template: `%s | ${t("title")}`,
    },
    description: t("description"),
  };
}
```

- [ ] **Step 2: Add metadata to sub-pages**

For Quick Start, FAQ, and Changelog pages, add `metadata` exports. Add the following translation keys to both `messages/en.json` and `messages/zh.json`, then use `generateMetadata` in each page file:

Add to `messages/en.json`:

```json
"quickStartMeta": { "title": "Quick Start" },
"faqMeta": { "title": "FAQ" },
"changelogMeta": { "title": "Changelog" }
```

Add to `messages/zh.json`:

```json
"quickStartMeta": { "title": "快速开始" },
"faqMeta": { "title": "常见问题" },
"changelogMeta": { "title": "更新日志" }
```

For pages that are `"use client"`, split them: create a `generateMetadata` in a separate server-side wrapper or make the metadata static. The simplest approach: convert the pages that need metadata to server components where possible, or use `generateMetadata` alongside client components (Next.js supports `generateMetadata` exports alongside `"use client"` pages — the export is extracted at build time).

Create `src/app/[locale]/quick-start/layout.tsx`:

```typescript
import { getTranslations } from "next-intl/server";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "quickStartMeta" });
  return { title: t("title") };
}

export default function Layout({ children }: { children: React.ReactNode }) {
  return children;
}
```

Repeat the same pattern for `src/app/[locale]/faq/layout.tsx` (namespace: `"faqMeta"`) and `src/app/[locale]/changelog/layout.tsx` (namespace: `"changelogMeta"`).

- [ ] **Step 3: Verify metadata**

```bash
npm run dev
```

- Check each page's `<title>` tag in the browser tab
- `/en` → "GLM Excel Custom"
- `/en/faq` → "FAQ | GLM Excel Custom"

- [ ] **Step 4: Build check**

```bash
npm run build
```

Ensure zero errors.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add SEO metadata for all pages"
```

---

### Task 10: Deploy to Vercel

**Files:**
- No code changes

- [ ] **Step 1: Push to GitHub**

```bash
git push -u origin main
```

- [ ] **Step 2: Connect repo to Vercel**

Use Vercel dashboard or CLI:

```bash
npx vercel link
```

Or via Vercel MCP tools: import the `Nicevva/glm-excel-web` GitHub repo.

- [ ] **Step 3: Deploy**

```bash
npx vercel --prod
```

Or push to `main` — Vercel auto-deploys.

- [ ] **Step 4: Verify live site**

- Visit the Vercel-assigned URL
- Check all pages: Home, Quick Start, FAQ, Changelog
- Test language switching
- Test animations on scroll

- [ ] **Step 5: Commit any Vercel config files**

```bash
git add -A
git commit -m "chore: add Vercel project config"
git push
```
