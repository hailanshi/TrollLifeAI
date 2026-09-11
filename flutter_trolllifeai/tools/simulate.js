// 数值与流程模拟器（开发期自检用，不属于 Flutter 工程代码）
//
// 用 JS 复刻 event_engine.dart 的关键算法（漂移 / 收入 / 开销 / 上限 / 被捕 /
// 成瘾发作 / 事件筛选 / 标记副作用），跑若干条完整人生，检查：
//   1. 不会出现 NaN / 未定义数值
//   2. 寿命分布、死亡原因分布是否合理
//   3. 事件池是否够用（是否出现连续多年没有事件）
//   4. 财富上限、负债、入狱等规则是否真的生效
//
// 用法: node tools/simulate.js

const fs = require('fs');
const path = require('path');

const dataDir = path.join(__dirname, '..', 'assets', 'json');
const read = (f) => JSON.parse(fs.readFileSync(path.join(dataDir, f), 'utf8'));

const talents = read('talents.json');
const skills = read('skills.json');
const cities = read('city.json');
const events = read('event.json');
const achievements = read('achievements.json');

const ATTRS = ['智力', '体质', '魅力', '财富', '快乐', '运气', '健康值', '成瘾值', '名声值', '压力值', '罪恶值'];
const skillIds = new Set(skills.map((s) => s.skillId));

// --- 事件标记解析（与 LifeEventMarker 一致的规则） ---
function rawMarkers(text) {
  if (typeof text !== 'string') return [];
  return (text.match(/【[^】]*】/g) || []).map((s) => s.slice(1, -1)).filter(Boolean);
}
function stripAll(text) {
  return (text || '').replace(/【[^】]*】/g, '').replace(/\s+([，。！？、；：])/g, '$1').trim();
}
const ERA_KEYWORDS = { '80年代': '80', '90年代': '90', '00年代': '00', '10年代': '10', '20年代': '20', '80': '80', '90': '90', '00': '00', '10': '10', '20': '20' };
function eraFromMarker(m) {
  const s = (m || '').trim();
  if (!s) return '';
  if (s.startsWith('年代')) {
    const parts = s.split(':');
    return parts.length >= 2 ? (ERA_KEYWORDS[parts[1].trim()] || '') : '';
  }
  return ERA_KEYWORDS[s] || '';
}
function isEraMarker(m) { return !!eraFromMarker(m); }

// 事件预处理
const EVENTS = events.map((e, idx) => {
  const eraLimit = rawMarkers(e.title).map(eraFromMarker).filter(Boolean);
  return {
    idx,
    minAge: e.age_range[0],
    maxAge: e.age_range[1],
    title: stripAll(e.title),
    rawTitle: e.title,
    story: stripAll(e.story),
    choices: e.choices,
    eraLimit: [...new Set(eraLimit)],
    allText: [e.title, e.story, ...e.choices.map((c) => c.option_text + ' ' + c.desc)].join(' '),
  };
});

// 所有标记出现情况统计
const markerKinds = {};
const unknownSkillRefs = new Set();
const missingAttrKeys = [];
EVENTS.forEach((e) => {
  const texts = [e.rawTitle, e.story, ...e.choices.map((c) => c.desc)];
  texts.forEach((t) => {
    rawMarkers(t).forEach((m) => {
      const kind = m.split(':')[0];
      markerKinds[kind] = (markerKinds[kind] || 0) + 1;
      if (kind === '习得') {
        const id = m.split(':')[1];
        if (!skillIds.has(id)) unknownSkillRefs.add(id);
      }
    });
  });
  e.choices.forEach((c) => {
    const keys = Object.keys(c.attr_change || {});
    ATTRS.forEach((k) => { if (!(k in c.attr_change)) missingAttrKeys.push(`#${e.idx} 缺 ${k}`); });
    keys.forEach((k) => { if (!ATTRS.includes(k)) missingAttrKeys.push(`#${e.idx} 多余键 ${k}`); });
  });
});

