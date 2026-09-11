import json, re, os
root = r"C:\Users\fanyo\Desktop\ds\项目1"
data = json.load(open(os.path.join(root, "assets/json/event.json"), encoding="utf-8"))
GROUPS = {
  "需要配偶/恋人": r"离婚|冷战|分居|出轨|背叛|配偶|爱人|丈夫|妻子|老公|老婆",
  "需要子女":     r"孩子叛逆|孩子青春期|子女叛逆|孩子离家|儿子|女儿|孩子考上|带娃|孙子|孙女",
  "需要宠物":     r"宠物|毛孩子|小猫|小狗|流浪猫|流浪狗|遛狗|猫砂|狗粮",
  "需要服刑/案底": r"越狱|减刑|出狱|狱友|牢狱|服刑|案底|监狱",
  "需要工作":     r"失业|被裁|裁员|跳槽|升职|加薪|同事|老板|公司|职场|加班|工资|月薪|面试|简历|入职|上班",
}
for name, pat in GROUPS.items():
    hits = []
    for i, ev in enumerate(data):
        t = ev["title"] + " " + ev["story"] + " " + " ".join(c.get("option_text","")+c.get("desc","") for c in ev["choices"])
        if re.search(pat, t):
            hits.append((i+1, ev["age_range"], ev["title"]))
    print(f"=== {name}：{len(hits)} 条 ===")
    for i, ar, ti in hits[:14]:
        print(f"   #{i:<4} {ar[0]}-{ar[1]:<4} {ti[:34]}")
    if len(hits) > 14: print(f"   … 另有 {len(hits)-14} 条")
    print()
