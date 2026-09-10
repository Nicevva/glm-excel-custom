# -*- coding: utf-8 -*-
# Rebuilds the branded multi-provider taskpane bundle from the pristine .orig.
# Idempotent & reproducible: always reads <PATH>.orig, writes <PATH>.
#
# What it does:
#   P1  model-resolution fallback (unknown model name -> default model object)
#   P2  settings UI: provider select + free Base URL + free model, each with a
#       "?" help tooltip; provider switch auto-fills the real API URL
#   P3  API-key field gets a "?" help tooltip
#   Branding (remove GLM/Zhipu identity, use AI-in-Excel / [Author]):
#   P4  app title constant
#   P5  about description text  (i18n value)
#   P6  contact line + support link -> mailto:your.email@example.com
#   P7  header logo image  -> header-logo.png
#   P8  empty-state image alt text
import io, sys, json

PATH = "public/assets/taskpane-DG2CZyG2.js"
ORIG = PATH + ".orig"
src = io.open(ORIG, encoding="utf-8").read()


# ---- helpers ----------------------------------------------------------------
def lit(s, old, new, name, count=1):
    """Literal replacement asserting an exact occurrence count."""
    n = s.count(old)
    if n != count:
        print("ERROR %s: expected %d match(es), found %d" % (name, count, n))
        sys.exit(1)
    print("OK  %s" % name)
    return s.replace(old, new)


def set_i18n(s, key, en, zh, name):
    """Replace the whole {en:..,zh:..} value object for an i18n key.
    Avoids matching Chinese source bytes (terminal-encoding-safe)."""
    anchor = '"%s":{' % key
    i = s.find(anchor)
    if i < 0:
        print("ERROR %s: key %s not found" % (name, key))
        sys.exit(1)
    j = s.find('}', i)
    val = '"%s":{en:%s,zh:%s}' % (key, json.dumps(en, ensure_ascii=False),
                                  json.dumps(zh, ensure_ascii=False))
    print("OK  %s" % name)
    return s[:i] + val + s[j + 1:]


def badge(text):
    """A small circular '?' with a native multi-line title tooltip."""
    return ('ie.jsx("span",{title:' + json.dumps(text, ensure_ascii=False) +
            ',style:{display:"inline-flex",alignItems:"center",justifyContent:"center",'
            'width:"15px",height:"15px",borderRadius:"50%",border:"1px solid currentColor",'
            'fontSize:"10px",lineHeight:"1",marginLeft:"5px",opacity:"0.5",cursor:"help",'
            'userSelect:"none",flex:"none"},children:"?"})')


def label(expr, text):
    """Wrap a label (JS expression) + a '?' help badge in a flex row."""
    return ('ie.jsxs("span",{style:{display:"inline-flex",alignItems:"center"},children:['
            + expr + ',' + badge(text) + ']})')


# ---- help-tooltip copy ------------------------------------------------------
H_PROVIDER = ("选择模型服务商。切换后会自动填好对应接口地址，可再手动修改。\n"
              "• GLM（智谱）—— 官方直连\n"
              "• OpenAI —— 官方 GPT 接口\n"
              "• Anthropic Claude —— 官方 Claude 接口\n"
              "• OpenAI 兼容 / 自定义 —— 任意中转或第三方接口")
H_BASEURL = ("只需填写服务商提供的真实 HTTP / HTTPS API 根地址，程序自动处理本地代理，无需手动拼接。\n"
             "• OpenAI：https://api.openai.com/v1\n"
             "• Anthropic：https://api.anthropic.com（末尾 /v1 会在请求时自动处理）\n"
             "• 本地接口：http://127.0.0.1:8080\n"
             "OpenAI 兼容接口一般含 /v1；请以服务商要求为准，程序不会自动补上。\n"
             "不要填写密钥、查询参数或 /chat/completions、/messages 等完整请求路径。")
H_MODEL = ("要使用的模型名称，需与服务商一致。\n"
           "例：gpt-4o、claude-opus-4-5、glm-5\n"
           "中转站请填其支持的模型名。")
H_APIKEY = ("服务商签发的访问密钥（常以 sk- 开头）。\n"
            "仅保存在本浏览器本地，不会上传。\n"
            "在对应服务商控制台或中转后台获取。")


