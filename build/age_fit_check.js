const fs=require('fs'),path=require('path');
const ROOT=process.cwd();const store={};
global.window=global;
global.localStorage={getItem:k=>store[k]||null,setItem:(k,v)=>{store[k]=String(v)},removeItem:k=>{delete store[k]}};
global.document={readyState:'complete',getElementById:()=>({innerHTML:'',className:'',value:'',style:{},scrollTop:0}),addEventListener(){}};
global.__TL_DATA__=JSON.parse(fs.readFileSync(path.join(ROOT,'assets/json/event.json'),'utf8'));
global.__TL_RULES__=JSON.parse(fs.readFileSync(path.join(ROOT,'src/age-rules.json'),'utf8'));
(0,eval)(fs.readFileSync(path.join(ROOT,'src/js/01_core.js'),'utf8'));
const T=global.TL;
T.DATA={event:global.__TL_DATA__,talents:[{name:'x',desc:'x',attrModify:{}}],achievements:[{name:'a',desc:'a',trigger:'t'}],skills:[],city:[{cityName:'小县城',eraFactor:{'90':true},desc:'',attrEffect:{'压力值':0,'财富上限':1}}]};
// 独立于规则表的"禁忌词"清单，用来人工核对
const TABOO = [
  [/高考|中考|高三|初三|升学/, [0,13], '升学'],
  [/幼儿园|学前班|小红花/, [9,110], '幼儿园'],
  [/早恋|情书|暗恋/, [0,11], '早恋'],
  [/面试|简历|入职|试用期/, [0,15], '求职'],
  [/升职|加薪|被裁|裁员|跳槽|同事|加班|月薪/, [0,15], '职场'],
  [/创业|融资|开店|合伙人/, [0,19], '创业'],
  [/买房|房贷|首付|楼市|房价/, [0,19], '房产'],
  [/结婚|婚礼|彩礼/, [0,19], '结婚'],
  [/怀孕|生子|生育|降生/, [0,19], '生育'],
  [/孙子|孙女|抱上孙/, [0,44], '孙辈'],
  [/退休|养老|广场舞|保健品|卧床/, [0,49], '养老'],
  [/抽烟|吸烟|喝酒|酒瘾|应酬/, [0,11], '烟酒'],
  [/网吧|网瘾|街机/, [0,9], '网吧'],
  [/入狱|服刑|出狱|减刑|越狱|案底/, [0,13], '牢狱'],
  [/诈骗|违法|盗窃|斗殴|判刑|抓获/, [0,13], '犯罪'],
  [/考试|成绩|作业|家长会/, [70,110], '考试(老年)'],
  [/职场|加班|升职|跳槽|创业|融资/, [70,110], '职场(老年)'],
  [/买房|房贷|股票|理财|投资|炒币/, [85,110], '投资(老年)'],
  [/诈骗|入狱|违法|赌博/, [70,110], '犯罪(老年)'],
  [/早恋|情书|表白|相亲/, [80,110], '恋爱(老年)'],
];
const ages=[3,6,10,14,17,22,28,35,45,55,62,72,85,100,108];
let totalBad=0;
console.log('年龄 | 池子 | 抽样(前2条) | 违规');
for(const age of ages){
  T.S={age:age,era:'90',cityName:'小县城',pets:[{alive:true}],relations:[{type:'spouse',name:'x',alive:true},{type:'child',name:'y',alive:true}],skills:[],talents:[],addictions:{},flags:{eraSeen:{}},usedTitles:[],attrs:{},job:'程序员',salary:20000,prison:0,stat:{},assets:{}};
  const pool=T.DATA.event.filter(e=>T.eventMatch(e,age,'90'));
  const bad=[];
  for(const e of pool){
    const txt=T.eventText(e);
    for(const [re,band,label] of TABOO){
      if(band[0]<=age&&age<=band[1]&&re.test(txt)){bad.push(label+':'+e.title.slice(0,12));break;}
    }
  }
  totalBad+=bad.length;
  console.log(String(age).padStart(4)+' | '+String(pool.length).padStart(4)+' | '+pool.slice(0,2).map(e=>e.title.slice(0,14)).join(' / ')+' | '+(bad.length?bad.slice(0,3).join(' , '):'✓'));
}
console.log('\n违规总数: '+totalBad);
