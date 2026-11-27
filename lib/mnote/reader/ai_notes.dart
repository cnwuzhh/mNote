import 'package:material_ui/material_ui.dart';

import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/theme/mnote_theme.dart';

/// Run state of an AI note while (or after) it is generated. Not saved.
enum AiRunStatus { loading, done, error }

class AiRunState {
  new({
    this.status = AiRunStatus.loading,
    this.partial = '',
    this.error,
    this.provider,
  });
  AiRunStatus status;
  String partial;
  String? error;
  String? provider;
}

String aiNoteLabel(AiNote n) => n.kind == AiNote.explain ? '释' : '译';

/// The small 「译」/「释」 marker shown next to a translated / explained
/// passage. Tap: open the result; long-press: delete.
class AiMarker extends StatelessWidget {
  const new({
    super.key,
    required this.note,
    required this.status,
    required this.onTap,
    required this.onLongPress,
  });

  final AiNote note;
  final AiRunStatus status;
  final VoidCallback onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    final err = status == AiRunStatus.error;
    final loading = status == AiRunStatus.loading;
    final color = err ? const Color(0xFFC0392B) : p.accent;
    return Tooltip(
      message:
          '${note.kind == AiNote.explain ? 'AI 解释' : 'AI 翻译'}${loading
              ? '（生成中）'
              : err
              ? '（失败，点开重试）'
              : ''}',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: p.paper2,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: loading ? color.withValues(alpha: 0.55) : color,
              width: loading ? 1 : 1.3,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) ...[
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: color,
                  ),
                ),
                const SizedBox(width: 3),
              ],
              Text(
                err ? '!' : aiNoteLabel(note),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.1,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expanded result of an AI note: streaming text, error, or the answer with
/// 「AI 生成 · 模型 · 可能有误」 and actions.
class AiNotePanel extends StatelessWidget {
  const new({
    super.key,
    required this.note,
    required this.run,
    required this.targetLanguageLabel,
    required this.onClose,
    required this.onSaveAsNote,
    required this.onMakeCard,
    required this.onCopy,
    required this.onRegenerate,
    required this.onDelete,
    required this.onOpenSettings,
  });

  final AiNote note;
  final AiRunState? run;
  final String targetLanguageLabel;
  final VoidCallback onClose,
      onSaveAsNote,
      onMakeCard,
      onCopy,
      onRegenerate,
      onDelete,
      onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final p = MnotePalette.of(context);
    final status =
        run?.status ??
        (note.result.isEmpty ? AiRunStatus.error : AiRunStatus.done);
    final explain = note.kind == AiNote.explain;
    final text = status == AiRunStatus.done
        ? (note.result.isNotEmpty ? note.result : run?.partial ?? '')
        : run?.partial ?? '';
    final provider = run?.provider ?? note.providerName;

    Widget action(
      String key,
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool primary = false,
    }) => Padding(
      padding: const EdgeInsets.only(right: 6, top: 6),
      child: primary
          ? FilledButton.icon(
              key: ValueKey(key),
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onTap,
              icon: Icon(icon, size: 16),
              label: Text(label),
            )
          : OutlinedButton.icon(
              key: ValueKey(key),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.ink2,
                side: BorderSide(color: p.line),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onTap,
              icon: Icon(icon, size: 16),
              label: Text(label),
            ),
    );

    return Material(
      key: const ValueKey('ai-panel'),
      color: p.paper,
      elevation: 10,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 440,
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  explain ? Icons.lightbulb_outline : Icons.translate,
                  size: 18,
                  color: p.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  explain ? '解释' : '翻译',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
                if (!explain) ...[
                  const SizedBox(width: 8),
                  Text(
                    targetLanguageLabel,
                    style: TextStyle(fontSize: 13, color: p.ink3),
                  ),
                ],
                const Spacer(),
                IconButton(
                  key: const ValueKey('ai-panel-close'),
                  tooltip: '收起',
                  iconSize: 18,
                  onPressed: onClose,
                  icon: Icon(Icons.close, color: p.ink3),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (status == AiRunStatus.error)
              Text(
                '${explain ? '解释' : '翻译'}失败：${run?.error ?? '没有结果'}',
                key: const ValueKey('ai-panel-error'),
                style: const TextStyle(fontSize: 14, color: Color(0xFFB03A2E)),
              )
            else if (text.isEmpty)
              Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: p.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    explain ? '正在解释…' : '正在翻译…',
                    style: TextStyle(fontSize: 14, color: p.ink3),
                  ),
                ],
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: SelectableText(
                    text + (status == AiRunStatus.loading ? ' ▍' : ''),
                    key: const ValueKey('ai-panel-text'),
                    style: TextStyle(fontSize: 15, height: 1.6, color: p.ink),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            if (status != AiRunStatus.error)
              Text(
                'AI 生成${provider.isEmpty ? '' : ' · $provider'} · 可能有误',
                key: const ValueKey('ai-panel-source'),
                style: TextStyle(fontSize: 12, color: p.ink3),
              ),
            Wrap(
              children: [
                if (status == AiRunStatus.done) ...[
                  action(
                    'ai-save-note',
                    Icons.sticky_note_2_outlined,
                    '存为批注',
                    onSaveAsNote,
                    primary: true,
                  ),
                  action(
                    'ai-make-card',
                    Icons.note_add_outlined,
                    explain ? '摘录为卡片（附解释）' : '摘录为卡片（附译文）',
                    onMakeCard,
                  ),
                  action('ai-copy', Icons.copy_outlined, '复制', onCopy),
                ],
                if (status != AiRunStatus.loading)
                  action(
                    'ai-regenerate',
                    Icons.refresh,
                    status == AiRunStatus.error ? '重试' : '重新生成',
                    onRegenerate,
                    primary: status == AiRunStatus.error,
                  ),
                if (status == AiRunStatus.error)
                  action(
                    'ai-settings',
                    Icons.settings_outlined,
                    'AI 设置',
                    onOpenSettings,
                  ),
                action('ai-delete', Icons.delete_outline, '删除', onDelete),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