console.log('===== 数据一致性 =====');
console.log('事件数:', EVENTS.length, '| 年代限定事件:', EVENTS.filter((e) => e.eraLimit.length).length);
console.log('标记种类:', JSON.stringify(markerKinds, null, 0));
console.log('未定义的技能 id 引用:', [...unknownSkillRefs].length ? [...unknownSkillRefs].join(',') : '(无)');
console.log('attr_change 键问题:', missingAttrKeys.length ? missingAttrKeys.slice(0, 5).join('; ') : '(无)');
console.log('年龄区间:', Math.min(...EVENTS.map((e) => e.minAge)), '-', Math.max(...EVENTS.map((e) => e.maxAge)));

// --- 技能关键词 ---
const skillKeywords = {
  programming: ['代码', '编程', '互联网', '程序', '软件', 'AI', '开发', '算法'],
  cooking: ['做饭', '厨', '餐饮', '菜', '食堂', '小吃', '饭馆'],
  painting: ['画', '美术', '绘画', '设计', '插画'],
  music: ['音乐', '唱歌', '乐队', '演出', '主播', '直播'],
  foreign_language: ['外语', '英语', '留学', '出国', '外企', '移民', '翻译'],
  medical: ['医院', '手术', '生病', '治疗', '医', '病', '体检'],
  sport: ['体育', '运动', '比赛', '跑步', '篮球', '足球', '健身'],
  business: ['创业', '投资', '生意', '谈判', '公司', '融资', '做生意'],
  photography: ['摄影', '拍照', '相机', '短视频', '自媒体', '镜头'],
  car_repair: ['汽修', '修车', '汽车', '修理', '技师'],
  driving: ['司机', '驾驶', '外卖', '网约车', '开车', '货运', '骑手'],
  finance: ['理财', '股票', '基金', '投资', '金融', '存款', '收益'],
  law: ['官司', '法律', '律师', '诉讼', '维权', '合同'],
  nursing: ['护理', '护士', '照顾', '病房', '养老'],
  teaching: ['教师', '老师', '教育', '讲课', '培训', '考试', '补习'],
  hospitality: ['酒店', '餐饮', '服务员', '前台', '民宿', '客栈'],
  ecommerce: ['电商', '淘宝', '网店', '带货', '直播', '快递', '店铺'],
  writing: ['写作', '写书', '小说', '文案', '回忆录', '编辑', '稿费'],
  barber: ['理发', '美发', '剪头', '发廊'],
  welding: ['电焊', '焊工', '工地', '技工', '工厂', '车间'],
  first_aid: ['急救', '救人', '意外', '受伤', '抢救'],
  budgeting: ['记账', '省钱', '预算', '开销', '攒钱'],
  gardening: ['园艺', '种花', '种菜', '院子', '盆栽'],
  pet_care: ['宠物', '猫', '狗', '流浪', '兽医'],
  makeup: ['化妆', '造型', '美妆', '颜值'],
  fitness: ['健身', '锻炼', '体能', '跑步', '瑜伽'],
  meditation: ['冥想', '静坐', '禅', '放松', '心理咨询'],
  self_defense: ['防身', '打架', '暴力', '冲突', '抢', '抢劫'],
  negotiation_life: ['砍价', '谈判', '纠纷', '讨价', '协商', '和解'],
};

const WEALTH_CAP_BASE = 300000;

function makeChar(era, city, talent) {
  const attrs = { 智力: 50, 体质: 50, 魅力: 50, 财富: 0, 快乐: 60, 运气: 50, 健康值: 70, 成瘾值: 0, 名声值: 0, 压力值: 20, 罪恶值: 0 };
  Object.entries(talent.attrModify).forEach(([k, v]) => { attrs[k] = (attrs[k] || 0) + v; });
  return {
    era, cityName: city.cityName, capFactor: city.attrEffect['财富上限'], stressMod: city.attrEffect['压力值'],
    age: 0, attrs, talent: talent.name, skills: [], addictions: { 烟瘾: 0, 酒瘾: 0, 网瘾: 0, 赌瘾: 0 },
    debt: 0, cash: attrs['财富'] < 0 ? 0 : attrs['财富'], relations: [], pets: [], fired: new Set(),
    eraEventsSeen: new Set(), alive: true, deathAge: -1, deathReason: '', hasJob: false, career: '无',
    careerLevel: 0, unemployed: false, retired: false, jailed: false, jailLeft: 0, totalJail: 0,
    house: false, car: false, log: [], hospitalYears: 0, lowHealthYears: 0, eventYears: 0, emptyYears: 0,
    maxSingleGain: 0, lifespan: (Math.random() < 0.02 ? 100 + Math.floor(Math.random() * 11) : 72 + Math.floor(Math.random() * 24)),
  };
}
if (false) makeChar;

