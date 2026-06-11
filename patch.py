# -*- coding: utf-8 -*-
# Rebuilds the branded multi-provider taskpane bundle from the pristine .orig.
# Idempotent & reproducible: always reads <PATH>.orig, writes <PATH>.
#
# What it does:
#   P1  model-resolution fallback (unknown model name -> default model object)
#   P2  settings UI: provider select + free Base URL + free model, each with a
#       "?" help tooltip; provider switch auto-fills the local CORS proxy URL
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
H_BASEURL = ("模型 API 的根地址，SDK 会自动在后面拼接 /v1/messages 等路径。\n"
             "• OpenAI：https://api.openai.com/v1\n"
             "• Anthropic：https://api.anthropic.com\n"
             "• 中转 / 第三方：填其提供的地址\n"
             "若中转报跨域（CORS）错误，改用本地代理（切换供应商会自动填好，端口自动选取）：\n"
             "<本机地址>/proxy/中转域名")
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
    'ie.jsx(Tp,{value:a,style:{width:"100%"},onChange:V=>{l(V);'
    'V==="anthropic"?(y(location.origin+"/proxy/api.anthropic.com"),p("claude-opus-4-5")):'
    'V==="openai"?(y(location.origin+"/proxy/api.openai.com/v1"),p("gpt-4o")):'
    'V==="GLM"?(y(CE),p("glm-5")):(y(location.origin+"/proxy/"),p(""))},'
    'options:[{value:"GLM",label:"GLM (智谱)"},'
    '{value:"openai",label:"OpenAI"},'
    '{value:"anthropic",label:"Anthropic Claude"},'
    '{value:"openai-compatible",label:"OpenAI 兼容 / 自定义"}]})}),'
    'ie.jsx(Il.Item,{label:' + label('"接口地址 (Base URL)"', H_BASEURL) + ',children:'
    'ie.jsx(Vp,{value:v,onChange:V=>y(V.target.value),'
    'placeholder:"切换供应商会自动填入本机代理地址，也可手动改",'
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
           'customPrefixUrl:location.origin+"/proxy/api.siliconflow.cn/v1/",'
           'thinking:"none",followMode:!0}'),
          "P11 default-config")

with io.open(PATH, "w", encoding="utf-8") as f:
    f.write(src)
print("DONE -> %s" % PATH)
