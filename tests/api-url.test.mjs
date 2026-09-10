import test from "node:test";
import assert from "node:assert/strict";
import { createHarness, baseInput, nodes, text, sdkUrl } from "./bundle-harness.mjs";

const config = (url, provider = "openai-compatible", model = "custom-model") => ({
  provider, model, apiKey: "test-key", customPrefixUrl: url, thinking: "none", followMode: true,
});

// Break caught: retaining a stale local proxy origin in the settings or storage.
for (const [saved, real] of [
  ["https://localhost:3000/proxy/api.openai.com/v1", "https://api.openai.com/v1"],
  ["https://127.0.0.1:3001/proxy/http:/10.22.68.139:8080/v1", "http://10.22.68.139:8080/v1"],
  ["http://[::1]:3099/proxy/http://10.22.68.139:8080/team/v1/", "http://10.22.68.139:8080/team/v1/"],
  ["/proxy/openrouter.ai/api/v1", "https://openrouter.ai/api/v1"],
  ["/proxy/http:/10.22.68.139:8080", "http://10.22.68.139:8080"],
  ["https://relay.example/proxy/team/v1", "https://relay.example/proxy/team/v1"],
]) {
  test(`settings displays and saves the real target of ${saved}`, () => {
    const h = createHarness(config(saved));
    assert.equal(baseInput(h.settings()).props.value, real);
    assert.equal(h.stored().customPrefixUrl, real);
    assert.equal(h.load().customPrefixUrl, real);
  });
}

test("first launch displays the real SiliconFlow URL", () => {
  const h = createHarness();
  assert.equal(baseInput(h.settings()).props.value, "https://api.siliconflow.cn/v1/");
});

