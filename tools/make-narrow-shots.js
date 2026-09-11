/**
 * make-narrow-shots.js —— 在 390px 宽的 iframe 里真实渲染 app.html
 * 用途：① 报告真实 iPhone 宽度下有没有横向溢出；② 截图真机尺寸下的各个界面。
 * 用法： node tools/make-narrow-shots.js   然后 powershell -File tools/shot.ps1
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'build');

/* 各场景在 iframe 内部要执行的动作 */
const SCENES = {
  narrow_start: `
    TL.resetAll();
    window.ui.tab = 'start'; window.ui.startMode = 'new';
    window.ui.setEra('90'); window.ui.setCity('一线城市');
    window.ui.drawTalents(); window.ui.pickTalent(0);`,
  narrow_home: `
    TL.resetAll();
    window.ui.tab = 'start'; window.ui.setEra('90'); window.ui.setCity('一线城市');
    window.ui.drawTalents(); window.ui.pickTalent(0); window.ui.beginLife();
    for (var i = 0; i < 34; i++) {
      if (!TL.S.alive) { break; }
      window.ui.nextYear();
      if (window.ui.currentEvent) { window.ui.chooseEvent(0); }
    }
    window.ui.go('home');`,
  narrow_ai: `
    TL.resetAll();
    window.ui.tab = 'start'; window.ui.setEra('00'); window.ui.setCity('一线城市');
    window.ui.drawTalents(); window.ui.pickTalent(0); window.ui.beginLife();
    TL.ai.setConfig({ enabled: true, key: 'sk-演示用假Key-不会上传', chance: 0.35, maxPerLife: 30 });
    TL.S.ai.used = 4; TL.S.ai.fails = 1;
    TL.S.ai.cache.push({ title: '深夜接到老同学的电话' });
    TL.S.ai.cache.push({ title: '公司楼下新开了家咖啡店' });
    window.ui.aiMsg = '✓ 连接成功，模型回复：通过';
    window.ui.go('ai');`,
  narrow_death: `
    TL.resetAll();
    window.ui.tab = 'start'; window.ui.setEra('90'); window.ui.setCity('省会城市');
    window.ui.drawTalents(); window.ui.pickTalent(0); window.ui.beginLife();
    for (var i = 0; i < 30; i++) {
      if (!TL.S.alive) { break; }
      window.ui.nextYear();
      if (window.ui.currentEvent) { window.ui.chooseEvent(0); }
    }
    ['呱呱坠地','成年礼','打工人','有房一族','携手一生','戒烟成功'].forEach(function (n) { TL.unlock(n); });
    window.ui.doGodKill();`,
  narrow_actions: `
    TL.resetAll();
    window.ui.tab = 'start'; window.ui.setEra('10'); window.ui.setCity('新一线城市');
    window.ui.drawTalents(); window.ui.pickTalent(0); window.ui.beginLife();
    TL.S.age = 28; TL.S.job = '大厂程序员'; TL.S.salary = 26000;
    TL.S.attrs['财富'] = 180000; TL.S.actionPoints = 1;
    TL.addRelation('spouse', '小雨'); TL.addRelation('child', '小宝');
    TL.addRelation('friend', '老周'); TL.addRelation('enemy', '老王');
    TL.addPet('猫');
    for (var i = 0; i < 5; i++) { TL.addLog('第 ' + (22 + i) + ' 年：示例人生记录'); }
    window.ui.go('home');`,
  /* 模拟带刘海机型：给顶栏注入 48px 安全区，验证内容区留白会跟着变高（不再被顶栏盖住） */
  narrow_notch: `
    var st = d.createElement('style');
    st.textContent = '#topbar{padding-top:48px}';
    d.head.appendChild(st);
    TL.resetAll();
    window.ui.tab = 'start'; window.ui.setEra('00'); window.ui.setCity('一线城市');
    window.ui.drawTalents(); window.ui.pickTalent(0); window.ui.beginLife();
    window.ui.go('ai');
    window.ui.syncLayout();
    var tb = d.getElementById('topbar'), sc = d.getElementById('screen');
    window.__notchReport = 'TOPBAR=' + Math.round(tb.getBoundingClientRect().height) +
      ' PADTOP=' + sc.style.paddingTop + ' PADBOTTOM=' + sc.style.paddingBottom;`,

  narrow_relations: `
    window.ui.tab = 'start'; window.ui.setEra('90'); window.ui.setCity('一线城市');
    window.ui.drawTalents(); window.ui.pickTalent(0); window.ui.beginLife();
    TL.S.age = 32;
    TL.addRelation('friend', '老周'); TL.addRelation('lover', '阿哲');
    TL.addRelation('spouse', '小雨'); TL.addRelation('child', '小宝');
    TL.addRelation('enemy', '老王'); TL.addRelation('friend', '小林');
    TL.addPet('猫'); TL.addPet('狗');
    TL.addAddiction('烟瘾', 45); TL.addAddiction('网瘾', 30);
    TL.S.attrs['成瘾值'] = 62; TL.S.job = '大厂程序员'; TL.S.salary = 28000;
    TL.S.assets.debt = 45000; TL.S.assets.house = 1;
    for (var i = 0; i < 6; i++) { TL.addLog('第 ' + (i + 20) + ' 年：示例人生记录 ' + i); }
    window.ui.go('home');
    d.getElementById('screen').scrollTop = 1750;`,
  narrow_event: `
    TL.resetAll();
    window.ui.tab = 'start'; window.ui.setEra('00'); window.ui.setCity('新一线城市');
    window.ui.drawTalents(); window.ui.pickTalent(0); window.ui.beginLife();
    for (var i = 0; i < 60; i++) {
      if (!TL.S.alive) { break; }
      window.ui.nextYear();
      if (window.ui.currentEvent) { break; }
    }`,
  narrow_god: `
    TL.resetAll();
    window.ui.tab = 'start'; window.ui.setEra('20'); window.ui.setCity('一线城市');
    window.ui.drawTalents(); window.ui.pickTalent(0); window.ui.beginLife();
    TL.S.godUnlocked = true; TL.S.flags.godUsed = 1; TL.unlock('开挂人生');
    window.ui.go('god');`,
  narrow_ach: `
    TL.resetAll();
    window.ui.tab = 'start'; window.ui.setEra('90'); window.ui.setCity('北上广深');
    window.ui.drawTalents(); window.ui.pickTalent(0); window.ui.beginLife();
    ['呱呱坠地','成年礼','打工人','有房一族','有车一族','携手一生','初为父母','铁哥们','戒烟成功','百岁人生','时代见证者','职场晋升']
      .forEach(function (n) { TL.unlock(n); });
    window.ui.go('ach');`,
  narrow_skill: `
    TL.resetAll();
    window.ui.tab = 'start'; window.ui.setEra('00'); window.ui.setCity('二线城市');
    window.ui.drawTalents(); window.ui.pickTalent(0); window.ui.beginLife();
    ['programming','driving','medical','business','cooking','fitness','finance','law','pet_care','meditation']
      .forEach(function (id) { TL.learnSkill(id); });
    window.ui.go('skill');`
};

