const fs=require('fs'),path=require('path');const ROOT=process.cwd();
const dir=path.join(ROOT,'build/patches');
const files=fs.readdirSync(dir).filter(f=>/^events_.*\.json$/.test(f));
const SPOUSE=/老伴|配偶|妻子|丈夫|老婆|老公|媳妇/;
let n=0;
for(const f of files){
  const arr=JSON.parse(fs.readFileSync(path.join(dir,f),'utf8'));
  arr.forEach((e,i)=>{
    const parts=[['title',e.title],['story',e.story]];
    e.choices.forEach((c,j)=>{parts.push(['choice'+j+'.desc',c.desc]);parts.push(['choice'+j+'.text',c.option_text]);});
    for(const [where,txt] of parts){
      if(!txt)continue;
      const idx=txt.search(/她|他/);
      if(idx<0)continue;
      // 只在同一句里出现配偶词，或整条事件里出现配偶词时才算可疑
      const ctx=txt.slice(Math.max(0,idx-16),idx+16).replace(/\s+/g,' ');
      const spouseCtx=SPOUSE.test(txt)||SPOUSE.test(e.story)||SPOUSE.test(e.title);
      if(spouseCtx){ n++; console.log(f.replace('events_','').replace('.json','')+'#'+(i+1)+' ['+where+'] '+e.title.slice(0,20)+'  …'+ctx+'…'); }
    }
  });
}
console.log('\n可疑处共 '+n+' 处');