# ---- P1: model-resolution fallback -----------------------------------------
src = lit(src,
          'se?Q=se:Q=D7(U.provider,U.model),K=Q.contextWindow',
          ('se?Q=se:Q=D7(U.provider,U.model)||{id:U.model,name:U.model,'
           'api:U.provider==="anthropic"?"anthropic-messages":"openai-completions",'
           'provider:U.provider,baseUrl:U.customPrefixUrl,reasoning:!1,input:["text"],'
           'cost:{input:0,output:0,cacheRead:0,cacheWrite:0},'
           'contextWindow:131072,maxTokens:8192},K=Q.contextWindow'),
          "P1 model-fallback")

# ---- P2: settings UI (provider / base url / model) + tooltips ---------------
p2_old = ('ie.jsx(Il.Item,{label:r("settings.env"),children:ie.jsx(Tp,{value:v,'
          'onChange:y,options:o,disabled:!a,style:{width:"100%"},optionRender:V=>'
          'ie.jsx(zT,{children:`${V.data.label} (${V.data.value})`})})}),'
          'ie.jsx(Il.Item,{label:r("settings.model"),children:ie.jsx(Tp,{value:d,'
          'style:{width:"100%"},onChange:p,options:T,placeholder:r("settings.selectModel"),'
          'disabled:!a,fieldNames:i})}),')

p2_new = (
    'ie.jsx(Il.Item,{label:' + label('"接口提供商 (Provider)"', H_PROVIDER) + ',children:'
    'ie.jsx(Tp,{value:a,style:{width:"100%"},onChange:V=>{l(V);y(defaultApiBaseUrl(V));'
    'V==="anthropic"?p("claude-opus-4-5"):V==="openai"?p("gpt-4o"):'
    'V==="GLM"?p("glm-5"):p("")},'
    'options:[{value:"GLM",label:"GLM (智谱)"},'
    '{value:"openai",label:"OpenAI"},'
    '{value:"anthropic",label:"Anthropic Claude"},'
    '{value:"openai-compatible",label:"OpenAI 兼容 / 自定义"}]})}),'
    'ie.jsx(Il.Item,{label:' + label('"接口地址 (Base URL)"', H_BASEURL) + ','
    'validateStatus:apiBaseUrlError(v)?"error":void 0,'
    'help:apiBaseUrlError(v)||("程序自动处理本地代理，无需手动拼接。"+'
    '(a==="anthropic"?"末尾 /v1 会在请求时自动处理。":"兼容接口一般含 /v1，请按服务商提供的路径填写。")),children:'
    'ie.jsx(Vp,{value:v,onChange:V=>y(V.target.value),onBlur:()=>y(displayApiBaseUrl(v)),'
    'placeholder:"例如 "+(defaultApiBaseUrl(a)||"http://127.0.0.1:8080 或 https://api.example.com/v1"),'
    'style:{width:"100%"}})}),'
    'ie.jsx(Il.Item,{label:' + label('r("settings.model")', H_MODEL) + ',children:'
    'ie.jsx(Vp,{value:d,onChange:V=>p(V.target.value),'
    'placeholder:"gpt-4o / claude-opus-4-5 / glm-5",style:{width:"100%"}})}),'
)
src = lit(src, p2_old, p2_new, "P2 settings-ui+tooltips")

# ---- P3: API-key field tooltip ---------------------------------------------
src = lit(src,
          'ie.jsx(Il.Item,{label:r("settings.apiKey"),children:',
          'ie.jsx(Il.Item,{label:' + label('r("settings.apiKey")', H_APIKEY) + ',children:',
          "P3 apikey-tooltip")

# ---- P4: app title ----------------------------------------------------------
src = lit(src, 'fot="GLM in Excel"', 'fot="AI in Excel (Custom)"', "P4 app-title")

# ---- P5: about description --------------------------------------------------
src = set_i18n(src, "settings.aboutDesc",
               ("AI in Excel (Custom) — chat with AI models directly inside Excel. "
                "Supports OpenAI, Anthropic Claude and any compatible/relay endpoint. "
                "Your API key is stored only in this browser. "
                "Developed by Nicevva. "
                "GitHub: github.com/Nicevva/glm-excel-custom | "
                "Web: glm-excel-web.vercel.app"),
               ("AI in Excel (Custom) —— 在 Excel 中直接与 AI 模型对话，"
                "支持 OpenAI、Anthropic Claude 及任意兼容 / 中转接口。"
                "API 密钥仅保存在本浏览器本地，不会上传。由 Nicevva 开发。"
                "GitHub：github.com/Nicevva/glm-excel-custom | "
                "主页：glm-excel-web.vercel.app"),
               "P5 aboutDesc")

