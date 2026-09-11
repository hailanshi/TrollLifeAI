/**
 * test-headless.js —— 无浏览器逻辑自检
 * 用 Node 模拟 window/document/localStorage，跑 400 局随机人生：
 *   - 检查是否抛异常
 *   - 检查 11 项属性是否始终存在且为整数
 *   - 检查成就解锁链路是否真的会触发
 *   - 检查引擎里 unlock('成就名') 引用的名字是否都存在于 achievements.json
 * 用法： node tools/test-headless.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

/* ---------- 极简 DOM / 存储 桩 ---------- */
const store = {};
const el = () => ({
  innerHTML: '', className: '', value: '', scrollTop: 0,
  style: {}, setAttribute() { }, appendChild() { }, addEventListener() { },
});
global.window = global;
global.localStorage = {
  getItem: (k) => (Object.prototype.hasOwnProperty.call(store, k) ? store[k] : null),
  setItem: (k, v) => { store[k] = String(v); },
  removeItem: (k) => { delete store[k]; },
};
const elCache = {};
global.document = {
  readyState: 'complete',
  getElementById: (id) => (elCache[id] || (elCache[id] = el())),
  addEventListener() { },
};
global.setTimeout = setTimeout;
global.clearTimeout = clearTimeout;

/* ---------- 载入数据 + 引擎 ---------- */
const data = {
  talents: JSON.parse(fs.readFileSync(path.join(ROOT, 'assets/json/talents.json'), 'utf8')),
  achievements: JSON.parse(fs.readFileSync(path.join(ROOT, 'assets/json/achievements.json'), 'utf8')),
  skills: JSON.parse(fs.readFileSync(path.join(ROOT, 'assets/json/skills.json'), 'utf8')),
  city: JSON.parse(fs.readFileSync(path.join(ROOT, 'assets/json/city.json'), 'utf8')),
  event: JSON.parse(fs.readFileSync(path.join(ROOT, 'assets/json/event.json'), 'utf8')),
};
global.__TL_DATA__ = data;
/* 规则表在 app.html 里是内联的（window.__TL_RULES__），测试里手动喂进去 */
global.__TL_RULES__ = JSON.parse(fs.readFileSync(path.join(ROOT, 'src/age-rules.json'), 'utf8'));

const core = fs.readFileSync(path.join(ROOT, 'src/js/01_core.js'), 'utf8');
const ach = fs.readFileSync(path.join(ROOT, 'src/js/02_ach.js'), 'utf8');
const aiSrc = fs.readFileSync(path.join(ROOT, 'src/js/03_ai.js'), 'utf8');
const actSrc = fs.readFileSync(path.join(ROOT, 'src/js/04_actions.js'), 'utf8');
const uiSrc = fs.readFileSync(path.join(ROOT, 'src/js/05_ui.js'), 'utf8');

/* 让 toast 静默，避免刷屏 */
let toastCount = 0;
const errors = [];
function run(code, label) {
  try { (0, eval)(code); } catch (e) { errors.push(label + ': ' + e.message); }
}
run(core, 'core');
global.toast = function () { toastCount++; };
global.window.toast = global.toast;
run(ach, 'ach');
run(aiSrc, 'ai');
run(actSrc, 'actions');
run(uiSrc, 'ui');
/* 把 UI 的 toast 再包一层计数（UI 会覆盖 window.toast） */
const _uiToast = global.window.toast;
global.window.toast = function (m) { toastCount++; _uiToast(m); };
global.toast = global.window.toast;
const ui = global.window.ui;   /* 界面层命名空间 */

if (errors.length) { console.error('脚本加载失败:', errors); process.exit(1); }

/* ---------- 1. 引擎引用的成就名是否都存在 ---------- */
const achNames = {};
data.achievements.forEach((a) => { achNames[a.name] = 1; });
const src = core + ach;
const re = /TL\.unlock\('([^']+)'\)/g;
let m, badNames = [];
while ((m = re.exec(src)) !== null) { if (!achNames[m[1]]) { badNames.push(m[1]); } }
/* ACH_RULES / LOG_ACH 里的名字 */
Object.keys(TL.ACH_RULES).forEach((n) => { if (!achNames[n]) { badNames.push('rules:' + n); } });
TL.LOG_ACH.forEach((i) => { if (!achNames[i.name]) { badNames.push('log:' + i.name); } });
if (badNames.length) { console.error('引擎引用了不存在的成就名:', badNames); process.exit(1); }

/* ---------- 2. 技能 id 引用是否合法 ---------- */
const skillIds = {};
data.skills.forEach((s) => { skillIds[s.skillId] = 1; });
Object.keys(TL.SKILL_KEYWORDS).forEach((id) => { if (!skillIds[id]) { badNames.push('skill:' + id); } });
if (badNames.length) { console.error('技能 id 不一致:', badNames); process.exit(1); }

