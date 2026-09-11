import json, re, os
root = r"C:\Users\fanyo\Desktop\ds\项目1"
RULES = [
    (r"幼儿园|学前班|小红花", 0, 8, "幼儿园"),
    (r"高考|中考|升学考试|志愿填报|复读", 14, 20, "升学考试"),
    (r"早恋|情书|表白|暗恋|初恋|谈恋爱|约会", 12, 60, "恋爱"),
    (r"校园|学校|同学|班主任|老师|作业|校运会|兴趣班|特长班|同桌|宿舍|考研|大学|班里", 6, 24, "校园"),
    (r"相亲|结婚|婚礼|彩礼|婚姻|配偶", 20, 100, "婚姻"),
    (r"怀孕|生子|生育|子女|孩子|带娃", 20, 100, "生育"),
    (r"失业|裁员|跳槽|升职|加薪|同事|老板|公司|加班|职场|工资|月薪|面试|简历|入职|打工", 18, 100, "职场"),
    (r"买房|房贷|首付|楼市|房价", 20, 100, "房产"),
    (r"创业|融资|股权|合伙人|开店|做生意", 20, 100, "创业"),
    (r"退休|养老|广场舞|老年|孙子|孙女|保健品|遛弯|跳广场舞", 50, 110, "老年"),
    (r"网吧|通宵打游戏|游戏机", 12, 100, "网吧"),
    (r"入狱|服刑|出狱|越狱|减刑|案底|牢狱|监狱", 16, 100, "犯罪"),
    (r"出轨|离婚|冷战|分居", 20, 100, "婚变"),
    (r"孩子叛逆|孩子青春期|子女叛逆|孩子离家|儿子叛逆|女儿叛逆", 32, 100, "子女叛逆"),
    (r"考试|成绩|升学", 7, 24, "考试"),
]
def gate(ev):
    t = ev.get("title","") + " " + ev.get("story","")
    for c in ev.get("choices", []):
        t += " " + c.get("option_text","") + " " + c.get("desc","")
    a, b = ev["age_range"]
    lo, hi = a, b
    hits = []
    for pat, mn, mx, name in RULES:
        if re.search(pat, t):
            hits.append(name)
            lo = max(lo, mn); hi = min(hi, mx)
    if lo > hi:   # 规则相互冲突 → 放弃纠偏，保留原区间
        return a, b, hits + ["冲突忽略"]
    return lo, hi, hits

data = json.load(open(os.path.join(root, "assets/json/event.json"), encoding="utf-8"))
print(f"=== assets/json/event.json 共 {len(data)} 条（原始 35 + 新增 120）===")
bad = 0
for i, ev in enumerate(data):
    lo, hi, hits = gate(ev)
    a, b = ev["age_range"]
    if (lo, hi) != (a, b):
        bad += 1
        tag = "原始" if i < 35 else "新增"
        print(f"  [{tag} #{i+1}] {a}-{b} -> {lo}-{hi}   {ev['title'][:30]}   （{'/'.join(hits)}）")
print(f"\n需要纠偏：{bad} 条 / 共 {len(data)} 条")
