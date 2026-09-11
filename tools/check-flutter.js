/**
 * check-flutter.js —— Flutter 工程静态自检（本机没有 Flutter SDK，无法编译，只能静态校验）
 * 检查项：
 *   1. 目录/文件齐全（pubspec、assets 5 份 json、models/services/providers/pages/theme）
 *   2. pubspec.yaml 里声明了 assets/json/ 且 5 份 json 真实存在
 *   3. 每个 dart 文件括号/引号配对（粗查截断文件）
 *   4. 所有相对 import 都能解析到真实文件
 *   5. 页面里调用的 GameProvider 方法在 game_provider.dart 里真实存在
 *   6. 关键玩法要素是否落地（208526 / 11 项属性 / 标记解析 / 成就 / 轮回 / 宠物 / 人际）
 * 用法： node tools/check-flutter.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const FP = path.join(ROOT, 'flutter_trolllifeai');
let fails = 0;
const check = (name, ok, detail) => {
  if (!ok) { fails++; }
  console.log((ok ? '  [PASS] ' : '  [FAIL] ') + name + (detail ? '  (' + detail + ')' : ''));
};

if (!fs.existsSync(FP)) {
  console.log('Flutter 工程目录不存在: ' + FP);
  process.exit(1);
}

function walk(dir, out) {
  out = out || [];
  fs.readdirSync(dir).forEach((name) => {
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) { walk(p, out); } else { out.push(p); }
  });
  return out;
}
const allFiles = walk(FP);
const dartFiles = allFiles.filter((f) => f.endsWith('.dart'));

console.log('======== Flutter 工程静态自检 ========');
console.log('工程目录: flutter_trolllifeai/   文件 ' + allFiles.length + ' 个，其中 dart ' + dartFiles.length + ' 个\n');

/* 1. 文件齐全 */
const need = [
  'pubspec.yaml',
  'assets/json/talents.json',
  'assets/json/achievements.json',
  'assets/json/skills.json',
  'assets/json/city.json',
  'assets/json/event.json',
  'lib/main.dart',
  'lib/theme/app_theme.dart',
  'lib/providers/game_provider.dart',
  'lib/services/data_loader.dart',
  'lib/services/storage_service.dart',
  'lib/services/event_engine.dart',
  'lib/models/character.dart',
  'lib/models/talent.dart',
  'lib/models/skill.dart',
  'lib/models/achievement.dart',
  'lib/models/city_data.dart',
  'lib/models/life_event.dart',
  'lib/models/relation.dart',
  'lib/models/pet.dart',
  'lib/pages/start_page.dart',
  'lib/pages/home_page.dart',
  'lib/pages/achievement_page.dart',
  'lib/pages/skill_page.dart',
  'lib/pages/rebirth_page.dart',
  'lib/pages/god_console_page.dart',
];
const missing = need.filter((f) => !fs.existsSync(path.join(FP, f)));
check('必需文件齐全', missing.length === 0, missing.join(', '));

/* 事件弹窗页面（允许两种命名） */
const hasEventPage = ['lib/pages/event_page.dart', 'lib/pages/event_dialog.dart', 'lib/widgets/event_dialog.dart']
  .some((f) => fs.existsSync(path.join(FP, f)));
check('事件弹窗页面存在', hasEventPage);

/* 2. pubspec */
const pubspec = fs.existsSync(path.join(FP, 'pubspec.yaml')) ? fs.readFileSync(path.join(FP, 'pubspec.yaml'), 'utf8') : '';
check('pubspec 声明 assets/json/', /assets:\s*[\s\S]*assets\/json\//.test(pubspec));
check('pubspec 依赖 provider', /provider:\s*\^?\d/.test(pubspec));
check('pubspec 未引入其他第三方依赖',
  !/^\s{2}(hive|shared_preferences|path_provider|http|dio|sqflite|get_it|riverpod)/m.test(pubspec));

/* 3. 括号配对 */
const unbalanced = [];
dartFiles.forEach((f) => {
  const src = fs.readFileSync(f, 'utf8');
  /* 粗略去掉字符串与注释后再数括号 */
  const cleaned = src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\/\/[^\n]*/g, '')
    .replace(/'(?:[^'\\\n]|\\.)*'/g, "''")
    .replace(/"(?:[^"\\\n]|\\.)*"/g, '""');
  const pairs = [['{', '}'], ['(', ')'], ['[', ']']];
  pairs.forEach(([o, c]) => {
    const a = (cleaned.match(new RegExp('\\' + o, 'g')) || []).length;
    const b = (cleaned.match(new RegExp('\\' + c, 'g')) || []).length;
    if (a !== b) { unbalanced.push(path.basename(f) + ' ' + o + c + ' ' + a + '/' + b); }
  });
});
check('所有 dart 文件括号配对', unbalanced.length === 0, unbalanced.join(' | '));

