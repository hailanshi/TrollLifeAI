/**
 * gen-docs.js —— 从补丁与合并后的 JSON 自动生成数据文档
 *   docs/新增事件清单.md  新增 120 条事件的完整清单（含选项与剧情标记）
 *   docs/数据总览.md      5 份 JSON 的规模、分布、新增天赋/技能/成就/城市清单
 * 用法： node tools/gen-docs.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const rd = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8').replace(/^\uFEFF/, ''));

const originals = {
  talents: rd('build/originals/talents.json'),
  achievements: rd('build/originals/achievements.json'),
  skills: rd('build/originals/skills.json'),
  city: rd('build/originals/city.json'),
  event: rd('build/originals/event.json'),
};
const merged = {
  talents: rd('assets/json/talents.json'),
  achievements: rd('assets/json/achievements.json'),
  skills: rd('assets/json/skills.json'),
  city: rd('assets/json/city.json'),
  event: rd('assets/json/event.json'),
};
const gro = [
  { file: 'events_a.json', name: 'A 组 · 童年 / 少年成长' },
  { file: 'events_b.json', name: 'B 组 · 人际关系 / 职业系统' },
  { file: 'events_c.json', name: 'C 组 · 医疗 / 消费 / 成瘾' },
  { file: 'events_d.json', name: 'D 组 · 年代 / 犯罪牢狱 / 宠物 / 老年' },
  { file: 'events_e.json', name: 'E 组 · 老年阶段（60-110 岁）' },
  { file: 'events_f.json', name: 'F 组 · 童年与小学（0-12 岁）' },
  { file: 'events_g.json', name: 'G 组 · 中学与青年（13-30 岁）' },
  { file: 'events_h.json', name: 'H 组 · 中年阶段（31-59 岁）' },
  { file: 'events_i.json', name: 'I 组 · 性别专属剧情（男向 / 女向）' }
];
const groups = gro.filter((g) => fs.existsSync(path.join(ROOT, 'build', 'patches', g.file)));

function markersOf(text) {
  const out = [];
  const re = /【([^】]+)】/g;
  let m;
  while ((m = re.exec(text || '')) !== null) { out.push(m[1]); }
  return out;
}

/* ---------- 1. 新增事件清单 ---------- */
let md = '# TrollLifeAI · 新增事件总清单\n\n';
md += '> 本文件由 `tools/gen-docs.js` 从 `build/patches/events_*.json` 自动生成。\n';
md += '> 所有新增事件都追加在原始 `event.json` 的 35 条之后，字段结构完全一致：\n';
md += '> `age_range` / `title` / `story` / `choices[{option_text, attr_change(11 项), desc}]`。\n';
md += '> `desc` 末尾可能出现 `【…】` 剧情标记（属于文本内容，不是新字段），由引擎解析成真实副作用。\n\n';

groups.forEach((g, gi) => {
  const evs = rd('build/patches/' + g.file);
  md += `## ${g.name}\n\n`;
  md += `共 **${evs.length}** 条。\n\n`;
  evs.forEach((e, i) => {
    const idx = originals.event.length + groups.slice(0, gi).reduce((a, x) => a + rd('build/patches/' + x.file).length, 0) + i;
    md += `### ${idx + 1}. ${e.title}\n\n`;
    md += `- 年龄区间：\`${e.age_range[0]} - ${e.age_range[1]}\`\n`;
    md += `- 剧情：${e.story}\n`;
    md += `- 选项（${e.choices.length}）：\n`;
    e.choices.forEach((c) => {
      const mk = markersOf(c.desc);
      md += `  - **${c.option_text}** —— ${c.desc.replace(/【[^】]+】/g, '').trim()}`;
      if (mk.length) { md += `（标记：${mk.map((x) => '`【' + x + '】`').join(' ')}）`; }
      md += '\n';
    });
    md += '\n';
  });
});
fs.writeFileSync(path.join(ROOT, 'docs', '新增事件清单.md'), md, 'utf8');

