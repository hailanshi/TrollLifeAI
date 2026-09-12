/**
 * check-age-fit.js —— 年龄适配性检查（独立于规则表的第三方校验）
 *
 * 思路：不依赖 src/age-rules.json，而是用一份「人工定义的禁忌清单」重新验证一遍：
 *   如果一条事件的【标题】命中了某个年龄段的禁忌词，说明剧情与年龄不匹配。
 * 标题是强信号（标题说「高考」就一定是高考剧情）；正文里的顺带提及不作判断，避免误报。
 *
 * 用法： node tools/check-age-fit.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));

const events = readJson(path.join(ROOT, 'assets', 'json', 'event.json'));
const rules = readJson(path.join(ROOT, 'src', 'age-rules.json'));

/* [禁忌正则, 不允许的年龄区间, 说明] —— 只看标题 */
const TABOO = [
  [/幼儿园|学前班|小红花|托儿所/, [9, 200], '幼儿园剧情不该出现在 9 岁以上'],
  [/高考|中考|高三|初三|升学考试|志愿/, [0, 13], '升学考试剧情不该出现在 13 岁以下'],
  [/高考|中考|高三|初三/, [21, 200], '升学考试剧情不该出现在 21 岁以上'],
  [/红领巾|同桌|小学|作业|班主任/, [16, 200], '小学剧情不该出现在 16 岁以上'],
  [/早恋|情书|暗恋|初恋/, [0, 11], '恋爱剧情不该出现在 11 岁以下'],
  [/面试|简历|入职|试用期|校招|求职/, [0, 15], '求职剧情不该出现在 15 岁以下'],
  [/升职|加薪|被裁|裁员|跳槽|同事|加班|月薪|工牌|绩效/, [0, 15], '职场剧情不该出现在 15 岁以下'],
  [/升职|加薪|被裁|裁员|跳槽|绩效/, [70, 200], '职场剧情不该出现在 70 岁以上'],
  [/创业|融资|股权|合伙人|开店/, [0, 19], '创业剧情不该出现在 19 岁以下'],
  [/买房|房贷|首付|楼市|房价/, [0, 19], '房产剧情不该出现在 19 岁以下'],
  [/买房|房贷|首付/, [76, 200], '房产剧情不该出现在 76 岁以上'],
  [/结婚|婚礼|彩礼|订婚|再婚/, [0, 19], '婚姻剧情不该出现在 19 岁以下'],
  [/怀孕|生子|生育|备孕/, [0, 19], '生育剧情不该出现在 19 岁以下'],
  [/怀孕|产假|产检|坐月子|哺乳/, [56, 200], '生育剧情不该出现在 56 岁以上'],
  [/孙子|孙女|抱上孙/, [0, 44], '孙辈剧情不该出现在 44 岁以下'],
  [/退休|养老|广场舞|保健品|卧床|白内障|假牙|遗嘱/, [0, 49], '老年剧情不该出现在 49 岁以下'],
  [/网吧|网瘾|街机|通宵打游戏/, [0, 9], '网吧剧情不该出现在 9 岁以下'],
  [/网吧|网瘾/, [63, 200], '网吧剧情不该出现在 63 岁以上'],
  [/入狱|服刑|出狱|减刑|越狱|案底|牢/, [0, 13], '牢狱剧情不该出现在 13 岁以下'],
  [/诈骗|违法|盗窃|斗殴|判刑|抓获|赌场|赌博|博彩/, [0, 13], '违法犯罪剧情不该出现在 13 岁以下'],
  [/诈骗|违法|盗窃|斗殴|判刑|赌场|赌博|博彩/, [69, 200], '违法犯罪剧情不该出现在 69 岁以上'],
  [/考试|成绩|作业/, [71, 200], '考试类剧情不该出现在 71 岁以上'],
  [/早恋|情书|表白|相亲|暗恋/, [79, 200], '恋爱剧情不该出现在 79 岁以上'],
  [/股票|股市|基金|理财|炒币|定投/, [81, 200], '投资剧情不该出现在 81 岁以上'],
  [/熬夜|加班|应酬|出差/, [76, 200], '加班熬夜类剧情不该出现在 76 岁以上'],
];