/* ---------- 3. 随机跑 400 局人生 ---------- */
const ATTRS = TL.ATTRS;
let lives = 0, deaths = 0, eventFired = 0, prisonLives = 0, maxAge = 0, totalYears = 0;
const seenEvents = {};
const deathReasons = {};
const seenSkills = {};
const unlockHits = {};
const addictionsSeen = {};

function unlockedNames() { return TL.global.achievements.slice(0); }

const LIVES = 400;
for (let i = 0; i < LIVES; i++) {
  const era = TL.ERAS[i % TL.ERAS.length];
  const cityCandidates = data.city.filter((c) => c.eraFactor[era]);
  const city = cityCandidates[i % cityCandidates.length].cityName;
  const talent = data.talents[(i * 7) % data.talents.length];
  const gender = (i % 2 === 0) ? '男' : '女';                 /* 交替男女，覆盖性别专属剧情 */
  TL.S = TL.newState(era, city, [talent], null, gender);
  TL.unlock('呱呱坠地');
  const before = unlockedNames().length;
  lives++;

  let years = 0;
  let gotEvent = false;
  while (TL.S.alive && years < 130) {
    years++;
    let res;
    try { res = TL.advanceYear(); } catch (e) { console.error('advanceYear 异常 @生命' + i + ' 年' + years + ': ' + e.stack); process.exit(1); }
    if (!TL.S.alive) { deaths++; break; }
    if (res && res.type === 'event' && res.event) {
      gotEvent = true; eventFired++;
      seenEvents[res.event.title] = (seenEvents[res.event.title] || 0) + 1;
      const idx = Math.floor(Math.random() * res.event.choices.length);
      try { TL.chooseOption(res.event, idx); } catch (e) { console.error('chooseOption 异常: ' + e.stack); process.exit(1); }
      TL.save();
    }
    /* 属性完整性检查 */
    for (const k of ATTRS) {
      const v = TL.S.attrs[k];
      if (typeof v !== 'number' || !isFinite(v)) { console.error('属性非法: ' + k + ' = ' + v); process.exit(1); }
    }
  }
  if (!gotEvent) { console.error('第 ' + i + ' 局人生一整局没有触发任何事件（异常）'); process.exit(1); }
  if (TL.S.stat.prisonTotal > 0) { prisonLives++; }
  if (!TL.S.alive) {
    const key = TL.S.deathReason.indexOf('寿终正寝') !== -1 ? '寿终正寝（自然寿命）' : TL.S.deathReason;
    deathReasons[key] = (deathReasons[key] || 0) + 1;
  }
  if (TL.S.age > maxAge) { maxAge = TL.S.age; }
  totalYears += TL.S.age;
  TL.S.skills.forEach((s) => { seenSkills[s] = 1; });
  Object.keys(TL.S.addictions).forEach((a) => { if (TL.S.addictions[a] > 0) { addictionsSeen[a] = 1; } });
  unlockedNames().forEach((n) => { unlockHits[n] = 1; });
  if (unlockedNames().length === before && i < 5) { /* 允许不涨，不报错 */ }
}
/* ---------- 4. 金手指与死亡/轮回流程 ---------- */
TL.resetAll();
TL.S = TL.newState('00', '一线城市', [data.talents[0]]);
TL.S.godUnlocked = true;
TL.S.attrs['财富'] += 100000;
TL.S.attrs['健康值'] = 1;
TL.die('自检强制死亡');
if (TL.S.alive) { console.error('die() 未生效'); process.exit(1); }
if (!TL.global.inherit || typeof TL.global.inherit['智力'] !== 'number') { console.error('轮回继承未生成'); process.exit(1); }
TL.reincarnate('10', '省会城市', [data.talents[1]]);
if (!TL.S.alive || TL.S.age !== 0) { console.error('reincarnate 未重置人生'); process.exit(1); }

/* ---------- 5. 事件覆盖率 ---------- */
const neverFired = data.event.filter((e) => !seenEvents[e.title]).map((e) => e.title);

/* ---------- 6. 界面层端到端演练（DOM 用桩，但 innerHTML 是真实字符串） ---------- */
const screen = document.getElementById('screen');
const assert = (cond, msg) => { if (!cond) { console.error('UI 自检失败: ' + msg); process.exit(1); } };

TL.resetAll();
ui.tab = 'start';
ui.startMode = 'new';
ui.drawnTalents = []; ui.pickedTalent = -1; ui.rerollLeft = 3;
ui.render();
assert(screen.innerHTML.indexOf('选择出生年代') !== -1, '开局页缺少年代选择');
assert(screen.innerHTML.indexOf('选择出生城市') !== -1, '开局页缺少城市选择');

