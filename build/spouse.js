const fs=require('fs'),path=require('path');const ROOT=process.cwd();
const evs=JSON.parse(fs.readFileSync(path.join(ROOT,'assets/json/event.json'),'utf8'));
const want=['老伴住院，陪护床睡了一夜又一夜','她的枕头还留着洗发水的味道','黄昏恋遇上子女的冷脸','为孩子的教育方式吵到半夜','孩子半夜摔门走了','重点高中的录取通知','在手术室门口等了五个小时'];
for(const t of want){
  const e=evs.find(x=>x.title===t); if(!e)continue;
  console.log('=== '+e.title+' ['+e.age_range.join('-')+'] ===');
  console.log('  story: '+e.story);
  e.choices.forEach(c=>console.log('  - '+c.option_text+' | '+c.desc));
  console.log('');
}