function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }
function applyDelta(c, delta) {
  const applied = {};
  Object.entries(delta).forEach(([k, v]) => {
    if (!v) return;
    const before = c.attrs[k];
    let after = before + v;
    if (k === '财富') {
      const cap = Math.round(WEALTH_CAP_BASE * c.capFactor);
      if (after > cap) after = cap;
      c.cash = after;
    } else if (['健康值', '快乐', '压力值', '成瘾值', '罪恶值', '名声值'].includes(k)) {
      after = clamp(after, 0, 100);
    } else {
      after = clamp(after, 0, 200);
    }
    if (after === before) return;
    c.attrs[k] = after;
    applied[k] = after - before;
  });
  return applied;
}

function successBonus(c, ev) {
  let hits = 0;
  c.skills.forEach((id) => {
    const words = skillKeywords[id] || [];
    if (words.some((w) => ev.allText.includes(w))) hits++;
  });
  let bonus = Math.min(hits * 0.07, 0.35);
  let luckBonus = clamp((c.attrs['运气'] - 50) / 500, -0.1, 0.1);
  return bonus + luckBonus;
}

function pickEvents(c, maxCount = 2) {
  const pool = EVENTS.filter((e) => c.age >= e.minAge && c.age <= e.maxAge
    && (e.eraLimit.length === 0 || e.eraLimit.includes(c.era))
    && !c.fired.has(e.rawTitle));
  const picked = [];
  if (pool.some((e) => e.eraLimit.length) && !c.eraEventsSeen.has(c.era)) {
    const locked = pool.filter((e) => e.eraLimit.length);
    const chosen = locked[Math.floor(Math.random() * locked.length)];
    picked.push(chosen); c.fired.add(chosen.rawTitle); c.eraEventsSeen.add(c.era);
  }
  const rest = pool.filter((e) => e.eraLimit.length === 0);
  while (picked.length < maxCount && rest.length) {
    const i = Math.floor(Math.random() * rest.length);
    const e = rest.splice(i, 1)[0];
    if (picked.some((p) => p.rawTitle === e.rawTitle)) continue;
    picked.push(e); c.fired.add(e.rawTitle);
  }
  return picked;
}

function computeIncome(c) {
  if (c.unemployed && !c.retired) return 0;
  if (c.retired) return Math.round(12000 * c.capFactor);
  let base;
  if (c.age < 12) base = 2000;
  else if (c.age < 16) base = 6000;
  else if (c.age < 18) base = Math.round(24000 * c.capFactor);
  else if (c.career === '无' && !c.hasJob) base = Math.round(30000 * c.capFactor);
  else {
    base = Math.round(52000 * c.capFactor) + c.careerLevel * 15000;
    if (c.skills.includes('programming') || c.skills.includes('finance')) base = Math.round(base * 1.15);
  }
  const cap = Math.round(WEALTH_CAP_BASE * c.capFactor);
  const room = cap - c.attrs['财富'];
  if (room <= 0) return 0;
  return Math.min(base, room);
}

const DEBT_INTEREST_CAP = 8000;
const DEBT_HARD_LIMIT = 1500000;
const DEBT_WRITE_OFF = 1000000;
const ADDICTION_GROWTH = 2;

function creditLimit(c) {
  if (c.age < 16) return 20000;
  let limit = Math.round(150000 * c.capFactor);
  if (c.hasJob || c.career !== '无') limit += 100000;
  if (c.house) limit += 200000;
  return Math.max(limit, 20000);
}

function computeLivingCost(c) {
  let scale = 1.0;
  if (c.age < 7) scale = 0.15;
  else if (c.age < 12) scale = 0.25;
  else if (c.age < 16) scale = 0.35;
  else if (c.age < 20) scale = 0.55;
  else if (c.age < 45) scale = 0.7;
  else if (c.age < 60) scale = 0.75;
  else scale = 0.8;
  let cost = 24000 * c.capFactor * scale;
  if (c.house) cost += 6000;
  if (c.car) cost += 8000;
  cost += c.pets.filter((p) => p.alive).length * 3000;
  cost += c.relations.filter((r) => r.type === 'child' && r.alive).length * 6000;
  if (c.skills.includes('budgeting')) cost *= 0.85;
  return Math.round(cost);
}

