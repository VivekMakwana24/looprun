import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/social_models.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/ui/people/people_view_models.dart';
import 'package:looprun/ui/people/public_profile_view_model.dart';
import 'package:looprun/ui/profile/rename_view_model.dart';

import '../fakes/fakes.dart';
import '../fakes/social_fixtures.dart';
import 'screen_harness.dart';

void main() {
  group('followers and following', () {
    test('followers load, and a row can be followed in place', () async {
      final h = Harness();
      h.api.followerPages = [page([person('a', followsMe: true), person('b', following: true)])];
      final c = await signedInContainer(h);
      final sub = c.listen(followersViewModelProvider, (_, __) {});
      await settle();
      expect(sub.read().items.length, 2);
      final vm = c.read(followersViewModelProvider.notifier);
      expect(await vm.toggleFollow(sub.read().items.first), isNull);
      expect(sub.read().items.first.isFollowing, isTrue);
      expect(await vm.toggleFollow(sub.read().items.last), isNull);
      expect(sub.read().items.last.isFollowing, isFalse);
      expect(h.api.socialCalls, containsAll(['follow:a', 'unfollow:b']));
    });

    test('following list pages', () async {
      final h = Harness();
      h.api.followingPages = [page([person('a', following: true)], 'p1'), page([person('b', following: true)])];
      final c = await signedInContainer(h);
      final sub = c.listen(followingViewModelProvider, (_, __) {});
      await settle();
      await c.read(followingViewModelProvider.notifier).loadMore();
      expect(sub.read().items.map((p) => p.id), ['a', 'b']);
    });

    test('the follow limit is explained and the row stays as it was', () async {
      final h = Harness();
      h.api.followerPages = [page([person('a')])];
      h.api.socialErrors['follow:a'] = const ApiException(409, 'x', code: 'follow_limit');
      final c = await signedInContainer(h);
      final sub = c.listen(followersViewModelProvider, (_, __) {});
      await settle();
      final error = await c.read(followersViewModelProvider.notifier).toggleFollow(sub.read().items.single);
      expect(error, contains('500'));
      expect(sub.read().items.single.isFollowing, isFalse);
    });
  });

  group('blocked', () {
    test('unblock removes the row', () async {
      final h = Harness();
      h.api.blockPages = [page([user('u9', 'Zed'), user('u8', 'Yan')])];
      final c = await signedInContainer(h);
      final sub = c.listen(blockedViewModelProvider, (_, __) {});
      await settle();
      expect(sub.read().items.map((p) => p.name), ['Zed', 'Yan']);
      expect(await c.read(blockedViewModelProvider.notifier).unblock(sub.read().items.first), isNull);
      expect(sub.read().items.map((p) => p.id), ['u8']);
      expect(h.api.unblocked, ['u9']);
    });

    test('a failed unblock keeps the row', () async {
      final h = Harness();
      h.api.blockPages = [page([user('u9', 'Zed')])];
      h.api.socialErrors['unblockUser:u9'] = const ApiException(null, 'offline');
      final c = await signedInContainer(h);
      final sub = c.listen(blockedViewModelProvider, (_, __) {});
      await settle();
      expect(await c.read(blockedViewModelProvider.notifier).unblock(sub.read().items.single), contains('connection'));
      expect(sub.read().items.length, 1);
    });
  });

  test('rivals come as one list', () async {
    final h = Harness();
    h.api.rivalList = [person('a'), person('b')];
    final c = await signedInContainer(h);
    final sub = c.listen(rivalsViewModelProvider, (_, __) {});
    await settle();
    expect(sub.read().items.length, 2);
    expect(sub.read().hasMore, isFalse);
  });

  group('search', () {
    test('finds by prefix, ignores short input, and drops stale answers', () async {
      final h = Harness();
      h.api.people = [person('a', name: 'Maya'), person('b', name: 'Mark'), person('c', name: 'Amy')];
      final c = await signedInContainer(h);
      final sub = c.listen(userSearchViewModelProvider, (_, __) {});
      final vm = c.read(userSearchViewModelProvider.notifier);

      await vm.search('m');
      expect(sub.read().queryTooShort, isTrue);
      expect(sub.read().searched, isFalse);
      expect(h.api.searches, isEmpty);

      await vm.search('Ma');
      expect(sub.read().results.map((p) => p.name), ['Maya', 'Mark']);
      expect(sub.read().searched, isTrue);

      await vm.search('zz');
      expect(sub.read().results, isEmpty);
      expect(sub.read().searched, isTrue, reason: '"nobody found" is a real answer');

      await vm.search('ma');
      await vm.search('');
      expect(sub.read().results, isEmpty, reason: 'clearing the box clears the list');
    });

    test('offline search says so', () async {
      final h = Harness();
      h.api.socialErrors['searchUsers'] = const ApiException(null, 'offline');
      final c = await signedInContainer(h);
      final sub = c.listen(userSearchViewModelProvider, (_, __) {});
      await c.read(userSearchViewModelProvider.notifier).search('ma');
      expect(sub.read().offline, isTrue);
      expect(sub.read().error, isNotNull);
    });

    test('follow from the results', () async {
      final h = Harness();
      h.api.people = [person('a', name: 'Maya')];
      final c = await signedInContainer(h);
      final sub = c.listen(userSearchViewModelProvider, (_, __) {});
      final vm = c.read(userSearchViewModelProvider.notifier);
      await vm.search('ma');
      expect(await vm.toggleFollow(sub.read().results.single), isNull);
      expect(sub.read().results.single.isFollowing, isTrue);
    });
  });

  group('public profile', () {
    const bob = Profile(
      id: 'u2',
      name: 'Bob',
      cellsHeld: 40,
      weeklyRank: 7,
      followersCount: 3,
      followingCount: 4,
      joinedAt: 1700000000000,
    );

    test('loads the profile', () async {
      final h = Harness();
      h.api.profiles['u2'] = bob;
      final c = await signedInContainer(h);
      final sub = c.listen(publicProfileViewModelProvider('u2'), (_, __) {});
      await settle();
      expect(sub.read().profile!.name, 'Bob');
      expect(sub.read().loading, isFalse);
    });

    test('404 (unknown, deleted or blocked) is "not found", not an error to retry blindly', () async {
      final h = Harness();
      final c = await signedInContainer(h);
      final sub = c.listen(publicProfileViewModelProvider('nobody'), (_, __) {});
      await settle();
      expect(sub.read().notFound, isTrue);
      expect(sub.read().profile, isNull);
    });

    test('offline shows an error and load() works afterwards', () async {
      final h = Harness();
      h.api.profiles['u2'] = bob;
      h.api.socialErrors['getProfile:u2'] = const ApiException(null, 'offline');
      final c = await signedInContainer(h);
      final p = publicProfileViewModelProvider('u2');
      final sub = c.listen(p, (_, __) {});
      await settle();
      expect(sub.read().offline, isTrue);
      expect(sub.read().notFound, isFalse);
      h.api.socialErrors.clear();
      await c.read(p.notifier).load();
      expect(sub.read().profile!.id, 'u2');
    });

    test('follow and unfollow use the server counts', () async {
      final h = Harness();
      h.api.profiles['u2'] = bob;
      h.api.followersCountAfterFollow = 4;
      final c = await signedInContainer(h);
      final p = publicProfileViewModelProvider('u2');
      final sub = c.listen(p, (_, __) {});
      await settle();
      expect(await c.read(p.notifier).toggleFollow(), isNull);
      expect(sub.read().profile!.isFollowing, isTrue);
      expect(sub.read().profile!.followersCount, 4);
      expect(await c.read(p.notifier).toggleFollow(), isNull);
      expect(sub.read().profile!.isFollowing, isFalse);
    });

    test('you cannot follow or block yourself', () async {
      final h = Harness();
      h.api.profiles['u1'] = const Profile(id: 'u1', name: 'Me', isMe: true);
      final c = await signedInContainer(h);
      final p = publicProfileViewModelProvider('u1');
      c.listen(p, (_, __) {});
      await settle();
      await c.read(p.notifier).toggleFollow();
      await c.read(p.notifier).block();
      expect(h.api.socialCalls.where((s) => s.startsWith('follow') || s.startsWith('blockUser')), isEmpty);
    });

    test('block and report reach the server', () async {
      final h = Harness();
      h.api.profiles['u2'] = bob;
      final c = await signedInContainer(h);
      final p = publicProfileViewModelProvider('u2');
      c.listen(p, (_, __) {});
      await settle();
      expect(await c.read(p.notifier).report('rude'), isNull);
      expect(h.api.reports.single, {'kind': 'user', 'target_id': 'u2', 'reason': 'rude'});
      expect(await c.read(p.notifier).block(), isNull);
      expect(h.api.blocked, ['u2']);
    });

    test('a rate limit is explained', () async {
      final h = Harness();
      h.api.profiles['u2'] = bob;
      h.api.socialErrors['follow:u2'] = const ApiException(429, 'x');
      final c = await signedInContainer(h);
      final p = publicProfileViewModelProvider('u2');
      final sub = c.listen(p, (_, __) {});
      await settle();
      expect(await c.read(p.notifier).toggleFollow(), contains('Wait'));
      expect(sub.read().profile!.isFollowing, isFalse);
      expect(sub.read().busy, isFalse);
    });
  });

  group('rename', () {
    test('saves the name on the server and in the signed-in session', () async {
      final h = Harness();
      final c = await signedInContainer(h);
      expect(await c.read(renameViewModelProvider.notifier).rename('  Mia   K '), isNull);
      expect(h.api.renames, ['Mia K']);
      expect(c.read(authRepositoryProvider).current!.user.name, 'Mia K');
      expect(c.read(authRepositoryProvider).current!.user.id, 'u1');
      final stored = await c.read(tokenStoreProvider).read();
      expect(stored!.userName, 'Mia K', reason: 'kept for the next launch');
    });

    test('a rejected name says so and changes nothing', () async {
      final h = Harness();
      h.api.socialErrors['renameMe'] = const ApiException(422, 'x', code: 'name_rejected');
      final c = await signedInContainer(h);
      expect(await c.read(renameViewModelProvider.notifier).rename('Valid'), contains('name'));
      expect(c.read(authRepositoryProvider).current!.user.name, 'Vivek');
      expect(c.read(renameViewModelProvider), isFalse, reason: 'not busy any more');
    });

    test('a too short name is refused before any request', () async {
      final h = Harness();
      final c = await signedInContainer(h);
      expect(await c.read(renameViewModelProvider.notifier).rename('a'), isNotNull);
      expect(h.api.socialCalls, isEmpty);
    });
  });
}
