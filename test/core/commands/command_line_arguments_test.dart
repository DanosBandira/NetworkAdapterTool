import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/commands/command_line_arguments.dart';

void main() {
  group('split', () {
    test('separates arguments typed on one line by spaces', () {
      expect(
        CommandLineArguments.split(
          '-Address 10.100.10.100 -user Administrator -pw secret',
        ),
        [
          '-Address',
          '10.100.10.100',
          '-user',
          'Administrator',
          '-pw',
          'secret',
        ],
      );
    });

    test('keeps quoted text with spaces together without the quotes', () {
      expect(CommandLineArguments.split(r'-Path "C:\My Files" -Force'), [
        '-Path',
        r'C:\My Files',
        '-Force',
      ]);
    });

    test('ignores extra spaces and newlines', () {
      expect(CommandLineArguments.split('  -a   1\n-b\t2  \n'), [
        '-a',
        '1',
        '-b',
        '2',
      ]);
    });

    test('keeps an explicitly quoted empty argument', () {
      expect(CommandLineArguments.split('-Name ""'), ['-Name', '']);
    });

    test('gives no arguments for empty text', () {
      expect(CommandLineArguments.split('   '), isEmpty);
    });
  });

  test('join quotes only what needs it and splits back the same', () {
    const arguments = ['-Path', r'C:\My Files', '', '-Force'];

    final text = CommandLineArguments.join(arguments);

    expect(text, r'-Path "C:\My Files" "" -Force');
    expect(CommandLineArguments.split(text), arguments);
  });
}
