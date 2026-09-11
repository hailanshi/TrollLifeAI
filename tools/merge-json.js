/**
 * merge-json.js —— TrollLifeAI 数据合并 / 校验脚本
 *
 * 作用：
 *   1. 读取工作区根目录下 5 份「原始 JSON」（只读，绝不修改）；
 *   2. 读取 build/patches 下的新增内容补丁；
 *   3. 严格校验：原始条目必须 100% 保留（深比较）、事件 attr_change 必须齐全 11 项、数值必须为整数、
 *      技能标记必须存在于 skills.json、标题不得重复；
 *   4. 输出合并后的完整 5 份 JSON 到 assets/json/（原始内容在前，新增内容追加在数组末尾）；
 *   5. 生成 build/data-report.json 校验报告。
 *
 * 用法： node tools/merge-json.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const PATCH_DIR = path.join(ROOT, 'build', 'patches');
const OUT_DIR = path.join(ROOT, 'assets', 'json');

const ATTR_KEYS = ['智力', '体质', '魅力', '财富', '快乐', '运气', '健康值', '成瘾值', '名声值', '压力值', '罪恶值'];
const TALENT_KEYS = ['智力', '体质', '魅力', '财富', '快乐', '运气'];
const EVENT_KEYS = ['age_range', 'title', 'story', 'choices'];
const CHOICE_KEYS = ['option_text', 'attr_change', 'desc'];
const CITY_KEYS = ['cityName', 'eraFactor', 'desc', 'attrEffect'];
const SKILL_KEYS = ['skillId', 'name', 'desc', 'effect'];
const ACH_KEYS = ['name', 'desc', 'trigger'];
const ERAS = ['80', '90', '00', '10', '20'];

const report = { generatedAt: new Date().toISOString(), files: {}, errors: [], warnings: [], markers: {} };
const errors = (m) => report.errors.push(m);
const warns = (m) => report.warnings.push(m);

function readJson(p) {
  const raw = fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '');
  return JSON.parse(raw);
}
function readPatch(name) {
  const p = path.join(PATCH_DIR, name);
  if (!fs.existsSync(p)) return [];
  return readJson(p);
}
function isInt(v) {
  return typeof v === 'number' && isFinite(v) && Math.floor(v) === v;
}
function sameKeys(obj, keys, label, where) {
  const got = Object.keys(obj);
  const missing = keys.filter((k) => got.indexOf(k) === -1);
  const extra = got.filter((k) => keys.indexOf(k) === -1);
  if (missing.length) errors(`${label} @${where} 缺少字段: ${missing.join(',')}`);
  if (extra.length) warns(`${label} @${where} 多余字段: ${extra.join(',')}`);
  return missing.length === 0 && extra.length === 0;
}
function deepEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

/* ---------------- 1. 原始数据（只读） ---------------- */
const originals = {
  talents: readJson(path.join(ROOT, 'talents.json')),
  achievements: readJson(path.join(ROOT, 'achievements.json')),
  skills: readJson(path.join(ROOT, 'skills.json')),
  city: readJson(path.join(ROOT, 'city.json')),
  event: readJson(path.join(ROOT, 'event.json')),
};
Object.keys(originals).forEach((k) => {
  if (!Array.isArray(originals[k])) errors(`原始 ${k}.json 顶层不是数组`);
  report.files[k] = { original: originals[k].length };
});

/* ---------------- 2. 补丁数据 ---------------- */
const patches = {
  talents: readPatch('talents.patch.json'),
  achievements: readPatch('achievements.patch.json'),
  skills: readPatch('skills.patch.json'),
  city: readPatch('city.patch.json'),
  event: [].concat(
    readPatch('events_a.json'),
    readPatch('events_b.json'),
    readPatch('events_c.json'),
    readPatch('events_d.json')
  ),
};

/* ---------------- 3. 校验：原有条目字段 ---------------- */
originals.talents.forEach((t, i) => {
  sameKeys(t, ['name', 'desc', 'attrModify'], '天赋', `talents[${i}]`);
  sameKeys(t.attrModify, TALENT_KEYS, '天赋attrModify', `talents[${i}]`);
});
originals.city.forEach((c, i) => {
  sameKeys(c, CITY_KEYS, '城市', `city[${i}]`);
  sameKeys(c.eraFactor, ERAS, '城市eraFactor', `city[${i}]`);
});
originals.skills.forEach((s, i) => sameKeys(s, SKILL_KEYS, '技能', `skills[${i}]`));
originals.achievements.forEach((a, i) => sameKeys(a, ACH_KEYS, '成就', `achievements[${i}]`));
originals.event.forEach((e, i) => {
  sameKeys(e, EVENT_KEYS, '事件', `event[${i}]`);
  (e.choices || []).forEach((c, j) => {
    sameKeys(c, CHOICE_KEYS, '选项', `event[${i}].choices[${j}]`);
    sameKeys(c.attr_change, ATTR_KEYS, '选项attr_change', `event[${i}].choices[${j}]`);
  });
});