function naturalDrift(age) {
  if (age <= 6) return { 健康值: 2, 快乐: 1, 压力值: -3 };
  if (age <= 17) return { 健康值: 2, 快乐: 1, 压力值: -2 };
  if (age <= 35) return { 健康值: 1 };
  if (age <= 55) return { 压力值: 1, 快乐: -1 };
  if (age <= 70) return { 健康值: -1, 快乐: -1 };
  return { 健康值: -3, 压力值: -1, 快乐: -1 };
}

function applyMarkers(c, markers) {
  markers.forEach((m) => {
    const parts = m.split(':');
    const kind = parts[0];
    if (isEraMarker(kind) || kind === '年代' || kind === '年代限定') return;
    switch (kind) {
      case '习得': {
        const id = parts[1];
        if (id && skillIds.has(id) && !c.skills.includes(id)) c.skills.push(id);
        break;
      }
      case '宠物': c.pets.push({ name: parts[1] || '猫', alive: true, hasOffspring: false }); break;
      case '宠物生病': { const p = c.pets.find((x) => x.alive); if (p) c.cash -= 3000; break; }
      case '宠物走失': break;
      case '宠物繁育': { const p = c.pets.find((x) => x.alive); if (p) { p.hasOffspring = true; c.pets.push({ name: '幼崽', alive: true, hasOffspring: false }); } break; }
      case '宠物离世': { const p = c.pets.find((x) => x.alive); if (p) p.alive = false; break; }
      case '关系': c.relations.push({ name: parts[2] || parts[1], type: parts[1], alive: true }); break;
      case '关系结束': { const r = c.relations.find((x) => x.name === parts[1]); if (r) r.alive = false; break; }
      case '职业': c.career = parts[1]; c.hasJob = true; c.unemployed = false; break;
      case '升职': c.careerLevel++; break;
      case '失业': c.unemployed = true; c.hasJob = false; break;
      case '跳槽': c.hasJob = true; c.unemployed = false; c.careerLevel++; break;
      case '创业': c.hasJob = true; c.cash -= 40000; break;
      case '破产': c.unemployed = true; c.cash = 0; c.debt += 60000; break;
      case '入狱': c.jailed = true; c.jailLeft = parseInt(parts[1], 10) || 3; c.unemployed = true; break;
      case '出狱': c.jailed = false; c.jailLeft = 0; break;
      case '案底': break;
      case '减刑': if (c.jailLeft > 1) c.jailLeft--; else { c.jailed = false; c.jailLeft = 0; } break;
      case '买房': { const p = Math.round(400000 * c.capFactor); c.cash -= p; c.house = true; break; }
      case '买车': c.cash -= 150000; c.car = true; break;
      case '奢侈品': c.cash -= 20000; break;
      case '保险': c.cash -= 6000; break;
      case '负债': c.debt += parseInt(parts[1], 10) || 10000; break;
      case '还债': { const amt = parseInt(parts[1], 10) || 10000; c.cash -= amt; c.debt -= amt; if (c.debt < 0) { c.cash += -c.debt; c.debt = 0; } break; }
      case '成瘾': { const n = parts[1]; if (n) c.addictions[n] = clamp((c.addictions[n] || 0) + 15, 0, 100); break; }
      case '戒断': { const n = parts[1]; if (n) c.addictions[n] = clamp((c.addictions[n] || 0) - 40, 0, 100); break; }
      default: break;
    }
  });
}

function syncAddictionAttr(c) {
  const vals = Object.values(c.addictions);
  c.attrs['成瘾值'] = vals.length ? clamp(Math.floor(vals.reduce((a, b) => a + b, 0) / vals.length), 0, 100) : 0;
}