# ---- P6: contact line + support link ---------------------------------------
src = set_i18n(src, "settings.corsAbout",
               "Questions? Visit GitHub: ",
               "有问题请访问 GitHub：",
               "P6a contact-text")
src = set_i18n(src, "settings.updateCoding",
               "github.com/Nicevva/glm-excel-custom", "github.com/Nicevva/glm-excel-custom",
               "P6b link-text")
src = lit(src,
          ('"https://bigmodel.cn/glm-coding?utm_source=bigModel&utm_medium=Frontend%20Model%20Group'
           '&utm_content=glm-code&utm_campaign=Platform_Ops&_channel_track_key=bW5juXcZ"'),
          '"https://github.com/Nicevva/glm-excel-custom"',
          "P6c link-href")

# ---- P7: header logo image --------------------------------------------------
src = lit(src,
          'ie.jsx("img",{src:"/assets/zhipu-color.svg",alt:"ZhipuAI",width:56,height:16})',
          'ie.jsx("img",{src:"/assets/header-logo.png",alt:"AI in Excel",width:50,height:50,style:{objectFit:"contain"}})',
          "P7 header-logo")

# ---- P8: empty-state image alt ---------------------------------------------
src = lit(src,
          'ie.jsx("img",{src:"/assets/icon-64.png",alt:"ZhipuAI",width:50,height:50})',
          'ie.jsx("img",{src:"/assets/icon-64.png",alt:"AI-in-Excel",width:50,height:50})',
          "P8 empty-logo")

# ---- P9: footer copyright (appears twice) ----------------------------------
src = lit(src,
          'Copyright (c) 2025 Mario Zechner.',
          'Copyright (c) 2026 Nicevva. github.com/Nicevva/glm-excel-custom',
          "P9 copyright", count=2)

# ---- P10: remove the "beta" badge next to the header logo ------------------
src = lit(src,
          (',ie.jsx("div",{className:"flex justify-center items-center w-9 h-4 px-2 '
           'py-[3.2px] gap-2 rounded-[80px] bg-[linear-gradient(90deg,#E4EDFF_0%,#EBE4FF_100%)] '
           'text-[#134CFF] text-xs",children:"beta"})'),
          '',
          "P10 remove-beta")

# ---- P11: default config (provider / base url / model) ---------------------
# Applies only when localStorage has no saved config yet.
src = lit(src,
          '{provider:WLe,model:zY,apiKey:"",customPrefixUrl:CE,thinking:"none",followMode:!0}',
          ('{provider:"openai-compatible",model:"Pro/zai-org/GLM-5.1",apiKey:"",'
           'customPrefixUrl:"https://api.siliconflow.cn/v1/",'
           'thinking:"none",followMode:!0}'),
          "P11 default-config")

# ---- P12: real URL storage/validation + automatic request-only proxy --------
# URL policy lives in a standalone ES module, not in minified patch strings.
src = ('import {defaultApiBaseUrl,normalizeApiBaseUrl,displayApiBaseUrl,'
       'apiBaseUrlError,migrateProviderConfig,providerConfigDraft,isProviderConfigured,requestApiBaseUrl}'
       ' from "./api-url.js";\n' + src)
src = lit(src,
          'return t.followMode===void 0&&(t.followMode=!0),t}',
          'return t.followMode===void 0&&(t.followMode=!0),migrateProviderConfig(t)}',
          "P12a migrate-loaded-url")
src = lit(src,
          'function zLe(e,t,n,r,o,i){localStorage.setItem(iO,JSON.stringify({provider:e,apiKey:t,model:n,customPrefixUrl:r,thinking:o,followMode:i}))}',
          ('function zLe(e,t,n,r,o,i){const s={provider:e,apiKey:t,model:n,'
           'customPrefixUrl:normalizeApiBaseUrl(r),thinking:o,followMode:i};'
           'return localStorage.setItem(iO,JSON.stringify(s)),s}'),
          "P12b validate-saved-url")