/* ---------------- 4. 校验并规范化新增内容 ---------------- */
function normAttr(a, label) {
  const out = {};
  ATTR_KEYS.forEach((k) => {
    let v = a ? a[k] : 0;
    if (typeof v !== 'number' || !isFinite(v)) {
      if (v !== 0) warns(`${label} 属性 ${k} 非法(${JSON.stringify(v)})，已置 0`);
      v = 0;
    }
    if (!isInt(v)) {
      warns(`${label} 属性 ${k} 为小数(${v})，已取整`);
      v = Math.round(v);
    }
    out[k] = v;
  });
  return out;
}

const knownSkillIds = originals.skills.concat(patches.skills).map((s) => s.skillId);
const MARKER_RE = /【([^】]+)】/g;
const markerCount = {};
function scanMarkers(text, where) {
  if (typeof text !== 'string') return;
  let m;
  MARKER_RE.lastIndex = 0;
  while ((m = MARKER_RE.exec(text)) !== null) {
    const body = m[1];
    const head = body.split(':')[0];
    markerCount[head] = (markerCount[head] || 0) + 1;
    if (head === '习得') {
      const id = body.split(':')[1];
      if (knownSkillIds.indexOf(id) === -1) errors(`${where} 技能标记 【习得:${id}】 不存在于 skills.json`);
    }
  }
}

// 4.1 天赋
patches.talents.forEach((t, i) => {
  const w = `新增天赋[${i}]`;
  if (!t.name || !t.desc) errors(`${w} 缺少 name/desc`);
  sameKeys(t.attrModify || {}, TALENT_KEYS, '天赋attrModify', w);
  Object.keys(t.attrModify || {}).forEach((k) => {
    if (!isInt(t.attrModify[k])) errors(`${w}.attrModify.${k} 必须是整数`);
  });
});

// 4.2 城市
patches.city.forEach((c, i) => {
  const w = `新增城市[${i}]`;
  sameKeys(c, CITY_KEYS, '城市', w);
  sameKeys(c.eraFactor || {}, ERAS, '城市eraFactor', w);
  Object.keys(c.eraFactor || {}).forEach((k) => {
    if (typeof c.eraFactor[k] !== 'boolean') errors(`${w}.eraFactor.${k} 必须是布尔值`);
  });
  if (!isInt(c.attrEffect['压力值'])) errors(`${w}.attrEffect.压力值 必须是整数`);
  if (typeof c.attrEffect['财富上限'] !== 'number') errors(`${w}.attrEffect.财富上限 必须是数字`);
});

// 4.3 技能
patches.skills.forEach((s, i) => {
  const w = `新增技能[${i}]`;
  sameKeys(s, SKILL_KEYS, '技能', w);
  if (knownSkillIds.filter((x) => x === s.skillId).length > 1) errors(`${w} skillId 重复: ${s.skillId}`);
});

// 4.4 成就
patches.achievements.forEach((a, i) => sameKeys(a, ACH_KEYS, '成就', `新增成就[${i}]`));

// 4.5 事件
const normEvents = patches.event.map((e, i) => {
  const w = `新增事件[${i}]`;
  sameKeys(e, EVENT_KEYS, '事件', w);
  if (!Array.isArray(e.age_range) || e.age_range.length !== 2 || !isInt(e.age_range[0]) || !isInt(e.age_range[1])) {
    errors(`${w} age_range 必须是两个整数`);
  } else if (e.age_range[0] > e.age_range[1]) {
    errors(`${w} age_range 起始年龄大于结束年龄`);
  }
  if (!e.title || !e.story) errors(`${w} 缺少 title/story`);
  if (!Array.isArray(e.choices) || e.choices.length < 1) errors(`${w} choices 不能为空`);
  const choices = (e.choices || []).map((c, j) => {
    const cw = `${w}.choices[${j}]`;
    if (!c.option_text || !c.desc) errors(`${cw} 缺少 option_text/desc`);
    const hasAll = ATTR_KEYS.every((k) => c.attr_change && Object.prototype.hasOwnProperty.call(c.attr_change, k));
    if (!hasAll) warns(`${cw} attr_change 缺字段，已自动补 0`);
    scanMarkers(c.desc, cw);
    return { option_text: c.option_text, attr_change: normAttr(c.attr_change, cw), desc: c.desc };
  });
  return { age_range: e.age_range, title: e.title, story: e.story, choices: choices };
});