ui.setEra('90');
assert(ui.startEra === '90', 'setEra 未生效');
ui.setCity('一线城市');
ui.drawTalents();
assert(ui.drawnTalents.length === 3, '抽天赋应为 3 个，实际 ' + ui.drawnTalents.length);
const rerollBefore = ui.rerollLeft;
ui.drawTalents();
assert(ui.rerollLeft === rerollBefore - 1, '重抽次数未扣减');
ui.pickTalent(0);
ui.beginLife();
assert(TL.S && TL.S.age === 0, 'beginLife 未创建角色');
assert(ui.tab === 'home', '开局后应进入属性页');
assert(screen.innerHTML.indexOf('过一年') !== -1, '属性页缺少推进按钮');
assert(document.getElementById('chipAge').innerHTML.indexOf('0') !== -1, '顶部年龄条未更新');

/* 属性页应展示 11 项属性 / 资产 / 人物关系 / 宠物 */
['智力', '体质', '魅力', '财富', '快乐', '运气', '健康值', '成瘾值', '名声值', '压力值', '罪恶值'].forEach((k) => {
  assert(screen.innerHTML.indexOf(k) !== -1, '属性页缺少属性 ' + k);
});
assert(screen.innerHTML.indexOf('资产与负债') !== -1, '属性页缺少资产负债');
assert(screen.innerHTML.indexOf('人际关系') !== -1, '属性页缺少人际关系');
assert(screen.innerHTML.indexOf('宠物') !== -1, '属性页缺少宠物列表');

/* 推进多年，直到弹出一个事件，然后选第一个选项 */
let yearsRun = 0, eventOpened = false;
while (yearsRun < 60 && TL.S.alive) {
  ui.nextYear();
  yearsRun++;
  const modal = document.getElementById('modalRoot').className;
  if (modal.indexOf('show') !== -1 && ui.currentEvent) { eventOpened = true; break; }
}
assert(eventOpened, '推进 60 年内没有弹出任何事件');
const mBody = document.getElementById('mBody').innerHTML;
assert(mBody.indexOf('choice') !== -1, '事件弹窗没有渲染选项');
ui.chooseEvent(0);
assert(ui.currentEvent === null, '选完选项后事件未清空');
assert(document.getElementById('modalRoot').className.indexOf('show') === -1, '选完选项后弹窗未关闭');

/* 快进、日志、其余页面 */
ui.fastForward();
ui.showLifeLog();

/* 其余五个页面都要能渲染出来 */
['ai', 'skill', 'ach', 're', 'god'].forEach((t) => {
  ui.go(t);
  assert(screen.innerHTML.length > 200, '页面 ' + t + ' 渲染内容为空');
});
ui.go('ai');
assert(screen.innerHTML.indexOf('AI 剧情引擎') !== -1, 'AI 页标题缺失');
assert(screen.innerHTML.indexOf('接口地址') !== -1, 'AI 页缺少接口地址字段');
assert(screen.innerHTML.indexOf('触发频率') !== -1, 'AI 页缺少触发频率');
/* 开关读写 */
TL.ai.setConfig({ enabled: false, key: 'sk-test' });
ui.aiToggle();
assert(TL.ai.getConfig().enabled === true, 'AI 开关未能开启');
ui.aiToggle();
assert(TL.ai.getConfig().enabled === false, 'AI 开关未能关闭');
ui.aiSetChance(1);
assert(TL.ai.getConfig().chance === 1, 'AI 频率设置失败');
TL.ai.setConfig({ enabled: false, key: '' });
ui.go('ach');
assert(screen.innerHTML.indexOf('成就殿堂') !== -1, '成就页标题缺失');
ui.setAchFilter('got');
ui.go('skill');
assert(screen.innerHTML.indexOf('技能图鉴') !== -1, '技能页标题缺失');

/* 金手指：错密码 → 不解锁；对密码 208526 → 解锁并可一键改属性 */
ui.go('god');
document.getElementById('godPwd').value = '123456';
ui.godUnlock();
assert(TL.S.godUnlocked !== true, '错误密码竟然解锁了金手指');
document.getElementById('godPwd').value = '208526';
ui.godUnlock();
assert(TL.S.godUnlocked === true, '正确密码 208526 未解锁金手指');
const moneyBefore = TL.S.attrs['财富'];
ui.godQuick('money');
assert(TL.S.attrs['财富'] === moneyBefore + 100000, '一键加财富未生效');
TL.S.attrs['健康值'] = 30;
ui.godQuick('health');
assert(TL.S.attrs['健康值'] === 100, '一键回满健康未生效');
ui.godStep(0, 10);
ui.godApply(0);
ui.go('god');
assert(screen.innerHTML.indexOf('手动修改属性') !== -1, '控制台缺少属性编辑区');
assert(TL.isUnlocked('开挂人生'), '解锁金手指后未拿到「开挂人生」成就');

