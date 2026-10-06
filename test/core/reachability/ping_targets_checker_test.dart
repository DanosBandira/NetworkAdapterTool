import 'package:flutter_test/flutter_test.dart';
import 'package:network_profile_switcher/core/contracts/host_pinger.dart';
import 'package:network_profile_switcher/core/models/ping_target.dart';
import 'package:network_profile_switcher/core/reachability/ping_targets_checker.dart';

import '../../fakes/scripted_host_pinger.dart';

void main() {
  const plc = PingTarget(ipAddress: '10.100.10.1', name: 'PLC');
  const hmi = PingTarget(ipAddress: '10.100.10.2', name: 'HMI');

  PingTargetsChecker checkerUsing(
    HostPinger pinger, {
    Duration tryFor = const Duration(milliseconds: 200),
  }) {
    return PingTargetsChecker(
      pinger,
      tryFor: tryFor,
      pauseAfterFailedAttempt: const Duration(milliseconds: 5),
    );
  }

  test('reports a target that answers right away', () async {
    final pinger = ScriptedHostPinger({
      plc.ipAddress: [const Duration(milliseconds: 2)],
    });

    final results = await checkerUsing(pinger).checkTargets([plc]).toList();

    expect(results.single.target, plc);
    expect(results.single.roundTripTime, const Duration(milliseconds: 2));
    expect(pinger.attemptsPerAddress[plc.ipAddress], 1);
  });

  test('keeps trying until the target answers', () async {
    final pinger = ScriptedHostPinger({
      plc.ipAddress: [null, null, const Duration(milliseconds: 4)],
    });

    final results = await checkerUsing(pinger).checkTargets([plc]).toList();

    expect(results.single.isReachable, isTrue);
    expect(pinger.attemptsPerAddress[plc.ipAddress], 3);
  });

  test('gives up when the time is up', () async {
    final pinger = ScriptedHostPinger();
    final stopwatch = Stopwatch()..start();

    final results = await checkerUsing(pinger).checkTargets([plc]).toList();

    expect(results.single.isReachable, isFalse);
    expect(results.single.roundTripTime, isNull);
    expect(pinger.attemptsPerAddress[plc.ipAddress], greaterThan(1));
    expect(
      stopwatch.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 200)),
    );
  });

  test('emits each target as soon as it is resolved', () async {
    final pinger = ScriptedHostPinger({
      hmi.ipAddress: [const Duration(milliseconds: 1)],
    });

    final results = await checkerUsing(pinger)
        .checkTargets([plc, hmi])
        .toList();

    // HMI answers immediately; PLC only fails after the time limit.
    expect(results.map((result) => result.target), [hmi, plc]);
  });

  test('counts a failing ping as no reply for that attempt', () async {
    final results = await checkerUsing(_ThrowingThenAnsweringPinger())
        .checkTargets([plc])
        .toList();

    expect(results.single.isReachable, isTrue);
  });

  test('completes immediately without targets', () async {
    final results = await checkerUsing(ScriptedHostPinger())
        .checkTargets([])
        .toList();

    expect(results, isEmpty);
  });
}

class _ThrowingThenAnsweringPinger implements HostPinger {
  int _attempts = 0;

  @override
  Future<Duration?> pingOnce(String ipAddress, Duration timeout) async {
    _attempts++;
    if (_attempts == 1) throw Exception('ping.exe could not be started');
    return const Duration(milliseconds: 1);
  }
}
