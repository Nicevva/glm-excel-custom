import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const bundleUrl = new URL("../public/assets/taskpane-DG2CZyG2.js", import.meta.url);
const source = readFileSync(bundleUrl, "utf8");
const helperImport = source.match(/import\s*\{[^}]*\}\s*from\s*["']\.\/api-url\.js["']/);
// A data URL runs the shipped ES module without inheriting an unrelated parent
// package.json's CommonJS mode (and without adding package/dependency files).
const helpers = helperImport ? await import("data:text/javascript;base64," + Buffer.from(
  readFileSync(new URL("./api-url.js", bundleUrl), "utf8"),
).toString("base64")) : {};

function section(start, end) {
  const first = source.indexOf(start);
  const last = source.indexOf(end, first + start.length);
  assert.ok(first >= 0 && last > first, `Bundle extraction landmarks: ${start} / ${end}`);
  return source.slice(first, last);
}

// Run the real compiled components without a browser. Only React's rendering
// primitives and the Office/network-owning Agent are replaced, not URL logic.
export function createHarness(savedConfig, origin = "https://localhost:3057", withWorkbook = false) {
  const store = new Map();
  if (savedConfig !== undefined) store.set("excelglm-provider-config", JSON.stringify(savedConfig));
  const localStorage = {
    getItem: key => store.get(key) ?? null,
    setItem: (key, value) => store.set(key, String(value)),
    removeItem: key => store.delete(key),
  };
  const agents = [];
  class OfflineAgent {
    constructor({ initialState }) {
      this.state = initialState;
      this.aborted = false;
      this.prompts = [];
      agents.push(this);
    }
    abort() { this.aborted = true; }
    subscribe() {}
    reset() { this.state.messages = []; }
    async prompt(text) { this.prompts.push(text); }
  }
  const context = vm.createContext({
    ...helpers, localStorage, location: { origin }, URL,
    console: { log() {}, error() {} },
    CE: "https://open.bigmodel.cn/api/paas/v4/",
    iO: "excelglm-provider-config", j0: { contextWindow: 0 },
    qY: { Provider: "ChatProvider" }, GLe: "system", BLe: [],
    b3e: OfflineAgent, qLe: value => value, T8: () => "message-id",
    P3e: async () => ({}),
    B3e: async () => "workbook-id",
    KF: async () => ({ id: "session-a", name: "Session A", messages: [] }),
    aA: async () => [], jF: async () => {}, qF: async () => null,
    GY: () => undefined, VY: [],
    // Unknown model IDs must keep exercising the production P1 fallback.
    D7: (provider, model) => model === "known-responses-model" ? {
      id: model, provider, api: "openai-responses", baseUrl: "https://catalog.example/v1",
      contextWindow: 128000, maxTokens: 8192,
    } : undefined,
    xc: () => ({ t: key => key }),
    ie: { jsx: (type, props) => ({ type, props }), jsxs: (type, props) => ({ type, props }), Fragment: "Fragment" },
    Il: { Item: "Form.Item" }, Tp: "Select", Vp: Object.assign(() => {}, { Password: "Password" }),
    zT: "Option", KY: "ConfiguredIcon", JY: "ShowKey", XY: "HideKey",
  });
  vm.runInContext(section("function _A(){", "function VLe("), context);
  vm.runInContext(section("function oot(){", "const S7="), context);
  vm.runInContext(section("function jLe({", "function Cc()"), context);

  function renderer(component, runEffects) {
    const slots = [];
    let cursor = 0;
    let dirty = false;
    let effects = [];
    let output;
    const memo = (factory, deps) => {
      const index = cursor++;
      const old = slots[index];
      if (!old || deps.some((value, i) => !Object.is(value, old.deps[i]))) {
        slots[index] = { deps, value: factory() };
      }
      return slots[index].value;
    };
    const hooks = {
      useState(initial) {
        const index = cursor++;
        if (!(index in slots)) slots[index] = typeof initial === "function" ? initial() : initial;
        return [slots[index], next => {
          const value = typeof next === "function" ? next(slots[index]) : next;
          if (!Object.is(slots[index], value)) { slots[index] = value; dirty = true; }
        }];
      },
      useRef: initial => memo(() => ({ current: initial }), []),
      useCallback: (callback, deps) => memo(() => callback, deps),
      useMemo: memo,
      useEffect(callback, deps) { memo(() => { if (runEffects) effects.push(callback); }, deps); },
    };
    return {
      render() {
        let iterations = 0;
        const previousHooks = context.k;
        do {
          assert.ok(++iterations < 20, "Component should settle after effects");
          dirty = false;
          cursor = 0;
          effects = [];
          context.k = hooks;
          output = component();
          for (const effect of effects) effect();
        } while (dirty);
        context.k = previousHooks;
        return output;
      },
    };
  }

  const chat = renderer(() => context.jLe({ children: null }), withWorkbook);
  let chatValue = chat.render().props.value;
  const syncChat = () => { chatValue = chat.render().props.value; return chatValue; };
  context.Cc = () => syncChat();
  const settings = renderer(() => context.oot(), true);
  return {
    context, agents,
    load: () => context._A(),
    save: (...args) => context.zLe(...args),
    stored: () => { const value = localStorage.getItem("excelglm-provider-config"); return value === null ? null : JSON.parse(value); },
    settings: () => settings.render(),
    chat: syncChat,
  };
}

export function nodes(tree) {
  if (tree == null || typeof tree !== "object") return [];
  if (Array.isArray(tree)) return tree.flatMap(nodes);
  return [tree, ...nodes(tree.props?.children)];
}

export function baseInput(tree) {
  return nodes(tree).find(node => node.type === "Form.Item" && /Base URL/.test(text(node.props.label)))?.props.children;
}

export function text(tree) {
  if (tree == null || typeof tree === "boolean") return "";
  if (typeof tree !== "object") return String(tree);
  if (Array.isArray(tree)) return tree.map(text).join(" ");
  return text(tree.props?.children);
}

// Execute each SDK's own URL join method. The only branch supplied here is the
// SDK's private "custom base URL" check; no URL concatenation is reimplemented.
export function sdkUrl(baseURL, path, anthropic = false) {
  const start = anthropic ? "buildURL(t,n,r){const o=!tt(this,dI" : "buildURL(t,n,r){const o=!Ze(this,CI";
  const end = anthropic ? "_calculateNonstreamingTimeout(" : "async prepareOptions(";
  const method = section(start, end);
  const context = vm.createContext({
    URL, tt: () => () => true, Ze: () => () => true,
    dI: {}, TH: {}, CI: {}, dV: {},
    Nre: value => /^https?:\/\//.test(value), Woe: value => /^https?:\/\//.test(value),
    Mre: value => Object.keys(value).length === 0, Hoe: value => Object.keys(value).length === 0,
  });
  const client = vm.runInContext(`({${method}})`, context);
  client.baseURL = baseURL;
  client.defaultQuery = () => ({});
  return client.buildURL(path);
}
