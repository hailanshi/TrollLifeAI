// TrollLifeAI 单元测试
//
// 运行：flutter test
// 覆盖：模型序列化、属性上下限、标记解析、成就判定、事件引擎逐年推进。

import 'package:flutter_test/flutter_test.dart';

import 'package:trolllifeai/models/achievement.dart';
import 'package:trolllifeai/models/asset_state.dart';
import 'package:trolllifeai/models/character.dart';
import 'package:trolllifeai/models/city_data.dart';
import 'package:trolllifeai/models/life_event.dart';
import 'package:trolllifeai/models/pet.dart';
import 'package:trolllifeai/models/relation.dart';
import 'package:trolllifeai/models/skill.dart';
import 'package:trolllifeai/models/talent.dart';
import 'package:trolllifeai/providers/game_provider.dart';
import 'package:trolllifeai/services/data_loader.dart';
import 'package:trolllifeai/services/event_engine.dart';
import 'package:trolllifeai/services/storage_service.dart';

/// 构造一个用于测试的角色
Character _makeCharacter({
  String era = '00',
  String city = '二线城市',
  double capFactor = 1.0,
  int stressMod = 0,
}) {
  return Character(
    name: '测试者',
    era: era,
    cityName: city,
    wealthCapFactor: capFactor,
    cityStressModifier: stressMod,
  );
}

/// 构造一个空的引擎（不依赖 assets）
EventEngine _makeEngine() => EventEngine(data: GameDataBundle.empty);