function runLife(seedNote) {
  const era = ['80', '90', '00', '10', '20'][Math.floor(Math.random() * 5)];
  const city = cities.filter((x) => x.eraFactor[era])[Math.floor(Math.random() * cities.filter((x) => x.eraFactor[era]).length)];
  const talent = talents[Math.floor(Math.random() * talents.length)];
  const c = makeChar(era, city, talent);
  const stats = { events: 0, emptyYears: 0, maxYearEvents: 0, jailYears: 0, breaks: 0, maxDebt: 0, maxWealth: 0, peakAddiction: 0, peakSin: 0, healthFromChoices: 0, writeOffs: 0 };
  let guard = 0;

  while (c.alive && guard++ < 300) {
    c.age += 1;
    if (c.age > c.lifespan + 5) break;

    if (c.jailed && c.jailLeft > 0) {
      c.jailLeft--; c.totalJail += 1; stats.jailYears++;
      if (c.jailLeft === 0) c.jailed = false;
      if (c.age >= c.lifespan) { c.alive = false; c.deathReason = '寿命'; c.deathAge = c.age; }
      continue;
    }

    const delta = { ...naturalDrift(c.age) };
    delta['压力值'] = (delta['压力值'] || 0) + c.stressMod;
    if (c.talent === '睡眠质量王') { delta['健康值'] = (delta['健康值'] || 0) + 2; }
    if (c.skills.includes('fitness')) delta['健康值'] = (delta['健康值'] || 0) + 1;
    if (c.skills.includes('meditation')) delta['压力值'] = (delta['压力值'] || 0) - 2;
    const income = computeIncome(c);
    if (income) delta['财富'] = (delta['财富'] || 0) + income;
    const cost = computeLivingCost(c);
    if (cost) delta['财富'] = (delta['财富'] || 0) - cost;
    // 自动还债（只在现金还宽裕时）
    if (c.debt > 0 && income > 0) {
      const projected = c.cash + (delta['财富'] || 0);
      if (projected > 0) {
        let repay = Math.min(Math.round(income * 0.3), c.debt, projected);
        if (repay > 0) { c.debt -= repay; delta['财富'] = (delta['财富'] || 0) - repay; }
      }
    }
    if (c.debt > 0) {
      let interest = Math.round(c.debt * 0.03);
      if (interest > DEBT_INTEREST_CAP) interest = DEBT_INTEREST_CAP;
      delta['财富'] = (delta['财富'] || 0) - interest;
      delta['压力值'] = (delta['压力值'] || 0) + 2;
    }
    applyDelta(c, delta);
    let cashGap = 0;
    if (c.cash < 0) {
      cashGap = -c.cash; c.cash = 0;
      const limit = creditLimit(c);
      const borrow = clamp(limit - c.debt, 0, cashGap);
      c.debt += borrow;
      c.attrs['财富'] = 0;
    }
    if (c.attrs['健康值'] <= 30) applyDelta(c, { 健康值: -1 });

    // 成瘾自然增长
    Object.keys(c.addictions).forEach((k) => { if (c.addictions[k] > 0) c.addictions[k] = clamp(c.addictions[k] + ADDICTION_GROWTH, 0, 100); });
    syncAddictionAttr(c);

    // 被捕
    if (c.attrs['罪恶值'] >= 60) {
      const chance = clamp(0.05 + (c.attrs['罪恶值'] - 60) / 100, 0.05, 0.6);
      if (Math.random() < chance) {
        c.jailed = true; c.jailLeft = 2 + Math.floor(Math.random() * 4); c.unemployed = true;
        applyDelta(c, { 罪恶值: -10, 快乐: -10, 名声值: -10 });
      }
    }
    // 安分守己慢慢洗白
    if (c.attrs['罪恶值'] > 0 && c.hasJob && !c.unemployed) applyDelta(c, { 罪恶值: -2 });
    // 成瘾发作
    if (c.attrs['成瘾值'] >= 60) {
      const chance = clamp((c.attrs['成瘾值'] - 60) / 120 + 0.12, 0, 0.55);
      if (Math.random() < chance) {
        stats.breaks++;
        const name = Object.entries(c.addictions).sort((a, b) => b[1] - a[1])[0][0];
        const pickIdx = Math.floor(Math.random() * 3);
        const ch = [ { 成瘾值: -18, 健康值: -4 }, { 成瘾值: -12, 健康值: -2 }, { 成瘾值: 12, 健康值: -7 } ][pickIdx];
        applyDelta(c, ch);
        c.addictions[name] = clamp(c.addictions[name] + (pickIdx === 2 ? 12 : -18), 0, 100);
        syncAddictionAttr(c);
        if (pickIdx !== 2) applyMarkers(c, [`戒断:${name}`]);
      }
    }

    // 事件
    const picked = pickEvents(c);
    if (picked.length === 0) stats.emptyYears++;
    stats.events += picked.length;
    stats.maxYearEvents = Math.max(stats.maxYearEvents, picked.length);
    picked.forEach((ev) => {
      // 「理智玩家」：如果有不作恶的选项，70% 概率不选犯罪选项
      let choiceIdx = Math.floor(Math.random() * ev.choices.length);
      if (Math.random() < 0.7) {
        const ok = ev.choices.map((ch, i) => ({ ch, i })).filter((x) => (x.ch.attr_change['罪恶值'] || 0) <= 0);
        if (ok.length) choiceIdx = ok[Math.floor(Math.random() * ok.length)].i;
      }
      const ch = ev.choices[choiceIdx];
      const bonus = successBonus(c, ev);
      const success = Math.random() < clamp(0.72 + bonus, 0.05, 0.99);
      const factor = (success && bonus > 0) ? 1 + bonus : (success ? 1 : 0.7);
      const scaled = {};
      Object.entries(ch.attr_change).forEach(([k, v]) => { scaled[k] = Math.round(v * factor); });
      const applied = applyDelta(c, scaled);
      stats.healthFromChoices += (applied['健康值'] || 0);
      if (applied['财富'] > c.maxSingleGain) c.maxSingleGain = applied['财富'];
      applyMarkers(c, rawMarkers(ch.desc));
      syncAddictionAttr(c);
    });

    // 负债硬上限清算
    if (c.debt >= DEBT_HARD_LIMIT) {
      c.debt = Math.max(0, c.debt - DEBT_WRITE_OFF);
      c.house = false; c.car = false;
      applyDelta(c, { 快乐: -10, 压力值: 10 });
      stats.writeOffs++;
    }

    stats.maxDebt = Math.max(stats.maxDebt, c.debt);
    stats.maxWealth = Math.max(stats.maxWealth, c.attrs['财富']);
    stats.peakAddiction = Math.max(stats.peakAddiction, c.attrs['成瘾值']);
    stats.peakSin = Math.max(stats.peakSin, c.attrs['罪恶值']);

    // 死亡判定
    if (c.attrs['健康值'] <= 0) { c.alive = false; c.deathReason = '健康归零'; c.deathAge = c.age; break; }
    if (c.age >= c.lifespan) { c.alive = false; c.deathReason = '寿终正寝'; c.deathAge = c.age; break; }
    if (c.age >= 60) c.retired = true;
  }
  if (guard >= 300) stats.runaway = true;

  // 数值健康检查
  Object.entries(c.attrs).forEach(([k, v]) => {
    if (typeof v !== 'number' || Number.isNaN(v)) throw new Error(`属性 ${k} 非法: ${v}`);
  });
  if (Number.isNaN(c.debt) || c.debt < 0) throw new Error(`负债非法: ${c.debt}`);
  if (Number.isNaN(c.cash)) throw new Error('现金 NaN');
  return { c, stats, era, talent: talent.name };
}