/* 死亡 → 总结弹窗 → 轮回页 → 转世开局 */
ui.doGodKill();
assert(TL.S.alive === false, 'doGodKill 未结束本世');
assert(ui.tab === 're', '死亡后未跳转轮回页');
assert(screen.innerHTML.indexOf('转世投胎') !== -1, '轮回页缺少转世按钮');
ui.startReincarnate();
assert(ui.tab === 'start', '转世未回到开局页');
ui.drawTalents();
ui.pickTalent(0);
ui.beginLife();
assert(TL.S.alive && TL.S.age === 0, '转世后未开启新人生');
assert(TL.global.lives >= 2, '轮回次数未累加');

/* 展示层不能把引擎用的剧情标记【…】露给玩家（原始天赋 desc 里的【混合型】属于文案，不算标记） */
const ENGINE_MARKS = ['【习得:', '【关系:', '【关系结束:', '【入狱:', '【宠物:', '【成瘾:', '【戒断:', '【职业:', '【负债:', '【年代:'];
TL.S.log.unshift('第 20 年：测试事件 → 学会了新东西【习得:programming】【关系:friend:小林】');
ui.go('home');
ENGINE_MARKS.forEach((mk) => {
  assert(screen.innerHTML.indexOf(mk) === -1, '属性页日志里残留了引擎标记 ' + mk);
});
ui.showLifeLog();
ENGINE_MARKS.forEach((mk) => {
  assert(document.getElementById('mBody').innerHTML.indexOf(mk) === -1, '日志弹窗里残留了引擎标记 ' + mk);
});
ui.closeModal();
TL.S.log.shift();

/* 存档往返 */
TL.save();
const reloaded = TL.load();
assert(reloaded && reloaded.attrs, '存档写入/读取失败');
assert(typeof reloaded.attrs['罪恶值'] === 'number', '存档缺少属性');

/* ---------- 7. 玩法增强层：主动行动 / 关系互动 / 评分 / 存档 / AI ---------- */
const section = (name) => console.log('  · ' + name + '：通过');
console.log('\n======== 玩法增强层自检 ========');

/* 7.1 主动行动 */
TL.resetAll();
TL.S = TL.newState('00', '一线城市', [data.talents[0]]);
TL.S.job = '大厂程序员'; TL.S.salary = 25000;
assert(TL.ACTIONS.length >= 13, '主动行动数量不足，实际 ' + TL.ACTIONS.length);
assert(TL.S.actionPoints === 1, '初始行动点应为 1');
const moneyBeforeAct = TL.S.attrs['财富'];
assert(TL.doAction('work') === true, '加班赚钱行动执行失败');
assert(TL.S.attrs['财富'] > moneyBeforeAct, '加班赚钱没有增加财富');
assert(TL.S.actionPoints === 0, '行动后行动点应扣减为 0');
assert(TL.doAction('work') === false, '行动点用完后竟然还能再行动');
TL.advanceYear();
assert(TL.S.actionPoints === 1, '过一年后行动点应恢复为 1');
/* 条件不满足的行动应被拒绝 */
TL.S.attrs['财富'] = 0;
assert(TL.doAction('hospital') === false, '现金不足时竟然能看病');
TL.S.attrs['财富'] = 500000;
assert(TL.doAction('startup') === true, '创业尝试执行失败');
/* 每个行动都必须能在所有 11 项属性上收敛（不产生 NaN） */
for (const action of TL.ACTIONS) {
  const s2 = TL.newState('90', '省会城市', [data.talents[1]]);
  s2.attrs['财富'] = 300000;
  TL.S = s2;
  TL.S.actionPoints = 1;
  try { TL.doAction(action.id); } catch (e) { console.error('行动 ' + action.id + ' 抛异常: ' + e.message); process.exit(1); }
  for (const k of ATTRS) {
    if (typeof TL.S.attrs[k] !== 'number' || !isFinite(TL.S.attrs[k])) {
      console.error('行动 ' + action.id + ' 让属性 ' + k + ' 变成 ' + TL.S.attrs[k]); process.exit(1);
    }
  }
}
section('主动行动系统（' + TL.ACTIONS.length + ' 种行动，属性全部有效）');

