/**
 * fix-pronouns.js —— 把新增剧情里「指代配偶」的硬编码第三人称改成中性占位符
 * 只改 build/patches 下我自己新增的剧情文件，原始 5 份 JSON 与既有 35 条剧情一个字节都不动。
 * 用法： node tools/fix-pronouns.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DIR = path.resolve(__dirname, '..', 'build', 'patches');

/* 每项：[文件, 查找串, 替换串] —— 查找串必须唯一命中 */
const FIXES = [
  /* 1. 老伴住院：给「她」接水 → {配偶} */
  ['events_e.json',
    '半夜起来三次给她接水、翻身、看输液还剩多少。天亮时你下楼买两个包子，回来发现她已经自己坐起来了，还怪你瘦了。',
    '半夜起来三次给{配偶}接水、翻身、看输液还剩多少。天亮时你下楼买两个包子，回来发现{配偶}已经自己坐起来了，还怪你瘦了。'],
  ['events_e.json',
    '你睡了个整觉，儿子在饭桌上说了句爸也挺不容易。',
    '你睡了个整觉，儿子在饭桌上说了句你也不容易。'],
  ['events_e.json',
    '出院那天你在楼梯口差点跪下去，两个膝盖肿得发亮。【关系:spouse:老伴】',
    '出院那天你在楼梯口差点跪下去，两个膝盖肿得发亮。【关系:spouse:老伴】'],

  /* 2. 亡故老伴的枕头：标题与正文的「她」 → {配偶} */
  ['events_e.json', '"title": "她的枕头还留着洗发水的味道"', '"title": "{配偶}的枕头还留着洗发水的味道"'],
  ['events_e.json', '你把她的牙刷留在杯子里', '你把{配偶}的牙刷留在杯子里'],
  ['events_e.json', '她的枕头上有一点点洗发水的味道', '{配偶}的枕头上有一点点洗发水的味道'],

  /* 3. 黄昏恋：原文是男性视角（老太太），改成性别中立 */
  ['events_e.json',
    '老年大学认识的老太太愿意跟你搭伴过日子，她说不要名分，只想有个人一起买菜做饭。你把这事跟儿女提了，儿子筷子一放，说那套房以后算谁的。老太太还在楼下等你回话。',
    '老年大学认识的一个人愿意跟你搭伴过日子，说不要名分，只想有个人一起买菜做饭。你把这事跟儿女提了，儿子筷子一放，说那套房以后算谁的。{ta}还在楼下等你回话。'],
  ['events_e.json', '"option_text": "不管儿女态度，和她去领证"', '"option_text": "不管儿女反对，直接去领证"'],
  ['events_e.json', '公证办好了，房子保住了，楼下再没见过她。', '公证办好了，房子保住了，楼下再没见过那个人。'],

  /* 4. 手术室门口：配偶的手术后用「她」 → {配偶} */
  ['events_h.json', '她醒来第一眼看见的是你，你的年终奖少了一截。', '{配偶}醒来第一眼看见的是你，你的年终奖少了一截。'],
  ['events_h.json', '护理很专业，她嘴上说理解，夜里还是自己按的呼叫铃。', '护理很专业，{配偶}嘴上说理解，夜里还是自己按的呼叫铃。'],
];

let applied = 0, skipped = [];
FIXES.forEach(([file, from, to]) => {
  if (from === to) { return; }
  const p = path.join(DIR, file);
  if (!fs.existsSync(p)) { skipped.push(file + ' 不存在'); return; }
  let text = fs.readFileSync(p, 'utf8');
  const count = text.split(from).length - 1;
  if (count === 0) { skipped.push(file + ' 未命中: ' + from.slice(0, 24)); return; }
  if (count > 1) { skipped.push(file + ' 命中 ' + count + ' 次（跳过，避免误改）: ' + from.slice(0, 24)); return; }
  text = text.replace(from, to);
  fs.writeFileSync(p, text, 'utf8');
  applied++;
  console.log('✓ ' + file + '  ' + from.slice(0, 22) + '… → ' + to.slice(0, 22) + '…');
});

/* 改完必须仍是合法 JSON */
let bad = 0;
['events_e.json', 'events_h.json'].forEach((f) => {
  const p = path.join(DIR, f);
  try {
    const arr = JSON.parse(fs.readFileSync(p, 'utf8'));
    console.log('  ' + f + ' 仍可解析，共 ' + arr.length + ' 条');
  } catch (e) { bad++; console.log('  ✗ ' + f + ' JSON 损坏: ' + e.message); }
});
console.log('\n应用 ' + applied + ' 处修改' + (skipped.length ? ('，跳过 ' + skipped.length + ' 处：\n  ' + skipped.join('\n  ')) : ''));
process.exit(bad ? 1 : 0);
