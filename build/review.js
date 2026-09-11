const fs=require('fs'),path=require('path');const ROOT=process.cwd();
const evs=JSON.parse(fs.readFileSync(path.join(ROOT,'assets/json/event.json'),'utf8'));
function full(e){let t=(e.title||'')+' '+(e.story||'');e.choices.forEach(c=>{t+=' '+(c.option_text||'')+' '+(c.desc||'');});return t;}
console.log('=== 能出现在 8 岁及以下的事件（按声明区间）===');
evs.filter(e=>e.age_range[0]<=8).forEach(e=>{
  console.log('  ['+e.age_range.join('-')+'] '+e.title);
});
console.log('\n=== 能出现在 75 岁及以上的事件（按声明区间）===');
evs.filter(e=>e.age_range[1]>=75).forEach(e=>{
  console.log('  ['+e.age_range.join('-')+'] '+e.title);
});
