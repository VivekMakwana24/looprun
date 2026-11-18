import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'rename_view_model.dart';

/// Asks for a new display name and saves it. Returns true when the name was changed.
Future<bool> showRenameDialog(BuildContext context, {required String currentName}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _RenameDialog(currentName: currentName),
  );
  return ok == true;
}

class _RenameDialog extends ConsumerStatefulWidget {
  const _RenameDialog({required this.currentName});
  final String currentName;

  @override
  ConsumerState<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends ConsumerState<_RenameDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.currentName);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final error = await ref.read(renameViewModelProvider.notifier).rename(_text.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final busy = ref.watch(renameViewModelProvider);
    return AlertDialog(
      title: const Text('Display name'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Other runners see this name. 2 to 30 characters, 5 changes a day.',
              style: LrText.body(14, color: c.text2, height: 1.4)),
          const SizedBox(height: 12),
          TextField(
            key: const Key('rename_field'),
            controller: _text,
            autofocus: true,
            maxLength: 30,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => busy ? null : _save(),
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          key: const Key('rename_save'),
          onPressed: busy ? null : _save,
          child: Text(busy ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}
