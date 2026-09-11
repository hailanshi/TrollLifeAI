// 引用完整性检查：页面 / provider 中出现的本工程类名，必须在某处被定义。
// 只做「被引用但未定义」的单向检查，避免误报。

const fs = require('fs');
const path = require('path');

const root = process.argv[2] || '.';
const libDir = path.join(root, 'lib');

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

const files = walk(libDir, []);
const defined = new Set();
const enums = new Set();
const sources = new Map();

for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  sources.set(f, src);
  const classRe = /^\s*(?:abstract\s+|final\s+|sealed\s+)?class\s+([A-Za-z_$][\w$]*)/gm;
  let m;
  while ((m = classRe.exec(src)) !== null) defined.add(m[1]);
  const enumRe = /^\s*enum\s+([A-Za-z_$][\w$]*)/gm;
  while ((m = enumRe.exec(src)) !== null) { defined.add(m[1]); enums.add(m[1]); }
  const mixinRe = /^\s*mixin\s+([A-Za-z_$][\w$]*)/gm;
  while ((m = mixinRe.exec(src)) !== null) defined.add(m[1]);
  const typedefRe = /^\s*typedef\s+([A-Za-z_$][\w$]*)/gm;
  while ((m = typedefRe.exec(src)) !== null) defined.add(m[1]);
}

// 常见 Flutter / Dart SDK 类型白名单
const sdk = new Set([
  'Widget','StatelessWidget','StatefulWidget','State','BuildContext','Scaffold','AppBar','Text','Column','Row',
  'Container','Padding','EdgeInsets','SizedBox','Center','ListView','ListViewBuilder','Card','Icon','Icons','Colors',
  'Color','ThemeData','TextStyle','TextTheme','ColorScheme','MaterialApp','ThemeMode','Brightness','ButtonStyle',
  'ElevatedButton','OutlinedButton','TextButton','IconButton','PopupMenuButton','PopupMenuItem','PopupMenuEntry',
  'GestureDetector','InkWell','Divider','LinearProgressIndicator','CircularProgressIndicator','AlertDialog','Dialog',
  'TextField','TextEditingController','InputDecoration','BorderSide','BorderRadius','BoxDecoration','BoxShadow',
  'BoxConstraints','RoundedRectangleBorder','OutlineInputBorder','Chip','ChipThemeData','Slider','SliderThemeData',
  'SnackBar','SnackBarThemeData','ScaffoldMessenger','MediaQuery','MediaQueryData','TextScaler','Navigator',
  'MaterialPageRoute','Route','Future','Stream','Timer','Duration','DateTime','Random','List','Map','Set','Iterable',
  'String','StringBuffer','Object','dynamic','int','double','num','bool','void','Null','Function','Type','Symbol',
  'ChangeNotifier','ValueNotifier','Provider','ChangeNotifierProvider','Consumer','WidgetsBinding','WidgetsBindingObserver',
  'Platform','Directory','File','IOException','TextInputType','TextInputFormatter','FilteringTextInputFormatter',
  'LengthLimitingTextInputFormatter','AlwaysStoppedAnimation','Tween','Animation','Curve','Curves','SafeArea',
  'SingleChildScrollView','Wrap','Flexible','Expanded','Spacer','ClipRRect','LayoutBuilder','AnimatedContainer',
  'RootBundle','AssetBundle','services','foundation','material','widgets','dart','io','convert','async','math',
  'Localizations','GlobalKey','PageController','ScrollController','FocusNode','Theme','ThemeExtension','MainAxisAlignment',
  'CrossAxisAlignment','MainAxisSize','TextAlign','FontWeight','TextOverflow','Axis','AxisAlignment','Border','ShapeBorder',
  'InkRipple','SplashFactory','CardTheme','DialogTheme','DividerThemeData','AppBarTheme','InputDecorationTheme',
  'ListTileThemeData','IconThemeData','ProgressIndicatorThemeData','BottomSheetThemeData','ElevatedButtonThemeData',
  'OutlinedButtonThemeData','TextButtonThemeData','SystemUiOverlayStyle','ImageProvider','NetworkImage','AssetImage',
  'DragStartBehavior','HitTestBehavior','NotificationListener','ScrollNotification','CustomScrollView','SliverList',
  'SliverPadding','SliverToBoxAdapter','ValueKey','Key','UniqueKey','FutureBuilder','StreamBuilder','Builder',
  'Orientation','SystemChrome','DeviceOrientation','Rect','Offset','Size','Radius','RRect','Path','Canvas','Paint',
  'CustomPainter','CustomPaint','Table','TableRow','TableCell','Tooltip','Drawer','TabBar','TabController','Tab',
  'DefaultTabController','BottomNavigationBar','BottomNavigationBarItem','NavigationBar','Stack','Positioned',
  'Visibility','Opacity','Transform','FittedBox','AspectRatio','FractionallySizedBox','Align','AnimatedSwitcher',
  'AnimatedOpacity','AnimatedBuilder','ListenableBuilder','ValueListenableBuilder','SliverAppBar','PopupMenuItem',
  'showDialog','showModalBottomSheet','showDatePicker','showTimePicker','Image','AssetBundleImageProvider',
]);

const problems = [];
for (const f of files) {
  const src = sources.get(f);
  const rel = path.relative(root, f).replace(/\\/g, '/');
  // 使用位置：类型注解 / 泛型 / 构造函数调用 / 静态访问
  const usageRe = /(?:\bnew\s+|\bextends\s+|\bwith\s+|\bimplements\s+|\bas\s+|<|:|\bconst\s+|\(\s*)\s*([A-Z][A-Za-z0-9_$]*)/g;
  let m;
  const localDefs = new Set();
  const classRe = /class\s+([A-Za-z_$][\w$]*)/g;
  while ((m = classRe.exec(src)) !== null) localDefs.add(m[1]);
  while ((m = usageRe.exec(src)) !== null) {
    const name = m[1];
    if (defined.has(name) || sdk.has(name) || localDefs.has(name)) continue;
    problems.push(`${rel}: 引用未定义的类 ${name}`);
  }
}

console.log('===== 已定义的类/枚举 =====');
console.log(Array.from(defined).sort().join(', '));
console.log('\n===== 疑似未定义的引用 =====');
if (problems.length === 0) console.log('(无)');
else {
  const uniq = Array.from(new Set(problems));
  uniq.forEach((p) => console.log('  ' + p));
}
process.exit(problems.length ? 1 : 0);
