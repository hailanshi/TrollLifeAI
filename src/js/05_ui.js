/* =========================================================================
 * TrollLifeAI · 界面层
 * 规则：
 *  - 动态 DOM 一律用内联 onclick 调用 window.ui 上的方法，所有处理函数挂在 window 上；
 *  - 确认弹窗用全局变量 __confirm 存 {fn,args}，确定键统一走 window.doConfirmOK()；
 *  - 所有业务外层 try-catch，任何改动都给 toast 反馈；
 *  - 长列表弹窗：标题固定顶部 / 内容独立滚动 / 按钮固定底部。
 * ========================================================================= */
(function () {
  'use strict';

  var ui = {};
  window.ui = ui;

  ui.tab = 'home';
  ui.currentEvent = null;      /* 当前事件（避免用闭包传参） */
  ui.startEra = '00';
  ui.startCity = '二线城市';
  ui.drawnTalents = [];
  ui.pickedTalent = -1;
  ui.rerollLeft = 3;
  ui.startMode = 'new';        /* new | reincarnate */
  ui.achFilter = 'all';        /* all | got | locked */
  ui.busy = false;
  ui.playerName = '';          /* 开局页输入的名字（渲染会重建 DOM，所以存在这里） */
  ui.gender = '男';
  ui.currentEventIsAi = false; /* 当前弹窗里的事件是否由 AI 生成 */
  ui.aiState = null;           /* AI 请求进行中的状态（避免闭包丢参） */
  ui.saveTab = 0;

  /* ---------------- 小工具 ---------------- */
  function esc(t) {
    if (t === undefined || t === null) { return ''; }
    return String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  function $(id) { return document.getElementById(id); }
  /* 展示用文本：把引擎使用的剧情标记【…】去掉，玩家不该看到内部约定 */
  function stripMarks(t) {
    if (t === undefined || t === null) { return ''; }
    return String(t).replace(/【[^】]*】/g, '').replace(/\s{2,}/g, ' ').trim();
  }
  function cls(v) { return v > 0 ? 'up' : (v < 0 ? 'down' : 'zero'); }
  function sign(v) { return (v > 0 ? '+' : '') + TL.fmt(v); }

  window.toast = function (msg) {
    try {
      var t = $('toast');
      t.innerHTML = esc(msg);
      t.className = 'show';
      if (window.__toastTimer) { clearTimeout(window.__toastTimer); }
      window.__toastTimer = setTimeout(function () { t.className = ''; }, 2200);
    } catch (e) { }
  };

  function openModal(title, sub, body, foot) {
    try {
      $('mTitle').innerHTML = title;
      $('mSub').innerHTML = sub || '';
      $('mBody').innerHTML = body || '';
      $('mFoot').innerHTML = foot || '';
      $('mBody').scrollTop = 0;
      $('modalRoot').className = 'show';
    } catch (e) { window.toast('弹窗打开失败'); }
  }
  function closeModal() { try { $('modalRoot').className = ''; } catch (e) { } }
  ui.closeModal = closeModal;

  /* ---------------- 确认弹窗（全局变量，不用闭包） ---------------- */
  window.__confirm = null;
  ui.ask = function (title, text, fnName, args) {
    window.__confirm = { fn: fnName, args: args || [] };
    openModal(esc(title), '', '<div class="story">' + esc(text) + '</div>',
      '<div class="btnRow">' +
      '<button class="btn ghost" onclick="window.doConfirmCancel()">取消</button>' +
      '<button class="btn warn" onclick="window.doConfirmOK()">确定</button></div>');
  };
  /* 解析 'ui.doGiveUp' 这类带命名空间的函数名。
     历史 bug：以前用 window['ui.doGiveUp'] 取值，永远取不到（点在 window.ui 上），
     导致所有确认弹窗都报「动作丢失」（放弃本世/转世、清空存档、解锁全部成就都失效）。 */
  function resolveAction(path) {
    try {
      var parts = String(path || '').split('.');
      var obj = window, fn = null, ctx = null;
      for (var i = 0; i < parts.length; i++) {
        if (!obj) { return null; }
        ctx = obj;
        fn = obj[parts[i]];
        obj = fn;
      }
      if (typeof fn !== 'function') { return null; }
      return { fn: fn, ctx: ctx };
    } catch (e) { return null; }
  }

  window.doConfirmOK = function () {
    var c = window.__confirm;
    if (!c) { return; }
    try {
      var target = resolveAction(c.fn);
      if (target) { target.fn.apply(target.ctx, c.args || []); }
      else { window.toast('动作丢失：' + c.fn); }
    } catch (e) { window.toast('执行失败：' + e.message); }
    /* 注意：先执行，再关闭弹窗；关闭时不提前清空回调变量 */
    closeModal();
    window.__confirm = null;
  };
  window.doConfirmCancel = function () { closeModal(); window.__confirm = null; };

  /* ---------------- 视图切换 ---------------- */
  ui.go = function (tab) {
    try {
      ui.tab = tab;
      render();
      $('screen').scrollTop = 0;
    } catch (e) { window.toast('页面切换失败'); }
  };

  function navVisible(v) {
    $('nav').className = v ? 'safe-bottom' : 'hide';
    $('screen').className = v ? '' : 'noNav';
    syncLayout();
  }

  /* 用实测高度修正内容区上下留白：
     顶栏高度 = 刘海安全区 + 44pt；底部导航高度同理。
     不做这一步，iPhone 上每页第一行文字会被顶栏盖住。 */
  function syncLayout() {
    try {
      var topbar = $('topbar'), nav = $('nav'), screen = $('screen');
      if (!topbar || !screen) { return; }
      var topH = topbar.offsetHeight || 44;
      var navH = 0;
      if (nav && nav.className.indexOf('hide') === -1) { navH = nav.offsetHeight || 48; }
      screen.style.paddingTop = (topH + 10) + 'px';
      screen.style.paddingBottom = navH > 0 ? (navH + 12) + 'px' : '16px';
    } catch (e) { }
  }
  ui.syncLayout = syncLayout;
  function setTop(age, era) {
    var S = TL.S;
    if (age === null || !S) {
      $('chipAge').innerHTML = '年龄 --';
    } else {
      $('chipAge').innerHTML = esc(S.name || '') + ' · ' + (S.gender || '') + ' · ' + age + '岁';
    }
    $('chipEra').innerHTML = era ? ('年代 ' + TL.ERA_NAME[era]) : '年代 --';
  }

  function render() {
    var S = TL.S;
    syncLayout();
    if (ui.tab !== 'start' && (!S || !S.alive)) {
      if (S && !S.alive && ui.tab !== 're') { ui.tab = 're'; }
    }
    if (ui.tab === 'start') { navVisible(false); setTop(null, ui.startEra); viewStart(); return; }
    navVisible(true);
    setTop(S ? S.age : null, S ? S.era : '');
    var tabs = ['home', 'ai', 'skill', 'ach', 're', 'god'];
    for (var i = 0; i < tabs.length; i++) {
      $('tab_' + tabs[i]).className = 'tab' + (ui.tab === tabs[i] ? ' on' : '');
    }
    if (ui.tab === 'home') { viewHome(); }
    else if (ui.tab === 'ai') { viewAi(); }
    else if (ui.tab === 'skill') { viewSkill(); }
    else if (ui.tab === 'ach') { viewAch(); }
    else if (ui.tab === 're') { viewRe(); }
    else { viewGod(); }
  }
  ui.render = render;

  /* ---------------- 开局 / 转世页 ---------------- */
  function viewStart() {
    var html = '';
    var reinc = ui.startMode === 'reincarnate';
    html += '<div class="card"><h3>' + (reinc ? '转世重生' : '人生重开') + '<span class="tail">TrollLifeAI</span></h3>' +
      '<div class="muted">先决定「你是谁」，再选择出生年代与城市，抽取天赋后开启这一世。' +
      (reinc ? '上一世的少量属性已作为「前世余荫」继承。' : '') + '</div></div>';

    /* 名字与性别 */
    var nameVal = ui.playerName || '';
    html += '<div class="card"><h3>① 你是谁</h3>' +
      '<div class="nameRow">' +
      '<input class="inp nameInp" id="playerNameInput" type="text" maxlength="8" ' +
      'placeholder="给自己起个名字" value="' + esc(nameVal) + '" ' +
      'oninput="window.ui.onNameInput(this.value)">' +
      '<button class="btn sm nameDice" onclick="window.ui.randomName()">随机</button>' +
      '</div>' +
      '<div class="grid2" style="margin-top:8px">' +
      '<button class="btn sm ' + (ui.gender === '男' ? 'primary' : '') + '" onclick="window.ui.setGender(\'男\')">♂ 男</button>' +
      '<button class="btn sm ' + (ui.gender === '女' ? 'primary' : '') + '" onclick="window.ui.setGender(\'女\')">♀ 女</button>' +
      '</div>' +
      '<div class="tiny" style="margin-top:6px">性别会影响部分专属剧情（例如产假、彩礼、婆婆/岳父这类情节），也会改变剧情里的称谓。</div>' +
      '</div>';

    /* 年代 */
    html += '<div class="card"><h3>② 选择出生年代</h3><div class="grid3">';
    for (var i = 0; i < TL.ERAS.length; i++) {
      var e = TL.ERAS[i];
      html += '<button class="btn sm ' + (ui.startEra === e ? 'primary' : '') + '" onclick="window.ui.setEra(\'' + e + '\')">' + TL.ERA_NAME[e] + '</button>';
    }
    html += '</div><div class="tiny">不同年代会解锁专属的公共大事件，影响机遇、薪资与社会环境。</div></div>';

    /* 城市 */
    html += '<div class="card"><h3>③ 选择出生城市</h3>';
    for (var c = 0; c < TL.DATA.city.length; c++) {
      var city = TL.DATA.city[c];
      var ok = !!city.eraFactor[ui.startEra];
      html += '<div class="choice ' + (ui.startCity === city.cityName ? 'sel' : '') + '"' +
        (ok ? ' onclick="window.ui.setCity(\'' + esc(city.cityName) + '\')"' : '') +
        (ui.startCity === city.cityName ? ' style="border-color:#2b8c68"' : '') + '>' +
        '<div class="t">' + esc(city.cityName) + (ok ? '' : ' <span class="tiny">（该年代暂未开放）</span>') + '</div>' +
        '<div class="d">' + esc(city.desc) + '</div>' +
        '<div class="tiny">压力修正 ' + sign(city.attrEffect['压力值']) + ' · 财富上限系数 ×' + city.attrEffect['财富上限'] + '</div>' +
        '</div>';
    }
    html += '</div>';

    /* 天赋 */
    html += '<div class="card"><h3>④ 抽取天赋（3 选 1）<span class="tail">剩余重抽 ' + ui.rerollLeft + '</span></h3>';
    if (!ui.drawnTalents.length) {
      html += '<button class="btn primary" onclick="window.ui.drawTalents()">抽取天赋</button>';
    } else {
      for (var t = 0; t < ui.drawnTalents.length; t++) {
        var tal = ui.drawnTalents[t];
        html += '<div class="talentCard' + (ui.pickedTalent === t ? ' sel' : '') + '" onclick="window.ui.pickTalent(' + t + ')">' +
          '<div class="tn">' + esc(tal.name) + '</div>' +
          '<div class="td">' + esc(tal.desc) + '</div>' +
          '<div class="tm">' + talentModText(tal) + '</div></div>';
      }
      html += '<div class="btnRow">' +
        '<button class="btn ghost" onclick="window.ui.drawTalents()">重新抽取（剩 ' + ui.rerollLeft + '）</button></div>';
    }
    html += '</div>';

    /* 开始 */
    var ready = ui.startEra && ui.startCity && ui.pickedTalent >= 0;
    html += '<div class="card"><button class="btn primary" ' + (ready ? '' : 'disabled ') + 'onclick="window.ui.beginLife()">' +
      (reinc ? '开始这一世' : '开始人生') + '</button>' +
      '<button class="btn ghost" onclick="window.ui.askResetAll()">清空全部存档（含成就）</button>' +
      '<div class="tiny center">数据保存在本机 localStorage，不需要联网。</div></div>';

    if (TL.global.lives > 0) {
      html += '<div class="card"><h3>前尘往事</h3><div class="muted">已轮回 ' + TL.global.lives + ' 世 · 最高寿命 ' +
        TL.global.bestAge + ' 岁 · 成就 ' + TL.achStats().got + '/' + TL.achStats().total + '</div>' +
        '<div class="tiny">前世余荫：' + inheritText() + '</div></div>';
    }
    $('screen').innerHTML = html;
  }

  function talentModText(tal) {
    var m = tal.attrModify || {}, parts = [];
    for (var k in m) {
      if (!Object.prototype.hasOwnProperty.call(m, k)) { continue; }
      if (m[k] === 0) { continue; }
      parts.push(k + (m[k] > 0 ? '+' : '') + (k === '财富' ? TL.fmt(m[k]) : m[k]));
    }
    return parts.length ? parts.join('  ') : '无属性修正';
  }
  function inheritText() {
    var inh = TL.global.inherit || {}, parts = [];
    for (var k in inh) {
      if (!Object.prototype.hasOwnProperty.call(inh, k)) { continue; }
      if (inh[k]) { parts.push(k + '+' + inh[k]); }
    }
    return parts.length ? parts.join('  ') : '无';
  }

  /* ---------------- 名字与性别 ---------------- */
  ui.onNameInput = function (v) {
    ui.playerName = String(v || '').slice(0, 8);
  };
  ui.setGender = function (g) {
    var changed = (ui.gender !== g);
    ui.gender = (g === '女') ? '女' : '男';
    /* 名字还是上一个性别的默认名（或为空）时，自动换一个贴合的名字 */
    if (changed && (!ui.playerName || TL.has(TL.NAME_POOL['男'], ui.playerName) || TL.has(TL.NAME_POOL['女'], ui.playerName))) {
      ui.playerName = TL.randomName(ui.gender);
    }
    render();
  };
  ui.randomName = function () {
    ui.playerName = TL.randomName(ui.gender);
    window.toast('换了个名字：' + ui.playerName);
    render();
  };

  ui.setEra = function (e) {    ui.startEra = e;
    /* 城市必须适配年代 */
    var cur = TL.cityByName(ui.startCity);
    if (!cur || !cur.eraFactor[e]) {
      for (var i = 0; i < TL.DATA.city.length; i++) {
        if (TL.DATA.city[i].eraFactor[e]) { ui.startCity = TL.DATA.city[i].cityName; break; }
      }
    }
    render();
  };
  ui.setCity = function (name) { ui.startCity = name; render(); };

  ui.drawTalents = function () {
    try {
      if (ui.drawnTalents.length && ui.rerollLeft <= 0) { window.toast('重抽次数已用完'); return; }
      if (ui.drawnTalents.length) { ui.rerollLeft -= 1; }
      var pool = TL.DATA.talents.slice(0);
      var out = [], used = {};
      var guard = 0;
      while (out.length < 3 && guard < 500) {
        guard++;
        var i = TL.rnd(pool.length);
        if (used[i]) { continue; }
        used[i] = 1;
        out.push(pool[i]);
      }
      ui.drawnTalents = out;
      ui.pickedTalent = -1;
      window.toast('抽到 ' + out.length + ' 个天赋，请选择 1 个');
      render();
    } catch (e) { window.toast('抽天赋失败：' + e.message); }
  };
  ui.pickTalent = function (i) {
    ui.pickedTalent = i;
    window.toast('已选择：' + ui.drawnTalents[i].name);
    render();
  };
  ui.beginLife = function () {
    try {
      if (ui.pickedTalent < 0) { window.toast('请先抽取并选择天赋'); return; }
      var talents = [ui.drawnTalents[ui.pickedTalent]];
      var pname = ui.playerName || TL.randomName(ui.gender);
      if (ui.startMode === 'reincarnate') {
        TL.reincarnate(ui.startEra, ui.startCity, talents, pname, ui.gender);
      } else {
        TL.S = TL.newState(ui.startEra, ui.startCity, talents, pname, ui.gender);
        TL.addLog('第 0 年：' + pname + '（' + ui.gender + '）出生在【' + ui.startCity + '】，年代【' + TL.ERA_NAME[ui.startEra] + '】');
        TL.unlock('呱呱坠地');
      }
      TL.save();
      ui.startMode = 'new';
      ui.drawnTalents = []; ui.pickedTalent = -1; ui.rerollLeft = 3;
      ui.tab = 'home';
      window.toast(pname + ' 的人生开始了！点击「过一年」推进剧情');
      render();
    } catch (e) { window.toast('开局失败：' + e.message); }
  };

  ui.askResetAll = function () {
    ui.ask('清空全部存档', '将删除当前人生与所有已解锁成就，且无法恢复。确定继续？', 'ui.doResetAll', []);
  };
  ui.doResetAll = function () {
    TL.resetAll(); window.toast('已清空全部存档');
    ui.startMode = 'new'; ui.drawnTalents = []; ui.pickedTalent = -1; ui.rerollLeft = 3;
    ui.tab = 'start'; render();
  };

  /* ---------------- 属性主页 ---------------- */
  function viewHome() {
    var S = TL.S;
    if (!S) { ui.tab = 'start'; viewStart(); return; }
    if (!S.alive) { ui.tab = 're'; viewRe(); return; }
    var h = '';

    /* 状态与推进 */
    h += '<div class="card"><h3>人生进度<span class="tail">' + TL.ERA_NAME[S.era] + ' · ' + esc(S.cityName) + '</span></h3>' +
      '<div class="row"><div><div class="big">' + esc(S.name || '') +
      ' <span style="font-size:13px;color:#7fd1ae">' + (S.gender === '女' ? '♀' : '♂') + '</span></div>' +
      '<div class="tiny">' + S.age + ' 岁 · 预计寿命 ' + S.lifespan + ' 岁 · 职业：' + (S.job ? esc(S.job) : '无业') +
      (S.salary ? '（月薪 ' + TL.fmt(S.salary) + '）' : '') + '</div></div>' +
      '<div class="tiny center">' + (S.prison > 0 ? ('服刑中 剩 ' + S.prison + ' 年') : '自由身') + '</div></div>' +
      (S.prison > 0 ? '<div class="tiny">服刑期间只能推进年份，出狱后案底会压低收入。</div>' : '') +
      '<div class="sep"></div>' +
      '<button class="btn primary" onclick="window.ui.nextYear()">过一年（第 ' + (S.age + 1) + ' 岁）</button>' +
      '<div class="btnRow"><button class="btn sm" onclick="window.ui.fastForward()">快进 10 年</button>' +
      '<button class="btn sm ghost" onclick="window.ui.showLifeLog()">人生日志</button></div>' +
      '<div class="tiny">快进会替你做抉择（自动挑综合最划算的选项），结束后给出这十年的总结。</div>' +
      '</div>';

    /* 职业发展（行业阶梯 + 行业景气） */
    var ind = TL.industryById(S.jobIndustry);
    if (ind || S.job) {
      var mood = S.industryMood || 0;
      var perf = (S.performance === undefined) ? 50 : S.performance;
      var maxLv = ind ? ind.ladder.length - 1 : 0;
      var needPerf = (TL.CAREER.levelPerfNeed || [])[S.jobLevel] || 0;
      var needYears = (TL.CAREER.levelMinYears || [])[S.jobLevel] || 0;
      h += '<div class="card"><h3>职业发展<span class="tail">' + (ind ? esc(ind.name) : '—') + '</span></h3>';
      if (S.job) {
        h += '<div class="row"><div><div class="big" style="font-size:18px">' + esc(S.job) + '</div>' +
          '<div class="tiny">' + esc(TL.levelName(S.jobLevel)) + '级 · 第 ' + (S.jobLevel + 1) + '/' + (maxLv + 1) +
          ' 阶 · 司龄 ' + (S.jobTenure || 0) + ' 年</div></div>' +
          '<div class="tiny center">月薪<br><b style="font-size:14px;color:#7fd1ae">' + TL.fmt(S.salary) + '</b></div></div>';
      } else {
        h += '<div class="tiny down">目前处于失业状态' + (ind ? ('（行业：' + esc(ind.name) + '，景气 ' + mood + '）') : '') + '</div>';
      }
      if (ind) {
        h += '<div class="ladderBox">';
        for (var lv = 0; lv < ind.ladder.length; lv++) {
          var on = (S.job && lv <= S.jobLevel) ? ' on' : '';
          h += '<span class="ladderStep' + on + '">' + esc(ind.ladder[lv]) + '</span>';
        }
        h += '</div>';
      }
      h += '<div class="attrRow"><div style="flex:1"><div class="attrName">绩效</div>' +
        '<div class="bar"><i style="width:' + TL.clamp(perf, 0, 100) + '%;background:' +
        (perf >= 70 ? '#4a9d7f' : (perf >= 45 ? '#e0b060' : '#e8796b')) + '"></i></div></div>' +
        '<div class="attrVal">' + perf + '</div></div>';
      h += '<div class="attrRow"><div style="flex:1"><div class="attrName">行业景气 · ' + TL.industryMoodLabel(mood) + '</div>' +
        '<div class="bar"><i style="width:' + TL.clamp(mood, 0, 100) + '%;background:' +
        (mood >= 62 ? '#4a9d7f' : (mood >= 38 ? '#e0b060' : '#e8796b')) + '"></i></div></div>' +
        '<div class="attrVal">' + mood + '</div></div>';
      if (S.job && ind && S.jobLevel < maxLv) {
        h += '<div class="tiny">下一阶「' + esc(ind.ladder[S.jobLevel + 1]) + '」需要 绩效 ≥ ' + needPerf +
          '、司龄 ≥ ' + needYears + ' 年；可用「争取晋升」行动提高概率。</div>';
      } else if (S.job) {
        h += '<div class="tiny">已经是这个行业的最高职位。</div>';
      }
      if (mood > 0 && mood < 38) { h += '<div class="tiny down">行业正处于寒冬，注意裁员风险。</div>'; }
      h += '</div>';
    }

    /* 主动行动（每岁 1 点行动力） */
    h += '<div class="card"><h3>主动行动<span class="tail">行动点 ' + S.actionPoints + ' / 1</span></h3>' +
      '<div class="tiny">每年 1 点行动力，可以主动做一件事；也可以什么都不做直接过一年。</div>';
    if (S.prison > 0) { h += '<div class="tiny down" style="margin-top:6px">服刑期间失去行动自由</div>'; }
    h += '<div class="actGrid">';
    for (var ai = 0; ai < TL.ACTIONS.length; ai++) {
      var act = TL.ACTIONS[ai];
      var why = act.need ? act.need(S) : '';
      var usable = S.actionPoints > 0 && S.prison === 0 && !why;
      h += '<div class="actCard' + (usable ? '' : ' locked') + '"' +
        (usable ? ' onclick="window.ui.doAction(\'' + act.id + '\')"' : '') + '>' +
        '<div class="an">' + esc(act.name) + '<span class="atag">' + esc(act.tag) + '</span></div>' +
        '<div class="ad">' + esc(usable ? act.desc : (why || act.desc)) + '</div></div>';
    }
    h += '</div></div>';

    /* 11 项属性 */
    h += '<div class="card"><h3>角色属性<span class="tail">共 11 项</span></h3>';
    for (var i = 0; i < TL.ATTRS.length; i++) {
      var k = TL.ATTRS[i];
      var v = S.attrs[k];
      var show = (k === '财富') ? TL.fmt(v) : v;
      var pct = (k === '财富') ? TL.clamp(Math.round(v / TL.moneyCap() * 100), 0, 100) : TL.clamp(v, 0, 100);
      h += '<div class="attrRow"><div style="flex:1"><div class="attrName">' + k + '</div>' +
        '<div class="bar"><i style="width:' + pct + '%;background:' + barColor(k, v) + '"></i></div></div>' +
        '<div class="attrVal">' + show + '</div></div>';
    }
    h += '<div class="tiny">财富上限（城市系数）：' + TL.fmt(TL.moneyCap()) + '</div></div>';

    /* 资产与负债 */
    h += '<div class="card"><h3>资产与负债</h3>' +
      row('现金', TL.fmt(S.attrs['财富'])) +
      row('房产', S.assets.house + ' 套') +
      row('车辆', S.assets.car + ' 辆') +
      row('奢侈品', S.assets.luxury + ' 件') +
      row('商业保险', S.assets.insurance + ' 份') +
      row('负债', '<span class="' + (S.assets.debt > 0 ? 'down' : 'zero') + '">' + TL.fmt(S.assets.debt) + '</span>') +
      row('净资产', TL.fmt(S.attrs['财富'] - S.assets.debt + S.assets.house * 800000 * (TL.city().attrEffect['财富上限'] || 1))) +
      '</div>';

    /* 成瘾 */
    var addKeys = [];
    for (var ak in S.addictions) { if (Object.prototype.hasOwnProperty.call(S.addictions, ak)) { addKeys.push(ak); } }
    h += '<div class="card"><h3>成瘾状态<span class="tail">成瘾值 ' + S.attrs['成瘾值'] + '</span></h3>';
    if (!addKeys.length) { h += '<div class="tiny">暂无成瘾记录</div>'; }
    for (var a = 0; a < addKeys.length; a++) {
      h += row(addKeys[a], (S.addictions[addKeys[a]] || 0) + ' / 100');
    }
    if (S.attrs['成瘾值'] >= 60) { h += '<div class="tiny down">成瘾值偏高，每年都可能触发成瘾发作事件。</div>'; }
    h += '</div>';

    /* 人际关系 */
    h += '<div class="card"><h3>人际关系<span class="tail">' + S.relations.length + ' 人</span></h3>';
    if (!S.relations.length) { h += '<div class="tiny">暂无关系，多参与社交事件吧</div>'; }
    for (var r = 0; r < S.relations.length; r++) {
      var rel = S.relations[r];
      var relSub = (TL.REL_TYPES[rel.type] || rel.type) + ' · ' + (rel.since !== undefined ? (rel.since + ' 岁结识') : '');
      if (rel.type === 'child' && rel.stage) {
        relSub = '子女 · ' + (rel.age || 0) + ' 岁 · ' + TL.stageName(rel.stage) + (rel.talent ? (' · ' + rel.talent) : '');
      }
      h += '<div class="listItem"><div class="li-main"><div class="li-name">' +
        (rel.alive === false ? '<span class="tiny">[已结束] </span>' : '') + esc(rel.name) + '</div>' +
        '<div class="li-sub">' + esc(relSub) +
        (rel.lastAct !== undefined && rel.lastAct === S.age ? ' · 今年已互动' : '') + '</div></div>' +
        '<div class="li-right">好感 ' + rel.affinity + '</div></div>';
      if (rel.alive !== false && S.alive) {
        h += relButtons(rel, S);
      }
    }
    h += '</div>';

    /* 宠物 */
    h += '<div class="card"><h3>宠物<span class="tail">' + S.pets.length + ' 只</span></h3>';
    if (!S.pets.length) { h += '<div class="tiny">还没有宠物</div>'; }
    for (var p = 0; p < S.pets.length; p++) {
      var pet = S.pets[p];
      h += '<div class="listItem"><div class="li-main"><div class="li-name">' + esc(pet.name) + '</div>' +
        '<div class="li-sub">' + esc(pet.species) + ' · ' + pet.age + ' 岁</div></div>' +
        '<div class="li-right">' + (pet.alive ? ('健康 ' + pet.health) : (pet.lost ? '走失' : '已离世')) + '</div></div>';
    }
    h += '</div>';

    /* 天赋与本世技能 */
    h += '<div class="card"><h3>本世天赋</h3>';
    for (var t2 = 0; t2 < S.talents.length; t2++) {
      h += '<div class="listItem"><div class="li-main"><div class="li-name">' + esc(S.talents[t2].name) + '</div>' +
        '<div class="li-sub">' + esc(S.talents[t2].desc) + '</div></div></div>';
    }
    h += '<div class="tiny">已习得技能 ' + S.skills.length + ' 个（事件成功率加成 +' +
      Math.round(TL.skillBonus('测试') * 100) + '% 起）</div></div>';

    /* 最近日志 */
    h += '<div class="card"><h3>最近人生经历</h3><div class="scrollBox">';
    if (!S.log.length) { h += '<div class="tiny">还没有经历</div>'; }
    for (var g = 0; g < Math.min(S.log.length, 12); g++) {
      h += '<div class="logItem">' + esc(stripMarks(TL.fill(S.log[g]))) + '</div>';
    }
    h += '</div></div>';

    $('screen').innerHTML = h;
  }

  function barColor(k, v) {
    if (k === '压力值' || k === '成瘾值' || k === '罪恶值') {
      return v >= 70 ? '#e8796b' : (v >= 40 ? '#e0b060' : '#4a9d7f');
    }
    return v >= 60 ? '#4a9d7f' : (v >= 30 ? '#e0b060' : '#e8796b');
  }
  function row(label, val) {
    return '<div class="listItem"><div class="li-name">' + label + '</div><div class="li-right">' + val + '</div></div>';
  }
  function switchRow(label, on, handler) {
    return '<div class="switchRow"><span class="sl">' + esc(label) + '</span>' +
      '<span class="badge ' + (on ? 'on' : 'off') + '" onclick="window.' + handler + '">' +
      (on ? '已开启' : '已关闭') + '</span></div>';
  }
  function field(label, id, value, type, hint) {
    return '<div class="aiField"><div class="lab">' + esc(label) + '</div>' +
      '<input class="inp" id="' + id + '" type="' + (type || 'text') + '" value="' + esc(value) + '">' +
      (hint ? '<div class="hint">' + esc(hint) + '</div>' : '') + '</div>';
  }
  /* 把值安全地塞进内联 onclick 的 JS 字符串 */
  function arg(v) { return String(v === undefined || v === null ? '' : v).replace(/['"\\<>]/g, ''); }

  /* 关系互动按钮（送礼 / 深聊 / 和解 / 求婚） */
  function relButtons(rel, S) {
    var kinds = ['gift', 'chat'];
    if (rel.type === 'enemy') { kinds.push('reconcile'); }
    if (rel.type === 'lover') { kinds.push('propose'); }
    var h = '<div class="relBtns">';
    for (var i = 0; i < kinds.length; i++) {
      var k = kinds[i];
      var info = TL.INTERACTS[k];
      var why = TL.canInteract(rel, k);
      h += '<button class="btn tiny2' + (why ? ' locked' : '') + '"' +
        (why ? ' disabled' : (' onclick="window.ui.interact(\'' + arg(rel.name) + '\',\'' + k + '\')"')) + '>' +
        esc(info.name) + (info.cost ? ' ¥' + TL.fmt(info.cost) : '') + '</button>';
    }
    return h + '</div>';
  }

  /* 主动行动与关系互动 */
  ui.doAction = function (id) {
    try {
      if (!TL.doAction(id)) { return; }
      if (TL.S && !TL.S.alive) { ui.tab = 're'; render(); showDeath(); return; }
      render();
    } catch (e) { window.toast('行动失败：' + e.message); }
  };
  ui.interact = function (name, kind) {
    try {
      TL.interact(name, kind);
      render();
    } catch (e) { window.toast('互动失败：' + e.message); }
  };

  /* ---------------- 推进一年 / 事件弹窗 ---------------- */
  ui.nextYear = function () {
    try {
      if (ui.busy) { return; }
      var S = TL.S;
      if (!S || !S.alive) { ui.tab = 're'; render(); return; }
      ui.busy = true;
      var res = TL.advanceYear();
      TL.save();
      ui.busy = false;
      if (!S.alive) { TL.save(); ui.tab = 're'; render(); showDeath(); return; }
      if (res && res.type === 'event') { presentEvent(res.event); return; }
      if (res && res.type === 'prison') { window.toast(S.prison > 0 ? ('服刑中，剩余 ' + S.prison + ' 年') : '刑满释放'); }
      else if (res && res.type === 'caught') { window.toast('你被抓了，进入监狱'); }
      else { window.toast('第 ' + S.age + ' 年：平淡的一年'); }
      render();
      if (S.prison > 0 || (res && res.type === 'caught')) { /* 服刑中不弹事件 */ }
    } catch (e) { ui.busy = false; window.toast('推进失败：' + e.message); }
  };

  ui.fastForward = function () {
    try {
      if (ui.busy) { return; }
      var S = TL.S; if (!S || !S.alive) { return; }
      ui.busy = true;

      var startAge = S.age;
      var before = {};
      var k;
      for (k = 0; k < TL.ATTRS.length; k++) { before[TL.ATTRS[k]] = S.attrs[TL.ATTRS[k]]; }

      var done = 0, events = [], died = false;
      while (done < 10) {
        var res = TL.advanceYear();
        done += 1;
        /* 快进不等于跳过：事件的选项由引擎自动挑一个最划算的，并在总结里逐条列出 */
        if (res && res.type === 'event' && res.event && res.event.choices && res.event.choices.length) {
          var idx = TL.bestChoiceIndex(res.event);
          events.push({
            title: TL.fill(stripMarks(res.event.title), S),
            choice: TL.fill(stripMarks(res.event.choices[idx].option_text), S)
          });
          TL.chooseOption(res.event, idx);
        }
        if (!S.alive) { died = true; break; }
      }
      ui.busy = false;
      TL.save();

      var deltas = [];
      for (k = 0; k < TL.ATTRS.length; k++) {
        var key = TL.ATTRS[k];
        var d = S.attrs[key] - before[key];
        if (d !== 0) { deltas.push({ k: key, v: d }); }
      }
      showFastReport(startAge, done, events, deltas);

      if (!S.alive) { ui.tab = 're'; render(); showDeath(); return; }
      render();
    } catch (e) { ui.busy = false; window.toast('快进失败：' + e.message); }
  };

  /* 快进总结：把这十年发生的事列出来，让玩家知道"自动抉择"选了什么 */
  function showFastReport(startAge, years, events, deltas) {
    var S = TL.S;
    var body = '<div class="center" style="padding:2px 0 8px 0">' +
      '<div class="big">' + startAge + ' → ' + (S ? S.age : startAge + years) + ' 岁</div>' +
      '<div class="muted">共推进 ' + years + ' 年 · 经历 ' + events.length + ' 件事</div></div>';
    if (events.length) {
      body += '<div class="sep"></div><div class="tiny">快进期间自动替你做的选择：</div><div class="scrollBox">';
      for (var i = 0; i < events.length; i++) {
        body += '<div class="logItem">' + (i + 1) + '. <b>' + esc(events[i].title) + '</b><br>' +
          '<span class="tiny">→ ' + esc(events[i].choice) + '</span></div>';
      }
      body += '</div>';
    }
    body += '<div class="sep"></div><div class="tiny">这十年的属性净变化：</div><div class="attrWrap">';
    if (!deltas.length) { body += '<span class="tiny">没有变化</span>'; }
    for (var j = 0; j < deltas.length; j++) {
      var d = deltas[j];
      body += '<span class="delta ' + cls(d.v) + '">' + d.k + (d.v > 0 ? '+' : '') +
        (d.k === '财富' ? TL.fmt(d.v) : d.v) + '</span>';
    }
    body += '</div>';
    openModal('快进总结', '十年过去了', body,
      '<button class="btn" onclick="window.ui.closeModal()">知道了</button>');
  }

  /* 呈现事件：能走 AI 就先让 AI 续写，失败/超时/用户跳过则回退本地剧情 */
  function presentEvent(localEvent) {
    if (TL.ai.shouldUse()) { startAiFlow(localEvent); return; }
    ui.aiState = null;
    ui.currentEventIsAi = false;
    ui.currentEvent = localEvent;
    openEvent();
  }

  function startAiFlow(localEvent) {
    ui.aiState = { local: localEvent, done: false };
    ui.currentEventIsAi = false;
    openModal('AI 正在续写剧情',
      '第 ' + TL.S.age + ' 岁 · ' + TL.ERA_NAME[TL.S.era] + ' · ' + esc(TL.S.cityName),
      '<div class="center-note">正在请求模型生成这一年的原创事件…<br>通常几秒内返回；拿不到结果会自动改用本地剧情。</div>',
      '<div class="btnRow"><button class="btn ghost" onclick="window.ui.aiFallback()">不等了，用本地剧情</button></div>');
    TL.ai.generate(function (err, ev) {
      var st = ui.aiState;
      if (!st || st.done) { return; }
      st.done = true;
      if (err || !ev) {
        if (TL.S && TL.S.ai) { TL.S.ai.fails = (TL.S.ai.fails || 0) + 1; }
        window.toast('AI 未成功（' + (err || '未知原因') + '），已改用本地剧情');
        ui.currentEventIsAi = false;
        ui.currentEvent = st.local;
        openEvent();
        return;
      }
      if (TL.S && TL.S.ai) {
        TL.S.ai.used = (TL.S.ai.used || 0) + 1;
        TL.S.ai.cache.push(ev);
        if (TL.S.ai.cache.length > 30) { TL.S.ai.cache.shift(); }
      }
      ui.currentEventIsAi = true;
      ui.currentEvent = ev;
      TL.addLog('第 ' + TL.S.age + ' 年：AI 续写剧情「' + stripMarks(ev.title) + '」');
      TL.save();
      window.toast('AI 原创剧情已生成');
      openEvent();
    });
  }

  ui.aiFallback = function () {
    var st = ui.aiState;
    if (!st || st.done) { return; }
    st.done = true;
    ui.currentEventIsAi = false;
    ui.currentEvent = st.local;
    window.toast('已改用本地剧情');
    openEvent();
  };

  function eraTagOf(ev) {
    var m = /^【(80|90|00|10|20)年代】/.exec(ev.title || '');
    if (m) { return '<span class="tagEra">' + m[1] + '年代专属</span>'; }
    var ds = '';
    for (var i = 0; i < ev.choices.length; i++) { ds += ev.choices[i].desc || ''; }
    var m2 = /【(80|90|00|10|20)年代】/.exec(ds);
    if (m2) { return '<span class="tagEra">' + m2[1] + '年代专属</span>'; }
    return '';
  }

  function openEvent() {
    var ev = ui.currentEvent;
    if (!ev) { return; }
    var aiBadge = ui.currentEventIsAi ? '<span class="tagAi">AI 原创</span>' : '';
    var body = aiBadge + eraTagOf(ev) + '<div class="story">' + esc(stripMarks(TL.fill(ev.story))) + '</div><div class="sep"></div>';
    for (var i = 0; i < ev.choices.length; i++) {
      body += '<div class="choice" onclick="window.ui.chooseEvent(' + i + ')">' +
        '<div class="t">' + (i + 1) + '. ' + esc(stripMarks(TL.fill(ev.choices[i].option_text))) + '</div>' +
        '<div class="d">' + esc(stripMarks(TL.fill(ev.choices[i].desc))) + '</div></div>';
    }
    var bonus = TL.skillBonus(ev.title + ' ' + ev.story);
    var sub = '第 ' + TL.S.age + ' 岁 · ' + TL.ERA_NAME[TL.S.era] + ' · ' + esc(TL.S.cityName) +
      (bonus > 0 ? (' · 技能加成 +' + Math.round(bonus * 100) + '%') : '');
    openModal(esc(stripMarks(TL.fill(ev.title))), sub, body,
      '<div class="tiny center">选择后属性自动结算，剧情不可逆</div>');
  }

  ui.chooseEvent = function (i) {
    try {
      var ev = ui.currentEvent;
      if (!ev) { closeModal(); return; }
      var ch = ev.choices[i];
      if (!ch) { window.toast('选项不存在'); return; }
      TL.chooseOption(ev, i);
      closeModal();
      ui.currentEvent = null;
      ui.currentEventIsAi = false;
      ui.aiState = null;
      TL.save();
      if (TL.S && !TL.S.alive) { ui.tab = 're'; render(); showDeath(); return; }
      render();
    } catch (e) { window.toast('结算失败：' + e.message); }
  };

  ui.showLifeLog = function () {
    var S = TL.S; if (!S) { return; }
    var body = '';
    if (!S.log.length) { body = '<div class="tiny">还没有经历</div>'; }
    for (var i = 0; i < S.log.length; i++) { body += '<div class="logItem">' + esc(stripMarks(TL.fill(S.log[i]))) + '</div>'; }
    openModal('人生日志', '共 ' + S.log.length + ' 条记录', body,
      '<button class="btn" onclick="window.ui.closeModal()">关闭</button>');
  };

  /* ---------------- 死亡结算 ---------------- */
  function showDeath() {
    var S = TL.S; if (!S) { return; }
    var st = TL.achStats();
    var sc = TL.scoreLife(S);
    var body = '<div class="center"><div class="big">享年 ' + S.age + ' 岁</div>' +
      '<div class="muted">' + esc(S.deathReason) + '</div></div><div class="sep"></div>' +
      '<div class="center" style="padding:6px 0 10px 0">' +
      '<div class="tiny">人生评分</div><div class="big">' + sc.score + ' 分</div>' +
      '<div class="muted">称号：' + esc(sc.title.name) + ' · ' + esc(sc.title.desc) + '</div></div>' +
      '<div class="sep"></div>' +
      row('出生时代', TL.ERA_NAME[S.era]) + row('出生地', esc(S.cityName)) +
      row('最终职业', S.job ? esc(S.job) : '无业') +
      row('最高财富', TL.fmt(S.stat.maxMoney)) +
      row('一生总收入', TL.fmt(S.stat.income)) +
      row('累计入狱', S.stat.prisonTotal + ' 年') +
      row('朋友 / 敌人', TL.relCount('friend') + ' / ' + TL.relCount('enemy')) +
      row('子女', TL.relCount('child') + ' 人') +
      row('成就进度', st.got + ' / ' + st.total) +
      row('习得技能', S.skills.length + ' 个') +
      (S.ai && S.ai.used ? row('AI 原创剧情', S.ai.used + ' 条') : '') +
      '<div class="sep"></div><div class="tiny">转世将继承少量属性（智力/体质/魅力/运气 的 8%）。</div>';
    openModal('人生总结', '这一世结束了', body,
      '<div class="btnRow"><button class="btn ghost" onclick="window.ui.showScoreDetail()">评分明细</button>' +
      '<button class="btn primary" onclick="window.ui.gotoRebirth()">转世轮回</button></div>');
  }

  /* 评分明细（弹窗里再开一层，用全局状态而不是闭包） */
  ui.showScoreDetail = function () {
    var S = TL.S; if (!S) { return; }
    var sc = TL.scoreLife(S);
    var body = '';
    for (var i = 0; i < sc.detail.length; i++) {
      body += row(esc(sc.detail[i].label), (sc.detail[i].val > 0 ? '+' : '') + sc.detail[i].val);
    }
    body += '<div class="sep"></div>' + row('<b>总分</b>', '<b>' + sc.score + '</b>') +
      '<div class="tiny">评分 = 年龄 + 各项属性加权 + 财富资产 + 人际 + 技能 + 成就 − 压力/成瘾/罪恶/负债。</div>';
    openModal('人生评分明细', esc(sc.title.name), body,
      '<button class="btn" onclick="window.ui.closeModal()">关闭</button>');
  };
  ui.gotoRebirth = function () { closeModal(); ui.tab = 're'; render(); };

  /* ---------------- AI 剧情设置页 ---------------- */
  ui.aiMsg = '';
  ui.aiTesting = false;

  function chanceBtn(v, label) {
    var c = TL.ai.getConfig();
    var on = Math.abs(c.chance - v) < 0.001;
    return '<button class="btn sm ' + (on ? 'primary' : '') + '" onclick="window.ui.aiSetChance(' + v + ')">' +
      label + '<br><span class="tiny">' + Math.round(v * 100) + '%</span></button>';
  }

  function viewAi() {
    var c = TL.ai.getConfig();
    var S = TL.S;
    var h = '';

    h += '<div class="card"><h3>AI 剧情引擎<span class="tail">' + esc(TL.ai.status()) + '</span></h3>' +
      '<div class="muted">开启后，每年按概率让大模型为你原创一条贴合当前年龄 / 年代 / 城市 / 职业 / 属性 / 技能的剧情事件。' +
      '生成结果会经过本地严格校验（结构、11 项属性、数值范围），不合格或超时就自动回退内置的 155 条剧情池，不会卡住游戏。</div>' +
      '<div class="tiny" style="margin-top:6px">接口采用 OpenAI 兼容格式（<b>/chat/completions</b>），可填 DeepSeek、OpenAI 或任意兼容网关。' +
      'API Key 只保存在本机存储（localStorage），<b>不会写进 app.html</b>，也不会随存档导出。</div></div>';

    h += '<div class="card"><h3>开关与用量</h3>' +
      switchRow('开启 AI 剧情', c.enabled, 'ui.aiToggle()') +
      switchRow('JSON 模式（推荐）', c.jsonMode, 'ui.aiToggleJson()') +
      row('触发频率', Math.round(c.chance * 100) + '% 的年份') +
      row('本世已用', (S && S.ai ? S.ai.used : 0) + ' / ' + c.maxPerLife + ' 次') +
      row('本世失败', (S && S.ai ? (S.ai.fails || 0) : 0) + ' 次') +
      '<div class="tiny">建议先用「偶尔」试水；每次大约几百到一千 token。</div></div>';

    h += '<div class="card"><h3>接口配置</h3>' +
      field('接口地址 URL', 'aiUrl', c.url, 'text', '默认 DeepSeek 官方：https://api.deepseek.com/v1/chat/completions') +
      field('模型名称', 'aiModel', c.model, 'text', '例如 deepseek-chat / deepseek-reasoner / gpt-4o-mini') +
      field('API Key', 'aiKey', c.key, 'password', '只在你的设备上保存；请勿把带 Key 的文件推到公开仓库') +
      '<div class="aiField"><div class="lab">触发频率</div><div class="grid3">' +
      chanceBtn(0.15, '偶尔') + chanceBtn(0.35, '经常') + chanceBtn(1, '每年') +
      '</div></div>' +
      '<div class="grid2">' +
      '<div class="aiField"><div class="lab">每世最大次数</div><input class="inp" id="aiMax" type="number" value="' + c.maxPerLife + '"></div>' +
      '<div class="aiField"><div class="lab">超时(毫秒)</div><input class="inp" id="aiTimeout" type="number" value="' + c.timeout + '"></div>' +
      '</div>' +
      '<div class="aiField"><div class="lab">从几岁开始用 AI</div><input class="inp" id="aiStartAge" type="number" value="' + c.startAge + '">' +
      '<div class="hint">童年阶段建议保持默认 6，把早期留白给内置剧情。</div></div>' +
      '<button class="btn primary" onclick="window.ui.aiSave()">保存配置</button>' +
      '<div class="btnRow">' +
      '<button class="btn sm" onclick="window.ui.aiTest()">' + (ui.aiTesting ? '测试中…' : '测试连接') + '</button>' +
      '<button class="btn sm ghost" onclick="window.ui.aiClearKey()">清除 Key</button>' +
      '</div>' +
      (ui.aiMsg ? ('<div class="tiny" style="margin-top:8px;color:#9fd0ff">' + esc(ui.aiMsg) + '</div>') : '') +
      '<div class="tiny" style="margin-top:8px">在 iPhone 壳里走原生通道直连（不受 CORS 限制）；' +
      '在电脑浏览器里直接打开时，若接口不允许跨域请求会失败，这属于浏览器限制。</div></div>';

    /* 本世 AI 原创剧情缓存 */
    h += '<div class="card"><h3>本世 AI 原创剧情<span class="tail">' +
      (S && S.ai ? S.ai.cache.length : 0) + ' 条</span></h3>';
    if (!S || !S.ai || !S.ai.cache.length) {
      h += '<div class="tiny">还没有 AI 生成的剧情。开启后过几年就会遇到。</div>';
    } else {
      h += '<div class="scrollBox">';
      for (var i = S.ai.cache.length - 1; i >= 0; i--) {
        h += '<div class="logItem">✨ ' + esc(stripMarks(TL.fill(S.ai.cache[i].title))) + '</div>';
      }
      h += '</div>';
    }
    h += '</div>';

    $('screen').innerHTML = h;
  }

  ui.aiToggle = function () {
    var c = TL.ai.getConfig();
    var was = !!c.enabled;
    if (!was && !c.key) { window.toast('请先填写 API Key 再开启'); }
    TL.ai.setConfig({ enabled: !was });
    window.toast(was ? '已关闭 AI 剧情' : '已开启 AI 剧情');
    render();
  };
  ui.aiToggleJson = function () {
    var c = TL.ai.getConfig();
    var was = !!c.jsonMode;
    TL.ai.setConfig({ jsonMode: !was });
    window.toast(was ? '已关闭 JSON 模式' : '已开启 JSON 模式');
    render();
  };
  ui.aiSetChance = function (v) {
    TL.ai.setConfig({ chance: v });
    window.toast('触发频率：' + Math.round(v * 100) + '%');
    render();
  };
  ui.aiSave = function () {
    try {
      var url = $('aiUrl') ? String($('aiUrl').value).trim() : '';
      var model = $('aiModel') ? String($('aiModel').value).trim() : '';
      var key = $('aiKey') ? String($('aiKey').value).trim() : '';
      if (!url) { window.toast('接口地址不能为空'); return; }
      if (url.indexOf('http') !== 0) { window.toast('接口地址必须以 http 开头'); return; }
      TL.ai.setConfig({
        url: url,
        model: model || 'deepseek-chat',
        key: key,
        maxPerLife: parseInt($('aiMax') ? $('aiMax').value : '30', 10) || 30,
        timeout: parseInt($('aiTimeout') ? $('aiTimeout').value : '45000', 10) || 45000,
        startAge: parseInt($('aiStartAge') ? $('aiStartAge').value : '6', 10)
      });
      ui.aiMsg = '';
      window.toast('AI 配置已保存到本机');
      render();
    } catch (e) { window.toast('保存失败：' + e.message); }
  };
  ui.aiTest = function () {
    try {
      if (ui.aiTesting) { return; }
      ui.aiSave();
      ui.aiTesting = true;
      ui.aiMsg = '正在测试连接…';
      render();
      TL.ai.test(function (err, ok) {
        ui.aiTesting = false;
        ui.aiMsg = err ? ('✗ ' + err) : ('✓ ' + ok);
        window.toast(err ? '连接失败' : '连接成功');
        render();
      });
    } catch (e) { ui.aiTesting = false; window.toast('测试失败：' + e.message); }
  };
  ui.aiClearKey = function () {
    TL.ai.setConfig({ key: '', enabled: false });
    ui.aiMsg = '';
    window.toast('已清除 API Key 并关闭 AI 剧情');
    render();
  };

  /* ---------------- 技能页 ---------------- */
  function viewSkill() {
    var S = TL.S;
    var h = '<div class="card"><h3>技能图鉴<span class="tail">已习得 ' + (S ? S.skills.length : 0) + ' / ' + TL.DATA.skills.length + '</span></h3>' +
      '<div class="muted">技能由剧情事件永久习得，可提升相关事件的成功率（每个命中技能 +7%，最高 +35%）。</div></div>';
    var got = [], locked = [];
    for (var i = 0; i < TL.DATA.skills.length; i++) {
      if (S && TL.has(S.skills, TL.DATA.skills[i].skillId)) { got.push(TL.DATA.skills[i]); }
      else { locked.push(TL.DATA.skills[i]); }
    }
    h += '<div class="card"><h3>已习得</h3>';
    if (!got.length) { h += '<div class="tiny">还没有任何技能</div>'; }
    for (var g = 0; g < got.length; g++) {
      h += '<div class="listItem"><div class="li-main"><div class="li-name">✦ ' + esc(got[g].name) + '</div>' +
        '<div class="li-sub">' + esc(got[g].desc) + '</div>' +
        '<div class="li-sub">效果：' + esc(got[g].effect) + '</div></div></div>';
    }
    h += '</div><div class="card"><h3>未习得</h3>';
    for (var l = 0; l < locked.length; l++) {
      h += '<div class="listItem locked"><div class="li-main"><div class="li-name">' + esc(locked[l].name) + '</div>' +
        '<div class="li-sub">' + esc(locked[l].effect) + '</div></div></div>';
    }
    h += '</div>';
    $('screen').innerHTML = h;
  }

  /* ---------------- 成就页 ---------------- */
  function viewAch() {
    var st = TL.achStats();
    var h = '<div class="card"><h3>成就殿堂<span class="tail">' + st.got + ' / ' + st.total + '</span></h3>' +
      '<div class="muted">成就跨轮回永久保留。达成条件由引擎自动监听。</div>' +
      '<div class="btnRow">' +
      '<button class="btn sm ' + (ui.achFilter === 'all' ? 'primary' : 'ghost') + '" onclick="window.ui.setAchFilter(\'all\')">全部</button>' +
      '<button class="btn sm ' + (ui.achFilter === 'got' ? 'primary' : 'ghost') + '" onclick="window.ui.setAchFilter(\'got\')">已解锁</button>' +
      '<button class="btn sm ' + (ui.achFilter === 'locked' ? 'primary' : 'ghost') + '" onclick="window.ui.setAchFilter(\'locked\')">未解锁</button>' +
      '</div></div><div class="card">';
    var shown = 0;
    for (var i = 0; i < TL.DATA.achievements.length; i++) {
      var a = TL.DATA.achievements[i];
      var got = TL.isUnlocked(a.name);
      if (ui.achFilter === 'got' && !got) { continue; }
      if (ui.achFilter === 'locked' && got) { continue; }
      shown++;
      h += '<div class="listItem' + (got ? '' : ' locked') + '"><div class="li-main">' +
        '<div class="li-name">' + (got ? '★ ' : '☆ ') + esc(a.name) + '</div>' +
        '<div class="li-sub">' + esc(a.desc) + '</div>' +
        '<div class="li-sub">触发：' + esc(a.trigger) + '</div></div>' +
        '<div class="li-right">' + (got ? '已解锁' : '未解锁') + '</div></div>';
    }
    if (!shown) { h += '<div class="center-note">没有符合条件的成就</div>'; }
    h += '</div>';
    $('screen').innerHTML = h;
  }
  ui.setAchFilter = function (f) { ui.achFilter = f; render(); };

  /* ---------------- 轮回页 ---------------- */
  function viewRe() {
    var S = TL.S;
    var st = TL.achStats();
    var sc = S ? TL.scoreLife(S) : null;
    var h = '<div class="card"><h3>轮回转世<span class="tail">已轮回 ' + TL.global.lives + ' 世</span></h3>' +
      '<div class="muted">死亡后开启新的一世：保留全部成就，继承少量属性，重新抽取天赋。</div>' +
      '<div class="sep"></div>' +
      row('历史最高寿命', TL.global.bestAge + ' 岁') +
      row('成就进度', st.got + ' / ' + st.total) +
      (sc ? row('当前人生评分', sc.score + ' 分 · ' + esc(sc.title.name)) : '') +
      row('前世余荫', inheritText()) +
      '</div>';

    if (S && !S.alive) {
      h += '<div class="card"><h3>本世结算</h3>' +
        row('享年', S.age + ' 岁') + row('死因', esc(S.deathReason)) +
        (sc ? row('评分 / 称号', sc.score + ' 分 · ' + esc(sc.title.name)) : '') +
        row('最高财富', TL.fmt(S.stat.maxMoney)) +
        row('本世技能', S.skills.length + ' 个') +
        row('累计入狱', S.stat.prisonTotal + ' 年') +
        '<button class="btn primary" onclick="window.ui.startReincarnate()">转世投胎</button>' +
        '<button class="btn ghost" onclick="window.ui.showSummaryAgain()">再看一次人生总结</button></div>';
    } else if (S && S.alive) {
      h += '<div class="card"><h3>本世仍在继续</h3><div class="muted">当前 ' + S.age + ' 岁，' +
        esc(S.deathReason ? S.deathReason : '人生还在继续，死亡后才能开启轮回。') + '</div>' +
        '<button class="btn ghost" onclick="window.ui.go(\'home\')">回到属性页</button></div>';
    } else {
      h += '<div class="card"><button class="btn primary" onclick="window.ui.startNewLife()">开始新的人生</button></div>';
    }

    /* 存档管理：3 个槽位 + 文本导出/导入 */
    h += '<div class="card"><h3>存档管理<span class="tail">3 个槽位</span></h3>' +
      '<div class="tiny">存档保存在本机 localStorage，可随时回滚到某个节点。</div>';
    for (var i = 1; i <= 3; i++) {
      var info = TL.slotInfo(i);
      var label = info.empty
        ? '空槽位'
        : ((info.alive ? '存活 ' : '已结束 ') + info.age + ' 岁 · ' + TL.ERA_NAME[info.era] + ' · ' + info.city);
      h += '<div class="listItem"><div class="li-main"><div class="li-name">槽位 ' + i + '</div>' +
        '<div class="li-sub">' + esc(label) + '</div></div>' +
        (info.empty ? '' : '<div class="li-right">' + (info.savedAt ? new Date(info.savedAt).toLocaleDateString() : '') + '</div>') +
        '</div><div class="relBtns">' +
        '<button class="btn tiny2" onclick="window.ui.saveToSlot(' + i + ')">保存到此处</button>' +
        '<button class="btn tiny2' + (info.empty ? ' locked' : '') + '"' + (info.empty ? ' disabled' : (' onclick="window.ui.loadFromSlot(' + i + ')"')) + '>读取</button>' +
        '<button class="btn tiny2' + (info.empty ? ' locked' : '') + '"' + (info.empty ? ' disabled' : (' onclick="window.ui.deleteSlot(' + i + ')"')) + '>删除</button>' +
        '</div>';
    }
    h += '<div class="btnRow"><button class="btn sm" onclick="window.ui.doExport()">导出存档文本</button>' +
      '<button class="btn sm ghost" onclick="window.ui.askImport()">导入存档文本</button></div></div>';

    h += '<div class="card"><h3>危险操作</h3>' +
      '<button class="btn ghost" onclick="window.ui.askGiveUp()">放弃本世，直接转世</button></div>';
    $('screen').innerHTML = h;
  }

  /* ---------------- 存档槽位与导入导出 ---------------- */
  ui.saveToSlot = function (i) {
    var err = TL.saveSlot(i);
    window.toast(err ? err : ('已保存到槽位 ' + i));
    if (!err) { render(); }
  };
  ui.loadFromSlot = function (i) {
    var err = TL.loadSlot(i);
    if (err) { window.toast(err); return; }
    window.toast('已读取槽位 ' + i);
    ui.tab = TL.S && TL.S.alive ? 'home' : 're';
    render();
    if (TL.S && !TL.S.alive) { showDeath(); }
  };
  ui.deleteSlot = function (i) {
    var err = TL.deleteSlot(i);
    window.toast(err ? err : ('已删除槽位 ' + i));
    render();
  };
  ui.doExport = function () {
    var txt = TL.exportSave();
    if (!txt) { window.toast('导出失败：当前没有人生'); return; }
    openModal('导出存档', '共 ' + txt.length + ' 个字符，长按可全选复制',
      '<textarea class="inp" id="expBox" readonly>' + esc(txt) + '</textarea>' +
      '<div class="tiny" style="margin-top:6px">把它贴到备忘录或聊天窗口即可备份；导入时整段粘回来。</div>',
      '<button class="btn" onclick="window.ui.closeModal()">关闭</button>');
  };
  ui.askImport = function () {
    openModal('导入存档', '粘贴之前导出的存档文本',
      '<textarea class="inp" id="impBox" placeholder="在这里粘贴存档 JSON"></textarea>',
      '<div class="btnRow"><button class="btn ghost" onclick="window.ui.closeModal()">取消</button>' +
      '<button class="btn primary" onclick="window.ui.doImport()">导入并覆盖</button></div>');
  };
  ui.doImport = function () {
    try {
      var box = $('impBox');
      var txt = box ? box.value : '';
      if (!txt || txt.length < 20) { window.toast('请先粘贴存档内容'); return; }
      var err = TL.importSave(txt);
      if (err) { window.toast(err); return; }
      closeModal();
      window.toast('存档导入成功');
      ui.tab = TL.S && TL.S.alive ? 'home' : 're';
      render();
    } catch (e) { window.toast('导入失败：' + e.message); }
  };

  ui.startReincarnate = function () {
    ui.startMode = 'reincarnate';
    ui.tab = 'start';
    ui.drawnTalents = []; ui.pickedTalent = -1; ui.rerollLeft = 3;
    render();
  };
  ui.startNewLife = function () {
    ui.startMode = 'new'; ui.tab = 'start';
    ui.drawnTalents = []; ui.pickedTalent = -1; ui.rerollLeft = 3;
    render();
  };
  ui.showSummaryAgain = function () { showDeath(); };
  ui.askGiveUp = function () {
    ui.ask('放弃本世', '将立刻结束当前人生并进入轮回结算，确定继续？', 'ui.doGiveUp', []);
  };
  ui.doGiveUp = function () {
    try {
      if (!TL.S) { window.toast('当前没有进行中的人生'); return; }
      if (TL.S.alive) { TL.die('主动放弃，人生提前结束'); }
      TL.save();
      window.toast('本世已结束，可转世投胎');
      ui.tab = 're'; render();
    } catch (e) { window.toast('操作失败：' + e.message); }
  };

  /* ---------------- 金手指控制台（密码 208526） ---------------- */
  function viewGod() {
    var S = TL.S;
    var h = '';
    if (!S) {
      h += '<div class="card"><h3>金手指控制台</h3><div class="muted">需要先开始一局人生。</div>' +
        '<button class="btn ghost" onclick="window.ui.go(\'re\')">去轮回页</button></div>';
      $('screen').innerHTML = h; return;
    }
    if (!S.godUnlocked) {
      h += '<div class="card"><h3>金手指控制台</h3>' +
        '<div class="muted">输入 6 位密码解锁。提示：命运藏在某个旧网页的代码里。</div>' +
        '<input class="inp" id="godPwd" type="tel" inputmode="numeric" maxlength="8" placeholder="请输入密码">' +
        '<button class="btn primary" onclick="window.ui.godUnlock()">解锁控制台</button>' +
        '<div class="tiny">解锁后本局标记为「开挂人生」。</div></div>';
      $('screen').innerHTML = h; return;
    }

    h += '<div class="card"><h3>金手指已解锁<span class="tail">开挂中</span></h3>' +
      '<div class="muted">直接修改本世属性与资源，修改立即生效并写入存档。</div>' +
      '<div class="btnRow"><button class="btn sm" onclick="window.ui.godQuick(\'money\')">一键 +10万财富</button>' +
      '<button class="btn sm" onclick="window.ui.godQuick(\'health\')">一键回满健康</button></div>' +
      '<div class="btnRow"><button class="btn sm" onclick="window.ui.godQuick(\'clean\')">清空成瘾/罪恶</button>' +
      '<button class="btn sm" onclick="window.ui.godQuick(\'stress\')">压力清零</button></div>' +
      '<div class="btnRow"><button class="btn sm" onclick="window.ui.godQuick(\'skill\')">习得全部技能</button>' +
      '<button class="btn sm" onclick="window.ui.godQuick(\'life\')">寿命 +20 年</button></div>' +
      '</div>';

    h += '<div class="card"><h3>手动修改属性</h3>';
    for (var i = 0; i < TL.ATTRS.length; i++) {
      var k = TL.ATTRS[i];
      h += '<div style="margin:8px 0"><div class="row"><span class="attrName">' + k + '</span>' +
        '<span class="tiny">当前 ' + TL.fmt(S.attrs[k]) + '</span></div>' +
        '<div class="row" style="margin-top:4px">' +
        '<button class="btn sm" style="flex:0 0 46px" onclick="window.ui.godStep(' + i + ',-10)">-10</button>' +
        '<input class="inp" id="godIn' + i + '" style="flex:1" type="number" value="0">' +
        '<button class="btn sm" style="flex:0 0 46px" onclick="window.ui.godStep(' + i + ',10)">+10</button>' +
        '<button class="btn sm primary" style="flex:0 0 64px" onclick="window.ui.godApply(' + i + ')">应用</button>' +
        '</div></div>';
    }
    h += '<div class="tiny">输入正负数后点「应用」直接叠加到该属性上。</div></div>';

    h += '<div class="card"><h3>深度修改</h3>' +
      '<button class="btn ghost" onclick="window.ui.askGodUnlockAll()">解锁全部成就（不可逆）</button>' +
      '<button class="btn ghost" onclick="window.ui.askGodKill()">直接结束本世（测试用）</button></div>';

    $('screen').innerHTML = h;
  }

  ui.godUnlock = function () {
    try {
      var el = $('godPwd');
      var v = el ? String(el.value).replace(/\s/g, '') : '';
      if (v === TL.GOD_PASSWORD) {
        TL.S.godUnlocked = true;
        TL.S.flags.godUsed = 1;
        TL.global.cheatsUsed = (TL.global.cheatsUsed || 0) + 1;
        TL.unlock('开挂人生');
        TL.save(); TL.saveGlobal();
        window.toast('金手指已解锁');
        render();
      } else {
        window.toast('密码错误，请重新输入');
      }
    } catch (e) { window.toast('解锁失败：' + e.message); }
  };
  ui.godStep = function (i, d) {
    try {
      var k = TL.ATTRS[i];
      TL.S.attrs[k] += d;
      if (k === '财富' && TL.S.attrs[k] > TL.S.stat.maxMoney) { TL.S.stat.maxMoney = TL.S.attrs[k]; }
      TL.checkAchievements(); TL.save();
      window.toast(k + ' ' + (d > 0 ? '+' : '') + d);
      render();
    } catch (e) { window.toast('修改失败：' + e.message); }
  };
  ui.godApply = function (i) {
    try {
      var k = TL.ATTRS[i];
      var el = $('godIn' + i);
      var d = parseInt(el ? el.value : '0', 10);
      if (isNaN(d) || d === 0) { window.toast('请输入非 0 的整数'); return; }
      TL.S.attrs[k] += d;
      if (k === '财富' && TL.S.attrs[k] > TL.S.stat.maxMoney) { TL.S.stat.maxMoney = TL.S.attrs[k]; }
      TL.checkAchievements(); TL.save();
      window.toast(k + ' 修改为 ' + TL.fmt(TL.S.attrs[k]));
      render();
    } catch (e) { window.toast('修改失败：' + e.message); }
  };
  ui.godQuick = function (kind) {
    try {
      var S = TL.S;
      if (kind === 'money') { S.attrs['财富'] += 100000; window.toast('财富 +100,000'); }
      else if (kind === 'health') { S.attrs['健康值'] = 100; window.toast('健康值已回满'); }
      else if (kind === 'clean') {
        S.attrs['成瘾值'] = 0; S.attrs['罪恶值'] = 0;
        for (var k in S.addictions) { if (Object.prototype.hasOwnProperty.call(S.addictions, k)) { S.addictions[k] = 0; } }
        window.toast('成瘾值与罪恶值已清零');
      }
      else if (kind === 'stress') { S.attrs['压力值'] = 0; window.toast('压力值已清零'); }
      else if (kind === 'skill') {
        S.skills = [];
        for (var i = 0; i < TL.DATA.skills.length; i++) { S.skills.push(TL.DATA.skills[i].skillId); }
        window.toast('已习得全部 ' + S.skills.length + ' 个技能');
      }
      else if (kind === 'life') { S.lifespan += 20; window.toast('寿命上限 +20 年'); }
      if (S.attrs['财富'] > S.stat.maxMoney) { S.stat.maxMoney = S.attrs['财富']; }
      TL.checkAchievements(); TL.save();
      render();
    } catch (e) { window.toast('操作失败：' + e.message); }
  };
  ui.askGodUnlockAll = function () {
    ui.ask('解锁全部成就', '这会一次性解锁所有成就并永久保存，无法撤销。确定继续？', 'ui.doGodUnlockAll', []);
  };
  ui.doGodUnlockAll = function () {
    try {
      for (var i = 0; i < TL.DATA.achievements.length; i++) {
        var n = TL.DATA.achievements[i].name;
        if (!TL.isUnlocked(n)) { TL.global.achievements.push(n); }
      }
      TL.saveGlobal();
      window.toast('已解锁全部成就（' + TL.DATA.achievements.length + ' 个）');
      render();
    } catch (e) { window.toast('操作失败：' + e.message); }
  };
  ui.askGodKill = function () {
    ui.ask('结束本世', '将直接判定角色死亡并进入轮回结算，用于测试死亡与转世流程。', 'ui.doGodKill', []);
  };
  ui.doGodKill = function () {
    try {
      if (TL.S && TL.S.alive) { TL.die('金手指强制结束本世'); TL.save(); }
      window.toast('本世已结束');
      ui.tab = 're'; render();
    } catch (e) { window.toast('操作失败：' + e.message); }
  };

  /* ---------------- 原生取数通道（联网时优先走 App 壳，浏览器回退 fetch） ---------------- */
  window.apiGetText = function (url, timeout, cb) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeFetch) {
        window.__nativeCb = cb;
        window.webkit.messageHandlers.nativeFetch.postMessage({ url: url, timeout: timeout || 15000 });
        return;
      }
      var done = false;
      var timer = setTimeout(function () { if (!done) { done = true; cb('TIMEOUT', null); } }, timeout || 15000);
      fetch(url, { method: 'GET' }).then(function (r) { return r.text(); }).then(function (t) {
        if (done) { return; } done = true; clearTimeout(timer); cb(null, t);
      })['catch'](function (e) {
        if (done) { return; } done = true; clearTimeout(timer); cb(String(e), null);
      });
    } catch (e) { cb(String(e), null); }
  };
  /* 供壳回传数据使用 */
  window.__nativeResult = function (err, text) {
    try { if (typeof window.__nativeCb === 'function') { window.__nativeCb(err, text); } } catch (e) { }
  };

  /* ---------------- 启动 ---------------- */
  function boot() {
    try {
      var saved = TL.load();
      if (saved) {
        TL.S = saved;
        ui.tab = saved.alive ? 'home' : 're';
      } else {
        ui.tab = 'start';
      }
      render();
      syncLayout();
      /* 旋转 / 窗口变化后重新测量（竖屏为主，但桌面浏览器拖窗口也要正确） */
      window.addEventListener('resize', function () { syncLayout(); });
      window.addEventListener('orientationchange', function () { setTimeout(syncLayout, 300); });
      if (saved && !saved.alive) { showDeath(); }
    } catch (e) {
      ui.tab = 'start';
      try { render(); } catch (e2) { }
      window.toast('启动异常：' + e.message);
    }
  }
  ui.boot = boot;

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  /* 全局错误兜底：任何未捕获异常都提示，避免「点了没反应」 */
  window.onerror = function (msg) {
    try { window.toast('发生错误：' + msg); } catch (e) { }
    return false;
  };
})();
