/**
 * selfcheck.js —— 交付前自检（对应需求里的验收清单）
 * 用法： node tools/selfcheck.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const results = [];
let failed = 0;

function check(name, ok, detail) {
  results.push({ name, ok: !!ok, detail: detail || '' });
  if (!ok) { failed++; }
}

const appPath = path.join(ROOT, 'app.html');
const app = fs.readFileSync(appPath, 'utf8');
const inlineJsRaw = fs.readFileSync(path.join(ROOT, 'build', 'inline-check.js'), 'utf8');

/* 静态检查用：去掉 JS 注释，避免注释里的示例文字被当成真实代码 */
function stripJsComments(src) {
  return src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/[^\n]*/g, '$1');
}
const inlineJs = stripJsComments(inlineJsRaw);

/* 1. 内联 JS 语法（由 build 导出的 inline-check.js 供 node --check 使用） */
try {
  new Function(inlineJsRaw); /* 语法级别校验 */
  check('内联 JS 语法可解析', true);
} catch (e) {
  check('内联 JS 语法可解析', false, e.message);
}

/* 2. 所有 onclick 调用的函数都真实挂在 window 上 */
const onclickRe = /onclick\s*=\s*"([^"]*)"/g;
const calls = {};
let m;
while ((m = onclickRe.exec(app)) !== null) {
  const body = m[1];
  const callRe = /window\.([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)/g;
  let c;
  while ((c = callRe.exec(body)) !== null) { calls[c[1]] = (calls[c[1]] || 0) + 1; }
}
const callPaths = Object.keys(calls);
const missing = [];
callPaths.forEach((p) => {
  const tail = p.split('.').pop();
  /* 允许的写法： window.xxx = function / window.xxx = ident / ui.xxx = function / ui.xxx = ident / xxx: function */
  const t = tail.replace(/\$/g, '\\$');
  const defRe = new RegExp('(?:window\\.|ui\\.|\\b)' + t + '\\s*=\\s*(?:function|[A-Za-z_$][\\w$]*\\s*;)|' +
    '(?:window\\.|ui\\.|\\b)' + t + '\\s*=\\s*function|' + t + '\\s*:\\s*function');
  if (!defRe.test(inlineJs)) { missing.push(p); }
});
check('onclick 调用的函数均已挂到 window', missing.length === 0,
  'onclick 路径 ' + callPaths.length + ' 个；缺失: ' + (missing.join(', ') || '无'));
check('window.ui 命名空间已挂载', /window\.ui\s*=\s*ui/.test(inlineJs));
check('确认弹窗走全局变量 + doConfirmOK', /window\.__confirm\s*=/.test(inlineJs) && /window\.doConfirmOK\s*=\s*function/.test(inlineJs));

/* 3. iOS 兼容铁律 */
const styleBlock = (/<style>([\s\S]*?)<\/style>/.exec(app) || [, ''])[1];
check('CSS 未使用 inset 简写', !/(^|[^\w-])inset\s*:/.test(styleBlock) && !/inset\s*\(/.test(styleBlock));
check('弹窗用 top/left/right/bottom 定位', /top:0;left:0;right:0;bottom:0/.test(styleBlock.replace(/\s/g, '')));
check('安全区适配 env(safe-area-inset-*)', /env\(safe-area-inset-top\)/.test(styleBlock) && /env\(safe-area-inset-bottom\)/.test(styleBlock));
check('viewport 锁定缩放 + viewport-fit=cover',
  /maximum-scale=1/.test(app) && /user-scalable=no/.test(app) && /viewport-fit=cover/.test(app));
check('html,body touch-action:manipulation', /touch-action:manipulation/.test(styleBlock));
check('输入框字号 16px（防 iOS 自动放大）', /input[^{]*\{[^}]*font-size:16px/.test(styleBlock));
check('弹窗长列表：头部/内容/按钮三段式', /modalHead/.test(styleBlock) && /modalBody[^{]*\{[^}]*overflow-y:auto/.test(styleBlock) && /modalFoot/.test(styleBlock));

/* 4. 老语法 JS（先剥掉字符串与正则字面量，避免把 /```json/ 误判成模板字符串） */
const jsBare = inlineJs
  .replace(/'(?:[^'\\\n]|\\.)*'/g, "''")
  .replace(/"(?:[^"\\\n]|\\.)*"/g, '""')
  .replace(/\/(?![*\/])(?:[^\/\\\n\[]|\\.|\[(?:[^\]\\]|\\.)*\])+\/[gimsuy]*/g, '/re/');
const arrow = /=>/.test(jsBare);
const tmpl = /`/.test(jsBare);
const optionalChain = /\?\.[A-Za-z_$(]/.test(inlineJs);
const nullish = /\?\?/.test(inlineJs);
const flat = /\.flat\s*\(/.test(inlineJs);
const letConst = /(^|[^\w.])(let|const)\s+[A-Za-z_$]/.test(inlineJs);
check('未使用箭头函数', !arrow);
check('未使用模板字符串', !tmpl);
check('未使用可选链 ?.', !optionalChain);
check('未使用空值合并 ??', !nullish);
check('未使用 .flat()', !flat);
check('未使用 let / const（老语法）', !letConst);

/* 5. 无动态 DOM 事件绑定 */
check('无 el.onclick = 动态绑定', !/\.onclick\s*=/.test(inlineJs));
check('无 addEventListener 绑业务按钮（仅 DOMContentLoaded）',
  (inlineJs.match(/addEventListener/g) || []).length <= 2);

/* 6. 无外部依赖 */
check('无外部 script src', !/<script[^>]+src=/i.test(app));
check('无外部 link href', !/<link[^>]+href=/i.test(app));
check('无外部图片/字体 URL', !/url\(\s*['"]?https?:/i.test(app));

/* 7. 数据内联与统计 */
const dataMatch = /window\.__TL_DATA__\s*=\s*(\{[\s\S]*?\});\n<\/script>/.exec(app);
let data = null;
try { data = JSON.parse(dataMatch[1].replace(/<\\\//g, '</')); } catch (e) { }
check('内联数据可解析', !!data, data ? '' : '解析失败');
if (data) {
  check('事件数量 ≥ 155', data.event.length >= 155, '实际 ' + data.event.length);
  check('天赋数量 ≥ 44', data.talents.length >= 44, '实际 ' + data.talents.length);
  check('成就数量 ≥ 74', data.achievements.length >= 74, '实际 ' + data.achievements.length);
  check('技能数量 ≥ 29', data.skills.length >= 29, '实际 ' + data.skills.length);
  check('城市数量 ≥ 9', data.city.length >= 9, '实际 ' + data.city.length);
  const KEYS = ['智力', '体质', '魅力', '财富', '快乐', '运气', '健康值', '成瘾值', '名声值', '压力值', '罪恶值'];
  let bad = 0;
  data.event.forEach((e) => {
    (e.choices || []).forEach((c) => {
      KEYS.forEach((k) => { if (typeof c.attr_change[k] !== 'number') { bad++; } });
    });
  });
  check('所有 attr_change 均含 11 项数值', bad === 0, '异常字段 ' + bad + ' 个');
}

/* 8. 金手指密码 */
check('保留金手指密码 208526', /208526/.test(inlineJs));

/* 9. 玩法增强层（主动行动 / 关系互动 / 评分 / 存档 / AI） */
check('主动行动系统（≥13 种行动）',
  (inlineJs.match(/id: '(work|hospital|fitness|study|social|invest|family|rest|rehab|date|child|startup|pet|checkup)'/g) || []).length >= 13);
check('关系互动（送礼/深聊/和解/求婚）',
  /INTERACTS\s*=/.test(inlineJs) && /gift:/.test(inlineJs) && /propose:/.test(inlineJs) && /reconcile:/.test(inlineJs));
check('人生评分与称号', /scoreLife/.test(inlineJs) && /TITLES\s*=/.test(inlineJs));
check('存档槽位 + 导出/导入', /saveSlot/.test(inlineJs) && /exportSave/.test(inlineJs) && /importSave/.test(inlineJs));
check('AI 配置页与触发链路', /aiSave/.test(inlineJs) && /aiTest/.test(inlineJs) && /shouldUse/.test(inlineJs));
check('AI 结果本地校验（11 项 + 越界夹取 + 不合格丢弃）',
  /normalizeEvent/.test(inlineJs) && /clampInt/.test(inlineJs) && /extractJson/.test(inlineJs));
check('AI 失败自动回退本地剧情', /aiFallback/.test(inlineJs) && /presentEvent/.test(inlineJs));
check('app.html 内未嵌入任何 API Key', !/sk-[A-Za-z0-9]{16,}/.test(app) && !/Bearer sk-/.test(app));
check('AI Key 仅存本机（独立 localStorage 键，不随存档导出）',
  /TL\.AI_KEY\s*=\s*'tlai_ai_v1'/.test(inlineJs) && /exportSave[\s\S]{0,300}version: 1, exportedAt/.test(inlineJs));
check('底部导航 6 个页签（含 AI）', (app.match(/id="tab_\w+"/g) || []).length === 6 && /id="tab_ai"/.test(app));
check('AI 页签回调已挂 window', /ui\.aiSave\s*=\s*function/.test(inlineJs) && /ui\.aiTest\s*=\s*function/.test(inlineJs));
check('展示文本剥离剧情标记（剧情/选项/日志/标题）',
  /stripMarks\(ev\.story\)/.test(inlineJs) &&
  /stripMarks\(ev\.choices\[i\]\.desc\)/.test(inlineJs) &&
  /stripMarks\(ev\.title\)/.test(inlineJs) &&
  /stripMarks\(S\.log\[/.test(inlineJs));

/* 9. 壳工程与流水线文件齐全 */
const required = [
  'ios-shell/TrollLifeApp/main.m',
  'ios-shell/TrollLifeApp/AppDelegate.h',
  'ios-shell/TrollLifeApp/AppDelegate.m',
  'ios-shell/TrollLifeApp/ViewController.h',
  'ios-shell/TrollLifeApp/ViewController.m',
  'ios-shell/TrollLifeApp/Info.plist',
  'ios-shell/TrollLifeApp/project.yml',
  'ios-shell/TrollLifeApp/Resources/index.html',
  'ios-shell/TrollLifeApp/Resources/AppIcon60x60@2x.png',
  'ios-shell/TrollLifeApp/Resources/AppIcon60x60@3x.png',
  '.github/workflows/build-ipa.yml',
  'assets/json/talents.json',
  'assets/json/achievements.json',
  'assets/json/skills.json',
  'assets/json/city.json',
  'assets/json/event.json',
];
const missingFiles = required.filter((f) => !fs.existsSync(path.join(ROOT, f)));
check('交付文件齐全', missingFiles.length === 0, missingFiles.join(', '));

/* 10. 壳里没有业务逻辑（只允许容器代码）；注释先剥离，避免注释里的反面示例误判 */
const vcRaw = fs.readFileSync(path.join(ROOT, 'ios-shell/TrollLifeApp/ViewController.m'), 'utf8');
const vc = vcRaw.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/[^\n]*$/gm, '');
check('壳内注册 nativeFetch 通道', /addScriptMessageHandler:self name:@"nativeFetch"/.test(vc));
check('壳内注册 nativeHttp 通道（支持 POST，供 AI 接口用）',
  /addScriptMessageHandler:self name:@"nativeHttp"/.test(vc) && /handleNativeHttp/.test(vc) && /HTTPMethod = method/.test(vc));
check('壳内回传 window.__nativeHttpResult', /__nativeHttpResult/.test(vc));
check('壳内禁用缩放', /pinchGestureRecognizer\.enabled = NO/.test(vc));
check('壳内设置 contentInsetAdjustmentNever', /contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever/.test(vc));
check('壳内使用 loadFileURL:allowingReadAccessToURL:', /loadFileURL:.*allowingReadAccessToURL:/.test(vc));
check('壳内未使用私有 KVC 打开 file 跨域', !/allowFileAccessFromFileURLs/.test(vc));

/* 10.5 壳源文件完整性（新加的 .m/.h 必须登记进 project.yml，否则 CI 会漏编） */
const shellDir = path.join(ROOT, 'ios-shell/TrollLifeApp');
const shellSrc = fs.readdirSync(shellDir).filter((f) => /\.(m|h)$/.test(f));
const projYml = fs.readFileSync(path.join(shellDir, 'project.yml'), 'utf8');
const notListed = shellSrc.filter((f) => projYml.indexOf('- path: ' + f) === -1);
check('壳源文件全部登记进 project.yml', notListed.length === 0,
  '共 ' + shellSrc.length + ' 个，未登记: ' + (notListed.join(', ') || '无'));

/* 10.6 ObjC 源码括号/花括号配对（粗查截断或漏写） */
const objcBad = [];
shellSrc.forEach((f) => {
  const src = fs.readFileSync(path.join(shellDir, f), 'utf8');
  const cleaned = src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/[^\n]*$/gm, '')
    .replace(/@?"(?:[^"\\\n]|\\.)*"/g, '""');
  [['{', '}'], ['(', ')'], ['[', ']']].forEach(([o, c]) => {
    const a = (cleaned.split(o).length - 1);
    const b = (cleaned.split(c).length - 1);
    if (a !== b) { objcBad.push(f + ' ' + o + c + '=' + a + '/' + b); }
  });
});
check('ObjC 源文件括号配对', objcBad.length === 0, objcBad.join(' | '));

/* 10.7 崩溃日志与自诊断能力（本次新增，专门用来定位闪退） */
check('崩溃日志落盘到 Documents（文件 App 可见）',
  /NSDocumentDirectory/.test(fs.readFileSync(path.join(shellDir, 'TLDiagnostics.m'), 'utf8')) &&
  /UIFileSharingEnabled/.test(fs.readFileSync(path.join(shellDir, 'Info.plist'), 'utf8')));
check('未捕获异常 + 信号处理器齐全',
  /NSSetUncaughtExceptionHandler/.test(fs.readFileSync(path.join(shellDir, 'TLDiagnostics.m'), 'utf8')) &&
  /SIGSEGV/.test(fs.readFileSync(path.join(shellDir, 'TLDiagnostics.m'), 'utf8')) &&
  /backtrace_symbols_fd/.test(fs.readFileSync(path.join(shellDir, 'TLDiagnostics.m'), 'utf8')));
check('启动面包屑（可反推 dyld 级崩溃）',
  /TLMarkLaunchStart/.test(fs.readFileSync(path.join(shellDir, 'main.m'), 'utf8')) &&
  /tl_last_ready/.test(fs.readFileSync(path.join(shellDir, 'TLDiagnostics.m'), 'utf8')));
check('安全模式（连续启动失败则跳过 WKWebView）',
  /TLIsSafeMode/.test(vc) && /fails >= 2/.test(fs.readFileSync(path.join(shellDir, 'TLDiagnostics.m'), 'utf8')));
check('白屏检测（加载完成后再查 DOM 长度）', /页面 DOM 长度/.test(vc));

/* 11. 工作流避坑点 */
const wf = fs.readFileSync(path.join(ROOT, '.github/workflows/build-ipa.yml'), 'utf8');
check('CI 使用 macos-15', /runs-on:\s*macos-15/.test(wf));
check('CI 用真实退出码判断编译结果', /PIPESTATUS\[0\]/.test(wf));
check('CI 校验主程序存在（防空壳包）', /test -f "\$APP\/TrollLifeApp"/.test(wf));
check('CI 手动拷贝 index.html 与图标后签名', /cp "\$RES\/index\.html" "\$APP\/index\.html"/.test(wf) && /codesign --force --sign -/.test(wf));
check('CI ipa 路径一致（zip 与 upload）',
  /zip -qry "\$GITHUB_WORKSPACE\/TrollLifeAI\.ipa"/.test(wf) && /path:\s*\$\{\{\s*github\.workspace\s*\}\}\/TrollLifeAI\.ipa/.test(wf));
check('CI 失败时公开 build log', /if:\s*failure\(\)/.test(wf));

/* 12. 原始 JSON 未被改动（与 build/originals 快照对比，若存在快照） */
const snapDir = path.join(ROOT, 'build', 'originals');
if (fs.existsSync(snapDir)) {
  ['talents', 'achievements', 'skills', 'city', 'event'].forEach((f) => {
    const cur = fs.readFileSync(path.join(ROOT, f + '.json'), 'utf8');
    const old = fs.readFileSync(path.join(snapDir, f + '.json'), 'utf8');
    check('原始 ' + f + '.json 未被修改', cur.replace(/\s+/g, '') === old.replace(/\s+/g, ''));
  });
}

/* 输出 */
console.log('======== 交付自检清单 ========');
results.forEach((r) => {
  console.log((r.ok ? '  [PASS] ' : '  [FAIL] ') + r.name + (r.detail ? '  (' + r.detail + ')' : ''));
});
console.log('--------------------------------');
console.log('通过 ' + (results.length - failed) + ' / ' + results.length +
  '，app.html ' + (app.length / 1024).toFixed(1) + ' KB，onclick 全局函数 ' + callPaths.length + ' 个');
process.exit(failed ? 1 : 0);
