const fs=require('fs'),path=require('path');
const ROOT=process.cwd();
const store={};
global.window=global;
global.localStorage={getItem:k=>store[k]||null,setItem:(k,v)=>{store[k]=String(v)},removeItem:k=>{delete store[k]}};
global.document={readyState:'complete',getElementById:()=>({innerHTML:'',className:'',value:'',style:{},scrollTop:0}),addEventListener(){}};
global.__TL_DATA__=JSON.parse(fs.readFileSync(path.join(ROOT,'assets/json/event.json'),'utf8'));
global.__TL_RULES__=JSON.parse(fs.readFileSync(path.join(ROOT,'src/age-rules.json'),'utf8'));
(0,eval)(fs.readFileSync(path.join(ROOT,'src/js/01_core.js'),'utf8'));
const T=global.TL;
T.DATA={event:global.__TL_DATA__,talents:[{name:'x',desc:'x',attrModify:{}}],achievements:[{name:'a',desc:'a',trigger:'t'}],skills:[],city:[{cityName:'小县城',eraFactor:{'90':true},desc:'',attrEffect:{'压力值':0,'财富上限':1}}]};
const ages=[3,5,7,9,11,13,15,17,20,25,30,40,55,65,80,105];
console.log('年龄 | 可抽事件数 | 抽样标题');
for(const age of ages){
  T.S={age:age,era:'90',cityName:'小县城',pets:[],relations:[],skills:[],talents:[],addictions:{},flags:{eraSeen:{}},usedTitles:[],attrs:{},job:'',salary:0,prison:0,stat:{},assets:{}};
  const pool=T.DATA.event.filter(e=>T.eventMatch(e,age,'90'));
  const s=[];
  for(let i=0;i<3;i++){const e=T.randomEvent(); if(e)s.push(e.title.slice(0,15));}
  console.log(String(age).padStart(4)+' | '+String(pool.length).padStart(6)+'     | '+s.join(' / '));
}