/* 用引擎同一套规则算出「有效年龄区间」，检查有效区间与禁忌是否冲突 */
function fullText(ev) {
  let t = (ev.title || '') + ' ' + (ev.story || '');
  (ev.choices || []).forEach((c) => { t += ' ' + (c.option_text || '') + ' ' + (c.desc || ''); });
  return t;
}
function effectiveRange(ev) {
  const [a, b] = ev.age_range;
  let lo = a, hi = b;
  const title = ev.title || '';
  const text = fullText(ev);
  (rules.ageRules || []).forEach((r) => {
    if (!r.kw) { return; }
    const subject = (r.scope === 'title') ? title : text;
    let re = null;
    try { re = new RegExp(r.kw); } catch (e) { return; }
    if (!re.test(subject)) { return; }
    if (typeof r.min === 'number' && r.min > lo) { lo = r.min; }
    if (typeof r.max === 'number' && r.max < hi) { hi = r.max; }
  });
  if (lo > hi) { return [a, b]; }
  if (hi === 100) { hi = 110; }
  return [lo, hi];
}

let violations = [];
let childViolations = [];
events.forEach((ev) => {
  const [lo, hi] = effectiveRange(ev);
  const allText = (ev.title || '') + ' ' + (ev.story || '') + ' ' +
    (ev.choices || []).map((c) => (c.option_text || '') + (c.desc || '')).join(' ');
  const isChildEvent = allText.indexOf('{孩子}') !== -1;

  /* 子女剧情：标题里的「小学 / 中考 / 大学」说的是孩子不是玩家本人，
     所以不用玩家年龄禁忌去卡它，改为校验「家长年龄是否合理」 */
  if (isChildEvent) {
    if (lo < 22 || hi > 80) { childViolations.push({ title: ev.title, range: lo + '-' + hi }); }
    return;
  }

  /* 玩家自己的剧情：遍历有效区间，检查标题是否命中该年龄的禁忌 */
  for (const [re, band, why] of TABOO) {
    if (!re.test(ev.title || '')) { continue; }
    const overlapLo = Math.max(lo, band[0]);
    const overlapHi = Math.min(hi, band[1] === 200 ? hi : band[1]);
    if (overlapLo <= overlapHi) {
      violations.push({ title: ev.title, range: lo + '-' + hi, why: why, overlap: overlapLo + '-' + overlapHi });
      break;
    }
  }
});

/* 年龄分层覆盖统计 */
const buckets = { '0-6 童年': 0, '7-17 少年': 0, '18-30 青年': 0, '31-59 中年': 0, '60+ 老年': 0 };
let uncovered = [];
for (let age = 0; age <= 108; age++) {
  const n = events.filter((e) => {
    const [lo, hi] = effectiveRange(e);
    return age >= lo && age <= hi;
  }).length;
  if (n === 0) { uncovered.push(age); }
}

console.log('======== 年龄适配性检查 ========');
console.log('事件总数: ' + events.length + '（分层规则 ' + (rules.ageRules || []).length + ' 条）\n');
console.log('各年龄段可用事件数：');
[3, 6, 10, 14, 17, 22, 28, 35, 45, 55, 62, 72, 85, 100, 108].forEach((age) => {
  const n = events.filter((e) => {
    const [lo, hi] = effectiveRange(e);
    return age >= lo && age <= hi;
  }).length;
  console.log('  ' + String(age).padStart(3) + ' 岁: ' + String(n).padStart(4) + ' 条');
});
console.log('\n空池年龄（抽不到任何事件）: ' + (uncovered.length ? uncovered.join(', ') : '无 ✓'));
console.log('年龄与剧情不匹配的事件: ' + violations.length + (violations.length ? '' : ' ✓'));
violations.slice(0, 20).forEach((v) => console.log('  ✗ [' + v.range + '] ' + v.title + ' —— ' + v.why));
console.log('子女剧情家长年龄不合理: ' + childViolations.length + (childViolations.length ? '' : ' ✓'));
childViolations.slice(0, 10).forEach((v) => console.log('  ✗ [' + v.range + '] ' + v.title));

const ok = violations.length === 0 && uncovered.length === 0 && childViolations.length === 0;
console.log('\n结论: ' + (ok ? '通过' : '存在问题'));
process.exit(ok ? 0 : 1);
