/* =========================================================================
 * TrollLifeAI · 成就引擎
 * 成就定义来自 achievements.json（name 作为稳定 ID），这里实现「自动监听触发器」。
 * 两类触发：
 *   1) LOG_ACH 关键词监听（扫描人生日志）
 *   2) ACH_RULES 数值/状态判定
 * 另外核心引擎在剧情副作用命中时会直接调用解锁接口。
 * ========================================================================= */
(function () {
  'use strict';

  /* ---------------- 解锁 ---------------- */
  TL.achByName = function (name) {
    for (var i = 0; i < TL.DATA.achievements.length; i++) {
      if (TL.DATA.achievements[i].name === name) { return TL.DATA.achievements[i]; }
    }
    return null;
  };
  TL.isUnlocked = function (name) { return TL.has(TL.global.achievements, name); };

  TL.unlock = function (name) {
    if (!name) { return false; }
    if (TL.isUnlocked(name)) { return false; }
    if (!TL.achByName(name)) { return false; } /* 未定义的成就名直接忽略，避免脏数据 */
    TL.global.achievements.push(name);
    TL.saveGlobal();
    window.toast('★ 成就解锁：' + name);
    return true;
  };

  /* ---------------- 日志关键词监听 ---------------- */
  TL.logHas = function (kw) {
    var s = TL.S; if (!s) { return false; }
    for (var i = 0; i < s.log.length; i++) {
      if (s.log[i].indexOf(kw) !== -1) { return true; }
    }
    return false;
  };
  TL.logCount = function (kw) {
    var s = TL.S, n = 0; if (!s) { return 0; }
    for (var i = 0; i < s.log.length; i++) {
      if (s.log[i].indexOf(kw) !== -1) { n++; }
    }
    return n;
  };

  /* 关键词组：命中任意一个即视为达成 */
  TL.LOG_ACH = [
    { name: '金榜题名', kws: ['高考'], extra: function (s) { return s.attrs['智力'] >= 75; } },
    { name: '学业中断', kws: ['辍学', '退学'] },
    { name: '老友重逢', kws: ['重逢'] },
    { name: '丧亲之痛', kws: ['父母离世', '办丧事', '父亲去世', '母亲去世', '亲人离世'] },
    { name: '感情破碎', kws: ['出轨', '背叛'] },
    { name: '融资成功', kws: ['融资', '投资人', '投资款', '天使轮'] },
    { name: '体质内上岸', kws: ['编制', '考编', '上岸', '公务员'] },
    { name: '手术台归来', kws: ['手术'] },
    { name: '心理重建', kws: ['心理咨询', '心理医生'] },
    { name: '被割韭菜', kws: ['暴雷', '血本无归', '亏光'] },
    { name: '下海经商', kws: ['下海'] },
    { name: '下岗再就业', kws: ['下岗'] },
    { name: '越狱未遂', kws: ['越狱'] },
    { name: '含饴弄孙', kws: ['孙子', '孙女', '孙辈', '抱上孙'] },
    { name: '回忆录作者', kws: ['回忆录'] },
    { name: '网暴受害者', kws: ['网暴', '谩骂', '被骂上热搜'] },
    { name: '机缘遇仙', kws: ['高人', '预知梦', '奇遇'] },
    { name: '流量红人', kws: ['爆火', '热搜', '涨粉'] },
    { name: '案底在身', kws: ['求职被拒', '案底'] },
    { name: '毛孩子爸妈', kws: ['流浪'] }
  ];

  /* ---------------- 状态 / 数值判定 ---------------- */
  TL.ACH_RULES = {
    '呱呱坠地': function (s) { return s.age >= 0; },
    '成年礼': function (s) { return s.age >= 18; },
    '情窦初开': function (s) { return TL.relCount('lover') >= 1; },
    '携手一生': function (s) { return TL.relCount('spouse') >= 1; },
    '初为父母': function (s) { return TL.relCount('child') >= 1; },
    '儿孙满堂': function (s) { return TL.relCount('child') >= 3; },
    '众叛亲离': function (s) { return TL.relCount('enemy') >= 3; },
    '铁哥们': function (s) {
      for (var i = 0; i < s.relations.length; i++) {
        if (s.relations[i].type === 'friend' && s.relations[i].affinity >= 90) { return true; }
      }
      return false;
    },
    '人脉广交': function (s) { return TL.relCount('friend') >= 10; },
    '一夜暴富': function (s) { return !!s.flags.bigGain; },
    '创业先锋': function (s) { return s.flags.startup && s.attrs['财富'] >= 80000; },
    '楼市赢家': function (s) { return s.flags.house && s.attrs['财富'] >= 150000; },
    '股神': function (s) { return !!s.flags.bigGain && (TL.logHas('股市') || TL.logHas('股票')); },
    '赌徒深渊': function (s) { return (s.addictions['赌瘾'] || 0) >= 50 || (s.assets.debt >= 50000 && (s.addictions['赌瘾'] || 0) > 0); },
    '浪子回头': function (s) {
      if (s.attrs['罪恶值'] >= 40) { s.flags.highCrime = 1; }
      return !!s.flags.highCrime && s.attrs['罪恶值'] <= 0;
    },
    '走遍山河': function (s) {
      if (TL.logHas('搬家') && s.flags.lastMoveYear !== s.age) { s.flags.lastMoveYear = s.age; s.moves += 1; }
      return s.moves >= 5;
    },
    '百病缠身': function (s) {
      if (s.attrs['健康值'] <= 20) {
        if (s.flags.lastHpYear !== s.age) { s.flags.lastHpYear = s.age; s.flags.lowHp = (s.flags.lowHp || 0) + 1; }
      }
      return (s.flags.lowHp || 0) >= 3;
    },
    '久病成医': function (s) { return TL.logCount('住院') >= 3; },
    'ICU奇迹': function (s) {
      if (TL.logHas('ICU') || TL.logHas('重症')) { s.flags.icu = 1; }
      return !!s.flags.icu && s.attrs['健康值'] >= 50;
    },
    '与遗传病共存': function (s) { return TL.logHas('遗传病') && s.attrs['健康值'] >= 60; },
    '理财达人': function (s) { return s.stat.income >= 100000 && TL.has(s.skills, 'finance'); },
    '时代见证者': function (s) {
      var n = 0;
      for (var i = 0; i < TL.ERAS.length; i++) { if (s.flags.eraSeen[TL.ERAS[i]]) { n++; } }
      return n >= 5;
    },
    '互联网原住民': function (s) {
      return !!(s.flags.eraSeen['00'] && s.flags.eraSeen['10'] && s.flags.eraSeen['20']);
    },
    '洗心革面': function (s) {
      if (s.flags.record && !s.flags.recordAge) { s.flags.recordAge = s.age; }
      return !!s.flags.record && s.attrs['罪恶值'] <= 5 && (s.age - (s.flags.recordAge || s.age)) >= 10;
    },
    '五毒俱全': function (s) {
      var n = 0;
      for (var i = 0; i < TL.ADDICTIONS.length; i++) {
        if ((s.addictions[TL.ADDICTIONS[i]] || 0) >= 50) { n++; }
      }
      return n >= 4;
    },
    '退休生活': function (s) { return s.age >= 60; }
  };

  /* ---------------- 主检查入口 ---------------- */
  TL.checkAchievements = function () {
    var s = TL.S;
    if (!s) { return; }
    try {
      var name, i;
      for (name in TL.ACH_RULES) {
        if (!Object.prototype.hasOwnProperty.call(TL.ACH_RULES, name)) { continue; }
        if (TL.isUnlocked(name)) { continue; }
        try { if (TL.ACH_RULES[name](s)) { TL.unlock(name); } } catch (e) { }
      }
      for (i = 0; i < TL.LOG_ACH.length; i++) {
        var item = TL.LOG_ACH[i];
        if (TL.isUnlocked(item.name)) { continue; }
        var hit = false;
        for (var j = 0; j < item.kws.length; j++) {
          if (TL.logHas(item.kws[j])) { hit = true; break; }
        }
        if (hit && item.extra && !item.extra(s)) { hit = false; }
        if (hit) { TL.unlock(item.name); }
      }
      if (s.assets.debt >= 50000) { s.flags.wasDebt = 1; }
    } catch (e) { }
  };

  TL.achStats = function () {
    var total = TL.DATA.achievements.length;
    var got = 0;
    for (var i = 0; i < TL.DATA.achievements.length; i++) {
      if (TL.isUnlocked(TL.DATA.achievements[i].name)) { got++; }
    }
    return { got: got, total: total };
  };
})();
