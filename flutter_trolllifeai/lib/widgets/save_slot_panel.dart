// 存档管理面板：3 个槽位（保存 / 读取 / 删除）+ 存档文本导出 / 导入。
//
// 主要放在轮回页；属性主页的菜单里也可以直接打开同一块面板。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/game_provider.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// 存档管理面板
class SaveSlotPanel extends StatefulWidget {
  const SaveSlotPanel({super.key});

  @override
  State<SaveSlotPanel> createState() => _SaveSlotPanelState();
}

class _SaveSlotPanelState extends State<SaveSlotPanel> {
  /// 槽位摘要（异步读取）
  List<SaveSlotInfo> _slots = <SaveSlotInfo>[];

  /// 是否还在读取中
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  /// 重新读取槽位摘要
  Future<void> _reload() async {
    final GameProvider game = context.read<GameProvider>();
    final List<SaveSlotInfo> list = await game.slotInfos();
    if (!mounted) return;
    setState(() {
      _slots = list;
      _loading = false;
    });
  }

  /// 统一的提示条
  void _toast(String text) {
    if (text.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// 保存到槽位
  Future<void> _save(int index) async {
    final GameProvider game = context.read<GameProvider>();
    final String error = await game.saveToSlot(index);
    _toast(error.isEmpty ? '已保存到槽位 $index' : error);
    await _reload();
  }

  /// 从槽位读取
  Future<void> _load(int index) async {
    final GameProvider game = context.read<GameProvider>();
    final String error = await game.loadFromSlot(index);
    _toast(error.isEmpty ? '已读取槽位 $index' : error);
    await _reload();
  }

  /// 删除槽位
  Future<void> _delete(int index) async {
    final GameProvider game = context.read<GameProvider>();
    final String error = await game.deleteSlot(index);
    _toast(error.isEmpty ? '已删除槽位 $index' : error);
    await _reload();
  }

  /// 导出：把存档 JSON 显示在可复制的多行文本框里
  void _export() {
    final GameProvider game = context.read<GameProvider>();
    final String text = game.exportSaveText();
    final TextEditingController controller = TextEditingController(text: text);
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('导出存档文本'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '共 ${text.length} 个字符，可全选复制（不含 API Key）',
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                readOnly: true,
                minLines: 6,
                maxLines: 10,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 11.5,
                ),
                decoration: const InputDecoration(hintText: '存档 JSON'),
              ),
              const SizedBox(height: 8),
              const Text(
                '把它贴到备忘录或聊天窗口即可备份；导入时整段粘回来。',
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 11.5,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              _toast('已复制到剪贴板');
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    ).whenComplete(() => controller.dispose());
  }

  /// 导入：粘贴文本后解析并覆盖，失败只提示不崩溃
  void _import() {
    final TextEditingController controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('导入存档文本'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '把之前导出的存档 JSON 整段粘贴进来，导入后会覆盖当前进度。',
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 11.5,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                minLines: 6,
                maxLines: 10,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 11.5,
                ),
                decoration: const InputDecoration(hintText: '在这里粘贴存档 JSON'),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final GameProvider game = context.read<GameProvider>();
              final String error = await game.importSaveText(controller.text);
              if (error.isNotEmpty) {
                _toast(error);
                return;
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              _toast('存档导入成功');
              await _reload();
            },
            child: const Text('导入并覆盖'),
          ),
        ],
      ),
    ).whenComplete(() => controller.dispose());
  }

  /// 单个槽位
  Widget _buildSlot(SaveSlotInfo info) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              TagChip(
                text: '槽位 ${info.index}',
                color: info.empty ? AppColors.textDim : AppColors.primaryLight,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  info.label,
                  style: TextStyle(
                    color: info.empty ? AppColors.textDim : AppColors.text,
                    fontSize: 13,
                  ),
                ),
              ),
              if (info.savedAtText.isNotEmpty)
                Text(
                  info.savedAtText,
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              _slotButton('保存到此处', () => _save(info.index), false),
              const SizedBox(width: 8),
              _slotButton('读取', () => _load(info.index), info.empty),
              const SizedBox(width: 8),
              _slotButton('删除', () => _delete(info.index), info.empty),
            ],
          ),
        ],
      ),
    );
  }

  /// 槽位上的小按钮
  Widget _slotButton(String label, VoidCallback onTap, bool disabled) {
    return OutlinedButton(
      onPressed: disabled ? null : onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: const TextStyle(fontSize: 12.5),
      ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final GameProvider game = context.watch<GameProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else
          ..._slots.map((SaveSlotInfo info) => _buildSlot(info)),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: _export,
                child: const Text('导出存档文本'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _import,
                child: const Text('导入存档文本'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          game.isMemoryOnly
              ? '当前存档只在内存中（磁盘不可写）'
              : '存档位置：${game.storagePath}',
          style: const TextStyle(
            color: AppColors.textDim,
            fontSize: 11.5,
            height: 1.6,
          ),
        ),
        if (!game.isMemoryOnly)
          Text(
            '槽位文件：${game.slotPathOf(1)}',
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 11,
              height: 1.6,
            ),
          ),
      ],
    );
  }
}
