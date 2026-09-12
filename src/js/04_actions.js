/* =========================================================================
 * TrollLifeAI · 玩法增强层
 *   1) 主动行动系统：每岁 1 点行动点，玩家可以主动「做事」，不再只是被动等事件
 *   2) 关系互动：送礼 / 深聊 / 和解 / 求婚（每人每年 1 次）
 *   3) 人生评分与称号：死亡结算时给出量化评价
 *   4) 存档管理：3 个槽位 + 文本导出/导入
 * ========================================================================= */
(function () {
  'use strict';

  /* ===================== 一、主动行动系统 ===================== */
  /* 每个行动：name 名称 / desc 说明 / tag 分类 / need 解锁条件（返回空串=可用，否则返回原因） /
     run 执行体（返回 {change, markers, log, toast}） */
  TL.ACTIONS = [
    {
      id: 'work', name: '加班赚钱', tag: '赚钱',
      desc: '接私活、加通宵班，钱到账但身体和情绪被透支',
      need: function () { return ''; },
      run: function (s) {
        if (s.job && s.salary > 0) {
          var gain = Math.round(s.salary * 0.6);
          return {
            change: { '财富': gain, '压力值': 6, '健康值': -3, '快乐': -2, '疲惫': 0 },
            log: '选择加班赚钱：' + s.job + ' 额外到手 ' + TL.fmt(gain) + ' 元',
            toast: '加班到手 ' + TL.fmt(gain) + ' 元，但压力 +6'
          };
        }
        var gain2 = 2500 + TL.rnd(2500);
        return {
          change: { '财富': gain2, '体质': -2, '压力值': 4 },
          log: '没有正式工作，只好去打零工，挣到 ' + TL.fmt(gain2) + ' 元',
          toast: '打零工赚 ' + TL.fmt(gain2) + ' 元'
        };
      }
    },
    {
      id: 'hospital', name: '看病就医', tag: '健康',
      desc: '花钱做检查与调养，把身体拉回来',
      need: function (s) {
        return s.attrs['财富'] >= 8000 ? '' : '现金不足 8000 元';
      },
      run: function (s) {
        var cost = (TL.has(s.skills, 'medical') || TL.has(s.skills, 'nursing')) ? 5000 : 8000;
        return {
          change: { '财富': -cost, '健康值': 12, '体质': 1, '压力值': -2 },
          log: '去医院看病调养，花了 ' + TL.fmt(cost) + ' 元',
          toast: '就医调养：健康 +12，花费 ' + TL.fmt(cost)
        };
      }
    },
    {
      id: 'fitness', name: '健身锻炼', tag: '健康',
      desc: '跑步撸铁，体质与健康稳步回升',
      need: function (s) { return s.attrs['健康值'] >= 20 ? '' : '身体太虚弱，需要先就医'; },
      run: function (s) {
        var bonus = TL.has(s.skills, 'fitness') ? 2 : 0;
        return {
          change: { '体质': 2, '健康值': 3 + bonus, '快乐': 1, '压力值': -3 },
          log: '坚持健身锻炼，身体状态变好' + (bonus ? '（健身技能加成）' : ''),
          toast: '体质 +2，健康 +' + (3 + bonus)
        };
      }
    },
    {
      id: 'study', name: '进修学习', tag: '成长',
      desc: '报班、看书、考证，有机会习得新技能',
      need: function (s) { return s.attrs['财富'] >= 5000 ? '' : '现金不足 5000 元'; },
      run: function (s) {
        var learn = null;
        if (Math.random() < 0.35) {
          var pool = [];
          for (var i = 0; i < TL.DATA.skills.length; i++) {
            if (!TL.has(s.skills, TL.DATA.skills[i].skillId)) { pool.push(TL.DATA.skills[i]); }
          }
          if (pool.length) { learn = TL.pick(pool); }
        }
        return {
          change: { '财富': -5000, '智力': 3, '压力值': 3 },
          markers: learn ? ('【习得:' + learn.skillId + '】') : '',
          log: '报班进修学习，智力提升' + (learn ? ('，并掌握了「' + learn.name + '」') : ''),
          toast: learn ? ('智力 +3，习得技能：' + learn.name) : '智力 +3（这次没学到新技能）'
        };
      }
    },
    {
      id: 'social', name: '社交应酬', tag: '人际',
      desc: '请客吃饭拓展人脉，有机会结识新朋友',
      need: function (s) { return s.attrs['财富'] >= 2000 ? '' : '现金不足 2000 元'; },
      run: function (s) {
        var gotFriend = Math.random() < 0.6;
        return {
          change: { '财富': -2000, '魅力': 1, '快乐': 2, '压力值': 2 },
          markers: gotFriend ? ('【关系:friend:' + TL.genName() + '】') : '',
          log: '参加饭局应酬' + (gotFriend ? '，认识了一位新朋友' : '，没交到新朋友'),
          toast: gotFriend ? '社交成功，结识新朋友' : '应酬一场，人脉没变化'
        };
      }
    },
    {
      id: 'invest', name: '投资理财', tag: '赚钱',
      desc: '把闲钱拿去投资，收益与亏损都有可能',
      need: function (s) { return s.attrs['财富'] >= 20000 ? '' : '现金不足 20000 元'; },
      run: function (s) {
        var winRate = 0.55;
        if (TL.has(s.skills, 'finance')) { winRate += 0.08; }
        if (TL.has(s.skills, 'business')) { winRate += 0.04; }
        for (var i = 0; i < s.talents.length; i++) {
          if (s.talents[i].name === '投资直觉' || s.talents[i].name === '商业嗅觉') { winRate += 0.08; }
          if (s.talents[i].name === '手气极差') { winRate -= 0.15; }
        }
        var base = Math.min(s.attrs['财富'], 120000);
        if (Math.random() < winRate) {
          var win = Math.round(base * (0.06 + Math.random() * 0.14));
          return {
            change: { '财富': win, '快乐': 2, '压力值': 1 },
            log: '投资理财小赚 ' + TL.fmt(win) + ' 元',
            toast: '投资盈利 +' + TL.fmt(win)
          };
        }
        var lose = Math.round(base * (0.05 + Math.random() * 0.12));
        return {
          change: { '财富': -lose, '快乐': -3, '压力值': 6 },
          log: '投资失利，亏了 ' + TL.fmt(lose) + ' 元',
          toast: '投资亏损 -' + TL.fmt(lose)
        };
      }
    },
    {
      id: 'family', name: '陪伴家人', tag: '人际',
      desc: '陪爱人孩子吃饭散步，关系与心情都会变好',
      need: function (s) {
        if (TL.relCount('spouse') + TL.relCount('child') + TL.relCount('friend') + TL.relCount('lover') === 0) {
          return '暂时没有可以陪伴的家人或朋友';
        }
        return '';
      },
      run: function () {
        return {
          change: { '财富': -1000, '快乐': 5, '压力值': -5, '健康值': 1 },
          markers: '',
          interactAll: 8,
          log: '花时间陪伴家人朋友，关系更亲近了',
          toast: '家人好感 +8，压力 -5'
        };
      }
    },
    {
      id: 'rest', name: '休息放松', tag: '健康',
      desc: '彻底放空一年，压力大降，但当年收入减半',
      need: function () { return ''; },
      run: function () {
        return {
          change: { '压力值': -10, '快乐': 4, '健康值': 2 },
          flags: { halfIncome: 1, restedYear: TL.S ? TL.S.age : 0 },
          log: '给自己放了个长假，压力缓解（当年收入减半、绩效下滑）',
          toast: '压力 -10，今年收入减半'
        };
      }
    },
    {
      id: 'rehab', name: '戒瘾治疗', tag: '健康',
      desc: '去戒瘾机构接受治疗，成功率不算高',
      need: function (s) { return s.attrs['成瘾值'] >= 20 ? '' : '成瘾值低于 20，暂时不需要'; },
      run: function (s) {
        var cost = (TL.has(s.skills, 'medical') || TL.has(s.skills, 'meditation')) ? 6000 : 10000;
        var rate = 0.7;
        for (var i = 0; i < s.talents.length; i++) {
          if (s.talents[i].name === '钢铁意志' || s.talents[i].name === '抗瘾体质') { rate += 0.12; }
        }
        if (TL.has(s.skills, 'meditation')) { rate += 0.05; }
        var types = [];
        for (var t in s.addictions) {
          if (Object.prototype.hasOwnProperty.call(s.addictions, t) && s.addictions[t] > 0) { types.push(t); }
        }
        var target = types.length ? TL.pick(types) : '';
        if (Math.random() < rate) {
          return {
            change: { '财富': -cost, '成瘾值': -25, '快乐': -4, '压力值': 6 },
            reduceAddiction: { type: target, value: 30 },
            log: '接受戒瘾治疗并取得进展' + (target ? ('（' + target + '）') : ''),
            toast: '戒瘾有效：成瘾值 -25'
          };
        }
        return {
          change: { '财富': -cost, '成瘾值': -5, '压力值': 12, '快乐': -6 },
          log: '戒瘾治疗失败，中途复吸/复饮',
          toast: '治疗失败，只降了 5 点成瘾值'
        };
      }
    },
    {
      id: 'date', name: '相亲交友', tag: '人际',
      desc: '主动出击寻找伴侣，魅力越高成功率越大',
      need: function (s) {
        if (TL.relCount('spouse') > 0) { return '已经有配偶了'; }
        if (TL.relCount('lover') > 0) { return '已经有恋人了'; }
        return s.attrs['财富'] >= 1000 ? '' : '现金不足 1000 元';
      },
      run: function (s) {
        var rate = 0.55 + Math.min(s.attrs['魅力'] / 300, 0.25);
        for (var i = 0; i < s.talents.length; i++) {
          if (s.talents[i].name === '天生丽质' || s.talents[i].name === '社交达人') { rate += 0.1; }
          if (s.talents[i].name === '社交恐惧') { rate -= 0.2; }
        }
        if (Math.random() < rate) {
          return {
            change: { '财富': -1000, '快乐': 8, '魅力': 2, '压力值': 2 },
            markers: '【关系:lover:' + TL.genName() + '】',
            log: '相亲成功，开始了一段恋爱',
            toast: '脱单成功！'
          };
        }
        return {
          change: { '财富': -1000, '快乐': -3, '压力值': 3 },
          log: '相亲几次都没成，有点受挫',
          toast: '相亲失败，下次再试'
        };
      }
    },
    {
      id: 'child', name: '生育子女', tag: '家庭',
      desc: '迎接新生命，幸福与压力同时暴涨',
      need: function (s) {
        if (TL.relCount('spouse') === 0) { return '需要先结婚'; }
        if (TL.relCount('child') >= 3) { return '子女已经够多了'; }
        return s.attrs['财富'] >= 20000 ? '' : '现金不足 20000 元';
      },
      run: function (s) {
        var female = (s.gender === '女');
        return {
          change: { '财富': -20000, '快乐': 8, '压力值': 12, '健康值': female ? -5 : -1 },
          markers: '【关系:child:' + TL.genName() + '】',
          log: female ? '经历怀孕与生产，家里迎来一个新生命' : '配偶顺利生产，你当上了爸爸',
          toast: female ? '怀孕生子：子女 +1，健康 -5' : '孩子出生：子女 +1'
        };
      }
    },
    {
      id: 'promote', name: '争取晋升', tag: '职业',
      desc: '主动扛项目、找领导对齐目标，绩效与人脉一起押上',
      need: function (s) {
        if (!s.job) { return '目前没有工作'; }
        var ind = TL.industryById(s.jobIndustry);
        var maxLv = ind ? ind.ladder.length - 1 : 0;
        if (s.jobLevel >= maxLv) { return '已经是这个行业的最高职位'; }
        return '';
      },
      run: function (s) {
        s.flags.pushedPromotion = s.age;
        return {
          change: { '压力值': 6, '健康值': -2, '智力': 1 },
          perf: 12,
          log: '主动争取晋升，把绩效压上去了（' + s.job + '）',
          toast: '绩效 +12，今年晋升概率提高'
        };
      }
    },
    {
      id: 'jump', name: '跳槽面试', tag: '职业',
      desc: '看行情谈新机会：景气好能涨薪，景气差白跑一趟',
      need: function (s) { return s.job ? '' : '目前没有工作，先在剧情里找份工作'; },
      run: function (s) {
        var mood = s.industryMood || 60;
        var rate = 0.4 + (mood - 40) / 120 + s.skills.length * 0.02 + (s.attrs['魅力'] - 50) / 200;
        if (TL.has(s.skills, 'negotiation_life')) { rate += 0.06; }
        rate = TL.clamp(rate, 0.15, 0.85);
        if (Math.random() < rate) {
          var before = s.salary;
          var after = TL.jobHop(s);
          if (after <= before) { after = Math.round(before * 1.12); s.salary = after; }
          return {
            change: { '快乐': 3, '压力值': -2, '名声值': 1 },
            log: '跳槽成功，月薪从 ' + TL.fmt(before) + ' 涨到 ' + TL.fmt(after),
            toast: '跳槽成功：月薪 → ' + TL.fmt(after)
          };
        }
        return {
          change: { '快乐': -3, '压力值': 8, '健康值': -1 },
          log: '跳槽面试失败，行情和运气都不在你这边',
          toast: '跳槽失败（行业景气 ' + mood + '）'
        };
      }
    },
    {
      id: 'startup', name: '创业尝试', tag: '赚钱',
      desc: '投钱试一个新项目，成败只在一线之间',
      need: function (s) { return s.attrs['财富'] >= 50000 ? '' : '现金不足 50000 元'; },
      run: function (s) {
        var rate = 0.45;
        if (TL.has(s.skills, 'business')) { rate += 0.08; }
        if (TL.has(s.skills, 'ecommerce')) { rate += 0.05; }
        for (var i = 0; i < s.talents.length; i++) {
          if (s.talents[i].name === '商业嗅觉') { rate += 0.08; }
          if (s.talents[i].name === '赌命之徒') { rate += 0.06; }
        }
        if (Math.random() < rate) {
          var gain = 60000 + TL.rnd(70000);
          return {
            change: { '财富': -50000 + gain, '名声值': 4, '压力值': 10, '智力': 2 },
            markers: '【创业】',
            log: '创业项目跑通了，赚到 ' + TL.fmt(gain) + ' 元',
            toast: '创业成功 +' + TL.fmt(gain)
          };
        }
        return {
          change: { '财富': -50000, '快乐': -6, '压力值': 15, '智力': 1 },
          markers: '【创业】',
          log: '创业项目失败，投入的 5 万打了水漂',
          toast: '创业失败，亏损 50,000'
        };
      }
    },
    {
      id: 'pet', name: '陪伴宠物', tag: '生活',
      desc: '带宠物散步、洗澡、玩耍，彼此都被治愈',
      need: function (s) {
        var alive = 0;
        for (var i = 0; i < s.pets.length; i++) { if (s.pets[i].alive) { alive++; } }
        return alive > 0 ? '' : '还没有宠物';
      },
      run: function (s) {
        var bonus = TL.has(s.skills, 'pet_care') ? 6 : 0;
        for (var i = 0; i < s.pets.length; i++) {
          if (s.pets[i].alive) { s.pets[i].health = TL.clamp(s.pets[i].health + 10 + bonus, 0, 100); }
        }
        return {
          change: { '财富': -500, '快乐': 4, '压力值': -3 },
          log: '花时间陪伴宠物，心情放松' + (bonus ? '（宠物养护技能加成）' : ''),
          toast: '宠物健康 +' + (10 + bonus) + '，快乐 +4'
        };
      }
    },
    {
      id: 'checkup', name: '全面体检', tag: '健康',
      desc: '早发现早治疗，把隐患掐在萌芽里',
      need: function (s) { return s.attrs['财富'] >= 3000 ? '' : '现金不足 3000 元'; },
      run: function (s) {
        var found = Math.random() < 0.25;
        var heal = TL.has(s.skills, 'medical') ? 8 : 5;
        return {
          change: { '财富': -3000, '健康值': heal + (found ? 4 : 0), '压力值': found ? 4 : 1 },
          log: found ? '体检查出早期隐患，及时治疗避免了恶化' : '做了一次全面体检，各项指标正常',
          toast: found ? ('查出隐患并已处理：健康 +' + (heal + 4)) : ('体检正常：健康 +' + heal)
        };
      }
    }
  ];

  TL.actionById = function (id) {
    for (var i = 0; i < TL.ACTIONS.length; i++) {
      if (TL.ACTIONS[i].id === id) { return TL.ACTIONS[i]; }
    }
    return null;
  };

  TL.genName = function () {
    var xing = ['小林', '阿哲', '小雨', '老周', '小美', '阿豪', '小柔', '老陈', '小夏', '阿泽', '小满', '老李', '小舟', '阿敏', '子墨', '佩琪'];
    return TL.pick(xing) + (TL.rnd(3) === 0 ? String(TL.rnd(90) + 10) : '');
  };

  /* 执行一个主动行动 */
  TL.doAction = function (id) {
    var s = TL.S;
    if (!s || !s.alive) { window.toast('当前没有进行中的人生'); return false; }
    if (s.actionPoints <= 0) { window.toast('今年的行动点已经用完了，先过一年吧'); return false; }
    var a = TL.actionById(id);
    if (!a) { window.toast('行动不存在'); return false; }
    var reason = a.need ? a.need(s) : '';
    if (reason) { window.toast('暂时不能做：' + reason); return false; }

    var res = null;
    try { res = a.run(s) || {}; } catch (e) { window.toast('行动执行失败：' + e.message); return false; }

    /* 属性结算（只取已知的 11 项，其它键忽略） */
    var change = {};
    for (var i = 0; i < TL.ATTRS.length; i++) {
      var k = TL.ATTRS[i];
      change[k] = (res.change && res.change[k]) ? res.change[k] : 0;
    }
    TL.applyAttr(change, true);
    if (res.markers) { TL.applyMarkers(res.markers); }
    if (res.flags) {
      for (var f in res.flags) {
        if (Object.prototype.hasOwnProperty.call(res.flags, f)) { s.flags[f] = res.flags[f]; }
      }
    }
    /* 行动也能直接改绩效（职业线） */
    if (res.perf) {
      s.performance = TL.clamp(((s.performance === undefined) ? 50 : s.performance) + res.perf, 0, 100);
    }
    if (res.reduceAddiction && res.reduceAddiction.type) {
      var t = res.reduceAddiction.type;
      s.addictions[t] = TL.clamp((s.addictions[t] || 0) - res.reduceAddiction.value, 0, 100);
    }
    if (res.interactAll) {
      for (var r = 0; r < s.relations.length; r++) {
        if (s.relations[r].alive !== false) {
          s.relations[r].affinity = TL.clamp(s.relations[r].affinity + res.interactAll, 0, 100);
        }
      }
    }

    s.actionPoints -= 1;
    TL.addLog('第 ' + s.age + ' 年（主动行动）：' + (res.log || a.name));
    if (res.toast) { window.toast(res.toast); } else { window.toast(a.name + ' 完成'); }
    TL.checkAchievements();
    TL.checkDeath();
    TL.save();
    return true;
  };

  /* ===================== 二、关系互动 ===================== */
  TL.INTERACTS = {
    gift: { name: '送礼', cost: 2000, desc: '花 2000 元送份礼物，好感 +8' },
    chat: { name: '深聊', cost: 0, desc: '认真聊一次，好感 +3，快乐 +2' },
    reconcile: { name: '和解', cost: 0, desc: '主动低头，有机会化敌为友' },
    propose: { name: '求婚', cost: 5000, desc: '向恋人求婚，成功即可结婚' }
  };

  TL.canInteract = function (rel, kind) {
    var s = TL.S;
    if (!s || !rel || rel.alive === false) { return '这段关系已经结束了'; }
    if (rel.lastAct === s.age) { return '今年已经互动过了'; }
    var info = TL.INTERACTS[kind];
    if (!info) { return '互动方式不存在'; }
    if (info.cost && s.attrs['财富'] < info.cost) { return '现金不足 ' + TL.fmt(info.cost) + ' 元'; }
    if (kind === 'reconcile' && rel.type !== 'enemy') { return '只有仇人才需要和解'; }
    if (kind === 'propose') {
      if (rel.type !== 'lover') { return '只有恋人才能求婚'; }
      if (TL.relCount('spouse') > 0) { return '你已经有配偶了'; }
    }
    return '';
  };

  TL.interact = function (name, kind) {
    var s = TL.S;
    if (!s || !s.alive) { return false; }
    var rel = null;
    for (var i = 0; i < s.relations.length; i++) {
      if (s.relations[i].name === name) { rel = s.relations[i]; break; }
    }
    if (!rel) { window.toast('找不到这段关系'); return false; }
    var why = TL.canInteract(rel, kind);
    if (why) { window.toast(why); return false; }
    var info = TL.INTERACTS[kind];

    if (info.cost) {
      TL.applyAttr({ '智力': 0, '体质': 0, '魅力': 0, '财富': -info.cost, '快乐': 0, '运气': 0, '健康值': 0, '成瘾值': 0, '名声值': 0, '压力值': 0, '罪恶值': 0 }, true);
    }
    var msg = '';
    if (kind === 'gift') {
      rel.affinity = TL.clamp(rel.affinity + 8, 0, 100);
      msg = '给 ' + name + ' 送了礼物，好感 +8';
    } else if (kind === 'chat') {
      rel.affinity = TL.clamp(rel.affinity + 3, 0, 100);
      TL.applyAttr({ '智力': 0, '体质': 0, '魅力': 1, '财富': 0, '快乐': 2, '运气': 0, '健康值': 0, '成瘾值': 0, '名声值': 0, '压力值': -2, '罪恶值': 0 }, true);
      msg = '和 ' + name + ' 深聊了一次，好感 +3';
    } else if (kind === 'reconcile') {
      if (Math.random() < 0.5) {
        rel.type = 'friend';
        rel.affinity = 55;
        msg = '与 ' + name + ' 冰释前嫌，化敌为友';
      } else {
        rel.affinity = TL.clamp(rel.affinity + 5, 0, 100);
        msg = name + ' 还没完全原谅你，但关系缓和了一些';
      }
    } else if (kind === 'propose') {
      var rate = 0.6 + Math.min(rel.affinity / 400, 0.2);
      if (Math.random() < rate) {
        rel.type = 'spouse';
        rel.affinity = TL.clamp(rel.affinity + 10, 0, 100);
        TL.applyAttr({ '智力': 0, '体质': 0, '魅力': 0, '财富': -10000, '快乐': 12, '运气': 1, '健康值': 2, '成瘾值': 0, '名声值': 3, '压力值': 4, '罪恶值': 0 }, true);
        msg = '求婚成功！' + name + ' 成为了你的配偶';
        TL.unlock('携手一生');
      } else {
        msg = name + ' 拒绝了你的求婚，需要更多相处';
        TL.applyAttr({ '智力': 0, '体质': 0, '魅力': 0, '财富': 0, '快乐': -8, '运气': 0, '健康值': 0, '成瘾值': 0, '名声值': 0, '压力值': 8, '罪恶值': 0 }, true);
      }
    }
    rel.lastAct = s.age;
    TL.addLog('第 ' + s.age + ' 年（关系互动）：' + msg);
    window.toast(msg);
    TL.checkAchievements();
    TL.save();
    return true;
  };

  /* ===================== 三、人生评分与称号 ===================== */
  TL.TITLES = [
    { min: 620, name: '传奇人生', desc: '后世会把你写进故事里' },
    { min: 520, name: '人生赢家', desc: '事业、财富、家庭、健康全都拿到了' },
    { min: 420, name: '小有成就', desc: '这一生过得比大多数人都好' },
    { min: 320, name: '平凡一生', desc: '普通人的一生，安稳而真实' },
    { min: 220, name: '碌碌无为', desc: '日子过得有些潦草' },
    { min: -9999, name: '悲惨人生', desc: '命运对你并不温柔' }
  ];

  TL.scoreLife = function (s) {
    if (!s) { return { score: 0, title: TL.TITLES[TL.TITLES.length - 1], detail: [] }; }
    var a = s.attrs;
    var detail = [];
    var score = 0;
    function add(label, val) { score += val; detail.push({ label: label, val: Math.round(val) }); }

    add('活到 ' + s.age + ' 岁', s.age * 1.2);
    add('智力', a['智力'] * 0.9);
    add('体质', a['体质'] * 0.7);
    add('魅力', a['魅力'] * 0.7);
    add('快乐', a['快乐'] * 0.9);
    add('运气', a['运气'] * 0.6);
    add('健康值', a['健康值'] * 0.6);
    add('名声值', a['名声值'] * 0.8);
    add('压力值', -a['压力值'] * 0.5);
    add('成瘾值', -a['成瘾值'] * 0.7);
    add('罪恶值', -a['罪恶值'] * 1.2);
    add('财富积累', Math.min(Math.max(a['财富'], 0), 2000000) / 20000);
    add('房产车辆', s.assets.house * 10 + s.assets.car * 5 + s.assets.luxury * 2);
    add('负债', -(s.assets.debt / 50000) * 5);
    add('人际关系', (TL.relCount('friend') + TL.relCount('lover') + TL.relCount('spouse') + TL.relCount('child')) * 3 - TL.relCount('enemy') * 4);
    add('技能', s.skills.length * 3);
    add('成就', TL.achStats().got * 4);
    add('宠物', s.pets.length * 2);

    score = Math.round(score);
    if (score < 0) { score = 0; }
    var title = TL.TITLES[TL.TITLES.length - 1];
    for (var i = 0; i < TL.TITLES.length; i++) {
      if (score >= TL.TITLES[i].min) { title = TL.TITLES[i]; break; }
    }
    return { score: score, title: title, detail: detail };
  };

  /* ===================== 四、存档管理 ===================== */
  TL.SLOT_COUNT = 3;
  TL.slotKey = function (i) { return 'tlai_slot_' + i; };

  TL.saveSlot = function (i) {
    try {
      if (!TL.S) { return '当前没有人生可以保存'; }
      var pack = { savedAt: Date.now(), version: 1, state: TL.S, global: TL.global };
      localStorage.setItem(TL.slotKey(i), JSON.stringify(pack));
      return null;
    } catch (e) { return '保存失败：' + e.message; }
  };
  TL.loadSlot = function (i) {
    try {
      var raw = localStorage.getItem(TL.slotKey(i));
      if (!raw) { return '槽位 ' + i + ' 是空的'; }
      var pack = JSON.parse(raw);
      if (!pack || !pack.state) { return '槽位数据损坏'; }
      TL.S = pack.state;
      if (pack.global) { TL.global = pack.global; }
      TL.saveGlobal();
      TL.save();
      return null;
    } catch (e) { return '读取失败：' + e.message; }
  };
  TL.slotInfo = function (i) {
    try {
      var raw = localStorage.getItem(TL.slotKey(i));
      if (!raw) { return { empty: true }; }
      var pack = JSON.parse(raw);
      var st = pack.state || {};
      return {
        empty: false,
        age: st.age || 0,
        era: st.era || '',
        city: st.cityName || '',
        alive: !!st.alive,
        savedAt: pack.savedAt || 0
      };
    } catch (e) { return { empty: true }; }
  };
  TL.deleteSlot = function (i) {
    try { localStorage.removeItem(TL.slotKey(i)); return null; } catch (e) { return '删除失败'; }
  };
  TL.exportSave = function () {
    try {
      return JSON.stringify({ version: 1, exportedAt: Date.now(), state: TL.S, global: TL.global });
    } catch (e) { return ''; }
  };
  TL.importSave = function (text) {
    try {
      var o = JSON.parse(String(text).trim());
      var st = o.state ? o.state : o;
      if (!st || !st.attrs) { return '不是有效的存档内容'; }
      TL.S = st;
      if (o.global) { TL.global = o.global; TL.saveGlobal(); }
      TL.save();
      return null;
    } catch (e) { return '解析失败：' + e.message; }
  };
})();