Object.keys(SCENES).forEach((name) => {
  const html = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>${name}</title>
<style>html,body{margin:0;background:#000;overflow:hidden}
#wrap{width:390px;height:932px;overflow:hidden}
iframe{width:390px;height:932px;border:0;display:block}</style></head>
<body data-narrow="pending">
<div id="wrap"><iframe id="f" src="../app.html"></iframe></div>
<script>
/* 演示外壳：在 390px 宽的 iframe 内真实运行 app.html，并统计横向溢出 */
var outerDoc = document;                 /* 先把父页面的 document 存起来 */
var ready = 0;
function tryRun() {
  var f = outerDoc.getElementById('f');
  var w = f.contentWindow;
  if (!w || !w.TL || !w.ui) {        /* 等 iframe 里的游戏加载完 */
    if (++ready < 80) { setTimeout(tryRun, 100); }
    else { outerDoc.body.setAttribute('data-narrow', 'NOT_READY'); }
    return;
  }
  var d = f.contentDocument;
  try {
    /* 以下场景代码直接以 iframe 内的作用域运行 */
    var TL = w.TL; var window = w; var document = d;
    ${SCENES[name]}
  } catch (e) {
    outerDoc.body.setAttribute('data-narrow', 'ERR ' + e.message);
    return;
  }
  setTimeout(function () {
    try {
      var out = [], all = d.querySelectorAll('*');
      for (var i = 0; i < all.length; i++) {
        var r = all[i].getBoundingClientRect();
        if (r.right > 390.5) {
          out.push(all[i].tagName + '.' + String(all[i].className || '-').slice(0, 22) + '[right=' + Math.round(r.right) + ']');
        }
      }
      outerDoc.body.setAttribute('data-narrow', 'COUNT=' + out.length + ' :: ' + out.slice(0, 12).join(' || ') +
        ' :: ' + (w.__notchReport || 'no-layout-report'));
    } catch (e2) { outerDoc.body.setAttribute('data-narrow', 'ERR2 ' + e2.message); }
  }, 300);
}
setTimeout(tryRun, 200);
</script>
</body></html>`;
  fs.writeFileSync(path.join(OUT, name + '.html'), html, 'utf8');
});
console.log('已生成 390px 演示页: ' + Object.keys(SCENES).join(', '));