src = lit(src,
          '[v,y]=k.useState(()=>(s==null?void 0:s.customPrefixUrl)||CE)',
          '[v,y]=k.useState(()=>(s==null?void 0:s.customPrefixUrl)??defaultApiBaseUrl(a))',
          "P12c retain-empty-custom-url")
src = lit(src,
          ('k.useEffect(()=>{a&&c&&d?(zLe(a,c,d,v,m,x),'
           't({provider:a,apiKey:c,model:d,thinking:m,followMode:x,customPrefixUrl:v}),'
           'E(!0)):E(!1)},[a,v,c,d,m,x,t])'),
          ('k.useEffect(()=>{const V={provider:a,apiKey:c,model:d,thinking:m,followMode:x,customPrefixUrl:v};'
           'isProviderConfigured(V)?(t(zLe(a,c,d,v,m,x)),E(!0)):'
           '(localStorage.setItem(iO,JSON.stringify(providerConfigDraft(V))),t(null),E(!1))},[a,v,c,d,m,x,t])'),
          "P12d settings-validation-state")
src = lit(src,
          'K=U!=null&&U.provider&&(U!=null&&U.apiKey)&&(U!=null&&U.model)&&(U!=null&&U.customPrefixUrl)?U:null',
          'K=isProviderConfigured(U)?U:null',
          "P12e validate-initial-config")
src = lit(src,
          'g=k.useCallback(U=>{var be;let K=0,Q;',
          ('g=k.useCallback(U=>{var be;if(!isProviderConfigured(U)){'
           'r.current&&(suspendedContext.current={session:c.current,messages:r.current.state.messages.slice()},r.current.abort()),'
           'r.current=null,s.current=null,i.current=!1,'
           'n(K=>({...K,providerConfig:null,isStreaming:!1,error:'
           'U?apiBaseUrlError(U.customPrefixUrl)||"请填写模型和 API 密钥。":'
           '"请在设置中填写有效接口地址、模型和 API 密钥。"}));return}'
           'U=migrateProviderConfig(U);let K=0,Q;'),
          "P12f reject-invalid-request-config")
src = lit(src,
          'const te={...Q,baseUrl:U.customPrefixUrl}',
          'const te={...Q,baseUrl:requestApiBaseUrl(U.customPrefixUrl,U.provider,location.origin)}',
          "P12g request-boundary-proxy")
src = lit(src,
          'v=k.useCallback(U=>{if(i.current)',
          'v=k.useCallback(U=>{if(!isProviderConfigured(U)){g(U);return}if(i.current)',
          "P12h clear-invalid-even-while-streaming")
src = lit(src,
          'await K.prompt(te),console.log("[Chat] Full context:",K.state.messages)',
          'if(r.current!==K)return;await K.prompt(te),console.log("[Chat] Full context:",K.state.messages)',
          "P12i cancel-invalidated-pending-request")
# Keep model context separately from the disabled Agent. Session identity guards
# it across new/switch/delete; explicit clear invalidates it immediately.
src = lit(src,
          'r=k.useRef(null),o=k.useRef(null),i=k.useRef(!1),s=k.useRef(null),a=k.useRef(null)',
          'r=k.useRef(null),suspendedContext=k.useRef(null),o=k.useRef(null),i=k.useRef(!1),s=k.useRef(null),a=k.useRef(null)',
          "P12j suspended-context-ref")
src = lit(src,
          'oe=((be=r.current)==null?void 0:be.state.messages)??[];',
          ('oe=((be=r.current)==null?void 0:be.state.messages)??'
           '(suspendedContext.current&&suspendedContext.current.session===c.current?'
           'suspendedContext.current.messages:[]);suspendedContext.current=null;'),
          "P12k restore-same-session-context")
src = lit(src,
          'E=k.useCallback(()=>{var U;y(),(U=r.current)==null||U.reset()',
          'E=k.useCallback(()=>{var U;suspendedContext.current=null;y(),(U=r.current)==null||U.reset()',
          "P12l clear-suspended-context")