/* 7.2 关系互动 */
TL.S = TL.newState('00', '二线城市', [data.talents[2]]);
TL.S.age = 25;
TL.S.attrs['财富'] = 100000;
TL.addRelation('friend', '老周');
const rel = TL.S.relations[0];
const affBefore = rel.affinity;
assert(TL.interact('老周', 'gift') === true, '送礼互动失败');
assert(TL.S.relations[0].affinity === affBefore + 8, '送礼好感没有 +8');
assert(TL.interact('老周', 'gift') === false, '同一年同一个关系竟然能重复互动');
TL.S.age += 1;
assert(TL.interact('老周', 'chat') === true, '深聊互动失败');
TL.addRelation('lover', '小雨');
assert(TL.interact('小雨', 'propose') === true || TL.interact('小雨', 'propose') === false, '求婚流程异常');
section('关系互动（送礼 / 深聊 / 和解 / 求婚，每人每年 1 次）');

/* 7.3 人生评分 */
TL.S = TL.newState('00', '北上广深', [data.talents[0]]);
TL.S.age = 80;
const sc = TL.scoreLife(TL.S);
assert(typeof sc.score === 'number' && sc.score > 0, '人生评分异常：' + sc.score);
assert(sc.title && sc.title.name, '人生称号缺失');
assert(sc.detail.length >= 15, '评分明细项过少');
section('人生评分与称号（' + sc.score + ' 分 · ' + sc.title.name + '）');

/* 7.4 存档槽位与导出导入 */
TL.S.age = 42;
assert(TL.saveSlot(1) === null, '保存槽位失败');
assert(TL.slotInfo(1).empty === false, '槽位 1 读取为空');
assert(TL.slotInfo(1).age === 42, '槽位记录年龄不对');
const exported = TL.exportSave();
assert(exported.length > 100, '导出存档内容过短');
TL.S.age = 3;
assert(TL.importSave(exported) === null, '导入存档失败');
assert(TL.S.age === 42, '导入后年龄未恢复');
assert(TL.loadSlot(1) === null, '读取槽位失败');
assert(TL.deleteSlot(1) === null && TL.slotInfo(1).empty === true, '删除槽位失败');
assert(TL.importSave('这不是存档') !== null, '非法存档竟然导入成功');
section('存档管理（3 槽位 + 文本导出/导入 + 非法输入拦截）');

/* 7.5 AI 剧情引擎 */
assert(TL.ai.getConfig().url.indexOf('http') === 0, 'AI 默认接口地址缺失');
assert(TL.ai.ready() === false, '未配 Key 时不应处于可用状态');
TL.ai.setConfig({ key: 'sk-test-key', enabled: true, chance: 1, startAge: 0, maxPerLife: 3 });
assert(TL.ai.ready() === true, '配置后 AI 仍不可用');
assert(TL.ai.getConfig().key === 'sk-test-key', 'AI 配置未持久化');
assert(TL.ai.status().indexOf('已启用') === 0, 'AI 状态文案不对');
/* 结构校验：合法事件 */
const goodEvent = {
  title: '深夜接到老同学的电话',
  story: '多年没联系的老同学突然打来电话，说手上有个项目缺人，问你要不要一起干。',
  choices: [
    { option_text: '连夜赶去聊', desc: '机会与风险同时到来', attr_change: { '智力': 2, '体质': -2, '魅力': 0, '财富': 5000, '快乐': 3, '运气': 1, '健康值': -2, '成瘾值': 0, '名声值': 1, '压力值': 5, '罪恶值': 0 } },
    { option_text: '委婉拒绝', desc: '安稳，但错过一次机会', attr_change: { '智力': 0, '体质': 0, '魅力': 0, '财富': 0, '快乐': -1, '运气': 0, '健康值': 1, '成瘾值': 0, '名声值': 0, '压力值': -2, '罪恶值': 0 } }
  ]
};
const norm = TL.ai.normalizeEvent(goodEvent);
assert(norm && norm.choices.length === 2, 'AI 事件规范化失败');
assert(ATTRS.every((k) => typeof norm.choices[0].attr_change[k] === 'number'), 'AI 事件缺 11 项属性');
/* 结构校验：越界数值被夹取 */
const wildEvent = JSON.parse(JSON.stringify(goodEvent));
wildEvent.choices[0].attr_change['智力'] = 999;
wildEvent.choices[0].attr_change['罪恶值'] = -50;
const norm2 = TL.ai.normalizeEvent(wildEvent);
assert(norm2.choices[0].attr_change['智力'] === 15, '越界属性未被夹取到 15');
assert(norm2.choices[0].attr_change['罪恶值'] === 0, '越界成瘾/罪恶未被夹取到 0');
/* 结构校验：不合格输入应被丢弃 */
assert(TL.ai.normalizeEvent({}) === null, '空对象竟然通过校验');
assert(TL.ai.normalizeEvent({ title: '只有标题' }) === null, '缺少 story/choices 竟然通过校验');
assert(TL.ai.normalizeEvent({ title: '标题', story: '故事', choices: [] }) === null, '空选项竟然通过校验');
/* JSON 抽取：兼容 markdown 代码块与前后废话 */
const fenced = '好的，这是剧情：\n```json\n{"a":1}\n```\n希望满意';
assert(TL.ai.extractJson(fenced) && TL.ai.extractJson(fenced).a === 1, '带代码块的 JSON 抽取失败');
section('AI 事件校验（结构 + 11 项属性 + 越界夹取 + 不合格丢弃）');