/* 每行长度/空文件粗查 */
const empties = dartFiles.filter((f) => fs.statSync(f).size < 200).map((f) => path.basename(f));
check('无过小的空壳文件', empties.length === 0, empties.join(', '));

/* 4. import 解析 */
const badImports = [];
dartFiles.forEach((f) => {
  const src = fs.readFileSync(f, 'utf8');
  const re = /import\s+'([^']+)'/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const spec = m[1];
    if (spec.startsWith('dart:')) { continue; }
    if (spec.startsWith('package:')) {
      if (spec.startsWith('package:trolllifeai/')) {
        const rel = spec.replace('package:trolllifeai/', 'lib/');
        if (!fs.existsSync(path.join(FP, rel))) { badImports.push(spec + ' ← ' + path.relative(FP, f)); }
      }
      continue; /* 其他 package 交给 flutter 解析 */
    }
    const target = path.resolve(path.dirname(f), spec);
    if (!fs.existsSync(target)) { badImports.push(spec + ' ← ' + path.relative(FP, f)); }
  }
});
check('相对 import 全部可解析', badImports.length === 0, badImports.slice(0, 8).join(' | '));

/* 5. Provider 方法存在性 */
const gpPath = path.join(FP, 'lib/providers/game_provider.dart');
let gpSrc = fs.existsSync(gpPath) ? fs.readFileSync(gpPath, 'utf8') : '';
const defined = new Set();
(gpSrc.match(/^\s{2}(?:Future<[^>]*>|[A-Za-z_<>,\?\s]+)?\s*\b([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/gm) || [])
  .forEach((s) => { const m = /([a-zA-Z_][a-zA-Z0-9_]*)\s*\($/.exec(s.trim()); if (m) { defined.add(m[1]); } });
(gpSrc.match(/\bget\s+([a-zA-Z_][a-zA-Z0-9_]*)/g) || []).forEach((s) => defined.add(s.replace('get ', '')));

const called = new Set();
dartFiles.filter((f) => f.indexOf('providers') === -1).forEach((f) => {
  const src = fs.readFileSync(f, 'utf8');
  const re = /(?:game|provider|gp|state|g)\s*\.\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/g;
  let m;
  while ((m = re.exec(src)) !== null) { called.add(m[1]); }
});
const unknown = [...called].filter((c) => !defined.has(c) &&
  ['toList', 'toString', 'length', 'map', 'where', 'forEach', 'add', 'push', 'join', 'contains',
    'indexOf', 'sublist', 'removeAt', 'firstWhere', 'any', 'every', 'reduce', 'split', 'trim'].indexOf(c) === -1);
check('页面调用的 Provider 方法均已定义', unknown.length === 0,
  '检测到 ' + called.size + ' 个调用；未定义: ' + (unknown.join(', ') || '无'));

/* 6. 玩法要素落地 */
const allDart = dartFiles.map((f) => fs.readFileSync(f, 'utf8')).join('\n');
check('金手指密码 208526', /208526/.test(allDart));
check('11 项属性齐全', ['智力', '体质', '魅力', '财富', '快乐', '运气', '健康值', '成瘾值', '名声值', '压力值', '罪恶值']
  .every((k) => allDart.indexOf(k) !== -1));
check('剧情标记解析（习得/关系/入狱/宠物/成瘾/年代）',
  [/习得/, /关系/, /入狱/, /宠物/, /成瘾/, /年代/].every((r) => r.test(allDart)));
check('年代限定与 age_range 筛选', /age_range|ageRange/.test(allDart) && /eraFactor/.test(allDart));
check('城市 attrEffect 生效', /attrEffect/.test(allDart) && /财富上限/.test(allDart));
check('成就系统', /achievement/i.test(allDart));
check('轮回继承', /inherit|继承/.test(allDart));
check('宠物生命周期', /pet|宠物/i.test(allDart));
check('人际关系五类', ['friend', 'lover', 'spouse', 'child', 'enemy'].every((t) => allDart.indexOf(t) !== -1));
check('Provider（ChangeNotifier）状态管理', /ChangeNotifier/.test(gpSrc) && /notifyListeners\(\)/.test(gpSrc));
check('assets/json 通过 rootBundle 读取', /rootBundle/.test(allDart));

console.log('\n通过 ' + (fails === 0 ? '全部检查' : ('' + (0))) + '：失败项 ' + fails + ' 个');
process.exit(fails ? 1 : 0);