# Follow mode is a preference, not a consequence of whether the URL is valid.
# The last saved draft also covers toggles made after the settings page mounted.
src = lit(src,
          'x=((I=e.providerConfig)==null?void 0:I.followMode)??!0;',
          'x=((I=e.providerConfig)==null?void 0:I.followMode)??(_A()?.followMode)??!0;',
          "P12m retain-follow-preference")
# Invalidate before the async operation, not after its session ID is committed:
# settings may restore a valid URL while the session database call is pending.
src = lit(src,
          'try{(U=r.current)==null||U.reset();const K=await vK(a.current);',
          'try{suspendedContext.current=null;(U=r.current)==null||U.reset();const K=await vK(a.current);',
          "P12n clear-context-before-new-session")
src = lit(src,
          '(K=r.current)==null||K.reset();try{const Q=await qF(U);',
          'suspendedContext.current=null;(K=r.current)==null||K.reset();try{const Q=await qF(U);',
          "P12o clear-context-before-switch-session")
src = lit(src,
          '(K=r.current)==null||K.reset(),await z3e(c.current);',
          'suspendedContext.current=null;(K=r.current)==null||K.reset(),await z3e(c.current);',
          "P12p clear-context-before-delete-session")

# ---- P13: tool details render as text, without lazy Markdown chunks ---------
# Keep the card, status and collapse behavior; only replace its fenced-code
# children. JSON data is passed as React text, never interpreted as markup.
p13_args_old = r'''ie.jsx(lS,{plugins:{code:rN},children:`\`\`\`json
${JSON.stringify(e.args,null,2)}
\`\`\``})'''
p13_args_new = (
    'ie.jsx("pre",{style:{margin:0,border:0,padding:".5em",maxHeight:"8rem",'
    'maxWidth:"100%",overflow:"auto",whiteSpace:"pre-wrap",overflowWrap:"anywhere",'
    'fontSize:"inherit"},children:ie.jsx("code",{style:{fontSize:"inherit",'
    'fontFamily:"var(--chat-font-mono)"},children:JSON.stringify(e.args,null,2)??""})})'
)
src = lit(src, p13_args_old, p13_args_new, "P13a tool-args-plain-text")

# A provided false/0/empty-string/null result is still a result; only undefined
# means no result yet. Preserve string/CSV output and pretty-print JSON objects.
p13_result_old = r'''e.result&&ie.jsxs("div",{className:"px-2 py-1.5 text-xs border-t border-(--chat-border)",children:[ie.jsx("div",{className:"text-(--chat-text-muted) text-[10px] uppercase mb-1",children:e.status==="error"?n("message.error"):n("message.result")}),ie.jsx("div",{className:`markdown-content max-h-40 overflow-y-auto **:data-[streamdown=code-block]:my-0 **:data-[streamdown=code-block]:border-0 ${e.status==="error"?"[&_code]:text-red-400!":""}`,children:ie.jsx(lS,{plugins:{code:rN},children:`\`\`\`json
${e.result}
\`\`\``})})]})'''
p13_result_new = (
    'e.result!==void 0&&ie.jsxs("div",{className:"px-2 py-1.5 text-xs border-t border-(--chat-border)",'
    'children:[ie.jsx("div",{className:"text-(--chat-text-muted) text-[10px] uppercase mb-1",'
    'children:e.status==="error"?n("message.error"):n("message.result")}),'
    'ie.jsx("div",{className:`markdown-content max-h-40 overflow-y-auto '
    '**:data-[streamdown=code-block]:my-0 **:data-[streamdown=code-block]:border-0 '
    '${e.status==="error"?"[&_code]:text-red-400!":""}`,children:'
    'ie.jsx("pre",{style:{margin:0,border:0,padding:".5em",maxHeight:"10rem",'
    'maxWidth:"100%",overflow:"auto",whiteSpace:"pre-wrap",overflowWrap:"anywhere",'
    'fontSize:"inherit"},children:ie.jsx("code",{style:{fontSize:"inherit",'
    'fontFamily:"var(--chat-font-mono)"},children:typeof e.result==="string"?'
    'e.result:JSON.stringify(e.result,null,2)??""})})})]})'
)
src = lit(src, p13_result_old, p13_result_new, "P13b tool-result-plain-text")

with io.open(PATH, "w", encoding="utf-8") as f:
    f.write(src)
print("DONE -> %s" % PATH)
