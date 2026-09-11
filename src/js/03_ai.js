/* =========================================================================
 * TrollLifeAI · AI 剧情引擎（可配置的 OpenAI 兼容接口）
 *
 * 设计原则：
 *   1) 接口完全可配置：地址 / 模型 / Key / 频率 / 每次人生上限，默认 DeepSeek 官方端点；
 *   2) Key 只存在本机 localStorage（键 tlai_ai_v1），**绝不写进 app.html**，避免推公开仓库泄漏；
 *   3) file:// 页面直连会被 CORS 拦，App 内优先走壳的 nativeHttp POST 通道，浏览器里回退 fetch；
 *   4) AI 只负责「生成一条剧情」，能不能落地由本地引擎校验：结构不对 / 属性越界 / 超时 → 自动回退本地事件池。
 * ========================================================================= */
(function () {
  'use strict';

  TL.ai = {};

  TL.AI_KEY = 'tlai_ai_v1';

  /* ---------------- 配置 ---------------- */
  TL.ai.DEFAULTS = {
    enabled: false,
    url: 'https://api.deepseek.com/v1/chat/completions',
    model: 'deepseek-chat',
    key: '',
    chance: 0.35,        /* 每年触发 AI 续写的概率 */
    maxPerLife: 30,      /* 每世最多请求次数（省钱） */
    timeout: 45000,      /* 超时毫秒 */
    jsonMode: true,      /* 是否带 response_format: json_object */
    startAge: 6          /* 从这个年龄开始才用 AI（童年留白） */
  };

  TL.ai.config = null;

  TL.ai.getConfig = function () {
    if (TL.ai.config) { return TL.ai.config; }
    var c = {};
    var k;
    for (k in TL.ai.DEFAULTS) {
      if (Object.prototype.hasOwnProperty.call(TL.ai.DEFAULTS, k)) { c[k] = TL.ai.DEFAULTS[k]; }
    }
    try {
      var raw = localStorage.getItem(TL.AI_KEY);
      if (raw) {
        var o = JSON.parse(raw);
        for (k in o) {
          if (Object.prototype.hasOwnProperty.call(o, k) && c[k] !== undefined) { c[k] = o[k]; }
        }
      }
    } catch (e) { }
    c.chance = TL.clamp(Number(c.chance) || 0, 0, 1);
    c.maxPerLife = TL.clamp(parseInt(c.maxPerLife, 10) || 30, 0, 500);
    c.timeout = TL.clamp(parseInt(c.timeout, 10) || 45000, 3000, 120000);
    TL.ai.config = c;
    return c;
  };

  TL.ai.setConfig = function (patch) {
    var c = TL.ai.getConfig();
    for (var k in patch) {
      if (Object.prototype.hasOwnProperty.call(patch, k)) { c[k] = patch[k]; }
    }
    /* 写入时也做一次范围归一化，避免界面显示值与实际生效值不一致 */
    c.chance = TL.clamp(Number(c.chance) || 0, 0, 1);
    c.maxPerLife = TL.clamp(parseInt(c.maxPerLife, 10) || 30, 0, 500);
    c.timeout = TL.clamp(parseInt(c.timeout, 10) || 45000, 3000, 120000);
    c.startAge = TL.clamp(parseInt(c.startAge, 10) || 0, 0, 100);
    TL.ai.config = c;
    try { localStorage.setItem(TL.AI_KEY, JSON.stringify(c)); } catch (e) { }
    return c;
  };

  TL.ai.ready = function () {
    var c = TL.ai.getConfig();
    return !!(c.enabled && c.url && c.model && c.key);
  };

  TL.ai.status = function () {
    var c = TL.ai.getConfig();
    if (!c.enabled) { return '已关闭'; }
    if (!c.key) { return '缺少 API Key'; }
    if (!c.url) { return '缺少接口地址'; }
    return '已启用（' + c.model + '）';
  };

  /* ---------------- 网络：原生通道优先，浏览器回退 fetch ---------------- */
  window.apiPost = function (url, headers, bodyText, timeout, cb) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeHttp) {
        window.__nativeHttpCb = cb;
        window.webkit.messageHandlers.nativeHttp.postMessage({
          url: url, method: 'POST', headers: headers || {}, body: bodyText, timeout: timeout || 60000
        });
        return;
      }
      var done = false;
      var timer = setTimeout(function () {
        if (!done) { done = true; cb('TIMEOUT', null, 0); }
      }, timeout || 60000);
      fetch(url, { method: 'POST', headers: headers || {}, body: bodyText })
        .then(function (r) {
          return r.text().then(function (t) { return { status: r.status, text: t }; });
        })
        .then(function (o) {
          if (done) { return; }
          done = true; clearTimeout(timer); cb(null, o.text, o.status);
        })['catch'](function (e) {
          if (done) { return; }
          done = true; clearTimeout(timer); cb(String(e), null, 0);
        });
    } catch (e) { cb(String(e), null, 0); }
  };

  /* 供壳回传（原生通道） */
  window.__nativeHttpResult = function (err, text, status) {
    try {
      if (typeof window.__nativeHttpCb === 'function') { window.__nativeHttpCb(err, text, status); }
    } catch (e) { }
  };

  /* ---------------- 提示词 ---------------- */
  TL.ai.SYSTEM = [
    '你是一款中文文字人生模拟器（人生重开模拟器）的剧情引擎。',
    '你要根据玩家当前的人生状态，原创一条贴合年龄、年代、城市、职业与属性的剧情事件。',
    '只输出一个 JSON 对象，不要任何解释、不要 markdown 代码块、不要多余文字。',
    'JSON 结构固定为：',
    '{"title":"事件标题","story":"第二人称剧情描述","choices":[{"option_text":"选项","desc":"结果说明","attr_change":{"智力":0,"体质":0,"魅力":0,"财富":0,"快乐":0,"运气":0,"健康值":0,"成瘾值":0,"名声值":0,"压力值":0,"罪恶值":0}}]}',
    '硬性规则：',
    '1. attr_change 必须完整包含 11 个键：智力、体质、魅力、财富、快乐、运气、健康值、成瘾值、名声值、压力值、罪恶值，值必须是整数。',
    '2. 除财富外每项取值范围 -15 到 15；财富取 -30000 到 30000。成瘾值、罪恶值只能取 0 到 20。',
    '3. title 不超过 18 个字，story 60-120 字，choices 2 到 3 个，option_text 不超过 14 个字，desc 不超过 40 字。',
    '4. 选项之间必须有取舍（有得有失），禁止出现只有好处没有代价的选项。',
    '5. 不要使用书名号双引号，需要引号时用「」。',
    '6. desc 末尾可选地追加剧情标记（不要新增 JSON 字段），可用：【习得:skillId】【关系:friend:名字】【关系结束:名字】【职业:岗位】【升职】【失业】【跳槽】【创业】【破产】【入狱:年数】【出狱】【案底】【减刑】【买房】【买车】【负债:金额】【还债:金额】【成瘾:烟瘾】【戒断:酒瘾】【宠物:猫】【宠物离世】，每个 desc 最多 2 个。',
    '7. 剧情必须与玩家的性别、年龄、年代、城市、职业相符；可以用占位符 {名字}、{ta}、{ta的}、{配偶}。'
  ].join('\n');

  TL.ai.buildUserPrompt = function (S) {
    var lines = [];
    var c = TL.ai.getConfig();
    lines.push('【当前人生状态】');
    lines.push('姓名：' + (S.name || '（未取名）') + '；性别：' + (S.gender || '男'));
    lines.push('年龄：' + S.age + ' 岁');
    lines.push('年代：' + TL.ERA_NAME[S.era] + '；出生城市：' + S.cityName);
    lines.push('职业：' + (S.job ? (S.job + '（月薪 ' + S.salary + '）') : '无业') + (S.prison > 0 ? '，正在服刑（剩余 ' + S.prison + ' 年）' : ''));
    var attrLine = [];
    for (var i = 0; i < TL.ATTRS.length; i++) { attrLine.push(TL.ATTRS[i] + S.attrs[TL.ATTRS[i]]); }
    lines.push('属性：' + attrLine.join('，'));
    if (S.skills.length) {
      var names = [];
      for (var k = 0; k < S.skills.length; k++) { names.push(TL.skillName(S.skills[k])); }
      lines.push('已习得技能：' + names.join('、'));
    }
    if (S.relations.length) {
      var rels = [];
      for (var r = 0; r < S.relations.length && r < 6; r++) {
        var rel = S.relations[r];
        rels.push((TL.REL_TYPES[rel.type] || rel.type) + rel.name + '(好感' + rel.affinity + ')');
      }
      lines.push('重要关系：' + rels.join('、'));
    }
    if (S.pets.length) {
      var pets = [];
      for (var p = 0; p < S.pets.length && p < 3; p++) { pets.push(S.pets[p].name + '(' + S.pets[p].species + ')'); }
      lines.push('宠物：' + pets.join('、'));
    }
    var add = [];
    for (var a in S.addictions) {
      if (Object.prototype.hasOwnProperty.call(S.addictions, a) && S.addictions[a] > 0) {
        add.push(a + S.addictions[a]);
      }
    }
    if (add.length) { lines.push('成瘾：' + add.join('、')); }
    var recent = S.usedTitles.slice(-14);
    if (recent.length) {
      lines.push('');
      lines.push('【最近已经发生过的剧情（不要重复这些主题与标题）】');
      lines.push(recent.join(' / '));
    }
    lines.push('');
    lines.push('【任务】');
    lines.push('请为这个 ' + S.age + ' 岁的人，原创 1 条' + TL.ERA_NAME[S.era] + '背景下、发生在' + S.cityName + '的剧情事件，' +
      '并给出 2-3 个有取舍的选项与完整的 11 项属性变化。只输出 JSON。');
    lines.push('剧情必须符合玩家的性别与年龄：' + (S.gender === '女' ? '这是女性角色，不要出现彩礼、岳父岳母、当伴郎这类男性视角情节' :
      '这是男性角色，不要出现产假、怀孕、婆婆、当伴娘这类女性视角情节') + '。');
    lines.push('建议在文本里使用占位符：{名字}（玩家姓名）、{ta}（他/她）、{ta的}（他的/她的）、{配偶}（丈夫/妻子），引擎会自动替换。');
    if (S.age <= 6) { lines.push('注意：这是幼儿阶段，剧情要贴近童年日常。'); }
    else if (S.age <= 17) { lines.push('注意：这是学生阶段，剧情要贴近校园与家庭。'); }
    else if (S.age >= 60) { lines.push('注意：这是老年阶段，剧情要贴近健康、养老与家庭。'); }
    return lines.join('\n');
  };

  /* ---------------- 响应解析与校验 ---------------- */
  function extractJson(text) {
    if (!text || typeof text !== 'string') { return null; }
    var t = text.replace(/```json/gi, '```').replace(/```/g, '').trim();
    var i = t.indexOf('{'), j = t.lastIndexOf('}');
    if (i === -1 || j === -1 || j <= i) { return null; }
    t = t.slice(i, j + 1);
    try { return JSON.parse(t); } catch (e) { }
    /* 常见问题兜底：去掉尾随逗号再试一次 */
    try { return JSON.parse(t.replace(/,\s*([}\]])/g, '$1')); } catch (e2) { }
    return null;
  }
  TL.ai.extractJson = extractJson;

  function clampInt(v, lo, hi) {
    var n = Number(v);
    if (!isFinite(n)) { return 0; }
    n = Math.round(n);
    if (n < lo) { n = lo; }
    if (n > hi) { n = hi; }
    return n;
  }
  function clip(str, max) {
    if (str === undefined || str === null) { return ''; }
    var s = String(str).replace(/[""]/g, '「').replace(/[""]/g, '」').replace(/[\r\n]+/g, ' ').trim();
    if (s.length > max) { s = s.slice(0, max); }
    return s;
  }

  /* 把 AI 返回的原始对象规范化成和 event.json 完全一致的结构；不合格返回 null */
  TL.ai.normalizeEvent = function (raw) {
    if (!raw || typeof raw !== 'object') { return null; }
    var title = clip(raw.title, 24);
    var story = clip(raw.story, 260);
    if (!title || !story) { return null; }
    var rawChoices = raw.choices;
    if (!rawChoices || !rawChoices.length) {
      if (raw.options && raw.options.length) { rawChoices = raw.options; } else { return null; }
    }
    var choices = [];
    for (var i = 0; i < rawChoices.length && i < 3; i++) {
      var rc = rawChoices[i] || {};
      var ot = clip(rc.option_text || rc.text || rc.option, 18);
      if (!ot) { continue; }
      var dsc = clip(rc.desc || rc.description || '', 70);
      var src = rc.attr_change || rc.attrChange || rc.attributes || {};
      var ch = {};
      var bad = 0;
      for (var k = 0; k < TL.ATTRS.length; k++) {
        var key = TL.ATTRS[k];
        var v = src[key];
        if (v === undefined || v === null || v === '') { v = 0; }
        var lo = -15, hi = 15;
        if (key === '财富') { lo = -30000; hi = 30000; }
        if (key === '成瘾值' || key === '罪恶值') { lo = 0; hi = 20; }
        var iv = clampInt(v, lo, hi);
        if (String(v) !== String(iv)) { bad++; }
        ch[key] = iv;
      }
      choices.push({ option_text: ot, attr_change: ch, desc: dsc });
    }
    if (!choices.length) { return null; }
    var eraM = /^【?(80|90|00|10|20)年代】?/.exec(title);
    var out = {
      age_range: [TL.S ? TL.S.age : 18, 110],
      title: title,
      story: story,
      choices: choices
    };
    if (eraM) { out.title = eraM[1] + '年代 · ' + title.replace(eraM[0], '').trim(); }
    out.ai = 1;   /* 运行时标记：AI 原创（不会写回 JSON 文件） */
    return out;
  };

  /* ---------------- 发起请求 ---------------- */
  TL.ai.generate = function (cb) {
    var c = TL.ai.getConfig();
    var S = TL.S;
    if (!S) { cb('没有进行中的人生', null); return; }
    if (!TL.ai.ready()) { cb(TL.ai.status(), null); return; }

    var body = {
      model: c.model,
      messages: [
        { role: 'system', content: TL.ai.SYSTEM },
        { role: 'user', content: TL.ai.buildUserPrompt(S) }
      ],
      temperature: 1.1,
      max_tokens: 900,
      stream: false
    };
    if (c.jsonMode) { body.response_format = { type: 'json_object' }; }

    var headers = { 'Content-Type': 'application/json' };
    if (c.key) { headers['Authorization'] = 'Bearer ' + c.key; }

    window.apiPost(c.url, headers, JSON.stringify(body), c.timeout, function (err, text, status) {
      try {
        if (err) { cb('请求失败：' + err, null); return; }
        if (status && (status < 200 || status >= 300)) {
          var hint = text ? String(text).slice(0, 160) : '';
          cb('接口返回 ' + status + (hint ? ('：' + hint) : ''), null);
          return;
        }
        var data = null;
        try { data = JSON.parse(text); } catch (e) { cb('返回内容不是 JSON', null); return; }
        var content = '';
        if (data && data.choices && data.choices.length && data.choices[0].message) {
          content = data.choices[0].message.content || '';
        } else if (data && data.output_text) {
          content = data.output_text;
        } else if (data && data.content) {
          content = data.content;
        }
        if (!content) { cb('返回里没有剧情内容', null); return; }
        var obj = extractJson(content);
        if (!obj) { cb('剧情 JSON 解析失败', null); return; }
        var ev = TL.ai.normalizeEvent(obj);
        if (!ev) { cb('剧情结构不合格（已丢弃）', null); return; }
        cb(null, ev);
      } catch (e) { cb('处理返回时出错：' + e.message, null); }
    });
  };

  /* 是否该用 AI 续写这一年 */
  TL.ai.shouldUse = function () {
    var c = TL.ai.getConfig();
    var S = TL.S;
    if (!S || !c.enabled || !c.key) { return false; }
    if (S.age < c.startAge) { return false; }
    if (!S.ai) { S.ai = { used: 0, fails: 0, cache: [] }; }
    if (S.ai.used >= c.maxPerLife) { return false; }
    if (S.prison > 0) { return false; }
    return Math.random() < c.chance;
  };

  /* 连接自检：发一条极短请求验证 Key / 地址 / 模型 */
  TL.ai.test = function (cb) {
    var c = TL.ai.getConfig();
    if (!c.url || !c.model) { cb('请先填写接口地址与模型'); return; }
    if (!c.key) { cb('请先填写 API Key'); return; }
    var body = {
      model: c.model,
      messages: [{ role: 'user', content: '只回复两个字：通过' }],
      temperature: 0,
      max_tokens: 16,
      stream: false
    };
    window.apiPost(c.url, { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + c.key },
      JSON.stringify(body), Math.min(c.timeout, 20000), function (err, text, status) {
        try {
          if (err) { cb('连接失败：' + err); return; }
          if (status && (status < 200 || status >= 300)) {
            cb('接口返回 ' + status + '：' + String(text || '').slice(0, 120));
            return;
          }
          var d = JSON.parse(text);
          var ctn = (d.choices && d.choices[0] && d.choices[0].message) ? d.choices[0].message.content : '';
          cb(null, '连接成功，模型回复：' + String(ctn).slice(0, 30));
        } catch (e) { cb('返回解析失败：' + e.message); }
      });
  };
})();
