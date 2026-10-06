/// How a network adapter obtains its IPv4 settings.
enum AddressingMode {
  dhcp,

  // Not named `static`: that is a reserved modifier in Dart and would be
  // ambiguous inside an enum body.
  staticIp,
}
