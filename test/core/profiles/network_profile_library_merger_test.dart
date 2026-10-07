import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/models/addressing_mode.dart';
import 'package:network_adapter_tool/core/models/network_preset.dart';
import 'package:network_adapter_tool/core/models/network_profile.dart';
import 'package:network_adapter_tool/core/models/network_profile_library.dart';
import 'package:network_adapter_tool/core/profiles/network_profile_library_merger.dart';

void main() {
  const merger = NetworkProfileLibraryMerger();

  NetworkProfile dhcpProfile(String name) =>
      NetworkProfile(name: name, addressingMode: AddressingMode.dhcp);

  NetworkPreset presetUsing(String presetName, String profileName) =>
      NetworkPreset(
        name: presetName,
        assignments: [
          PresetAssignment(adapterName: 'Ethernet', profileName: profileName),
        ],
      );

  test('adds imported items with new names unchanged', () {
    final result = merger.merge(
      NetworkProfileLibrary(profiles: [dhcpProfile('Office')]),
      NetworkProfileLibrary(
        profiles: [dhcpProfile('Lab')],
        presets: [presetUsing('Morning', 'Lab')],
      ),
    );

    expect(result.library.profiles.map((profile) => profile.name), [
      'Office',
      'Lab',
    ]);
    expect(result.library.presets.single.name, 'Morning');
    expect(result.renamedCount, 0);
  });

  test('renames duplicates, ignoring case, and updates their presets', () {
    final result = merger.merge(
      NetworkProfileLibrary(
        profiles: [dhcpProfile('Office')],
        presets: [presetUsing('Morning', 'Office')],
      ),
      NetworkProfileLibrary(
        profiles: [dhcpProfile('office')],
        presets: [presetUsing('MORNING', 'office')],
      ),
    );

    expect(result.library.profiles.map((profile) => profile.name), [
      'Office',
      'office (imported)',
    ]);
    final importedPreset = result.library.presets.last;
    expect(importedPreset.name, 'MORNING (imported)');
    expect(importedPreset.assignments.single.profileName, 'office (imported)');
    expect(result.renamedCount, 2);
  });

  test('numbers further duplicates', () {
    final result = merger.merge(
      NetworkProfileLibrary(
        profiles: [dhcpProfile('Lab'), dhcpProfile('Lab (imported)')],
      ),
      NetworkProfileLibrary(profiles: [dhcpProfile('Lab')]),
    );

    expect(result.library.profiles.last.name, 'Lab (imported 2)');
  });

  test('does not rename a line twice when names chain', () {
    // "A" becomes "A (imported)" while a profile with exactly that name is
    // imported too; each preset must keep pointing at its own profile.
    final result = merger.merge(
      NetworkProfileLibrary(profiles: [dhcpProfile('A')]),
      NetworkProfileLibrary(
        profiles: [dhcpProfile('A'), dhcpProfile('A (imported)')],
        presets: [presetUsing('Uses A', 'A')],
      ),
    );

    expect(result.library.profiles.map((profile) => profile.name), [
      'A',
      'A (imported)',
      'A (imported) (imported)',
    ]);
    expect(
      result.library.presets.single.assignments.single.profileName,
      'A (imported)',
    );
  });
}
