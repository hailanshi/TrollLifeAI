/* =========================================================================
 * TrollLifeAI · 核心引擎（业务逻辑全部在这一层，壳里没有任何业务）
 * 老语法 JS：只用 var / function，不用箭头函数、模板字符串、?. ?? .flat()
 * ========================================================================= */
(function () {
  'use strict';

  window.TL = {};

  /* ---------------- 常量 ---------------- */
  TL.ATTRS = ['智力', '体质', '魅力', '财富', '快乐', '运气', '健康值', '成瘾值', '名声值', '压力值', '罪恶值'];
  TL.ADDICTIONS = ['烟瘾', '酒瘾', '网瘾', '赌瘾'];
  TL.REL_TYPES = { friend: '朋友', lover: '恋人', spouse: '配偶', child: '子女', enemy: '仇人' };
  TL.ERAS = ['80', '90', '00', '10', '20'];
  TL.ERA_NAME = { '80': '80年代', '90': '90年代', '00': '00年代', '10': '10年代', '20': '20年代' };
  TL.SAVE_KEY = 'tlai_save_v1';
  TL.GLOBAL_KEY = 'tlai_global_v1';
  TL.GOD_PASSWORD = '208526';

  TL.DATA = window.__TL_DATA__ || { talents: [], achievements: [], skills: [], city: [], event: [] };

  /* ---------------- 工具 ---------------- */
  TL.clamp = function (v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); };
  TL.rnd = function (n) { return Math.floor(Math.random() * n); };
  TL.pick = function (arr) { return arr[TL.rnd(arr.length)]; };
  TL.fmt = function (n) {
    var neg = n < 0; var s = String(Math.abs(Math.round(n))); var out = '';
    while (s.length > 3) { out = ',' + s.slice(s.length - 3) + out; s = s.slice(0, s.length - 3); }
    return (neg ? '-' : '') + s + out;
  };
  TL.has = function (arr, v) { return arr && arr.indexOf(v) !== -1; };

  /* ---------------- 持久层（localStorage） ---------------- */
  TL.global = { achievements: [], lives: 0, bestAge: 0, inherit: { '智力': 0, '体质': 0, '魅力': 0 }, cheatsUsed: 0 };

  TL.saveGlobal = function () {
    try { localStorage.setItem(TL.GLOBAL_KEY, JSON.stringify(TL.global)); } catch (e) { }
  };
  TL.loadGlobal = function () {
    try {
      var raw = localStorage.getItem(TL.GLOBAL_KEY);
      if (raw) {
        var o = JSON.parse(raw);
        if (o && typeof o === 'object') {
          TL.global.achievements = o.achievements || [];
          TL.global.lives = o.lives || 0;
          TL.global.bestAge = o.bestAge || 0;
          TL.global.inherit = o.inherit || TL.global.inherit;
          TL.global.cheatsUsed = o.cheatsUsed || 0;
        }
      }
    } catch (e) { }
  };

  TL.S = null; /* 当前这一世的状态 */

  TL.newState = function (era, cityName, talents) {
    var cityObj = TL.cityByName(cityName) || TL.DATA.city[0];
    var s = {
      age: 0, era: era, cityName: cityObj.cityName,
      attrs: {}, assets: { house: 0, car: 0, luxury: 0, insurance: 0, debt: 0 },
      addictions: {}, relations: [], pets: [], skills: [], talents: talents || [],
      job: '', salary: 0, prison: 0, flags: { eraSeen: {} },
      log: [], usedTitles: [], godUnlocked: false,
      alive: true, deathReason: '', lifespan: 0, moves: 0,
      actionPoints: 1,                                   /* 每岁 1 点主动行动力 */
      ai: { used: 0, fails: 0, cache: [] },               /* AI 剧情使用统计 */
      stat: { maxMoney: 0, earnings: 0, income: 0, hospital: 0, crimeCaught: 0, prisonTotal: 0 }
    };
    var i;
    for (i = 0; i < TL.ATTRS.length; i++) { s.attrs[TL.ATTRS[i]] = 50; }
    s.attrs['财富'] = 0;
    s.attrs['健康值'] = 70;
    s.attrs['压力值'] = 20;
    s.attrs['快乐'] = 60;
    s.attrs['成瘾值'] = 0;
    s.attrs['罪恶值'] = 0;
    s.attrs['名声值'] = 0;
    for (i = 0; i < TL.ADDICTIONS.length; i++) { s.addictions[TL.ADDICTIONS[i]] = 0; }

    /* 天赋属性修正 */
    for (i = 0; i < s.talents.length; i++) {
      var mod = s.talents[i].attrModify || {};
      for (var k in mod) {
        if (Object.prototype.hasOwnProperty.call(mod, k) && s.attrs[k] !== undefined) {
          s.attrs[k] += mod[k];
        }
      }
    }
    /* 轮回继承（少量属性） */
    var inh = TL.global.inherit || {};
    for (var a in inh) {
      if (Object.prototype.hasOwnProperty.call(inh, a) && s.attrs[a] !== undefined) { s.attrs[a] += inh[a]; }
    }
    /* 城市 attrEffect：压力修正 + 财富上限系数 */
    s.attrs['压力值'] = TL.clamp(s.attrs['压力值'] + (cityObj.attrEffect['压力值'] || 0), 0, 999);
    s.lifespan = TL.calcLifespan(s);
    return s;
  };

  TL.calcLifespan = function (s) {
    var base = 62 + Math.round(s.attrs['体质'] * 0.35) + Math.round(s.attrs['健康值'] * 0.25);
    /* 天赋对寿命的影响 */
    for (var i = 0; i < s.talents.length; i++) {
      var n = s.talents[i].name;
      if (n === '长寿体质') { base += 12; }
      if (n === '短命基因') { base -= 12; }
      if (n === '打不死的小强') { base += 6; }
    }
    return TL.clamp(base + TL.rnd(17) - 8, 35, 110);
  };

  TL.cityByName = function (name) {
    for (var i = 0; i < TL.DATA.city.length; i++) {
      if (TL.DATA.city[i].cityName === name) { return TL.DATA.city[i]; }
    }
    return null;
  };
  TL.city = function () { return TL.cityByName(TL.S.cityName) || TL.DATA.city[0]; };

  /* 财富上限：城市 attrEffect.财富上限 系数 * 基础额度 */
  TL.moneyCap = function () {
    var f = TL.city().attrEffect['财富上限'];
    if (!f || f <= 0) { f = 1; }
    return Math.round(300000 * f);
  };

  /* ---------------- 技能加成（事件成功率） ---------------- */
  TL.SKILL_KEYWORDS = {
    programming: ['代码', '编程', '程序', '软件', '互联网', '开发', '游戏'],
    cooking: ['厨', '做饭', '餐饮', '开饭馆', '小吃'],
    painting: ['画', '美术', '设计', '文创'],
    music: ['音乐', '唱歌', '乐器', '演艺', '舞台', '直播'],
    foreign_language: ['外语', '外企', '出国', '移民', '留学'],
    medical: ['医院', '治病', '手术', '看病', '养生'],
    sport: ['体育', '比赛', '健身', '球', '运动'],
    business: ['谈判', '生意', '合作', '创业', '投资', '理财', '股票', '买房'],
    photography: ['摄影', '拍照', '短视频', '拍摄'],
    car_repair: ['汽修', '修车', '汽车'],
    driving: ['司机', '开车', '网约车', '外卖', '货运', '代驾'],
    finance: ['理财', '股票', '基金', '投资', '存钱', '理财保险'],
    law: ['官司', '法律', '维权', '警察', '审讯', '辩护'],
    nursing: ['护理', '养老', '照顾', '陪护'],
    teaching: ['老师', '讲课', '培训', '教学', '补课'],
    hospitality: ['酒店', '餐饮', '服务', '开店'],
    ecommerce: ['电商', '网店', '淘宝', '带货', '直播'],
    writing: ['写作', '写稿', '编剧', '文案', '回忆录'],
    barber: ['理发', '剪头', '美发'],
    welding: ['电焊', '工地', '船厂', '技工'],
    first_aid: ['急救', '救人', '溺水', '受伤', '昏迷'],
    budgeting: ['记账', '省钱', '开销', '攒钱'],
    gardening: ['种花', '种菜', '园艺', '阳台'],
    pet_care: ['宠物', '猫', '狗', '流浪'],
    makeup: ['化妆', '造型', '穿搭', '出镜'],
    fitness: ['健身', '锻炼', '体能', '马拉松'],
    meditation: ['冥想', '情绪', '冷静', '压力'],
    self_defense: ['斗殴', '打人', '抢劫', '防身', '冲突'],
    negotiation_life: ['砍价', '谈判', '协商', '纠纷', '赔偿']
  };

  /* 根据事件/选项文本计算技能带来的成功率加成（0 ~ 0.35） */
  TL.skillBonus = function (text) {
    if (!text || !TL.S) { return 0; }
    var bonus = 0;
    for (var i = 0; i < TL.S.skills.length; i++) {
      var id = TL.S.skills[i];
      var words = TL.SKILL_KEYWORDS[id];
      if (!words) { continue; }
      for (var j = 0; j < words.length; j++) {
        if (text.indexOf(words[j]) !== -1) { bonus += 0.07; break; }
      }
    }
    /* 天赋加成 */
    for (var k = 0; k < TL.S.talents.length; k++) {
      var tn = TL.S.talents[k].name;
      if (tn === '天资聪颖' || tn === '学霸体质' || tn === '社交达人' || tn === '商业嗅觉' ||
        tn === '投资直觉' || tn === '天生嗓音' || tn === '艺术天赋' || tn === '运动奇才' ||
        tn === '小镇做题家' || tn === '夜猫子') { bonus += 0.05; }
      if (tn === '拖延症') { bonus -= 0.08; }
      if (tn === '手气极差') { bonus -= 0.10; }
      if (tn === '法盲') { bonus += 0.0; }
    }
    if (bonus < 0) { bonus = 0; }
    if (bonus > 0.35) { bonus = 0.35; }
    return bonus;
  };

  /* ---------------- 属性变更 ---------------- */
  TL.applyAttr = function (change, noToast) {
    var s = TL.S; if (!s) { return null; }
    var applied = {};
    for (var i = 0; i < TL.ATTRS.length; i++) {
      var k = TL.ATTRS[i];
      var d = change[k] || 0;
      if (d === 0) { continue; }
      /* 城市财富上限：财富不能突破上限（金手指除外） */
      if (k === '财富') {
        var cap = TL.moneyCap();
        var after = s.attrs['财富'] + d;
        if (d > 0 && after > cap) { d = Math.max(0, cap - s.attrs['财富']); }
      }
      /* 天赋抵抗 */
      if (k === '压力值' && d > 0) {
        for (var t = 0; t < s.talents.length; t++) {
          var tn = s.talents[t].name;
          if (tn === '抗压强者' || tn === '钢铁意志' || tn === '乐天派') { d = Math.round(d * 0.6); }
          if (tn === '玻璃心') { d = Math.round(d * 1.5); }
        }
      }
      if (k === '成瘾值' && d > 0) {
        for (var t2 = 0; t2 < s.talents.length; t2++) {
          var tn2 = s.talents[t2].name;
          if (tn2 === '抗瘾体质') { d = Math.round(d * 0.5); }
          if (tn2 === '赌徒本性' && TL.S.addictions['赌瘾'] > 0) { d = Math.round(d * 1.4); }
        }
      }
      s.attrs[k] += d;
      applied[k] = d;
      /* 单次财富暴涨（≥5万）用于「一夜暴富 / 股神」成就 */
      if (k === '财富' && d >= 50000) { s.flags.bigGain = 1; s.stat.income += d; }
    }
    /* 夹取范围 */
    for (var j = 0; j < TL.ATTRS.length; j++) {
      var key = TL.ATTRS[j];
      if (key === '财富') { continue; }
      s.attrs[key] = TL.clamp(s.attrs[key], -99, 200);
    }
    if (s.attrs['财富'] > s.stat.maxMoney) { s.stat.maxMoney = s.attrs['财富']; }
    if (!noToast) { TL.toastAttr(applied); }
    TL.checkAchievements();
    return applied;
  };

  TL.toastAttr = function (applied) {
    var parts = [];
    for (var k in applied) {
      if (!Object.prototype.hasOwnProperty.call(applied, k)) { continue; }
      var v = applied[k];
      parts.push(k + (v > 0 ? '+' : '') + (k === '财富' ? TL.fmt(v) : v));
    }
    if (parts.length) { window.toast(parts.join('  ')); }
  };

  /* ---------------- 事件标记解析 ---------------- */
  /* desc 里形如 【买房】【入狱:3】【关系:friend:小林】 的标记，是剧情副作用钩子 */
  TL.parseMarkers = function (text) {
    var out = [];
    if (!text || typeof text !== 'string') { return out; }
    var re = /【([^】]+)】/g, m;
    while ((m = re.exec(text)) !== null) {
      var body = m[1];
      /* 年代标记 【80年代】 也在这里兼容 */
      var eraM = /^(80|90|00|10|20)年代$/.exec(body);
      if (eraM) { out.push({ type: '年代', args: [eraM[1]] }); continue; }
      var parts = body.split(':');
      out.push({ type: parts[0], args: parts.slice(1) });
    }
    return out;
  };

  TL.applyMarkers = function (text) {
    var s = TL.S; if (!s) { return; }
    var ms = TL.parseMarkers(text);
    for (var i = 0; i < ms.length; i++) {
      var t = ms[i].type, a = ms[i].args;
      try {
        if (t === '习得') { TL.learnSkill(a[0]); }
        else if (t === '宠物') { TL.addPet(a[0]); }
        else if (t === '宠物生病') { TL.petEvent('生病'); }
        else if (t === '宠物走失') { TL.petEvent('走失'); }
        else if (t === '宠物繁育') { TL.petEvent('繁育'); }
        else if (t === '宠物离世') { TL.petEvent('离世'); }
        else if (t === '关系') { TL.addRelation(a[0], a[1]); }
        else if (t === '关系结束') { TL.endRelation(a[0]); }
        else if (t === '职业') { s.job = a[0]; s.salary = TL.baseSalary(a[0], s); s.flags.jobFirst = 1; TL.unlock('打工人'); }
        else if (t === '升职') { s.salary = Math.round(s.salary * 1.4) || 8000; s.flags.promoted = 1; TL.unlock('职场晋升'); }
        else if (t === '失业') { s.job = ''; s.salary = 0; s.flags.fired = 1; TL.unlock('被优化了'); }
        else if (t === '跳槽') { s.salary = Math.round(s.salary * 1.3) || 9000; s.flags.jobHop = 1; TL.unlock('跳槽高手'); }
        else if (t === '创业') { s.flags.startup = 1; }
        else if (t === '破产') { s.flags.bankrupt = 1; s.job = ''; s.salary = 0; TL.unlock('公司破产'); }
        else if (t === '入狱') { TL.jail(parseInt(a[0], 10) || 1); }
        else if (t === '出狱') { s.prison = 0; s.flags.record = 1; }
        else if (t === '案底') { s.flags.record = 1; }
        else if (t === '减刑') { s.prison = Math.max(0, s.prison - 1); s.flags.commuted = 1; TL.unlock('减刑出狱'); }
        else if (t === '买房') { s.assets.house += 1; TL.unlock('有房一族'); }
        else if (t === '买车') { s.assets.car += 1; TL.unlock('有车一族'); }
        else if (t === '奢侈品') { s.assets.luxury += 1; }
        else if (t === '保险') { s.assets.insurance += 1; }
        else if (t === '负债') { s.assets.debt += (parseInt(a[0], 10) || 0); }
        else if (t === '还债') { s.assets.debt = Math.max(0, s.assets.debt - (parseInt(a[0], 10) || 0)); }
        else if (t === '成瘾') { TL.addAddiction(a[0], 10); }
        else if (t === '戒断') { TL.rehab(a[0]); }
        else if (t === '年代') { s.flags.eraSeen[a[0]] = 1; }
      } catch (e) { /* 单个标记失败不影响整局 */ }
    }
    /* 资产/债务相关的通用成就 */
    if (s.assets.debt >= 100000) { TL.unlock('负债累累'); }
    if (s.assets.debt === 0 && s.flags.wasDebt) { TL.unlock('无债一身轻'); }
    if (s.assets.debt >= 50000) { s.flags.wasDebt = 1; }
  };

  /* ---------------- 技能 / 宠物 / 人际 / 成瘾 / 牢狱 ---------------- */
  TL.learnSkill = function (id) {
    var s = TL.S;
    if (!id || TL.has(s.skills, id)) { return; }
    s.skills.push(id);
    var nm = TL.skillName(id);
    window.toast('习得技能：' + nm);
  };
  TL.skillName = function (id) {
    for (var i = 0; i < TL.DATA.skills.length; i++) {
      if (TL.DATA.skills[i].skillId === id) { return TL.DATA.skills[i].name; }
    }
    return id;
  };
  TL.skillById = function (id) {
    for (var i = 0; i < TL.DATA.skills.length; i++) {
      if (TL.DATA.skills[i].skillId === id) { return TL.DATA.skills[i]; }
    }
    return null;
  };

  var PET_NAMES = ['豆豆', '团子', '小黑', '旺财', '雪球', '布丁', '橘座', '毛球', '阿黄', '奶昔'];
  TL.addPet = function (species) {
    var s = TL.S;
    var p = { name: TL.pick(PET_NAMES), species: species || '猫', age: 0, alive: true, health: 90 };
    s.pets.push(p);
    if (s.pets.length === 1) { TL.unlock('宠物主人'); }
    window.toast('收养了宠物：' + p.name + '（' + p.species + '）');
  };
  TL.petEvent = function (kind) {
    var s = TL.S;
    var alive = [];
    for (var i = 0; i < s.pets.length; i++) { if (s.pets[i].alive) { alive.push(s.pets[i]); } }
    if (!alive.length) { return; }
    var p = TL.pick(alive);
    if (kind === '生病') { p.health -= 25; TL.unlock('宠物医院常客'); window.toast(p.name + ' 生病了'); }
    else if (kind === '走失') { p.alive = false; p.lost = true; window.toast(p.name + ' 走失了'); }
    else if (kind === '繁育') { TL.addPet(p.species); TL.addPet(p.species); TL.unlock('毛孩子满堂'); }
    else if (kind === '离世') { p.alive = false; TL.unlock('回喵星了'); window.toast(p.name + ' 离开了你'); }
  };

  TL.addRelation = function (type, name) {
    var s = TL.S;
    if (!TL.REL_TYPES[type] || !name) { return; }
    for (var i = 0; i < s.relations.length; i++) {
      if (s.relations[i].name === name) {
        s.relations[i].affinity = TL.clamp(s.relations[i].affinity + 10, 0, 100);
        return;
      }
    }
    var base = (type === 'enemy') ? 20 : 60;
    s.relations.push({ name: name, type: type, affinity: base, alive: true, since: s.age });
    if (type === 'lover' && s.age <= 18) { TL.unlock('青梅竹马'); }
    window.toast('新增关系：' + TL.REL_TYPES[type] + ' ' + name);
  };
  TL.endRelation = function (name) {
    var s = TL.S;
    for (var i = 0; i < s.relations.length; i++) {
      if (s.relations[i].name === name) {
        s.relations[i].alive = false;
        s.relations[i].affinity = 0;
        window.toast('关系结束：' + name);
      }
    }
  };
  TL.relCount = function (type) {
    var s = TL.S, n = 0;
    for (var i = 0; i < s.relations.length; i++) {
      if (s.relations[i].type === type && s.relations[i].alive !== false) { n++; }
    }
    return n;
  };

  TL.addAddiction = function (type, v) {
    var s = TL.S;
    if (!type || !s) { return; }
    if (s.addictions[type] === undefined) { s.addictions[type] = 0; }
    s.addictions[type] = TL.clamp(s.addictions[type] + v, 0, 100);
  };
  TL.rehab = function (type) {
    var s = TL.S;
    if (!type) { return; }
    var before = s.addictions[type] || 0;
    if (before >= 80) { TL.unlock('戒断地狱'); }
    s.addictions[type] = 0;
    s.flags.rehab = s.flags.rehab || {};
    s.flags.rehab[type] = 1;
    if (type === '烟瘾') { TL.unlock('戒烟成功'); }
    if (type === '酒瘾') { TL.unlock('戒酒成功'); }
    if (type === '网瘾') { TL.unlock('网瘾戒断'); }
    if (type === '赌瘾') { TL.unlock('戒赌勇士'); }
    window.toast('成功戒断：' + type);
  };

  TL.jail = function (years) {
    var s = TL.S;
    if (!s) { return; }
    years = TL.clamp(years || 1, 1, 20);
    s.prison += years;
    s.stat.prisonTotal += years;
    s.stat.crimeCaught += 1;
    s.flags.record = 1;
    TL.unlock('锒铛入狱');
    if (s.stat.prisonTotal >= 10) { TL.unlock('牢底坐穿'); }
    window.toast('被判入狱 ' + years + ' 年');
  };

  TL.baseSalary = function (job, s) {
    var base = 6000;
    var table = {
      '程序员': 22000, '大厂程序员': 30000, '国企职员': 9000, '工厂普工': 5500, '外卖骑手': 7000,
      '网约车司机': 7500, '教师': 8000, '公务员': 8500, '汽修工': 7000, '销售': 9000,
      '部门主管': 26000, '创业者': 0, '店主': 8000, '理发师': 6500, '电焊工': 11000,
      '护士': 8000, '电商运营': 12000, '主播': 10000, '作家': 7000, '快递员': 6000
    };
    if (table[job] !== undefined) { base = table[job]; }
    var f = TL.city().attrEffect['财富上限'] || 1;
    var intel = s ? (s.attrs['智力'] / 50) : 1;
    var skillMul = 1 + s.skills.length * 0.03;
    return Math.round(base * f * (0.7 + intel * 0.3) * skillMul);
  };

  /* ---------------- 每年推进 ---------------- */
  TL.naturalDrift = function () {
    var s = TL.S, d = {};
    for (var i = 0; i < TL.ATTRS.length; i++) { d[TL.ATTRS[i]] = 0; }
    if (s.age <= 6) { d['智力'] = 1; d['体质'] = 1; d['健康值'] = 1; d['快乐'] = 1; }
    else if (s.age <= 17) { d['智力'] = 1; d['体质'] = 1; d['压力值'] = 1; }
    else if (s.age <= 39) { d['压力值'] = 1; }
    else if (s.age <= 59) { d['体质'] = -1; d['健康值'] = -1; d['压力值'] = -1; }
    else { d['体质'] = -1; d['健康值'] = -2; d['压力值'] = -2; d['快乐'] = -1; }
    /* 自愈：年轻/心态好时恢复更快（避免随机选择下人均英年早逝） */
    var hp = s.attrs['健康值'];
    if (hp < 40) { d['健康值'] += 3; }
    else if (hp < 60 && s.attrs['压力值'] < 60) { d['健康值'] += 2; }
    else if (hp < 85 && s.age <= 45 && s.attrs['快乐'] >= 50) { d['健康值'] += 1; }
    /* 成瘾值自然代谢 + 健康损耗 */
    if (s.attrs['成瘾值'] > 0) { d['成瘾值'] = -1; }
    if (s.attrs['成瘾值'] >= 50) { d['健康值'] -= 1; }
    if (s.attrs['压力值'] >= 70) { d['健康值'] -= 2; }
    if (s.attrs['快乐'] >= 70) { d['健康值'] += 1; }
    /* 天赋被动 */
    for (var t = 0; t < s.talents.length; t++) {
      var n = s.talents[t].name;
      if (n === '睡眠质量王') { d['健康值'] += 2; d['压力值'] -= 2; }
      if (n === '铁胃') { d['体质'] += 1; }
      if (n === '天生劳碌命') { d['健康值'] -= 1; }
      if (n === '夜猫子') { d['健康值'] -= 1; }
      if (n === '晚熟之人' && s.age >= 40) { d['智力'] += 2; d['财富'] += 3000; }
    }
    /* 技能被动 */
    if (TL.has(s.skills, 'fitness')) { d['体质'] += 1; d['健康值'] += 1; }
    if (TL.has(s.skills, 'meditation')) { d['压力值'] -= 2; }
    if (TL.has(s.skills, 'gardening') && s.age >= 50) { d['压力值'] -= 1; d['快乐'] += 1; }
    if (TL.has(s.skills, 'budgeting')) { d['财富'] += 2000; }
    /* 压力过高伤身、快乐过低伤心 */
    if (s.attrs['压力值'] >= 85) { d['健康值'] -= 3; }
    if (s.attrs['快乐'] <= 15) { d['健康值'] -= 2; }
    return d;
  };

  TL.yearlyIncome = function () {
    var s = TL.S;
    if (s.prison > 0 || !s.job || !s.salary) { return 0; }
    var inc = Math.round(s.salary * (0.9 + Math.random() * 0.25));
    /* 「休息放松」行动会让当年收入减半 */
    if (s.flags.halfIncome) { inc = Math.round(inc * 0.5); }
    /* 城市财富上限：年收入软上限 */
    var cap = Math.round(TL.moneyCap() * 0.25);
    if (inc > cap) { inc = cap; }
    if (s.flags.record) { inc = Math.round(inc * 0.7); } /* 案底惩罚 */
    s.stat.income += inc;
    return inc;
  };

  TL.advanceYear = function () {
    var s = TL.S;
    if (!s || !s.alive) { return null; }
    s.age += 1;
    s.actionPoints = 1;                 /* 新的一年恢复 1 点行动力 */

    /* 1. 服刑中：跳过正常人生事件 */
    if (s.prison > 0) {
      s.prison -= 1;
      s.actionPoints = 0;               /* 狱中没有行动自由 */
      TL.applyAttr({ '智力': 0, '体质': -2, '魅力': -1, '财富': 0, '快乐': -3, '运气': -1, '健康值': -3, '成瘾值': 0, '名声值': -1, '压力值': 4, '罪恶值': -2 }, true);
      TL.addLog('第 ' + s.age + ' 年：在狱中服刑，还剩 ' + s.prison + ' 年');
      if (s.prison === 0) { TL.addLog('第 ' + s.age + ' 年：刑满释放，你走出监狱大门'); window.toast('刑满释放'); }
      TL.checkDeath();
      return { type: 'prison' };
    }

    /* 2. 自然漂移 + 收入 */
    TL.applyAttr(TL.naturalDrift(), true);
    var inc = TL.yearlyIncome();
    s.flags.halfIncome = 0;             /* 收入减半只在当年生效 */
    if (inc) { TL.applyAttr({ '财富': inc, '智力': 0, '体质': 0, '魅力': 0, '快乐': 0, '运气': 0, '健康值': 0, '成瘾值': 0, '名声值': 0, '压力值': 0, '罪恶值': 0 }, true); }

    /* 3. 医疗系统：健康告急且有钱时自动就医调养（花钱续命，医疗技能更省） */
    if (s.attrs['健康值'] < 50 && s.attrs['财富'] >= 20000) {
      var cost = 5000;
      if (TL.has(s.skills, 'medical') || TL.has(s.skills, 'nursing') || TL.has(s.skills, 'first_aid')) { cost = 3000; }
      s.attrs['财富'] -= cost;
      s.stat.hospital += 1;
      TL.applyAttr({
        '智力': 0, '体质': 0, '魅力': 0, '财富': 0, '快乐': 0, '运气': 0,
        '健康值': 8, '成瘾值': 0, '名声值': 0, '压力值': -3, '罪恶值': 0
      }, true);
      TL.addLog('第 ' + s.age + ' 年：花 ' + TL.fmt(cost) + ' 元就医调养，健康值回升');
    }

    /* 4. 债务利息 */
    if (s.assets.debt > 0) {
      s.assets.debt = Math.round(s.assets.debt * 1.05);
      if (s.assets.debt >= 100000) { TL.unlock('负债累累'); }
    }

    /* 4. 罪恶值抓捕判定（罪恶值越高越危险，学法可以降风险） */
    if (s.attrs['罪恶值'] >= 55) {
      var chance = (s.attrs['罪恶值'] - 55) / 200;
      if (TL.has(s.skills, 'law')) { chance *= 0.6; }
      for (var t = 0; t < s.talents.length; t++) {
        if (s.talents[t].name === '法盲') { chance *= 1.5; }
        if (s.talents[t].name === '道德底线高') { chance *= 0.5; }
      }
      if (chance > 0.35) { chance = 0.35; }
      if (Math.random() < chance) {
        TL.jail(1 + Math.floor(s.attrs['罪恶值'] / 25));
        TL.addLog('第 ' + s.age + ' 年：因罪恶值过高被警方抓获');
        TL.checkDeath();
        return { type: 'caught' };
      }
    }

    /* 5. 成瘾发作判定（成瘾值过高强制触发） */
    if (s.attrs['成瘾值'] >= 60 && Math.random() < 0.55) {
      var forced = TL.forcedEvent('成瘾发作');
      if (forced) { return { type: 'event', event: forced }; }
    }

    /* 6. 随机人生事件 */
    var ev = TL.randomEvent();
    TL.checkDeath();
    if (ev) { return { type: 'event', event: ev }; }
    TL.addLog('第 ' + s.age + ' 年：平淡的一年');
    return { type: 'quiet' };
  };

  /* 引擎内置的强制事件（成瘾发作 / 重病危险），属性同样是完整 11 项 */
  TL.FORCED = [
    {
      age_range: [14, 110], forced: '成瘾发作', title: '成瘾发作，你控制不住自己',
      story: '深夜你浑身发抖、心慌出汗，脑子里只有一个念头：必须再来一次。理智正在被一点点吃掉。',
      choices: [
        {
          option_text: '咬牙硬抗过去', desc: '痛苦但守住了底线，成瘾值下降',
          attr_change: { '智力': 1, '体质': -3, '魅力': 0, '财富': 0, '快乐': -6, '运气': 0, '健康值': -5, '成瘾值': -18, '名声值': 0, '压力值': 12, '罪恶值': 0 }
        },
        {
          option_text: '立刻满足自己', desc: '短暂解脱，成瘾值继续上涨，健康透支',
          attr_change: { '智力': -2, '体质': -2, '魅力': -1, '财富': -1500, '快乐': 5, '运气': -1, '健康值': -3, '成瘾值': 15, '名声值': -1, '压力值': 2, '罪恶值': 1 }
        }
      ]
    }
  ];
  TL.forcedEvent = function (kind) {
    for (var i = 0; i < TL.FORCED.length; i++) {
      if (TL.FORCED[i].forced === kind) { return TL.FORCED[i]; }
    }
    return null;
  };

  /* ---------------- 事件抽取 ---------------- */
  TL.eventEra = function (ev) {
    var m = /^【(80|90|00|10|20)年代】/.exec(ev.title || '');
    return m ? m[1] : '';
  };
  TL.eventMatch = function (ev, age, era) {
    if (!ev.age_range || age < ev.age_range[0] || age > ev.age_range[1]) { return false; }
    var e = TL.eventEra(ev);
    if (e && e !== era) { return false; }
    /* 年代标记（写在 desc 里）也要匹配 */
    var ds = '';
    for (var i = 0; i < (ev.choices || []).length; i++) { ds += ev.choices[i].desc || ''; }
    var re = /【(80|90|00|10|20)年代】/g, m;
    while ((m = re.exec(ds)) !== null) { if (m[1] !== era) { return false; } }
    return true;
  };
  TL.randomEvent = function () {
    var s = TL.S;
    var pool = [], fresh = [];
    for (var i = 0; i < TL.DATA.event.length; i++) {
      var ev = TL.DATA.event[i];
      if (!TL.eventMatch(ev, s.age, s.era)) { continue; }
      pool.push(ev);
      if (!TL.has(s.usedTitles, ev.title)) { fresh.push(ev); }
    }
    if (!pool.length) { return null; }
    var ev2 = fresh.length ? TL.pick(fresh) : TL.pick(pool);
    s.usedTitles.push(ev2.title);
    if (s.usedTitles.length > 400) { s.usedTitles.shift(); }
    return ev2;
  };

  /* 哪些属性「越大越好」：成瘾值/压力值/罪恶值越大越糟 */
  TL.GOOD_DIRECTION = {
    '智力': 1, '体质': 1, '魅力': 1, '财富': 1, '快乐': 1, '运气': 1,
    '健康值': 1, '成瘾值': -1, '名声值': 1, '压力值': -1, '罪恶值': -1
  };

  TL.chooseOption = function (ev, idx) {
    var s = TL.S;
    var ch = ev.choices[idx];
    if (!ch) { return; }
    var src = ch.attr_change || {};

    /* 技能成功率加成：命中相关技能时，有一定概率让「好的一面更好、坏的一面更轻」 */
    var bonus = TL.skillBonus((ev.title || '') + ' ' + (ev.story || '') + ' ' + (ch.option_text || ''));
    var lucky = bonus > 0 && Math.random() < bonus;
    var finalChange = {};
    for (var i = 0; i < TL.ATTRS.length; i++) {
      var k = TL.ATTRS[i];
      var d = src[k] || 0;
      if (lucky && d !== 0) {
        var good = (TL.GOOD_DIRECTION[k] === 1) ? (d > 0) : (d < 0);
        d = good ? Math.round(d * 1.5) : Math.round(d * 0.5);
      }
      finalChange[k] = d;
    }

    TL.applyAttr(finalChange);
    if (lucky) { window.toast('技能加成生效（+' + Math.round(bonus * 100) + '%）：结果向有利方向偏移'); }
    TL.applyMarkers(ch.desc || '');
    TL.applyMarkers(ev.title || '');
    TL.addLog('第 ' + s.age + ' 年：' + ev.title + ' → ' + ch.option_text + (lucky ? '（技能加成生效）' : ''));
    TL.checkAchievements();
    TL.checkDeath();
  };

  TL.addLog = function (t) {
    if (!TL.S) { return; }
    TL.S.log.unshift(t);
    if (TL.S.log.length > 120) { TL.S.log.pop(); }
  };

  /* ---------------- 死亡与轮回 ---------------- */
  TL.checkDeath = function () {
    var s = TL.S;
    if (!s || !s.alive) { return true; }
    if (s.attrs['健康值'] <= 0) { TL.die('健康值归零，身体彻底垮了'); return true; }
    if (s.age >= s.lifespan) { TL.die('寿终正寝，人生走到终点'); return true; }
    return false;
  };

  TL.die = function (reason) {
    var s = TL.S;
    s.alive = false;
    s.deathReason = reason;
    TL.global.lives += 1;
    if (s.age > TL.global.bestAge) { TL.global.bestAge = s.age; }
    if (s.age >= 100) { TL.unlock('百岁人生'); }
    if (s.age >= 60) { TL.unlock('退休生活'); }
    if (s.age < 40) { TL.unlock('英年早逝'); }
    if (s.attrs['健康值'] > 30 && reason.indexOf('寿终正寝') !== -1) { TL.unlock('寿终正寝'); }
    if (TL.relCount('spouse') === 0 && TL.relCount('child') === 0 && s.age >= 30) { TL.unlock('孤家寡人'); }
    if (s.flags.godUsed) { TL.unlock('开挂人生'); }
    TL.addLog('第 ' + s.age + ' 年：' + reason);
    TL.calcInherit();
    TL.saveGlobal();
    TL.save();
  };

  TL.calcInherit = function () {
    var s = TL.S;
    TL.global.inherit = {
      '智力': Math.round(s.attrs['智力'] * 0.08),
      '体质': Math.round(s.attrs['体质'] * 0.08),
      '魅力': Math.round(s.attrs['魅力'] * 0.08),
      '运气': Math.round(s.attrs['运气'] * 0.08)
    };
  };

  TL.reincarnate = function (era, cityName, talents) {
    TL.S = TL.newState(era, cityName, talents);
    TL.global.lives += 1;
    TL.unlock('轮回新生');
    TL.addLog('第 0 年：转世新生，年代【' + TL.ERA_NAME[era] + '】，出生地【' + cityName + '】');
    TL.save();
    return TL.S;
  };

  /* ---------------- 存档 ---------------- */
  TL.save = function () {
    try {
      if (TL.S) { localStorage.setItem(TL.SAVE_KEY, JSON.stringify(TL.S)); }
      else { localStorage.removeItem(TL.SAVE_KEY); }
    } catch (e) { }
  };
  TL.load = function () {
    try {
      var raw = localStorage.getItem(TL.SAVE_KEY);
      if (!raw) { return null; }
      var o = JSON.parse(raw);
      if (o && o.attrs) { return o; }
    } catch (e) { }
    return null;
  };
  TL.clearSave = function () {
    try { localStorage.removeItem(TL.SAVE_KEY); } catch (e) { }
    TL.S = null;
  };
  TL.resetAll = function () {
    try { localStorage.removeItem(TL.SAVE_KEY); localStorage.removeItem(TL.GLOBAL_KEY); } catch (e) { }
    TL.global = { achievements: [], lives: 0, bestAge: 0, inherit: { '智力': 0, '体质': 0, '魅力': 0 }, cheatsUsed: 0 };
    TL.S = null;
  };

  TL.loadGlobal();
})();
