import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// حوار إدخال نص/سبب آمن. يملك [TextEditingController] داخل State الخاص به
/// ويتخلّص منه في dispose() بالترتيب الصحيح للإطار (يُفكَّك حقل النص أولًا ثم
/// يُتخلّص من الـ controller) — مما يمنع خطأ:
///   "A TextEditingController was used after being disposed"
/// والانهيار المتتالي `_dependents.isEmpty` الذي يحدث عند التخلّص من controller
/// محلي فور إغلاق الحوار بينما حقل النص لا يزال حيًّا/مُركّزًا أثناء الأنيميشن.
///
/// يُرجع النص المُدخَل (مقصوصًا) عند التأكيد، أو null عند الإلغاء/الإغلاق.
Future<String?> showReasonDialog({
  required BuildContext context,
  required String title,
  String hint = '',
  String actionLabel = 'تأكيد',
  String cancelLabel = 'إلغاء',
  Color? confirmColor,
  bool required = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReasonInputDialog(
      title: title,
      hint: hint,
      actionLabel: actionLabel,
      cancelLabel: cancelLabel,
      confirmColor: confirmColor,
      required: required,
    ),
  );
}

class _ReasonInputDialog extends StatefulWidget {
  const _ReasonInputDialog({
    required this.title,
    required this.hint,
    required this.actionLabel,
    required this.cancelLabel,
    required this.confirmColor,
    required this.required,
  });

  final String title;
  final String hint;
  final String actionLabel;
  final String cancelLabel;
  final Color? confirmColor;
  final bool required;

  @override
  State<_ReasonInputDialog> createState() => _ReasonInputDialogState();
}

class _ReasonInputDialogState extends State<_ReasonInputDialog> {
  late final TextEditingController _controller = TextEditingController();
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _canSubmit = !widget.required;
    if (widget.required) {
      _controller.addListener(_onChanged);
    }
  }

  void _onChanged() {
    final canSubmit = _controller.text.trim().isNotEmpty;
    if (canSubmit != _canSubmit) setState(() => _canSubmit = canSubmit);
  }

  @override
  void dispose() {
    // يعمل بعد تفكيك حقل النص (EditableText) ضمن تفكيك شجرة الحوار — آمن.
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    // نغلق أولًا لوحة المفاتيح ثم نُغلق الحوار، فلا يبقى تركيز معلّق.
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: widget.hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop();
            },
            child: Text(widget.cancelLabel),
          ),
          FilledButton(
            style: widget.confirmColor == null
                ? null
                : FilledButton.styleFrom(backgroundColor: widget.confirmColor),
            onPressed: _canSubmit ? _submit : null,
            child: Text(widget.actionLabel),
          ),
        ],
      ),
    );
  }
}