console.log('\n===== 模拟 300 条人生 =====');
const N = 300;
const ages = []; const reasons = {}; const eras = {}; const talentCount = {};
let emptyYearsTotal = 0; let eventTotal = 0; let jailLives = 0; let breakLives = 0;
let maxWealthOverall = 0; let capHits = 0; let maxDebtOverall = 0; let runaway = 0;
let netWorthSum = 0; let healthGain = 0; let writeOffs = 0; let hundred = 0;
for (let i = 0; i < N; i++) {
  const { c, stats, era, talent } = runLife();
  ages.push(c.deathAge >= 0 ? c.deathAge : c.age);
  reasons[c.deathReason || '未知'] = (reasons[c.deathReason || '未知'] || 0) + 1;
  eras[era] = (eras[era] || 0) + 1;
  talentCount[talent] = (talentCount[talent] || 0) + 1;
  emptyYearsTotal += stats.emptyYears; eventTotal += stats.events;
  if (c.totalJail > 0) jailLives++;
  if (stats.breaks > 0) breakLives++;
  maxWealthOverall = Math.max(maxWealthOverall, c.attrs['财富']);
  if (c.attrs['财富'] >= Math.round(WEALTH_CAP_BASE * c.capFactor)) capHits++;
  maxDebtOverall = Math.max(maxDebtOverall, c.debt);
  if (stats.runaway) runaway++;
  netWorthSum += c.attrs['财富'] - c.debt;
  healthGain += stats.healthFromChoices;
  writeOffs += stats.writeOffs;
  if (c.deathAge >= 100) hundred++;
}
ages.sort((a, b) => a - b);
const avg = (arr) => arr.reduce((a, b) => a + b, 0) / arr.length;
console.log('寿命: 平均', avg(ages).toFixed(1), '最短', ages[0], '中位', ages[Math.floor(N / 2)], '最长', ages[N - 1], '| ≥100岁', hundred);
console.log('死因分布:', JSON.stringify(reasons));
console.log('年代分布:', JSON.stringify(eras));
console.log('事件总数', eventTotal, '| 平均每年', (eventTotal / avg(ages)).toFixed(2), '| 无事件年数占比', (emptyYearsTotal / ages.reduce((a, b) => a + b, 0) * 100).toFixed(1) + '%');
console.log('坐过牢的人生占比:', (jailLives / N * 100).toFixed(1) + '%', '| 经历过成瘾发作:', (breakLives / N * 100).toFixed(1) + '%');
console.log('最高财富(采样)', maxWealthOverall, '| 触顶次数', capHits, '| 最高负债', maxDebtOverall, '| 债务清算次数', writeOffs);
console.log('平均净资产', Math.round(netWorthSum / N), '| 事件带来的健康净变化总和', healthGain);
console.log('异常（循环未终止）:', runaway);
console.log('天赋覆盖种类:', Object.keys(talentCount).length, '/', talents.length, '| 成就总数', achievements.length);
console.log('\n数值与流程模拟通过（无 NaN / 无未终止循环）。');