/* ---------------- 4.6 新增事件的年龄纠偏（用共用规则表；原始 35 条一个字都不改） ---------------- */
const AGE_RULES = (() => {
  try {
    return readJson(path.join(ROOT, 'src', 'age-rules.json')).ageRules || [];
  } catch (e) { return []; }
})();
const ageAdjusted = [];
function eventFullText(ev) {
  let t = (ev.title || '') + ' ' + (ev.story || '');
  (ev.choices || []).forEach((c) => { t += ' ' + (c.option_text || '') + ' ' + (c.desc || ''); });
  return t;
}
function effectiveRange(ev) {
  const a = ev.age_range[0], b = ev.age_range[1];
  let lo = a, hi = b;
  const text = eventFullText(ev);
  AGE_RULES.forEach((r) => {
    if (!r.kw || !new RegExp(r.kw).test(text)) { return; }
    if (typeof r.min === 'number' && r.min > lo) { lo = r.min; }
    if (typeof r.max === 'number' && r.max < hi) { hi = r.max; }
  });
  if (lo > hi) { return [a, b]; }   /* 规则冲突 → 保留原区间 */
  return [lo, hi];
}
normEvents.forEach((e) => {
  const r = effectiveRange(e);
  if (r[0] !== e.age_range[0] || r[1] !== e.age_range[1]) {
    ageAdjusted.push({ title: e.title, from: e.age_range.slice(0), to: r.slice(0) });
    e.age_range = r;
  }
});
if (ageAdjusted.length) {
  report.ageAdjusted = ageAdjusted;
}

/* ---------------- 5. 重复检查 ---------------- */
function dupCheck(list, keyFn, label) {
  const seen = {};
  list.forEach((item, i) => {
    const k = keyFn(item);
    if (seen[k] !== undefined) errors(`${label} 重复：${k}（索引 ${seen[k]} 与 ${i}）`);
    seen[k] = i;
  });
}
const allEvents = originals.event.concat(normEvents);
dupCheck(allEvents, (e) => e.title, '事件标题');
dupCheck(originals.talents.concat(patches.talents), (t) => t.name, '天赋名称');
dupCheck(originals.achievements.concat(patches.achievements), (a) => a.name, '成就名称');
dupCheck(knownSkillIds, (s) => s, '技能ID');
dupCheck(originals.city.concat(patches.city), (c) => c.cityName, '城市名称');

/* ---------------- 6. 合并写出 ---------------- */
const merged = {
  talents: originals.talents.concat(patches.talents),
  achievements: originals.achievements.concat(patches.achievements),
  skills: originals.skills.concat(patches.skills),
  city: originals.city.concat(patches.city),
  event: originals.event.concat(normEvents),
};

if (report.errors.length === 0) {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  Object.keys(merged).forEach((k) => {
    // 原始条目必须与源文件逐字段一致（深比较），确保「原有内容全部保留不动」
    const n = originals[k].length;
    for (let i = 0; i < n; i++) {
      if (!deepEqual(merged[k][i], originals[k][i])) errors(`${k}.json 第 ${i} 条原始内容被改动！`);
    }
  });
}

if (report.errors.length === 0) {
  Object.keys(merged).forEach((k) => {
    fs.writeFileSync(path.join(OUT_DIR, `${k}.json`), JSON.stringify(merged[k], null, 4) + '\n', 'utf8');
    report.files[k].merged = merged[k].length;
    report.files[k].added = merged[k].length - originals[k].length;
  });
}

report.markers = markerCount;
report.eventAgeBuckets = {};
merged.event.forEach((e) => {
  const k = e.age_range.join('-');
  report.eventAgeBuckets[k] = (report.eventAgeBuckets[k] || 0) + 1;
});
report.totalEvents = merged.event.length;
report.totalAchievements = merged.achievements.length;
report.totalSkills = merged.skills.length;
report.totalTalents = merged.talents.length;
report.totalCities = merged.city.length;
report.attrKeyCheck = ATTR_KEYS.join(',');

fs.writeFileSync(path.join(ROOT, 'build', 'data-report.json'), JSON.stringify(report, null, 2), 'utf8');

console.log('=== 合并结果 ===');
Object.keys(report.files).forEach((k) => {
  const f = report.files[k];
  console.log(`${k}.json  原始 ${f.original} 条 -> 合并后 ${f.merged === undefined ? '(未写出)' : f.merged} 条  (+${f.added === undefined ? '?' : f.added})`);
});
console.log('事件年龄分布:', JSON.stringify(report.eventAgeBuckets));
if (ageAdjusted.length) {
  console.log('\n按规则纠偏年龄的新增事件（' + ageAdjusted.length + ' 条）：');
  ageAdjusted.forEach((a) => {
    console.log('  ' + a.from.join('-') + ' -> ' + a.to.join('-') + '   ' + a.title);
  });
}
console.log('标记统计:', JSON.stringify(markerCount));
console.log('错误:', report.errors.length, '  警告:', report.warnings.length);
report.errors.slice(0, 40).forEach((e) => console.log('  [ERR] ' + e));
report.warnings.slice(0, 20).forEach((e) => console.log('  [WARN] ' + e));
process.exit(report.errors.length ? 1 : 0);
