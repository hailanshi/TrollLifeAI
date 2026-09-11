/**
 * build-html.js —— 把 src/ 下的分片源码 + assets/json 数据，合成「单文件 HTML」
 *
 * 产物：
 *   app.html                              业务 100% 内联的单文件（浏览器双击可跑 / PWA 可加到主屏幕）
 *   ios-shell/TrollLifeApp/Resources/index.html   同一份副本，供打包进 .app 使用
 *
 * 只做拼装，不含任何业务逻辑。
 * 用法： node tools/build-html.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const read = (p) => fs.readFileSync(p, 'utf8');
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));

const head = read(path.join(ROOT, 'src', 'head.html'));
const body = read(path.join(ROOT, 'src', 'body.html'));

const data = {
  talents: readJson(path.join(ROOT, 'assets', 'json', 'talents.json')),
  achievements: readJson(path.join(ROOT, 'assets', 'json', 'achievements.json')),
  skills: readJson(path.join(ROOT, 'assets', 'json', 'skills.json')),
  city: readJson(path.join(ROOT, 'assets', 'json', 'city.json')),
  event: readJson(path.join(ROOT, 'assets', 'json', 'event.json')),
};
/* 剧情逻辑规则表（年龄纠偏 + 前提校验），网页版与 Flutter 版共用 */
const rules = readJson(path.join(ROOT, 'src', 'age-rules.json'));

const jsFiles = ['01_core.js', '02_ach.js', '03_ai.js', '04_actions.js', '05_ui.js'];
const jsParts = jsFiles.map((f) => '/* ===== ' + f + ' ===== */\n' + read(path.join(ROOT, 'src', 'js', f)));

const banner =
  '<!--\n' +
  '  TrollLifeAI · 人生重开模拟器（单文件版）\n' +
  '  业务 100% 内联在此文件内：HTML + CSS + JS + 数据，无任何外部依赖。\n' +
  '  数据来源：talents.json / achievements.json / skills.json / city.json / event.json（合并后）\n' +
  '  统计：事件 ' + data.event.length + ' 条 · 天赋 ' + data.talents.length + ' 个 · 技能 ' + data.skills.length +
  ' 个 · 成就 ' + data.achievements.length + ' 个 · 城市 ' + data.city.length + ' 座\n' +
  '  AI：可选接入 OpenAI 兼容接口（默认 DeepSeek），Key 由玩家在「AI」页填写并只存本机 localStorage，\n' +
  '      本文件内不含任何 API Key。\n' +
  '  生成时间：' + new Date().toISOString() + '\n' +
  '  注意：本文件由 tools/build-html.js 生成，请勿手工修改，改 src/ 后重新构建。\n' +
  '-->\n';

/* JSON 内联时把 </script> 与 <!-- 打断，避免提前结束脚本块 */
function safeJson(obj) {
  return JSON.stringify(obj).replace(/<\//g, '<\\/').replace(/<!--/g, '<\\!--');
}

const out =
  head +
  banner +
  body +
  '\n<script>\n/* ===== 游戏数据（由 5 份 JSON 合并后内联） ===== */\nwindow.__TL_DATA__ = ' +
  safeJson(data) +
  ';\n/* ===== 剧情逻辑规则表（年龄纠偏 + 前提校验） ===== */\nwindow.__TL_RULES__ = ' +
  safeJson(rules) +
  ';\n</script>\n' +
  '<script>\n' + jsParts.join('\n') + '\n</script>\n' +
  '</body>\n</html>\n';

const appPath = path.join(ROOT, 'app.html');
fs.writeFileSync(appPath, out, 'utf8');

const resDir = path.join(ROOT, 'ios-shell', 'TrollLifeApp', 'Resources');
fs.mkdirSync(resDir, { recursive: true });
fs.writeFileSync(path.join(resDir, 'index.html'), out, 'utf8');

fs.writeFileSync(path.join(ROOT, 'build', 'inline-check.js'),
  jsParts.join('\n'), 'utf8');

console.log('app.html 生成完成：' + (out.length / 1024).toFixed(1) + ' KB');
console.log('  事件 ' + data.event.length + ' / 天赋 ' + data.talents.length + ' / 技能 ' + data.skills.length +
  ' / 成就 ' + data.achievements.length + ' / 城市 ' + data.city.length);
console.log('iOS 壳资源副本：ios-shell/TrollLifeApp/Resources/index.html');
console.log('已导出 build/inline-check.js 供 node --check 语法校验');
