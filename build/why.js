const fs=require('fs'),path=require('path');const ROOT=process.cwd();
const evs=JSON.parse(fs.readFileSync(path.join(ROOT,'assets/json/event.json'),'utf8'));
const rules=JSON.parse(fs.readFileSync(path.join(ROOT,'src/age-rules.json'),'utf8'));
function full(e){let t=(e.title||'')+' '+(e.story||'');e.choices.forEach(c=>{t+=' '+(c.option_text||'')+' '+(c.desc||'');});return t;}
function eff(e){let [a,b]=e.age_range,lo=a,hi=b;const t=full(e),ti=e.title||'';
  rules.ageRules.forEach(r=>{if(!r.kw)return;const s=(r.scope==='title')?ti:t;if(!new RegExp(r.kw).test(s))return;
    if(typeof r.min==='number'&&r.min>lo)lo=r.min; if(typeof r.max==='number'&&r.max<hi)hi=r.max;});
  if(lo>hi)return [a,b]; if(hi===100)hi=110; return [lo,hi];}
for(const t of ['偷偷看小说被没收','好朋友搬家转学分别','学一门手艺']){
  const e=evs.find(x=>x.title===t);
  if(!e){console.log(t+' 不存在');continue;}
  const hit=rules.ageRules.filter(r=>r.kw&&new RegExp(r.kw).test((r.scope==='title')?e.title:full(e))).map(r=>r.id);
  console.log(e.title.padEnd(14)+' 声明='+e.age_range.join('-')+' 纠偏后='+eff(e).join('-')+' 命中规则='+(hit.join(',')||'无'));
}
