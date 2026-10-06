import 'dart:async';

import '../contracts/host_pinger.dart';
import '../models/ping_target.dart';

/// Pings a profile's targets until each one answers or the time is up.
///
/// Right after switching an adapter the link, ARP and the device itself can
/// take a few seconds, so a single ping would report false failures. All
/// targets are pinged concurrently; each result is emitted as soon as it is
/// known, so the UI can turn targets green one by one.
class PingTargetsChecker {
  const PingTargetsChecker(
    this._pinger, {
    this.tryFor = const Duration(seconds: 10),
    this.timeoutPerAttempt = const Duration(seconds: 1),
    this.pauseAfterFailedAttempt = const Duration(milliseconds: 500),
  });

  final Duration tryFor;
  final Duration timeoutPerAttempt;

  // ping.exe returns immediately for "Destination host unreachable"; the
  // pause keeps that from turning into a tight loop of processes.
  final Duration pauseAfterFailedAttempt;

  final HostPinger _pinger;

  /// Emits one result per target, in the order they resolve, then closes.
  Stream<PingTargetResult> checkTargets(List<PingTarget> targets) {
    final results = StreamController<PingTargetResult>();
    unawaited(
      Future.wait([
        for (final target in targets)
          _pingUntilReplyOrTimeUp(target).then(results.add),
      ]).whenComplete(results.close),
    );
    return results.stream;
  }

  Future<PingTargetResult> _pingUntilReplyOrTimeUp(PingTarget target) async {
    final elapsed = Stopwatch()..start();
    while (elapsed.elapsed < tryFor) {
      final roundTripTime = await _pingOnceTreatingErrorsAsNoReply(target);
      if (roundTripTime != null) {
        return PingTargetResult(target, roundTripTime: roundTripTime);
      }
      await Future<void>.delayed(pauseAfterFailedAttempt);
    }
    return PingTargetResult(target, roundTripTime: null);
  }

  // A failing ping.exe start (e.g. blocked by policy) counts as no reply for
  // this attempt rather than aborting the other targets.
  Future<Duration?> _pingOnceTreatingErrorsAsNoReply(PingTarget target) async {
    try {
      return await _pinger.pingOnce(target.ipAddress, timeoutPerAttempt);
    } on Exception {
      return null;
    }
  }
}

class PingTargetResult {
  const PingTargetResult(this.target, {required this.roundTripTime});

  final PingTarget target;

  /// `null` when the target did not answer within the time limit.
  final Duration? roundTripTime;

  bool get isReachable => roundTripTime != null;
}
