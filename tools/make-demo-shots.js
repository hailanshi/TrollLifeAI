/**
 * make-demo-shots.js —— 生成用于视觉验收的演示页（app.html + 自动操作脚本）
 * 目的：在没有真机的情况下，用无头浏览器真实跑一遍界面并截图。
 * 用法： node tools/make-demo-shots.js  然后由 tools/shot.ps1 截图
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(ROOT, 'app.html'), 'utf8');
const OUT = path.join(ROOT, 'build');
fs.mkdirSync(OUT, { recursive: true });

/* 公共驱动：清档 → 开局 → 若干年 → 指定收尾动作 */
function driver(body) {
  return `
<script>
/* ===== 演示驱动脚本（仅用于截图验收，不属于游戏本体） ===== */
function demoStart(era, city) {
  TL.resetAll();
  window.ui.tab = 'start';
  window.ui.startMode = 'new';
  window.ui.drawnTalents = []; window.ui.pickedTalent = -1; window.ui.rerollLeft = 3;
  window.ui.setEra(era);
  window.ui.setCity(city);
  window.ui.drawTalents();
  window.ui.pickTalent(0);
  window.ui.beginLife();
}
function demoYears(n, stopOnEvent) {
  for (var i = 0; i < n; i++) {
    if (!TL.S || !TL.S.alive) { break; }
    window.ui.nextYear();
    if (window.ui.currentEvent) {
      if (stopOnEvent) { return true; }
      window.ui.chooseEvent(0);
    }
  }
  return false;
}
setTimeout(function () {
  try { ${body} } catch (e) { document.title = 'DEMO_ERR: ' + e.message; }
}, 350);
</script>`;
}

const scenarios = {
  /* 开局页：抽到 3 个天赋 */
  demo_start: `
    TL.resetAll();
    window.ui.tab = 'start'; window.ui.startMode = 'new';
    window.ui.setEra('90'); window.ui.setCity('一线城市');
    window.ui.drawTalents(); window.ui.pickTalent(0);`,

  /* 属性主页：活到中年 */
  demo_home: `
    demoStart('90', '一线城市');
    demoYears(34, false);
    window.ui.go('home');`,

  /* 事件弹窗：停在有选项的那一刻 */
  demo_event: `
    demoStart('00', '新一线城市');
    for (var i = 0; i < 40; i++) {
      if (!TL.S.alive) { demoStart('10', '省会城市'); }
      window.ui.nextYear();
      if (window.ui.currentEvent) { break; }
    }`,

  /* 成就页：先解锁一批 */
  demo_ach: `
    demoStart('90', '北上广深');
    TL.S.attrs['财富'] = 260000; TL.S.assets.house = 1; TL.S.assets.car = 1;
    TL.unlock('有房一族'); TL.unlock('有车一族'); TL.unlock('打工人');
    TL.unlock('职场晋升'); TL.unlock('铁哥们'); TL.unlock('携手一生');
    TL.unlock('初为父母'); TL.unlock('手术台归来'); TL.unlock('戒烟成功');
    TL.unlock('毛孩子爸妈'); TL.unlock('时代见证者'); TL.unlock('百岁人生');
    TL.checkAchievements();
    window.ui.go('ach');`,

  /* 技能页：习得一批技能 */
  demo_skill: `
    demoStart('00', '二线城市');
    ['programming','driving','medical','business','cooking','fitness','finance','law','pet_care','meditation']
      .forEach(function (id) { TL.learnSkill(id); });
    window.ui.go('skill');`,

  /* 金手指控制台：密码解锁后 */
  demo_god: `
    demoStart('20', '一线城市');
    TL.S.godUnlocked = true; TL.S.flags.godUsed = 1; TL.unlock('开挂人生');
    window.ui.go('god');`,

  /* 人生总结：直接死亡结算 */
  demo_death: `
    demoStart('10', '省会城市');
    demoYears(26, false);
    window.ui.doGodKill();`
};

Object.keys(scenarios).forEach((name) => {
  const html = app.replace('</body>', driver(scenarios[name]) + '\n</body>');
  fs.writeFileSync(path.join(OUT, name + '.html'), html, 'utf8');
});
console.log('已生成演示页: ' + Object.keys(scenarios).join(', '));