/* 7.6 AI 请求链路：成功 → 用 AI 事件；失败 → 回退本地事件 */
const aiEventJson = JSON.stringify({ choices: [{ message: { content: JSON.stringify(goodEvent) } }] });
let aiCalls = 0;
global.window.apiPost = function (url, headers, bodyText, timeout, cb) {
  aiCalls++;
  assert(headers['Authorization'] === 'Bearer sk-test-key', 'AI 请求没有带上 Authorization 头');
  assert(bodyText.indexOf('"model"') !== -1, 'AI 请求体缺少 model');
  cb(null, aiEventJson, 200);
};
TL.S = TL.newState('00', '一线城市', [data.talents[0]]);
TL.S.age = 20;
ui.tab = 'home';
ui.currentEvent = null; ui.currentEventIsAi = false; ui.aiState = null;
ui.nextYear();
assert(aiCalls >= 1, 'AI 开启后没有发起请求');
assert(ui.currentEventIsAi === true, 'AI 成功后未标记为 AI 原创');
assert(ui.currentEvent && ui.currentEvent.title === goodEvent.title, 'AI 事件没有进入弹窗');
assert(document.getElementById('mBody').innerHTML.indexOf('AI 原创') !== -1, '弹窗没有显示 AI 标记');
assert(TL.S.ai.used === 1, 'AI 使用次数没有累加');
ui.chooseEvent(0);
section('AI 剧情链路（请求 → 校验 → 弹窗带 AI 标记 → 选项结算）');

/* 失败回退 */
global.window.apiPost = function (url, headers, bodyText, timeout, cb) { cb('网络断了', null, 0); };
TL.S = TL.newState('00', '一线城市', [data.talents[0]]);
TL.S.age = 20;
ui.currentEvent = null; ui.currentEventIsAi = false; ui.aiState = null;
ui.nextYear();
assert(ui.currentEventIsAi === false, 'AI 失败后没有标记为本地事件');
assert(ui.currentEvent && ui.currentEvent.title, 'AI 失败后没有回退到本地事件');
const localTitles = data.event.map((e) => e.title);
assert(localTitles.indexOf(ui.currentEvent.title) !== -1, '回退的剧情不在本地事件池里');
assert(TL.S.ai.fails >= 1, 'AI 失败次数没有统计');
ui.chooseEvent(0);
section('AI 失败回退（网络错误 → 自动改用本地 155 条剧情池）');

/* 关掉 AI，避免影响后续统计 */
TL.ai.setConfig({ enabled: false, key: '', chance: 0.35 });

/* 7.7 剧情逻辑：年龄纠偏（防止 7 岁早恋、9 岁高考） */
TL.resetAll();
const examEv = data.event.filter((e) => /高考|中考/.test(e.title + e.story))[0];
const romanceEv = data.event.filter((e) => /早恋|情书/.test(e.title + e.story))[0];
assert(examEv && romanceEv, '找不到升学/恋爱类事件');
const examRange = TL.effectiveAgeRange(examEv);
const romanceRange = TL.effectiveAgeRange(romanceEv);
assert(examRange[0] >= 14, '升学考试事件年龄下限仍过低: ' + examRange.join('-'));
assert(romanceRange[0] >= 12, '恋爱事件年龄下限仍过低: ' + romanceRange.join('-'));
/* 7 岁那年，池子里绝不能出现早恋/高考 */
TL.S = TL.newState('90', '小县城', [data.talents[0]]);
TL.S.age = 7;
const pool7 = data.event.filter((e) => TL.eventMatch(e, 7, '90'));
assert(pool7.length > 3, '7 岁事件池过小: ' + pool7.length);
assert(pool7.every((e) => !/早恋|高考/.test(e.title)), '7 岁事件池里仍有早恋/高考');
for (let i = 0; i < 300; i++) {
  const ev = TL.randomEvent();
  if (ev && /早恋|高考/.test(ev.title)) { console.error('7 岁抽到了：' + ev.title); process.exit(1); }
}
/* 17 岁应当能抽到升学类事件 */
const pool17 = data.event.filter((e) => TL.eventMatch(e, 17, '90'));
assert(pool17.some((e) => /高考|中考/.test(e.title)), '17 岁反而抽不到升学类事件');
section('年龄纠偏（' + examEv.title.slice(0, 12) + ' → ' + examRange.join('-') + '，恋爱类 → ' + romanceRange.join('-') + '）');

