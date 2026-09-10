import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import * as webStreams from "node:stream/web";
import { nodes, text } from "./bundle-harness.mjs";

const bundleUrl = new URL("../public/assets/taskpane-DG2CZyG2.js", import.meta.url);
// Only remove ES-module bootstrapping for the offline VM. ToolCard, React/JSX,
// Markdown, its parser/plugins and React.lazy all execute the shipped code.
const source = readFileSync(bundleUrl, "utf8")
  .replace(/^import \{[^}]+\} from "\.\/api-url\.js";\r?\n/, "")
  .replace('import"./modulepreload-polyfill-B5Qt9EMX.js";', "")
  .replace(/export\{[^}]+\};\s*$/, "");
const script = new vm.Script('"use strict";\n' + source +
  "\n;({ React:k, jsx:ie.jsx, ToolCard:yne, chatContext:qY, localeContext:yK });", {
  filename: fileURLToPath(bundleUrl),
  importModuleDynamically: vm.constants.USE_MAIN_CONTEXT_DEFAULT_LOADER,
});

function createToolHarness(initialPart) {
  const requests = [];
  const context = vm.createContext({
    console, URL, TextEncoder, TextDecoder, AbortController, Event,
    performance, atob, btoa, setTimeout, clearTimeout, ...webStreams,
    navigator: { userAgent: "node" },
    Office: { onReady() {} },
    // No app container means no Office/app startup. The only network-owning
    // boundary supplied is Vite's modulepreload DOM; no network is ever used.
    document: {
      getElementById: () => null,
      getElementsByTagName: () => [],
      querySelector: () => null,
      createElement: () => ({ style: {}, setAttribute() {}, getContext: () => null }),
      head: { appendChild: link => requests.push(link.href) },
    },
  });
  const { React, jsx, ToolCard, chatContext, localeContext } = script.runInContext(context);
  // Supply the preload-error event target only after initialization, so the
  // bundle uses its non-browser initialization paths in this Node harness.
  context.window = { dispatchEvent: () => true };
  const dispatcher = React.__SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED.ReactCurrentDispatcher;
  let part = initialPart, expanded = false, output, renderingToolCard;
  const hooks = {
    useState: initial => renderingToolCard
      ? [expanded, next => { expanded = typeof next === "function" ? next(expanded) : next; }]
      : [typeof initial === "function" ? initial() : initial, () => {}],
    useMemo: factory => factory(),
    useContext: value => value._currentValue,
    // First-render primitives keep the original Markdown path real in RED.
    useId: () => "tool-details-test", useTransition: () => [false, callback => callback()],
    useEffect() {},
  };

  // Drive only ToolCard's expand state and resolve its real descendants to the
  // host-element boundary. No general effect scheduler or Markdown doubles;
  // browser coverage owns ReactDOM scheduling and root-unmount behavior.
  function renderNode(node) {
    if (node == null || typeof node === "boolean") return null;
    if (Array.isArray(node)) return node.map(renderNode);
    if (typeof node !== "object") return node;
    let { type, props } = node;
    if (typeof type === "string") return { type, props: { ...props, children: renderNode(props.children) } };
    if (type === React.Fragment || type === React.Suspense) return renderNode(props.children);
    while (type?.$$typeof === Symbol.for("react.memo")) type = type.type;
    if (type?.$$typeof === Symbol.for("react.provider")) {
      const target = type._context, previous = target._currentValue;
      target._currentValue = props.value;
      try { return renderNode(props.children); }
      finally { target._currentValue = previous; }
    }
    if (type?.$$typeof === Symbol.for("react.lazy")) type = type._init(type._payload);
    if (type?.$$typeof === Symbol.for("react.forward_ref")) type = type.render;
    assert.equal(typeof type, "function", "Every non-host descendant must actually render");
    renderingToolCard = type === ToolCard;
    return renderNode(type(props, null));
  }

  async function render() {
    const previous = dispatcher.current;
    dispatcher.current = hooks;
    try {
      output = renderNode(jsx(chatContext.Provider, {
        value: { getSheetName: () => undefined },
        children: jsx(localeContext.Provider, {
          value: { t: key => key }, children: jsx(ToolCard, { part }),
        }),
      }));
      return output;
    } catch (error) {
      // React.lazy throws its real import promise; an absent chunk rejects it.
      if (error && typeof error.then === "function") { await error; return render(); }
      throw error;
    } finally { dispatcher.current = previous; }
  }

  return {
    requests, render,
    async click() {
      const button = nodes(output).find(node => node.type === "button");
      assert.ok(button, "Tool card retains its expand/collapse button");
      button.props.onClick();
      return render();
    },
    update(nextPart) { part = nextPart; return render(); },
  };
}

const fixture = {
  type: "toolCall", id: "repro-tool-1", name: "get_range_as_csv",
  args: { explanation: "读取本周总结数据" }, status: "running",
};
const codeText = tree => nodes(tree).filter(node => node.type === "code").map(node => text(node));
const codeNodes = tree => nodes(tree).filter(node => node.type === "pre");

// Break caught: eagerly mounting details causes the missing Markdown chunk to
// load even before the user opens a running card.
test("collapsed running card keeps its title and spinner without mounting details", async () => {
  const h = createToolHarness(fixture);
  const tree = await h.render();
  assert.equal(text(tree).trim(), "读取本周总结数据");
  assert.ok(nodes(tree).some(node => node.type === "svg" && /animate-spin/.test(node.props.className)));
  assert.equal(codeNodes(tree).length, 0);
  assert.doesNotMatch(text(tree), /message.args|message.result/);
  assert.deepEqual(h.requests, []);
});

