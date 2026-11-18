import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../core/lr_page.dart';
import '../core/widgets.dart';
import 'people_view_models.dart';
import 'user_list_screen.dart';

/// Find runners by the start of their display name (2 to 30 letters). Blocked runners, runners who hid
/// their name and you yourself never show up.
class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key});

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  final TextEditingController _text = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) ref.read(userSearchViewModelProvider.notifier).search(value);
    });
    setState(() {});
  }

  void _submit(String value) {
    _debounce?.cancel();
    ref.read(userSearchViewModelProvider.notifier).search(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final state = ref.watch(userSearchViewModelProvider);
    final vm = ref.read(userSearchViewModelProvider.notifier);

    Widget results;
    if (state.loading && state.results.isEmpty) {
      results = Center(child: CircularProgressIndicator(key: const Key('search_loading'), color: c.accent));
    } else if (state.error != null) {
      results = LrMessage(
        key: const Key('search_error'),
        title: state.offline ? "Can't reach the server" : 'The search did not work',
        text: state.offline ? 'Check your connection.' : state.error,
        actionLabel: 'Try again',
        onAction: () => vm.search(_text.text),
      );
    } else if (_text.text.trim().runes.length < 2) {
      results = const LrMessage(
        key: Key('search_hint'),
        title: 'Type at least 2 letters',
        text: 'Names are matched from the start, so "ma" finds Maya and Mark.',
      );
    } else if (state.searched && state.results.isEmpty) {
      results = const LrMessage(key: Key('search_empty'), title: 'Nobody found', text: 'Try the start of a name.');
    } else {
      results = ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: state.results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final person = state.results[i];
          return PersonRow(
            key: Key('person_${person.id}'),
            person: person,
            onOpen: () => context.push(userProfilePath(person.id)),
            actionLabel: person.isFollowing ? 'FOLLOWING' : 'FOLLOW',
            actionFilled: !person.isFollowing,
            onAction: () async {
              final error = await vm.toggleFollow(person);
              if (context.mounted) tellUser(context, error);
            },
          );
        },
      );
    }

    return LrPage(
      title: 'FIND RUNNERS',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('search_field'),
              controller: _text,
              autofocus: true,
              maxLength: 30,
              textInputAction: TextInputAction.search,
              onChanged: _changed,
              onSubmitted: _submit,
              style: LrText.body(16, color: c.text),
              decoration: InputDecoration(
                hintText: 'Start of a name',
                counterText: '',
                prefixIcon: Icon(Icons.search, color: c.muted),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: c.line),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: results),
          ],
        ),
      ),
    );
  }
}