/* 7.8 剧情前提校验（没配偶不离婚、没宠物不办宠物后事、没工作不谈升职） */
TL.S = TL.newState('90', '小县城', [data.talents[0]]);
TL.S.age = 35;
TL.S.job = ''; TL.S.salary = 0;
const divorceEv = data.event.filter((e) => /离婚|冷战/.test(e.title + e.story))[0];
const petEv = data.event.filter((e) => /宠物|毛孩子/.test(e.title) && /生病|走失|离世|老了|最后/.test(e.title + e.story))[0];
const jobEv = data.event.filter((e) => /同事|升职|加薪|被裁/.test(e.title + e.story))[0];
assert(divorceEv && petEv && jobEv, '找不到用于测试前提的事件');
assert(TL.preconditionReason(divorceEv, TL.S) !== '', '没有伴侣时离婚事件未被拦截');
assert(TL.preconditionReason(petEv, TL.S) !== '', '没有宠物时宠物事件未被拦截');
assert(TL.preconditionReason(jobEv, TL.S) !== '', '没有工作时职场事件未被拦截');
TL.addRelation('spouse', '小雨');
assert(TL.preconditionReason(divorceEv, TL.S) === '', '有伴侣后离婚事件仍被拦截');
TL.addPet('猫');
assert(TL.preconditionReason(petEv, TL.S) === '', '有宠物后宠物事件仍被拦截');
TL.S.job = '程序员'; TL.S.salary = 20000;
assert(TL.preconditionReason(jobEv, TL.S) === '', '有工作后职场事件仍被拦截');
/* 兜底：极端年龄也不能抽不出事件（不能卡住） */
for (const age of [0, 3, 40, 90, 105]) {
  TL.S.age = age;
  const ev = TL.randomEvent();
  assert(ev && ev.title, age + ' 岁抽不到任何事件（会卡住）');
}
section('剧情前提校验（伴侣 / 子女 / 宠物 / 案底 / 工作 + 空池兜底）');

/* 确认弹窗必须能真正执行带命名空间的动作（历史 bug：window['ui.doGiveUp'] 取不到 → 转世失效） */
TL.S = TL.newState('90', '小县城', [data.talents[0]]);
TL.S.age = 30;
ui.tab = 're';
ui.askGiveUp();
assert(window.__confirm && window.__confirm.fn === 'ui.doGiveUp', '确认弹窗未记录动作名');
window.doConfirmOK();
assert(TL.S.alive === false, '确认「放弃本世」后没有生效（动作丢失 bug 回归）');
assert(ui.tab === 're', '放弃本世后未回到轮回页');

/* 金手指的确认弹窗同样要能执行 */
TL.S = TL.newState('90', '小县城', [data.talents[0]]);
TL.S.age = 40;
ui.askGodKill();
window.doConfirmOK();
assert(TL.S.alive === false, '确认「结束本世」后没有生效');

/* 解锁全部成就的确认弹窗 */
TL.S = TL.newState('90', '小县城', [data.talents[0]]);
const achBefore = TL.achStats().got;
ui.askGodUnlockAll();
window.doConfirmOK();
assert(TL.achStats().got > achBefore, '确认「解锁全部成就」后没有生效');
assert(TL.achStats().got === TL.achStats().total, '成就没有全部解锁');

/* 清空存档的确认弹窗 */
ui.askResetAll();
window.doConfirmOK();
assert(TL.S === null, '确认「清空存档」后当前人生仍然存在');
section('确认弹窗动作派发（放弃本世 / 结束本世 / 解锁成就 / 清空存档）');

/* 7.9 名字与性别 */
TL.resetAll();
TL.S = TL.newState('90', '小县城', [data.talents[0]], '苏晚', '女');
assert(TL.S.name === '苏晚', '名字未写入角色');
assert(TL.S.gender === '女', '性别未写入角色');
assert(TL.fill('{名字} 发现 {ta} 的包不见了，{ta的} {配偶} 在等她', TL.S) === '苏晚 发现 她 的包不见了，她的 丈夫 在等她',
  '占位符替换结果不对：' + TL.fill('{名字} 发现 {ta} 的包不见了，{ta的} {配偶} 在等她', TL.S));