// ---------------------------------------------------------------------------
// 诊断模式：node tools/simulate.js --diag
// 打印一条人生的逐年负债来源，用于排查数值膨胀
// ---------------------------------------------------------------------------
if (process.argv.includes('--diag')) {
  const city = cities.find((x) => x.cityName === '二线城市');
  const talent = talents.find((t) => t.name === '天资聪颖');
  const c = makeChar('00', city, talent);
  let guard = 0;
  console.log('\nage\t收入\t标记负债\t现金缺口转债\t总负债\t财富\t健康');
  while (c.alive && guard++ < 200) {
    c.age += 1;
    if (c.jailed && c.jailLeft > 0) {
      c.jailLeft--; c.totalJail++;
      if (c.jailLeft === 0) c.jailed = false;
      continue;
    }
    const delta = { ...naturalDrift(c.age) };
    delta['压力值'] = (delta['压力值'] || 0) + c.stressMod;
    const income = computeIncome(c);
    if (income) delta['财富'] = (delta['财富'] || 0) + income;
    const cost = computeLivingCost(c);
    if (cost) delta['财富'] = (delta['财富'] || 0) - cost;
    let interest = 0;
    if (c.debt > 0) { interest = Math.min(Math.round(c.debt * 0.04), DEBT_INTEREST_CAP); delta['财富'] = (delta['财富'] || 0) - interest; }
    applyDelta(c, delta);
    let cashGap = 0;
    if (c.cash < 0) { cashGap = -c.cash; c.debt += cashGap; c.cash = 0; c.attrs['财富'] = 0; }
    const picked = pickEvents(c);
    let markerDebt = 0;
    picked.forEach((ev) => {
      const ch = ev.choices[0];
      const scaled = {};
      Object.entries(ch.attr_change).forEach(([k, v]) => { scaled[k] = Math.round(v); });
      applyDelta(c, scaled);
      const before = c.debt;
      applyMarkers(c, rawMarkers(ch.desc));
      markerDebt += c.debt - before;
      syncAddictionAttr(c);
    });
    console.log([c.age, income, markerDebt, cashGap, c.debt, c.attrs['财富'], c.attrs['健康值']].join('\t'));
    if (c.attrs['健康值'] <= 0 || c.age >= c.lifespan) { c.alive = false; break; }
    if (c.age >= 60) c.retired = true;
  }
}