// Break caught: opening the exact running fixture reaches Markdown's lazy
// fenced-code dependency and throws instead of showing arguments.
test("opening running tool details displays JSON without a lazy chunk request or crash", async () => {
  const h = createToolHarness(fixture);
  await h.render();
  const tree = await h.click();
  assert.deepEqual(codeText(tree), ['{\n  "explanation": "读取本周总结数据"\n}']);
  assert.match(text(tree), /message.args/);
  assert.ok(nodes(tree).some(node => node.type === "svg" && /animate-spin/.test(node.props.className)));
  assert.deepEqual(h.requests, []);
  const collapsed = await h.click();
  assert.equal(codeNodes(collapsed).length, 0);
  assert.doesNotMatch(text(collapsed), /message.args/);
  assert.deepEqual(codeText(await h.click()), ['{\n  "explanation": "读取本周总结数据"\n}']);
});

// Break caught: falsey results disappear, object results become [object Object],
// or error details accidentally use the success label/style.
for (const [name, status, result, expected] of [
  ["CSV string", "complete", "日期,总结\n周一,完成", "日期,总结\n周一,完成"],
  ["JSON object", "complete", { rows: [[1, false]], count: 0 }, '{\n  "rows": [\n    [\n      1,\n      false\n    ]\n  ],\n  "count": 0\n}'],
  ["JSON string", "complete", '{"rows":[1]}', '{"rows":[1]}'],
  ["empty string", "complete", "", ""],
  ["false", "complete", false, "false"],
  ["zero", "complete", 0, "0"],
  ["null", "complete", null, "null"],
  ["error string", "error", "读取失败", "读取失败"],
  ["error object", "error", { error: "未找到范围" }, '{\n  "error": "未找到范围"\n}'],
]) {
  test(`expanded ${name} result is readable plain text with ${status} status`, async () => {
    const h = createToolHarness({ ...fixture, status, result });
    await h.render();
    const tree = await h.click();
    assert.equal(codeText(tree).length, 2, "A provided result, including falsey JSON, has its own details");
    assert.equal(codeText(tree)[1], expected);
    assert.match(text(tree), status === "error" ? /message.error/ : /message.result/);
    assert.ok(nodes(tree).some(node => node.type === "svg" && node.props.className.includes(status === "error" ? "text-red-500" : "text-green-500")));
    if (status === "error") assert.ok(nodes(tree).some(node => /text-red-400/.test(node.props.className)));
    assert.deepEqual(h.requests, []);
  });
}

// Break caught: streamed args begin undefined/null, or memoized details retain
// stale args/results when the same tool-call ID updates.
for (const [name, args, expected] of [
  ["undefined", undefined, ""], ["null", null, "null"],
]) {
  test(`running ${name} args safely update through streaming completion`, async () => {
    const h = createToolHarness({ ...fixture, args });
    await h.render();
    let tree = await h.click();
    assert.deepEqual(codeText(tree), [expected]);
    assert.match(text(tree), /get_range_as_csv/);
    tree = await h.update({ ...fixture, args: { explanation: "更新", range: "A1:B2" } });
    assert.deepEqual(codeText(tree), ['{\n  "explanation": "更新",\n  "range": "A1:B2"\n}']);
    tree = await h.update({ ...fixture, args: { range: "A1:B2" }, status: "complete", result: [1, 2] });
    assert.deepEqual(codeText(tree), ['{\n  "range": "A1:B2"\n}', '[\n  1,\n  2\n]']);
    assert.match(text(tree), /message.result/);
    assert.deepEqual(h.requests, []);
  });
}

// Break caught: treating model-returned markup/fences as HTML or Markdown makes
// content active, drops its literal text, or requests another renderer chunk.
test("HTML and Markdown fences in args/results remain literal code text", async () => {
  const dangerous = '</code><img src=x onerror="alert(1)"><script>alert(2)</script>\n```html\n<b>unsafe</b>\n```';
  const h = createToolHarness({ ...fixture, args: { html: "<script>1</script>" }, status: "complete", result: dangerous });
  await h.render();
  const tree = await h.click();
  assert.deepEqual(codeText(tree), ['{\n  "html": "<script>1</script>"\n}', dangerous]);
  assert.ok(nodes(tree).every(node => !["script", "img", "b"].includes(node.type)));
  assert.ok(nodes(tree).every(node => !node.props.dangerouslySetInnerHTML));
  assert.deepEqual(h.requests, []);
});

// Break caught: long lines or large results expand the narrow Excel taskpane
// instead of wrapping and scrolling within the existing detail height limits.
test("long details have bounded scrolling and wrap within the narrow panel", async () => {
  const long = "一".repeat(2000);
  const h = createToolHarness({ ...fixture, args: { value: long }, status: "complete", result: long });
  await h.render();
  const tree = await h.click();
  assert.equal(codeText(tree)[1], long);
  const blocks = codeNodes(tree);
  assert.equal(blocks.length, 2);
  for (const block of blocks) {
    assert.ok(block.props.style.maxHeight, "Details must cap their height");
    assert.equal(block.props.style.maxWidth, "100%");
    assert.equal(block.props.style.overflow, "auto");
    assert.equal(block.props.style.whiteSpace, "pre-wrap");
    assert.equal(block.props.style.overflowWrap, "anywhere");
  }
  assert.deepEqual(h.requests, []);
});