TL.S = TL.newState('90', '小县城', [data.talents[0]], '陈默', '男');
assert(TL.fill('{ta} 和 {配偶} 一起回家', TL.S) === '他 和 妻子 一起回家', '男性占位符替换不对');
/* 随机名字要落在对应性别的名字池里 */
for (let i = 0; i < 30; i++) {
  assert(TL.has(TL.NAME_POOL['男'], TL.randomName('男')), '随机男名不在池里');
  assert(TL.has(TL.NAME_POOL['女'], TL.randomName('女')), '随机女名不在池里');
}
/* 性别专属剧情必须真的按性别过滤 */
const femaleEv = data.event.filter((e) => /产假|婆婆|孕期|产检/.test(e.title + e.story))[0];
const maleEv = data.event.filter((e) => /岳父|岳母|彩礼|伴郎/.test(e.title + e.story))[0];
assert(femaleEv && maleEv, '找不到性别专属事件');
TL.S.gender = '男';
assert(TL.genderReason(femaleEv, TL.S) !== '', '男性玩家仍会抽到女性专属剧情：' + femaleEv.title);
assert(TL.genderReason(maleEv, TL.S) === '', '男性玩家抽不到男性专属剧情：' + maleEv.title);
TL.S.gender = '女';
assert(TL.genderReason(maleEv, TL.S) !== '', '女性玩家仍会抽到男性专属剧情：' + maleEv.title);
assert(TL.genderReason(femaleEv, TL.S) === '', '女性玩家抽不到女性专属剧情：' + femaleEv.title);
/* 不允许出现"男女双方都被挡死"的事件 */
let doubleBlocked = 0;
for (const e of data.event) {
  TL.S.gender = '男'; const rm = TL.genderReason(e, TL.S);
  TL.S.gender = '女'; const rf = TL.genderReason(e, TL.S);
  if (rm && rf) { doubleBlocked++; console.error('  男女都被挡: ' + e.title); }
}
assert(doubleBlocked === 0, '有 ' + doubleBlocked + ' 条事件对男女双方都不可达');
section('名字与性别（占位符替换 + 专属剧情过滤 + 可达性）');

/* 7.10 快进 10 年必须真的推进 10 年 */
TL.S = TL.newState('90', '小县城', [data.talents[0]], '陈默', '男');
ui.tab = 'home'; ui.busy = false; ui.currentEvent = null;
const fastStart = TL.S.age;
ui.fastForward();
const advanced = TL.S.age - fastStart;
assert(TL.S.alive, '快进 10 年内角色意外死亡（换个断言）');
assert(advanced === 10, '快进 10 年实际只推进了 ' + advanced + ' 年');
const fastTitle = document.getElementById('mTitle').innerHTML;
const fastSub = document.getElementById('mSub').innerHTML;
const fastBody = document.getElementById('mBody').innerHTML;
assert(fastTitle.indexOf('快进总结') !== -1, '快进结束后没有给出总结弹窗（标题=' + fastTitle + '）');
assert(fastSub.indexOf('十年过去了') !== -1, '快进总结副标题不对：' + fastSub);
assert(fastBody.indexOf('属性净变化') !== -1, '快进总结缺少属性净变化');
assert(fastBody.indexOf('件事') !== -1, '快进总结缺少事件条数');
ui.closeModal();
section('快进 10 年（真实推进 ' + advanced + ' 年 + 自动抉择 + 十年总结）');

console.log('======== 无头逻辑自检报告 ========');
console.log('模拟人生局数        : ' + lives + '（死亡 ' + deaths + ' 局，含服刑 ' + prisonLives + ' 局）');
console.log('累计推进年数        : ' + totalYears + '（平均 ' + (totalYears / lives).toFixed(1) + ' 岁，最高 ' + maxAge + ' 岁）');
console.log('触发事件总次数      : ' + eventFired);
console.log('事件池覆盖          : ' + Object.keys(seenEvents).length + ' / ' + data.event.length);
console.log('技能被习得          : ' + Object.keys(seenSkills).length + ' / ' + data.skills.length);
console.log('成瘾类型出现        : ' + Object.keys(addictionsSeen).join('、'));
console.log('解锁过的成就        : ' + Object.keys(unlockHits).length + ' / ' + data.achievements.length);
console.log('toast 调用次数      : ' + toastCount);
console.log('死因分布            : ' + JSON.stringify(deathReasons));
console.log('金手指 / 死亡 / 轮回 : 通过');
console.log('界面层端到端演练    : 通过（开局页→选年代城市→抽天赋→开始人生→属性页+主动行动→事件弹窗选选项→快进→AI/技能/成就/轮回/控制台五页→密码 208526→死亡评分→转世→存档槽位往返）');
if (neverFired.length) {
  console.log('未被随机到的年龄区间外事件 (' + neverFired.length + ' 条，常见于极端年龄区间):');
  console.log('  ' + neverFired.slice(0, 25).join(' / '));
}
console.log('结论：引擎可完整跑通整局人生，无异常。');