// Break caught: provider switching leaks proxy URLs, or custom inherits GLM.
for (const [provider, expected] of [
  ["openai", "https://api.openai.com/v1"],
  ["anthropic", "https://api.anthropic.com"],
  ["GLM", "https://open.bigmodel.cn/api/paas/v4/"],
  ["openai-compatible", ""],
]) {
  test(`switching to ${provider} fills a real URL or an empty custom field`, () => {
    const h = createHarness(config("https://old.example/v1"));
    nodes(h.settings()).find(node => node.type === "Select").props.onChange(provider);
    const tree = h.settings();
    assert.equal(baseInput(tree).props.value, expected);
    if (provider === "anthropic") {
      assert.match(baseInput(tree).props.placeholder, /https:\/\/api.anthropic.com/);
      assert.doesNotMatch(baseInput(tree).props.placeholder, /\/v1/);
    }
    if (!expected) {
      assert.match(baseInput(tree).props.placeholder, /https?:\/\//);
      assert.match(text(tree), /settings.notConfigured/);
    }
  });
}

// Break caught: request boundary passes through real/old URLs or corrupts paths.
for (const [provider, url, path, finalUrl, model] of [
  ["openai-compatible", "http://10.22.68.139:8080", "/chat/completions", "https://localhost:3057/proxy/http:/10.22.68.139:8080/chat/completions"],
  ["openai-compatible", "http://10.22.68.139:8080/team/v1/", "/chat/completions", "https://localhost:3057/proxy/http:/10.22.68.139:8080/team/v1/chat/completions"],
  ["openai", "https://api.openai.com/v1", "/chat/completions", "https://localhost:3057/proxy/api.openai.com/v1/chat/completions"],
  ["openai", "https://relay.example/api/v1/", "/responses", "https://localhost:3057/proxy/relay.example/api/v1/responses", "known-responses-model"],
  ["anthropic", "https://api.anthropic.com/v1/", "/v1/messages", "https://localhost:3057/proxy/api.anthropic.com/v1/messages"],
  ["anthropic", "http://relay.example:8080/claude/v1", "/v1/messages", "https://localhost:3057/proxy/http:/relay.example:8080/claude/v1/messages"],
  ["anthropic", "https://relay.example/api/v1/v1", "/v1/messages", "https://localhost:3057/proxy/relay.example/api/v1/v1/messages"],
  ["anthropic", "https://relay.example/version-v1", "/v1/messages", "https://localhost:3057/proxy/relay.example/version-v1/v1/messages"],
  ["openai-compatible", "https://relay.example/proxy/team/v1", "/chat/completions", "https://localhost:3057/proxy/relay.example/proxy/team/v1/chat/completions"],
  ["openai-compatible", "https://localhost:3000/proxy/http:/10.22.68.139:8080/v1", "/chat/completions", "https://localhost:3057/proxy/http:/10.22.68.139:8080/v1/chat/completions"],
  ["openai-compatible", "/proxy/relay.example/v1", "/chat/completions", "https://localhost:3057/proxy/relay.example/v1/chat/completions"],
  ["openai-compatible", "http://[::1]:43125/v1", "/chat/completions", "https://localhost:3057/proxy/http:/[::1]:43125/v1/chat/completions"],
  ["GLM", "https://open.bigmodel.cn/api/paas/v4/", "/chat/completions", "https://open.bigmodel.cn/api/paas/v4/chat/completions"],
  ["GLM", "http://10.22.68.139:8080/custom/v1", "/chat/completions", "https://localhost:3057/proxy/http:/10.22.68.139:8080/custom/v1/chat/completions"],
]) {
  test(`request boundary + SDK path: ${provider} ${url} ${path}`, () => {
    const h = createHarness(config(url, provider, model));
    // No settings render: migration must work for existing chat configurations.
    h.chat().setProviderConfig(h.load());
    assert.equal(h.agents.length, 1);
    const actualModel = h.agents[0].state.model;
    assert.equal(sdkUrl(actualModel.baseUrl, path, provider === "anthropic"), finalUrl);
    if (model) assert.equal(actualModel.api, "openai-responses");
    else assert.equal(actualModel.api, provider === "anthropic" ? "anthropic-messages" : "openai-completions");
  });
}

// Break caught: input normalization moves the caret on every keystroke, or
// automatic saving retains whitespace instead of normalizing at the boundary.
test("typing preserves draft whitespace; saving and blur normalize it", () => {
  const h = createHarness(config("https://relay.example/v1"));
  baseInput(h.settings()).props.onChange({ target: { value: "  http://10.22.68.139:8080/v1  " } });
  const tree = h.settings();
  assert.equal(baseInput(tree).props.value, "  http://10.22.68.139:8080/v1  ");
  assert.equal(h.stored().customPrefixUrl, "http://10.22.68.139:8080/v1");
  assert.equal(typeof baseInput(tree).props.onBlur, "function");
  baseInput(tree).props.onBlur();
  assert.equal(baseInput(h.settings()).props.value, "http://10.22.68.139:8080/v1");
});

const invalidUrls = [
  "", "   ", "ftp://relay.example/v1", "javascript:alert(1)", "relay.example/v1", "//relay.example/v1",
  "https://user:pass@relay.example/v1", "https://relay.example/v1?key=secret", "https://relay.example/v1#anchor",
  "https://relay.example/v1?", "https://relay.example/v1#", "http:///relay.example", "https://relay.example:99999/v1",
  "http://relay example/v1", "https://relay.example/with space", "https://relay.example/\npath", "https://relay.example\\path", "/proxy/",
  "https://localhost:3000/proxy/", "https://localhost:3000/proxy/user:pass@relay.example/v1",
];
for (const url of invalidUrls) {
  test(`invalid input disables configured status and old requests: ${JSON.stringify(url)}`, async () => {
    const h = createHarness(config("https://previous.example/v1"));
    const tree = h.settings();
    const previous = h.agents[0];
    baseInput(tree).props.onChange({ target: { value: url } });
    const invalidTree = h.settings();
    assert.doesNotMatch(text(invalidTree), /settings.configured/);
    assert.match(text(invalidTree), /settings.notConfigured/);
    const field = nodes(invalidTree).find(node => node.type === "Form.Item" && node.props.children === baseInput(invalidTree));
    assert.equal(field.props.validateStatus, "error");
    assert.match(field.props.help, /[一-鿿]/);
    assert.equal(h.chat().state.providerConfig, null);
    assert.equal(h.stored()?.customPrefixUrl, "", "old URL must not return on reopening settings");
    assert.equal(h.stored().apiKey, "test-key", "invalid URL must not delete the user's API key");
    assert.equal(h.stored().model, "custom-model");
    const reopened = createHarness(h.stored());
    assert.equal(baseInput(reopened.settings()).props.value, "");
    assert.equal(reopened.chat().state.providerConfig, null);
    assert.ok(previous.aborted);
    await h.chat().sendMessage("must not use previous URL");
    assert.equal(previous.prompts.length, 0);
  });
}

// Break caught: disabling an invalid endpoint destroys the only model-context
// copy, even though the UI still displays the conversation.
const previousContext = () => [
  { role: "user", content: "The budget is 1200.", timestamp: 100 },
  { role: "assistant", content: [{ type: "text", text: "I will keep that budget." }],
    api: "openai-completions", provider: "openai-compatible", model: "custom-model",
    usage: { input: 12, output: 8, cacheRead: 0, cacheWrite: 0, totalTokens: 20,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
    stopReason: "stop", timestamp: 101 },
];

test("restoring a valid URL preserves the previous model conversation context", async () => {
  const h = createHarness(config("https://previous.example/v1"));
  h.settings();
  const oldAgent = h.agents[0];
  oldAgent.state.messages = previousContext();
  baseInput(h.settings()).props.onChange({ target: { value: "" } });
  h.settings();
  assert.equal(h.chat().state.providerConfig, null);
  assert.ok(oldAgent.aborted);
  baseInput(h.settings()).props.onChange({ target: { value: "http://new.example:8080/v1" } });
  h.settings();
  await h.chat().sendMessage("What budget did I give you?");
  const nextAgent = h.agents.at(-1);
  assert.notEqual(nextAgent, oldAgent);
  assert.deepEqual(JSON.parse(JSON.stringify(nextAgent.state.messages)), previousContext());
  assert.equal(nextAgent.state.model.baseUrl, "https://localhost:3057/proxy/http:/new.example:8080/v1");
  assert.equal(oldAgent.prompts.length, 0);
  assert.equal(nextAgent.prompts.length, 1);
});

test("clearing chat while the URL is invalid must not resurrect saved model context", () => {
  const h = createHarness(config("https://previous.example/v1"));
  h.settings();
  h.agents[0].state.messages = previousContext();
  baseInput(h.settings()).props.onChange({ target: { value: "" } });
  h.settings();
  h.chat().clearMessages();
  baseInput(h.settings()).props.onChange({ target: { value: "https://next.example/v1" } });
  h.settings();
  assert.deepEqual(Array.from(h.agents.at(-1).state.messages), []);
});

test("switching sessions while the URL is invalid must not resurrect old model context", async () => {
  const h = createHarness(config("https://previous.example/v1"));
  h.settings();
  h.agents[0].state.messages = previousContext();
  h.context.qF = async id => ({ id, name: "Different conversation", messages: [] });
  baseInput(h.settings()).props.onChange({ target: { value: "" } });
  h.settings();
  await h.chat().switchSession("different-session");
  baseInput(h.settings()).props.onChange({ target: { value: "https://next.example/v1" } });
  h.settings();
  assert.equal(h.chat().state.currentSession.id, "different-session");
  assert.deepEqual(Array.from(h.agents.at(-1).state.messages), []);
});

// Break caught: a URL restored during an asynchronous session switch consumes
// the old session snapshot before c.current changes to the destination session.
test("restoring URL while session lookup is pending must not carry the old context", async () => {
  const h = createHarness(config("https://previous.example/v1"));
  h.settings();
  const oldAgent = h.agents[0];
  oldAgent.state.messages = previousContext();
  baseInput(h.settings()).props.onChange({ target: { value: "" } });
  h.settings();
  let finishSwitch;
  h.context.qF = () => new Promise(resolve => { finishSwitch = resolve; });
  const pendingSwitch = h.chat().switchSession("different-session");
  baseInput(h.settings()).props.onChange({ target: { value: "https://next.example/v1" } });
  h.settings();
  finishSwitch({ id: "different-session", name: "Different conversation", messages: [] });
  await pendingSwitch;
  await h.chat().sendMessage("Start the different conversation");
  assert.equal(h.chat().state.currentSession.id, "different-session");
  assert.deepEqual(Array.from(h.agents.at(-1).state.messages), []);
  assert.equal(oldAgent.prompts.length, 0);
  assert.equal(h.agents.at(-1).prompts.length, 1);
});

for (const operation of ["newSession", "deleteCurrentSession"]) {
  test(`restoring URL while ${operation} is pending must not carry the old context`, async () => {
    const h = createHarness(config("https://previous.example/v1"), "https://localhost:3057", true);
    // Let the actual ChatProvider's workbook/session initialization settle.
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(h.chat().state.currentSession.id, "session-a");
    h.settings();
    h.agents.at(-1).state.messages = previousContext();
    baseInput(h.settings()).props.onChange({ target: { value: "" } });
    h.settings();
    let finishOperation;
    if (operation === "newSession") {
      h.context.vK = () => new Promise(resolve => { finishOperation = resolve; });
    } else {
      h.context.z3e = () => new Promise(resolve => { finishOperation = resolve; });
      h.context.KF = async () => ({ id: "session-b", name: "Session B", messages: [] });
    }
    const pendingOperation = h.chat()[operation]();
    baseInput(h.settings()).props.onChange({ target: { value: "https://next.example/v1" } });
    h.settings();
    finishOperation({ id: "session-b", name: "Session B", messages: [] });
    await pendingOperation;
    await h.chat().sendMessage("Start a different session");
    assert.equal(h.chat().state.currentSession.id, "session-b");
    assert.deepEqual(Array.from(h.agents.at(-1).state.messages), []);
    assert.equal(h.agents.at(-1).prompts.length, 1);
  });
}

// Break caught: the settings effect derives followMode from a nullable active
// config and silently overwrites the user's false preference with true.
test("invalid then valid URL preserves follow mode and other saved preferences", () => {
  const h = createHarness({ ...config("https://previous.example/v1"), followMode: false, thinking: "high" });
  baseInput(h.settings()).props.onChange({ target: { value: "" } });
  h.settings();
  assert.equal(h.stored().followMode, false);
  baseInput(h.settings()).props.onChange({ target: { value: "https://next.example/v1" } });
  h.settings();
  assert.deepEqual(h.stored(), { ...config("https://next.example/v1"), followMode: false, thinking: "high" });
  assert.equal(h.chat().state.providerConfig.followMode, false);
  assert.equal(h.agents.at(-1).state.thinkingLevel, "high");
});

test("follow mode changed after settings mount survives invalid then valid URL", () => {
  const h = createHarness(config("https://previous.example/v1"));
  h.settings();
  h.chat().toggleFollowMode();
  h.settings();
  assert.equal(h.chat().state.providerConfig.followMode, false);
  baseInput(h.settings()).props.onChange({ target: { value: "" } });
  h.settings();
  baseInput(h.settings()).props.onChange({ target: { value: "https://next.example/v1" } });
  h.settings();
  assert.equal(h.stored().followMode, false);
  assert.equal(h.chat().state.providerConfig.followMode, false);
});

// Break caught: an already-started send resumes after workbook metadata and
// prompts its captured old Agent even though settings have since become invalid.
test("invalidating settings during workbook lookup cancels the pending old request", async () => {
  const h = createHarness(config("https://previous.example/v1"));
  h.settings();
  let finishLookup;
  h.context.P3e = () => new Promise(resolve => { finishLookup = resolve; });
  const pending = h.chat().sendMessage("waiting for metadata");
  baseInput(h.settings()).props.onChange({ target: { value: "ftp://invalid.example" } });
  h.settings();
  finishLookup({});
  await pending;
  assert.equal(h.agents[0].prompts.length, 0);
  assert.equal(h.chat().state.providerConfig, null);
});

test("legacy invalid config cannot initialize an active provider", () => {
  const h = createHarness(config("ftp://relay.example/v1"));
  assert.equal(h.chat().state.providerConfig, null);
  h.chat().setProviderConfig(h.load());
  assert.equal(h.agents.length, 0);
  assert.match(h.chat().state.error, /[一-鿿]/);
});

test("save boundary normalizes legacy URLs without mutating provider paths", () => {
  const h = createHarness();
  h.save("anthropic", "key", "model", "  https://localhost:3000/proxy/relay.example/api/v1/  ", "none", false);
  assert.deepEqual(h.stored(), { provider: "anthropic", apiKey: "key", model: "model", customPrefixUrl: "https://relay.example/api/v1/", thinking: "none", followMode: false });
});

test("save boundary rejects invalid URLs rather than persisting them", () => {
  const h = createHarness();
  assert.throws(() => h.save("openai", "key", "model", "https://relay.example/v1?secret=x", "none", true), /[一-鿿]/);
  assert.equal(h.stored(), null);
});
