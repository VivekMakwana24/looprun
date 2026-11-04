import 'package:flutter/material.dart';

/// Asks why the user is reporting something. Returns the reason, or null if cancelled.
Future<String?> askReportReason(BuildContext context, {required String title}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReportDialog(title: title),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.title});
  final String title;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('report_reason_field'),
        controller: _text,
        maxLength: 500,
        maxLines: 4,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'What is wrong?',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('report_send_button'),
          onPressed: _text.text.trim().isEmpty ? null : () => Navigator.pop(context, _text.text.trim()),
          child: const Text('Send report'),
        ),
      ],
    );
  }
}
