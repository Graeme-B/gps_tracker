import 'package:flutter_test/flutter_test.dart';
import 'package:gps_tracker/gps_tracker.dart';
import 'package:gps_tracker/gps_tracker_platform_interface.dart';
import 'package:gps_tracker/gps_tracker_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockGpsTrackerPlatform
    with MockPlatformInterfaceMixin
    implements GpsTrackerPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final GpsTrackerPlatform initialPlatform = GpsTrackerPlatform.instance;

  test('$MethodChannelGpsTracker is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelGpsTracker>());
  });

  test('getPlatformVersion', () async {
    GpsTracker gpsTrackerPlugin = GpsTracker();
    MockGpsTrackerPlatform fakePlatform = MockGpsTrackerPlatform();
    GpsTrackerPlatform.instance = fakePlatform;

    expect(await gpsTrackerPlugin.getPlatformVersion(), '42');
  });
}