void main() {
  group('StatDelta 属性变化量', () {
    test('从中文键解析 11 项属性', () {
      final StatDelta delta = StatDelta.fromJson(<String, dynamic>{
        '智力': 3,
        '财富': -5000,
        '健康值': 2,
        '不存在的键': 99,
      });
      expect(delta.get(AttributeKey.intelligence), 3);
      expect(delta.get(AttributeKey.wealth), -5000);
      expect(delta.get(AttributeKey.health), 2);
      // 未知键应当被忽略而不是抛异常
      expect(delta.values.length, 3);
    });

    test('toReadable 输出中文可读文本', () {
      final StatDelta delta = StatDelta(<AttributeKey, int>{
        AttributeKey.intelligence: 3,
        AttributeKey.wealth: 20000,
      });
      final String text = delta.toReadable();
      expect(text.contains('智力+3'), isTrue);
      expect(text.contains('财富+2.00万'), isTrue);
    });

    test('scaled 按比例放大并四舍五入', () {
      final StatDelta delta = StatDelta.single(AttributeKey.charm, 10);
      expect(delta.scaled(0.7).get(AttributeKey.charm), 7);
      expect(delta.scaled(1.07).get(AttributeKey.charm), 11);
    });

    test('merge 合并两项变化', () {
      final StatDelta a = StatDelta.single(AttributeKey.luck, 5);
      final StatDelta b = StatDelta.single(AttributeKey.luck, 3);
      final StatDelta merged = a.merge(b);
      expect(merged.get(AttributeKey.luck), 8);
    });
  });

  group('Character 角色模型', () {
    test('初始 11 项属性符合设计', () {
      final Character c = _makeCharacter();
      expect(c.attr(AttributeKey.intelligence), 50);
      expect(c.attr(AttributeKey.constitution), 50);
      expect(c.attr(AttributeKey.charm), 50);
      expect(c.attr(AttributeKey.luck), 50);
      expect(c.attr(AttributeKey.wealth), 0);
      expect(c.attr(AttributeKey.health), 70);
      expect(c.attr(AttributeKey.stress), 20);
      expect(c.attr(AttributeKey.happiness), 60);
      expect(c.attr(AttributeKey.addiction), 0);
      expect(c.attr(AttributeKey.sin), 0);
      expect(c.attr(AttributeKey.fame), 0);
      expect(AttributeKeyX.all.length, 11);
    });

    test('财富上限 = 300000 × 城市系数', () {
      expect(_makeCharacter(capFactor: 0.6).wealthCap, 180000);
      expect(_makeCharacter(capFactor: 1.6).wealthCap, 480000);
      expect(_makeCharacter(capFactor: 2.0).wealthCap, 600000);
    });

    test('toJson / fromJson 往返一致', () {
      final Character c = _makeCharacter(capFactor: 1.4, stressMod: 5);
      c.age = 33;
      c.skills.add('programming');
      c.talents.add('天资聪颖');
      c.addictions['烟瘾'] = 42;
      c.relations.add(
        Relation(name: '小林', type: RelationType.friend, favor: 77),
      );
      c.pets.add(Pet(name: '猫·团子', species: '猫', age: 3));
      c.assets.cash = 12345;
      c.assets.debt = 6789;
      c.log('测试日志');

      final Character restored =
          Character.fromJson(c.toJson());
      expect(restored.name, '测试者');
      expect(restored.age, 33);
      expect(restored.skills, contains('programming'));
      expect(restored.addictions['烟瘾'], 42);
      expect(restored.relations.first.favor, 77);
      expect(restored.pets.first.name, '猫·团子');
      expect(restored.assets.cash, 12345);
      expect(restored.assets.debt, 6789);
      expect(restored.logs.isNotEmpty, isTrue);
    });

    test('关系数量统计正确', () {
      final Character c = _makeCharacter();
      c.relations.add(Relation(name: 'a', type: RelationType.friend, favor: 95));
      c.relations.add(Relation(name: 'b', type: RelationType.child));
      c.relations.add(Relation(name: 'c', type: RelationType.child));
      c.relations.add(Relation(name: 'd', type: RelationType.enemy));
      c.relations.add(
        Relation(name: 'e', type: RelationType.friend, favor: 50),
      );
      expect(c.childCount, 2);
      expect(c.enemyCount, 1);
      expect(c.closeFriendCount, 1);
      expect(c.activeRelations.length, 5);
    });

    test('成瘾统计与最严重成瘾', () {
      final Character c = _makeCharacter();
      c.addictions['烟瘾'] = 66;
      c.addictions['酒瘾'] = 12;
      expect(c.maxAddiction, 66);
      expect(c.severeAddictionCount, 1);
      expect(c.hasAddiction('烟瘾'), isTrue);
      expect(c.hasAddiction('赌瘾'), isFalse);
    });
  });

  group('AssetState 资产', () {
    test('净值 = 现金 + 房产 + 车辆 - 负债', () {
      final AssetState a = AssetState(cash: 10000, debt: 3000);
      a.properties.add(
        PropertyAsset(cityName: '杭州', price: 100000, value: 120000, boughtAge: 30),
      );
      a.vehicles.add(
        VehicleAsset(label: '家用轿车', price: 100000, value: 80000, boughtAge: 31),
      );
      expect(a.totalAsset, 210000);
      expect(a.netWorth, 207000);
    });

    test('负债 ≥50000 会记录「曾经高负债」标记', () {
      final AssetState a = AssetState();
      a.addDebt(60000);
      expect(a.everDebtOver50k, isTrue);
      expect(a.debt, 60000);
    });

    test('还债不会产生负负债', () {
      final AssetState a = AssetState(cash: 20000, debt: 5000);
      a.repay(8000);
      expect(a.debt, 0);
      // 多还的 3000 应该退回现金
      expect(a.cash, 17000);
    });
  });

  group('LifeEvent 事件与标记解析', () {
    test('从 JSON 解析事件并剔除标记', () {
      final LifeEvent e = LifeEvent.fromJson(<String, dynamic>{
        'age_range': <int>[18, 40],
        'title': '【90年代】排队买股票认购证',
        'story': '你排了一夜的队，天亮时终于买到。',
        'choices': <dynamic>[
          <String, dynamic>{
            'option_text': '全部买下',
            'attr_change': <String, dynamic>{
              '智力': 1,
              '体质': -1,
              '魅力': 0,
              '财富': 20000,
              '快乐': 3,
              '运气': 2,
              '健康值': -1,
              '成瘾值': 0,
              '名声值': 2,
              '压力值': 4,
              '罪恶值': 0,
            },
            'desc': '你成了街坊眼里的能人。【习得:finance】',
          },
        ],
      });
      expect(e.title, '排队买股票认购证');
      expect(e.eraLimit, contains('90'));
      expect(e.matchAge(20), isTrue);
      expect(e.matchAge(50), isFalse);
      expect(e.choices.first.displayDesc.contains('【'), isFalse);
      expect(e.choices.first.attrChange.get(AttributeKey.wealth), 20000);
    });

    test('stripAll 会清掉标记并清理标点前的空格', () {
      expect(
        LifeEventMarker.stripAll('你赢了 。【职业:程序员】'),
        '你赢了。',
      );
      expect(
        LifeEventMarker.stripAll('【宠物:猫】家里多了一只猫'),
        '家里多了一只猫',
      );
    });

    test('年代标记识别：80年代 与 年代:80', () {
      expect(LifeEventMarker.extractEraLimit('【80年代】粮票换鸡蛋'), <String>['80']);
      expect(LifeEventMarker.extractEraLimit('你在这里长大【年代:20】'), <String>['20']);
      expect(LifeEventMarker.extractEraLimit('【关系:friend:小林】'), isEmpty);
      expect(LifeEventMarker.eraFromMarker('90年代'), '90');
      expect(LifeEventMarker.eraFromMarker('年代:10'), '10');
      expect(LifeEventMarker.eraFromMarker('职业:程序员'), '');
    });

    test('内置强制事件有 11 项齐全的属性变化', () {
      final LifeEvent breakdown = LifeEvent.addictionBreakdown('烟瘾');
      expect(breakdown.forced, isTrue);
      expect(breakdown.choices.length, 3);
      for (final LifeEventChoice choice in breakdown.choices) {
        for (final AttributeKey key in AttributeKeyX.all) {
          expect(
            choice.attrChange.values.containsKey(key),
            isTrue,
            reason: '缺少属性 ${AttributeKeyX.toKey(key)}',
          );
        }
      }
    });
  });

  group('Talent / Skill / CityData / Achievement 解析', () {
    test('天赋只作用 6 项属性', () {
      final Talent t = Talent.fromJson(<String, dynamic>{
        'name': '天资聪颖',
        'desc': '悟性高',
        'attrModify': <String, dynamic>{'智力': 8, '快乐': 2},
      });
      expect(t.attrModify.get(AttributeKey.intelligence), 8);
      expect(t.attrModify.get(AttributeKey.happiness), 2);
      expect(t.attrModify.get(AttributeKey.health), 0);
      expect(t.isMixed, isFalse);
    });

    test('城市按年代筛选', () {
      final CityData c = CityData.fromJson(<String, dynamic>{
        'cityName': '一线城市',
        'eraFactor': <String, dynamic>{'80': false, '10': true},
        'desc': '机会多',
        'attrEffect': <String, dynamic>{'压力值': 4, '财富上限': 1.6},
      });
      expect(c.availableInEra('10'), isTrue);
      expect(c.availableInEra('80'), isFalse);
      expect(c.stressEffect, 4);
      expect(c.wealthCap, 480000);
    });

    test('技能与成就字段完整', () {
      final Skill s = Skill.fromJson(<String, dynamic>{
        'skillId': 'programming',
        'name': '编程',
        'desc': '会写代码',
        'effect': 'IT 事件成功率提升',
      });
      expect(s.skillId, 'programming');
      expect(s.effect.isNotEmpty, isTrue);

      final Achievement a = Achievement.fromJson(<String, dynamic>{
        'name': '有房一族',
        'desc': '买下第一套房',
        'trigger': '买房事件完成',
      });
      expect(a.name, '有房一族');
      expect(a.trigger, '买房事件完成');
    });
  });

  group('EventEngine 事件引擎', () {
    test('属性结算遵守上下限', () {
      final EventEngine engine = _makeEngine();
      final Character c = _makeCharacter();
      c.setAttr(AttributeKey.health, 5);
      c.setAttr(AttributeKey.stress, 95);
      engine.applyMarkers(c, <ParsedMarker>[]);
      // 直接构造一次事件选择来验证裁剪
      final LifeEvent event = LifeEvent(
        title: '测试事件',
        story: '',
        minAge: 0,
        maxAge: 120,
        rawTitle: '测试事件',
        rawStory: '',
        choices: const <LifeEventChoice>[
          LifeEventChoice(
            optionText: '受伤',
            attrChange: StatDelta(<AttributeKey, int>{
              AttributeKey.health: -50,
              AttributeKey.stress: 50,
            }),
            rawDesc: '',
            displayDesc: '',
          ),
        ],
      );
      c.status = LifeStatus.alive;
      engine.applyChoice(c, event, 0);
      expect(c.attr(AttributeKey.health), 0);
      expect(c.attr(AttributeKey.stress), 100);
    });

    test('【习得】标记在没有技能数据时也不会崩溃', () {
      final EventEngine engine = _makeEngine();
      final Character c = _makeCharacter();
      final List<String> msgs = engine.applyMarkers(
        c,
        EventEngine.parseMarkers('你学会了写字。【习得:writing】'),
      );
      expect(msgs, isNotEmpty);
      expect(c.skills, contains('writing'));
    });

    test('【关系】标记创建关系，重复触发会加强好感度', () {
      final EventEngine engine = _makeEngine();
      final Character c = _makeCharacter();
      engine.applyMarkers(c, EventEngine.parseMarkers('【关系:friend:小林】'));
      expect(c.countRelation(RelationType.friend), 1);
      final int before = c.relations.first.favor;
      engine.applyMarkers(c, EventEngine.parseMarkers('【关系:friend:小林】'));
      expect(c.countRelation(RelationType.friend), 1);
      expect(c.relations.first.favor >= before, isTrue);
    });

    test('【关系结束】会把关系置为失效', () {
      final EventEngine engine = _makeEngine();
      final Character c = _makeCharacter();
      engine.applyMarkers(c, EventEngine.parseMarkers('【关系:friend:小林】'));
      engine.applyMarkers(c, EventEngine.parseMarkers('【关系结束:小林】'));
      expect(c.activeRelations.isEmpty, isTrue);
      expect(c.oldFriends, contains('小林'));
    });

    test('【宠物】标记创建宠物，【宠物离世】结束生命', () {
      final EventEngine engine = _makeEngine();
      final Character c = _makeCharacter();
      engine.applyMarkers(c, EventEngine.parseMarkers('【宠物:狗】'));
      expect(c.pets.length, 1);
      expect(c.pets.first.species, '狗');
      engine.applyMarkers(c, EventEngine.parseMarkers('【宠物离世】'));
      expect(c.pets.first.isAlive, isFalse);
    });

    test('【入狱】进入服刑状态，【出狱】恢复自由', () {
      final EventEngine engine = _makeEngine();
      final Character c = _makeCharacter();
      c.hasJob = true;
      c.career = '程序员';
      engine.applyMarkers(c, EventEngine.parseMarkers('【入狱:3】【案底】'));
      expect(c.status, LifeStatus.inPrison);
      expect(c.jailYearsLeft, 3);
      expect(c.everJailed, isTrue);
      expect(c.hasCriminalRecord, isTrue);
      expect(c.unemployed, isTrue);
      engine.applyMarkers(c, EventEngine.parseMarkers('【出狱】'));
      expect(c.status, LifeStatus.alive);
      expect(c.jailYearsLeft, 0);
    });

    test('【减刑】减少剩余刑期', () {
      final EventEngine engine = _makeEngine();
      final Character c = _makeCharacter();
      engine.applyMarkers(c, EventEngine.parseMarkers('【入狱:5】'));
      engine.applyMarkers(c, EventEngine.parseMarkers('【减刑】'));
      expect(c.jailYearsLeft, 4);
      expect(c.everCommuted, isTrue);
    });

    test('【负债】与【还债】正确调整负债', () {
      final EventEngine engine = _makeEngine();
      final Character c = _makeCharacter();
      engine.applyMarkers(c, EventEngine.parseMarkers('【负债:20000】'));
      expect(c.assets.debt, 20000);
      engine.applyMarkers(c, EventEngine.parseMarkers('【还债:10000】'));
      expect(c.assets.debt, 10000);
    });

    test('【成瘾】开放键名，未知成瘾名也能处理', () {
      final EventEngine engine = _makeEngine();
      final Character c = _makeCharacter();
      engine.applyMarkers(c, EventEngine.parseMarkers('【成瘾:糖瘾】'));
      expect(c.addictions.containsKey('糖瘾'), isTrue);
      expect(c.addictions['糖瘾']! > 0, isTrue);
      expect(c.attr(AttributeKey.addiction) > 0, isTrue);
    });

    test('【买房】【买车】记录资产', () {
      final EventEngine engine = _makeEngine();
      final Character c = _makeCharacter();
      c.assets.cash = 2000000;
      c.setAttr(AttributeKey.wealth, 2000000);
      engine.applyMarkers(c, EventEngine.parseMarkers('【买房】【买车】'));
      expect(c.assets.properties.length, 1);
      expect(c.assets.vehicles.length, 1);
      expect(c.everBoughtHouse, isTrue);
      expect(c.everBoughtCar, isTrue);
    });

    test('未知标记只提示不崩溃', () {
      final EventEngine engine = _makeEngine();
      final Character c = _makeCharacter();
      final List<String> msgs = engine.applyMarkers(
        c,
        EventEngine.parseMarkers('【某个未来才有的标记:x:y】'),
      );
      expect(msgs.length, 1);
      expect(msgs.first.contains('未知标记'), isTrue);
    });

    test('技能关键词命中会提高成功率加成', () {
      final EventEngine engine = _makeEngine();
      final Character c = _makeCharacter();
      final LifeEvent event = LifeEvent(
        title: '互联网公司招聘',
        story: '你去面试程序员岗位。',
        minAge: 18,
        maxAge: 60,
        rawTitle: '互联网公司招聘',
        rawStory: '',
        choices: const <LifeEventChoice>[
          LifeEventChoice(
            optionText: '去面试',
            attrChange: StatDelta.zero,
            rawDesc: '',
            displayDesc: '',
          ),
        ],
      );
      final double before = engine.successBonus(c, event);
      c.skills.add('programming');
      final double after = engine.successBonus(c, event);
      expect(after > before, isTrue);
      // 加成上限 35% + 幸运 10%
      expect(after <= 0.45 + 0.0001, isTrue);
    });

    test('成就判定：入狱与减刑', () {
      final EventEngine engine = _makeEngine();
      final Character c = _makeCharacter();
      final Set<String> unlocked = <String>{};
      engine.applyMarkers(c, EventEngine.parseMarkers('【入狱:2】'));
      engine.applyMarkers(c, EventEngine.parseMarkers('【减刑】'));
      engine.applyMarkers(c, EventEngine.parseMarkers('【出狱】'));
      // 使用真实的成就表需要 assets，这里只验证不会抛异常
      expect(() => engine.checkAchievements(c, unlocked, 1), returnsNormally);
    });
  });

  group('开局流程（GameProvider）', () {
    test('年代列表与内建数据一致', () {
      final GameProvider game = GameProvider();
      expect(game.eras.length, 5);
      expect(game.eras.first, '80');
      expect(game.eraLabel('20'), '20年代');
      expect(game.eraDesc('90').isNotEmpty, isTrue);
    });

    test('未开局时阶段为 setup', () {
      final GameProvider game = GameProvider();
      expect(game.phase, GamePhase.setup);
      expect(game.hasCharacter, isFalse);
    });

    test('金手指密码常量为 208526', () {
      expect(kGodPassword, '208526');
      const int maxReroll = kMaxReroll;
      expect(maxReroll, 3);
    });
  });

  group('StorageService 存档', () {
    test('未初始化时降级为内存存档且不抛异常', () async {
      final StorageService storage = StorageService();
      expect(storage.memoryOnly, isTrue);
      await storage.save(
        const SaveSnapshot(character: <String, dynamic>{'name': '测试'}),
      );
      final SaveSnapshot loaded = await storage.load();
      expect(loaded.character['name'], '测试');
    });

    test('AchievementRecord 往返一致', () {
      const AchievementRecord r =
          AchievementRecord(name: '有房一族', age: 30, life: 2);
      final AchievementRecord restored =
          AchievementRecord.fromJson(r.toJson());
      expect(restored.name, '有房一族');
      expect(restored.age, 30);
      expect(restored.life, 2);
    });
  });
}
