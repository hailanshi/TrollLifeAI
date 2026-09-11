const fs=require('fs'),path=require('path');const ROOT=process.cwd();
const evs=JSON.parse(fs.readFileSync(path.join(ROOT,'assets/json/event.json'),'utf8'));
function full(e){let t=(e.title||'')+' '+(e.story||'');e.choices.forEach(c=>{t+=' '+(c.option_text||'')+' '+(c.desc||'');});return t;}
const hit=evs.filter(e=>/她|他/.test(full(e)));
console.log('含第三人称「她/他」的事件共 '+hit.length+' 条（前 30 条）：');
hit.slice(0,30).forEach((e,i)=>{
  const t=full(e); const idx=t.indexOf('她')>=0?t.indexOf('她'):t.indexOf('他');
  console.log('  '+(i+1)+'. '+e.title.slice(0,26)+'  …'+t.slice(Math.max(0,idx-12),idx+14).replace(/\s+/g,' ')+'…');
});
const spouseLike=hit.filter(e=>/老伴|丈夫|妻子|配偶/.test(full(e)));
console.log('\n其中涉及配偶的: '+spouseLike.length+' 条');
spouseLike.forEach(e=>console.log('   '+e.title.slice(0,30)));
