// 页面 ↔ Provider 方法对照检查
// 提取 lib/pages 与 lib/widgets 里对 GameProvider 的成员访问，与 provider 定义比对。

const fs = require('fs');
const path = require('path');

const root = process.argv[2] || '.';
const libDir = path.join(root, 'lib');

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

const all = walk(libDir, []);
const providerSrc = fs.readFileSync(path.join(libDir, 'providers', 'game_provider.dart'), 'utf8');

// 提取 provider 的成员名（字段/方法/getter）
const members = new Set();
const memberRe = /^\s{2}(?:final\s+|const\s+|static\s+)*([A-Za-z_$][\w$<>,\s\[\]?]*?)\s+([A-Za-z_$][\w$]*)\s*(\(|;|=)/gm;
let m;
while ((m = memberRe.exec(providerSrc)) !== null) members.add(m[2]);
// getter / setter
const getterRe = /^\s{2}(?:[A-Za-z_$][\w$<>,\s\[\]?]*?)\s+get\s+([A-Za-z_$][\w$]*)/gm;
while ((m = getterRe.exec(providerSrc)) !== null) members.add(m[1]);

const ownPrivate = new Set();
for (const name of members) if (name.startsWith('_')) ownPrivate.add(name);

const consumers = all.filter((f) => !f.includes('providers') && !f.includes('services') && !f.includes('models'));
const missing = [];
const usage = {};

for (const file of consumers) {
  const src = fs.readFileSync(file, 'utf8');
  const rel = path.relative(root, file).replace(/\\/g, '/');
  // game.xxx / provider.xxx / <GameProvider>.xxx
  const re = /\b(?:game|provider|gp|p)\s*\.\s*([A-Za-z_$][\w$]*)/g;
  while ((m = re.exec(src)) !== null) {
    const name = m[1];
    if (!members.has(name)) missing.push(`${rel}: game.${name}`);
    usage[name] = (usage[name] || new Set()).add(rel);
  }
  // context.read<GameProvider>().xxx / watch
  const re2 = /(?:read|watch)<GameProvider>\(\)\s*\.\s*([A-Za-z_$][\w$]*)/g;
  while ((m = re2.exec(src)) !== null) {
    const name = m[1];
    if (!members.has(name)) missing.push(`${rel}: provider.${name}`);
    usage[name] = (usage[name] || new Set()).add(rel);
  }
}

console.log('===== Provider 成员被页面调用的情况 =====');
const sorted = Object.keys(usage).sort();
for (const name of sorted) {
  const files = Array.from(usage[name]).map((f) => f.replace('lib/pages/', '').replace('lib/widgets/', ''));
  console.log(`${name.padEnd(28)} <- ${files.join(', ')}`);
}

console.log('\n===== 疑似不存在于 GameProvider 的成员 =====');
if (missing.length === 0) console.log('(无)');
else missing.forEach((s) => console.log('  ' + s));

// 未被任何页面调用的公开成员（提示用）
const unused = [];
for (const name of members) {
  if (name.startsWith('_')) continue;
  if (/^(init|dispose|toString|hashCode|runtimeType|notifyListeners|addListener|removeListener)$/.test(name)) continue;
  if (!usage[name]) unused.push(name);
}
console.log('\n===== GameProvider 中未被页面调用的公开成员 =====');
console.log(unused.sort().join(', ') || '(无)');
process.exit(missing.length ? 1 : 0);
