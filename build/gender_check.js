const fs=require('fs'),path=require('path');
const ROOT=process.cwd();const store={};
global.window=global;
global.localStorage={getItem:k=>store[k]||null,setItem:(k,v)=>{store[k]=String(v)},removeItem:k=>{delete store[k]}};
global.document={readyState:'complete',getElementById:()=>({innerHTML:'',className:'',value:'',style:{},scrollTop:0}),addEventListener(){}};
global.__TL_DATA__=JSON.parse(fs.readFileSync(path.join(ROOT,'assets/json/event.json'),'utf8'));
global.__TL_RULES__=JSON.parse(fs.readFileSync(path.join(ROOT,'src/age-rules.json'),'utf8'));
(0,eval)(fs.readFileSync(path.join(ROOT,'src/js/01_core.js'),'utf8'));
const T=global.TL;
const evs=global.__TL_DATA__;
let blocked=0, femaleOnly=0, maleOnly=0;
for(const e of evs){
  const m={gender:'男',pets:[{alive:true}],relations:[{type:'spouse',name:'a',alive:true},{type:'lover',name:'b',alive:true},{type:'child',name:'c',alive:true},{type:'friend',name:'d',alive:true}],flags:{record:1},prison:1,job:'x',salary:1,name:'测试'};
  const f=Object.assign({},m,{gender:'女'});
  const rm=T.genderReason(e,m), rf=T.genderReason(e,f);
  if(rm&&rf){blocked++;console.log('  ✗ 男女都被挡: '+e.title);}
  else if(rf) femaleOnly++;
  else if(rm) maleOnly++;
}
console.log('  男向专属 '+maleOnly+' 条 / 女向专属 '+femaleOnly+' 条 / 双向被封 '+blocked+' 条');
console.log('  事件总数 '+evs.length);
// 年龄区间有效性：每条事件在声明区间内至少有一岁能抽到（考虑规则收窄）
let dead=0;
for(const e of evs){
  const [a,b]=e.age_range; const [lo,hi]=T.effectiveAgeRange(e);
  if(hi<lo||hi<a||lo>b){dead++;console.log('  ✗ 有效区间为空: '+e.title+' 声明'+a+'-'+b+' 实际'+lo+'-'+hi);}
}
console.log('  有效区间为空的事件: '+dead+' 条');