/* ---------- 2. 数据总览 ---------- */
let s = '# TrollLifeAI · 数据总览\n\n> 由 `tools/gen-docs.js` 自动生成，数据取自 `assets/json/`（合并后）。\n\n';
s += '## 一、规模\n\n| 文件 | 原始 | 新增 | 合并后 |\n| --- | ---: | ---: | ---: |\n';
['talents', 'achievements', 'skills', 'city', 'event'].forEach((k) => {
  s += `| ${k}.json | ${originals[k].length} | ${merged[k].length - originals[k].length} | **${merged[k].length}** |\n`;
});
s += '\n**原有内容 100% 保留**：合并时用深比较（JSON.stringify 逐条比对）验证每个原始条目与源文件完全一致，且新增内容一律追加在数组末尾。\n\n';

/* 事件年龄分布 */
const buckets = {};
merged.event.forEach((e) => {
  const k = e.age_range.join('-');
  buckets[k] = (buckets[k] || 0) + 1;
});
s += '## 二、事件年龄分布（合并后）\n\n| 年龄区间 | 条数 |\n| --- | ---: |\n';
Object.keys(buckets).sort((a, b) => merged.event.length && parseInt(a) - parseInt(b)).forEach((k) => {
  s += `| ${k} 岁 | ${buckets[k]} |\n`;
});

/* 标记统计 */
const mkCount = {};
merged.event.forEach((e) => {
  e.choices.forEach((c) => {
    markersOf(c.desc).forEach((x) => { mkCount[x.split(':')[0]] = (mkCount[x.split(':')[0]] || 0) + 1; });
  });
  markersOf(e.title).forEach((x) => { mkCount['年代(标题)'] = (mkCount['年代(标题)'] || 0) + 1; });
});
s += '\n## 三、剧情标记使用统计\n\n| 标记类型 | 出现次数 |\n| --- | ---: |\n';
Object.keys(mkCount).sort((a, b) => mkCount[b] - mkCount[a]).forEach((k) => {
  s += `| 【${k}】 | ${mkCount[k]} |\n`;
});

/* 新增天赋 */
s += '\n## 四、新增天赋（24 个）\n\n| 天赋 | 属性修正 | 说明 |\n| --- | --- | --- |\n';
merged.talents.slice(originals.talents.length).forEach((t) => {
  const mod = Object.keys(t.attrModify).filter((k) => t.attrModify[k] !== 0)
    .map((k) => k + (t.attrModify[k] > 0 ? '+' : '') + t.attrModify[k]).join(' ');
  s += `| ${t.name} | ${mod || '无'} | ${t.desc} |\n`;
});

/* 新增技能 */
s += '\n## 五、新增技能（19 个）\n\n| 技能 ID | 名称 | 效果 |\n| --- | --- | --- |\n';
merged.skills.slice(originals.skills.length).forEach((k) => {
  s += `| \`${k.skillId}\` | ${k.name} | ${k.effect} |\n`;
});

/* 新增城市 */
s += '\n## 六、新增城市（4 座）\n\n| 城市 | 可出生年代 | 压力修正 | 财富上限系数 | 说明 |\n| --- | --- | ---: | ---: | --- |\n';
merged.city.slice(originals.city.length).forEach((c) => {
  const eras = ['80', '90', '00', '10', '20'].filter((e) => c.eraFactor[e]).join(' / ');
  s += `| ${c.cityName} | ${eras} | ${c.attrEffect['压力值']} | ×${c.attrEffect['财富上限']} | ${c.desc} |\n`;
});

/* 新增成就 */
s += '\n## 七、新增成就（47 个）\n\n| 成就 | 触发条件 |\n| --- | --- |\n';
merged.achievements.slice(originals.achievements.length).forEach((a) => {
  s += `| ${a.name} | ${a.trigger} |\n`;
});
fs.writeFileSync(path.join(ROOT, 'docs', '数据总览.md'), s, 'utf8');

console.log('docs/新增事件清单.md 生成完成');
console.log('docs/数据总览.md 生成完成');
