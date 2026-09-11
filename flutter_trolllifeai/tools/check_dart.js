// 工程自检脚本（仅用于开发期检查，不属于 Flutter 工程代码）
// 用法: node tools/check_dart.js <工程根目录>
// 检查项：
//   1. 每个 dart 文件的 {} () [] 配对（跳过字符串与注释）
//   2. 每个 dart 文件的引号配对（' " 三引号）
//   3. import 'xxx' 指向的文件是否真实存在
//   4. 常见漏写分号的可疑行（以标识符/)/]/} 结尾但既无 ; 也无 { , 的行）

const fs = require('fs');
const path = require('path');

const root = process.argv[2] || '.';
const libDir = path.join(root, 'lib');

function walk(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(p, out);
    else if (entry.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

const files = walk(libDir, []).sort();
let errors = 0;
let warnings = 0;
const rows = [];

for (const file of files) {
  const src = fs.readFileSync(file, 'utf8');
  const lines = src.split(/\r?\n/);

  // ---- 逐字符扫描，跳过注释与字符串 ----
  const stack = [];
  const pairs = { '}': '{', ')': '(', ']': '[' };
  let i = 0;
  let line = 1;
  let inLine = false;      // //
  let inBlock = false;     // /* */
  let strQuote = null;     // ' " ''' """
  let triple = false;
  const fileIssues = [];

  while (i < src.length) {
    const ch = src[i];
    const next2 = src.substr(i, 2);
    const next3 = src.substr(i, 3);
    if (ch === '\n') line++;

    if (inLine) {
      if (ch === '\n') inLine = false;
      i++;
      continue;
    }
    if (inBlock) {
      if (next2 === '*/') { inBlock = false; i += 2; continue; }
      i++;
      continue;
    }
    if (strQuote) {
      if (triple) {
        if (next3 === strQuote) { strQuote = null; triple = false; i += 3; continue; }
        if (ch === '\\') { i += 2; continue; }
        i++;
        continue;
      }
      if (ch === '\\') { i += 2; continue; }
      if (ch === strQuote) { strQuote = null; i++; continue; }
      if (ch === '\n') {
        fileIssues.push(`第 ${line} 行：字符串未闭合（${strQuote}）`);
        strQuote = null;
      }
      i++;
      continue;
    }

    // 注释开始
    if (next2 === '//') { inLine = true; i += 2; continue; }
    if (next2 === '/*') { inBlock = true; i += 2; continue; }

    // 字符串开始（含 r'...' 与三引号）
    if (ch === "'" || ch === '"') {
      if (next3 === ch + ch + ch) { strQuote = ch; triple = true; i += 3; continue; }
      strQuote = ch; i++; continue;
    }
    if ((ch === 'r' || ch === 'R') && (src[i + 1] === "'" || src[i + 1] === '"')) {
      // raw string：内部不处理转义
      const q = src[i + 1];
      if (src.substr(i + 1, 3) === q + q + q) {
        const end = src.indexOf(q + q + q, i + 4);
        if (end < 0) { fileIssues.push(`第 ${line} 行：raw 三引号字符串未闭合`); i = src.length; }
        else i = end + 3;
        continue;
      }
      const end = src.indexOf(q, i + 2);
      if (end < 0) { fileIssues.push(`第 ${line} 行：raw 字符串未闭合`); i = src.length; }
      else i = end + 1;
      continue;
    }

    if (ch === '{' || ch === '(' || ch === '[') {
      stack.push({ ch, line });
      i++;
      continue;
    }
    if (ch === '}' || ch === ')' || ch === ']') {
      const top = stack.pop();
      if (!top) {
        fileIssues.push(`第 ${line} 行：多余的 '${ch}'`);
      } else if (top.ch !== pairs[ch]) {
        fileIssues.push(`第 ${line} 行：'${ch}' 与第 ${top.line} 行的 '${top.ch}' 不匹配`);
      }
      i++;
      continue;
    }
    i++;
  }

  if (inBlock) fileIssues.push('文件末尾有未闭合的块注释 /*');
  if (strQuote) fileIssues.push('文件末尾有未闭合的字符串');
  for (const s of stack) {
    fileIssues.push(`第 ${s.line} 行的 '${s.ch}' 没有闭合`);
  }

  // ---- import 路径检查 ----
  const importRe = /import\s+['"]([^'"]+)['"]/g;
  let m;
  while ((m = importRe.exec(src)) !== null) {
    const spec = m[1];
    if (spec.startsWith('dart:') || spec.startsWith('package:')) continue;
    const target = path.resolve(path.dirname(file), spec);
    if (!fs.existsSync(target)) {
      fileIssues.push(`import 指向不存在的文件: ${spec}`);
    }
  }

  // ---- 可疑漏分号 ----
  lines.forEach((text, idx) => {
    // 先剥掉行尾注释，避免「语句; // 说明」被误判
    const t = text.replace(/\/\/.*$/, '').trim();
    if (!t) return;
    if (/^(\/\*|\*)/.test(t)) return;
    if (/[;{[(,:]$/.test(t)) return;
    if (/[}\]\)]$/.test(t)) return;
    if (/^(\}|\{|@|import|export|part|library)/.test(t)) return;
    if (/^(case|default|else|try|finally|do)\b/.test(t)) return;
    if (/^\s*['"].*['"],?$/.test(t)) return;
    // 形如 "final x = 1" 之类
    if (/^[A-Za-z_<>,\s\[\]]+\s+[A-Za-z_0-9]+\s*=\s*[^=].*[^;,{([]$/.test(t)) {
      fileIssues.push(`第 ${idx + 1} 行疑似漏写分号: ${t.slice(0, 60)}`);
    }
  });

  if (fileIssues.length) {
    errors += fileIssues.length;
    console.log(`\n[X] ${path.relative(root, file)}`);
    fileIssues.forEach((s) => console.log('    ' + s));
  } else {
    rows.push(`${path.relative(root, file).replace(/\\/g, '/')}|${lines.length}`);
  }
}

console.log('\n===== 通过检查的文件（路径|行数）=====');
rows.forEach((r) => console.log(r));
console.log(`\n合计 ${files.length} 个 dart 文件，问题 ${errors} 处，警告 ${warnings} 处。`);
process.exit(errors ? 1 : 0);
