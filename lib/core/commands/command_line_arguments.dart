/// Converts between the arguments text the user types, as on a command line,
/// and the argument list a command stores and passes to the program.
///
/// Spaces (and newlines) separate arguments; double quotes keep spaces
/// inside one argument: `-Path "C:\My Files" -Force` gives three arguments.
/// The quotes themselves are not passed on, so an argument cannot contain a
/// double quote.
class CommandLineArguments {
  const CommandLineArguments._();

  static final _whitespace = RegExp(r'\s');

  static List<String> split(String argumentsText) {
    final arguments = <String>[];
    final currentArgument = StringBuffer();
    var isInsideQuotes = false;
    // Tracks "" so an explicitly quoted empty argument is kept.
    var currentArgumentStarted = false;
    for (final character in argumentsText.split('')) {
      if (character == '"') {
        isInsideQuotes = !isInsideQuotes;
        currentArgumentStarted = true;
      } else if (!isInsideQuotes && _whitespace.hasMatch(character)) {
        if (currentArgumentStarted) arguments.add(currentArgument.toString());
        currentArgument.clear();
        currentArgumentStarted = false;
      } else {
        currentArgument.write(character);
        currentArgumentStarted = true;
      }
    }
    if (currentArgumentStarted) arguments.add(currentArgument.toString());
    return arguments;
  }

  /// The text that [split] turns back into [arguments].
  static String join(List<String> arguments) => [
    for (final argument in arguments)
      argument.isEmpty || argument.contains(_whitespace)
          ? '"$argument"'
          : argument,
  ].join(' ');
}
