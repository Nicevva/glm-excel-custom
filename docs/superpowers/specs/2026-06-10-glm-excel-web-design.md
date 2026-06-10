# GLM Excel Web — Product Landing Site Design

## Overview

A standalone multi-page website to introduce the `glm-excel-public` project.
Built with Next.js 15 (App Router), deployed on Vercel, bilingual (zh/en).

**Repository:** New GitHub repo `glm-excel-web` (separate from `glm-excel-public`)

**Target audience:** Both non-technical Excel users (simple download path) and
developers (source code, CLI instructions, technical docs).

**Visual style:** Clean white background, hand-drawn / sketch aesthetic, minimal
color, professional typography. Subtle animations via anime.js (~17KB).

---

## Tech Stack

| Layer        | Choice                  |
|------------- |------------------------ |
| Framework    | Next.js 15 App Router   |
| Styling      | Tailwind CSS            |
| i18n         | next-intl               |
| Animation    | anime.js                |
| Deployment   | Vercel (GitHub push)    |
| Language     | TypeScript              |

---

## Route Structure

```
/                        → redirect to /zh or /en (browser locale)
/[locale]/               → Home (Hero + Features + About)
/[locale]/quick-start    → Quick Start guide
/[locale]/faq            → FAQ
/[locale]/changelog      → Changelog
```

## Directory Layout

```
app/
  [locale]/
    page.tsx              ← Home
    quick-start/page.tsx
    faq/page.tsx
    changelog/page.tsx
    layout.tsx            ← Shared nav + footer
components/
  Navbar.tsx
  Footer.tsx
  LanguageSwitcher.tsx
  FeatureCard.tsx
  FaqAccordion.tsx
  ChangelogTimeline.tsx
messages/
  zh.json
  en.json
```

---

## Page Designs

### Home (`/[locale]/`)

Three sections, top to bottom:

**1. Hero**
- Product name: "GLM Excel Custom"
- Slogan: "Let Excel connect to any AI — OpenAI / Claude / GLM / any compatible endpoint"
- Two CTA buttons: "Download Installer" (→ GitHub Releases) + "View Source" (→ GitHub repo)
- Clean white background, optional hand-drawn style icon/illustration
- anime.js: title + slogan fade-in with slight upward translate

**2. Features (3–4 cards)**
- Multi-model support: OpenAI, Claude, GLM, any OpenAI-compatible endpoint
- Local-first: HTTPS local server, data never leaves your machine
- One-click install: No admin rights, auto cert + port allocation
- Built-in CORS proxy: Reverse proxy solves cross-origin restrictions
- anime.js: staggered fade-in on scroll into viewport

**3. About + Contact**
- Short project description
- GitHub repo link
- MIT License note

### Quick Start (`/[locale]/quick-start`)

- Tab switcher for two paths:
  - **Regular users:** Download installer → Run → Open Excel → Configure API Key (with screenshots)
  - **Developers:** Clone repo → Generate cert → Register manifest → Start server (code blocks)
- Provider configuration table at bottom (GLM / OpenAI / Claude / custom endpoint URLs)

### FAQ (`/[locale]/faq`)

- Accordion (expand/collapse) style
- Initial content extracted from README (cert, port, proxy topics)
- anime.js: smooth expand/collapse animation

### Changelog (`/[locale]/changelog`)

- Timeline style, each entry: version number, date, change list
- Reverse chronological (newest first)
- Initial content based on the single existing commit; append over time

---

## Shared Components

**Navbar:** Logo + page links (Home, Quick Start, FAQ, Changelog) + language toggle (zh/en)

**Footer:** GitHub link + MIT License + Copyright

**LanguageSwitcher:** Simple zh/en toggle button, preserves current route

---

## Animation Strategy (anime.js)

- Hero: title + slogan fade-in + translateY on page load
- Feature cards: staggered fade-in triggered by Intersection Observer on scroll
- FAQ accordion: smooth height + opacity transitions on expand/collapse
- Keep animations subtle and fast (200–400ms) to match the clean, restrained style

---

## i18n Strategy

- `next-intl` with `[locale]` route prefix
- Root `/` redirects based on `Accept-Language` header (default: `en`)
- All user-facing text in `messages/zh.json` and `messages/en.json`
- Metadata (title, description) localized per page for SEO

---

## Deployment

- New GitHub repo → connect to Vercel
- Auto-deploy on push to `main`
- No server-side data; fully static export possible (`output: 'export'` if needed)
