/* =========================================================================
 * TrollLifeAI · 职业深度线 + 家庭代际线
 *
 * 职业线：每个行业是一条职位阶梯（入门→熟练→资深→管理→领袖），
 *         行业景气随年代基线与随机波动变化，直接影响薪资、晋升概率与被裁风险。
 * 代际线：子女会跟着玩家一起变老（婴儿→幼儿→小学→中学→大学→成年→成家），
 *         同一批子女剧情只在对应阶段才触发，形成一条完整的成长链。
 * ========================================================================= */
(function () {
  'use strict';

  TL.CAREER = window.__TL_CAREER__ || {
    industries: [], levelNames: [], levelSalaryMul: [1], levelMinYears: [0], levelPerfNeed: [0], jobToIndustry: {}
  };

  /* ---------------- 行业与职位 ---------------- */
  TL.industryById = function (id) {
    var list = TL.CAREER.industries || [];
    for (var i = 0; i < list.length; i++) { if (list[i].id === id) { return list[i]; } }
    return null;
  };
  TL.jobTitle = function (industryId, level) {
    var ind = TL.industryById(industryId);
    if (!ind) { return ''; }
    return ind.ladder[TL.clamp(level, 0, ind.ladder.length - 1)];
  };
  TL.levelName = function (level) {
    var names = TL.CAREER.levelNames || [];
    return names[TL.clamp(level, 0, names.length - 1)] || '';
  };
  TL.eraMood = function (industryId, era) {
    var ind = TL.industryById(industryId);
    if (!ind || !ind.moodByEra) { return 60; }
    var v = ind.moodByEra[era];
    return (v === null || v === undefined) ? 0 : v;   /* 0 表示该年代这个行业还不存在 */
  };
  TL.industryMoodLabel = function (v) {
    if (v >= 80) { return '风口'; }
    if (v >= 62) { return '景气'; }
    if (v >= 45) { return '平稳'; }
    if (v >= 30) { return '下行'; }
    return '寒冬';
  };
  TL.calcSalary = function (s) {
    var ind = TL.industryById(s.jobIndustry);
    if (!ind) { return s.salary || 0; }
    var mul = (TL.CAREER.levelSalaryMul || [1])[TL.clamp(s.jobLevel, 0, 4)] || 1;
    var mood = TL.clamp((s.industryMood === undefined ? 60 : s.industryMood) / 60, 0.55, 1.6);
    var city = TL.city().attrEffect['财富上限'] || 1;
    var intel = 0.7 + (s.attrs['智力'] / 50) * 0.3;
    var skills = 1 + s.skills.length * 0.03;
    return Math.round(ind.base * mul * mood * city * intel * skills);
  };
  /* 入职：把剧情里的岗位名映射到行业与等级 */
  TL.takeJob = function (jobName, s) {
    s = s || TL.S;
    var map = TL.CAREER.jobToIndustry || {};
    var hit = map[jobName];
    s.jobIndustry = hit ? hit[0] : (s.jobIndustry || 'service');
    s.jobLevel = hit ? hit[1] : (s.jobLevel || 0);
    s.job = jobName || TL.jobTitle(s.jobIndustry, s.jobLevel);
    s.jobTenure = 0;
    if (s.performance === undefined) { s.performance = 50; }
    if (s.industryMood === undefined || !s.industryMood) { s.industryMood = TL.eraMood(s.jobIndustry, s.era); }
    s.salary = TL.calcSalary(s);
    if (s.jobIndustry === 'it' || s.jobIndustry === 'finance') { TL.unlock('大厂打工人'); }
    return s;
  };
  /* 跳槽：按行业景气与技能重算薪资；景气越高谈得越好 */
  TL.jobHop = function (s) {
    s = s || TL.S;
    var bonus = 1 + ((s.industryMood || 60) - 50) / 200 + s.skills.length * 0.02;
    if (TL.has(s.skills, 'negotiation_life')) { bonus += 0.05; }
    for (var i = 0; i < s.talents.length; i++) {
      if (s.talents[i].name === '社交达人' || s.talents[i].name === '商业嗅觉') { bonus += 0.05; }
    }
    s.salary = Math.round((s.salary || 6000) * TL.clamp(bonus, 0.8, 1.6));
    s.performance = 55;
    s.jobTenure = 0;
    return s.salary;
  };

  /* ---------------- 每年职业推进 ---------------- */
  TL.careerYearly = function () {
    var s = TL.S;
    var out = [];
    if (!s || s.prison > 0) { return out; }

    /* 1. 行业景气波动（向年代基线回归 + 随机游走） */
    if (s.jobIndustry) {
      var base = TL.eraMood(s.jobIndustry, s.era);
      if (base > 0) {
        if (!s.industryMood) { s.industryMood = base; }
        var pull = (base - s.industryMood) * 0.25;
        s.industryMood = TL.clamp(s.industryMood + pull + (TL.rnd(17) - 8), 5, 100);
      }
    }
    if (!s.job) { return out; }

    /* 2. 司龄与绩效 */
    s.jobTenure = (s.jobTenure || 0) + 1;
    if (s.jobTenure >= 10) { TL.unlock('职场老油条'); }
    var perf = (s.performance === undefined) ? 50 : s.performance;
    var drift = (s.attrs['智力'] - 50) / 25 + s.skills.length * 0.6 + (TL.rnd(21) - 8);
    for (var t = 0; t < s.talents.length; t++) {
      var tn = s.talents[t].name;
      if (tn === '天生劳碌命') { drift += 2; }
      if (tn === '拖延症') { drift -= 4; }
      if (tn === '晚熟之人' && s.age >= 40) { drift += 3; }
      if (tn === '夜猫子') { drift += 1; }
    }
    if (s.attrs['压力值'] >= 80) { drift -= 3; }
    if (s.flags.restedYear === s.age) { drift -= 3; }   /* 上一年在休息摸鱼 */
    s.performance = TL.clamp(Math.round(perf + drift), 0, 100);

    /* 3. 晋升判定 */
    var needPerf = (TL.CAREER.levelPerfNeed || [])[s.jobLevel] || 60;
    var needYears = (TL.CAREER.levelMinYears || [])[s.jobLevel] || 2;
    var ind = TL.industryById(s.jobIndustry);
    var maxLevel = ind ? ind.ladder.length - 1 : 0;
    if (s.jobLevel < maxLevel && s.performance >= needPerf && s.jobTenure >= needYears) {
      var chance = 0.35 + (s.performance - needPerf) / 200;
      if (s.industryMood >= 70) { chance += 0.10; }
      if (s.industryMood < 35) { chance -= 0.15; }
      if (s.flags.pushedPromotion === s.age) { chance += 0.25; }   /* 主动争取晋升 */
      if (Math.random() < chance) {
        s.jobLevel += 1;
        s.job = TL.jobTitle(s.jobIndustry, s.jobLevel);
        s.salary = TL.calcSalary(s);
        out.push('晋升为「' + s.job + '」，月薪 ' + TL.fmt(s.salary));
        TL.addLog('第 ' + s.age + ' 年：晋升为「' + s.job + '」（' + TL.levelName(s.jobLevel) + '）');
        window.toast('晋升！你现在是 ' + s.job);
        TL.unlock('步步高升');
        if (s.jobLevel >= 4) { TL.unlock('行业领袖'); }
      }
    }

    /* 4. 行业寒冬 → 裁员风险 */
    if (s.industryMood < 38) {
      var risk = (38 - s.industryMood) / 100 + (50 - s.performance) / 300;
      for (var k = 0; k < s.talents.length; k++) {
        if (s.talents[k].name === '小镇做题家' || s.talents[k].name === '学霸体质') { risk -= 0.04; }
      }
      if (TL.has(s.skills, 'law')) { risk -= 0.03; }
      risk = TL.clamp(risk, 0, 0.45);
      if (Math.random() < risk) {
        out.push('行业寒冬，' + s.job + ' 岗位被优化');
        TL.addLog('第 ' + s.age + ' 年：行业寒冬，被公司优化（原岗位 ' + s.job + '）');
        window.toast('行业寒冬：你被裁了');
        s.job = ''; s.salary = 0; s.flags.fired = 1;
        TL.unlock('被优化了');
        if (s.age >= 35 && s.age <= 50) { TL.unlock('中年危机'); }
        return out;
      }
    }
    s.salary = TL.calcSalary(s);
    return out;
  };

  /* ---------------- 家庭代际线 ---------------- */
  TL.CHILD_STAGES = [
    { id: 'baby', name: '婴儿', min: 0, max: 2 },
    { id: 'toddler', name: '幼儿', min: 3, max: 5 },
    { id: 'primary', name: '小学', min: 6, max: 11 },
    { id: 'teen', name: '中学', min: 12, max: 17 },
    { id: 'college', name: '大学', min: 18, max: 22 },
    { id: 'adult', name: '成年', min: 23, max: 29 },
    { id: 'family', name: '成家', min: 30, max: 200 }
  ];
  TL.CHILD_TALENTS = ['聪明', '健壮', '好看', '内向', '调皮', '有艺术天赋', '有运动天赋', '稳重', '倔强', '乐观'];

  TL.stageOfChildAge = function (age) {
    for (var i = 0; i < TL.CHILD_STAGES.length; i++) {
      if (age >= TL.CHILD_STAGES[i].min && age <= TL.CHILD_STAGES[i].max) { return TL.CHILD_STAGES[i]; }
    }
    return TL.CHILD_STAGES[TL.CHILD_STAGES.length - 1];
  };
  TL.stageName = function (stageId) {
    for (var i = 0; i < TL.CHILD_STAGES.length; i++) {
      if (TL.CHILD_STAGES[i].id === stageId) { return TL.CHILD_STAGES[i].name; }
    }
    return stageId;
  };
  TL.anyChildInStage = function (s, stageId) {
    for (var i = 0; i < s.relations.length; i++) {
      var r = s.relations[i];
      if (r.type === 'child' && r.alive !== false && r.stage === stageId) { return true; }
    }
    return false;
  };
  TL.childList = function (s) {
    var out = [];
    for (var i = 0; i < s.relations.length; i++) {
      if (s.relations[i].type === 'child') { out.push(s.relations[i]); }
    }
    return out;
  };
  /* 子女阶段校验：只对带 {孩子} 占位符的子女剧情生效 */
  TL.childStageReason = function (ev, s) {
    if (!s) { return ''; }
    var text = TL.eventText(ev);
    if (text.indexOf('{孩子}') === -1) { return ''; }
    if (TL.relCount('child') === 0) { return '还没有子女，不该触发这段剧情'; }
    var rules = TL.RULES.childStageRules || [];
    for (var i = 0; i < rules.length; i++) {
      var r = rules[i];
      if (!r.kw || !r.stage) { continue; }
      if (new RegExp(r.kw).test(text)) {
        if (!TL.anyChildInStage(s, r.stage)) {
          return '子女不在「' + TL.stageName(r.stage) + '」阶段，不该触发这段剧情';
        }
        return '';
      }
    }
    return '';
  };
  /* 每年子女长大一岁；阶段变化时提示；成年后按亲密度反哺 */
  TL.childrenYearly = function () {
    var s = TL.S, out = [];
    if (!s) { return out; }
    for (var i = 0; i < s.relations.length; i++) {
      var r = s.relations[i];
      if (r.type !== 'child' || r.alive === false) { continue; }
      var before = r.stage;
      r.age = (r.age || 0) + 1;
      var st = TL.stageOfChildAge(r.age);
      r.stage = st.id;
      if (before && before !== st.id) {
        out.push(r.name + ' 进入' + st.name + '阶段（' + r.age + ' 岁）');
        TL.addLog('第 ' + s.age + ' 年：' + r.name + ' 进入' + st.name + '阶段（' + r.age + ' 岁）');
        if (st.id === 'primary') { TL.unlock('背上小书包'); }
        if (st.id === 'college') { TL.unlock('望子成龙'); }
        if (st.id === 'family') { TL.unlock('儿女成家'); }
      }
      /* 成年后慢慢独立：亲密度缓慢下降；亲密度高则主动反哺 */
      if (st.id === 'adult' || st.id === 'family' || st.id === 'college') {
        r.affinity = TL.clamp((r.affinity || 60) - 1, 0, 100);
        if (r.affinity >= 70 && Math.random() < 0.3) {
          var give = 3000 + TL.rnd(9000);
          TL.applyAttr({ '智力': 0, '体质': 0, '魅力': 0, '财富': give, '快乐': 3, '运气': 0, '健康值': 0, '成瘾值': 0, '名声值': 1, '压力值': -2, '罪恶值': 0 }, true);
          out.push(r.name + ' 给你转了 ' + TL.fmt(give) + ' 元');
          TL.addLog('第 ' + s.age + ' 年：' + r.name + ' 主动给你转了 ' + TL.fmt(give) + ' 元');
        }
      }
    }
    return out;
  };
})();
