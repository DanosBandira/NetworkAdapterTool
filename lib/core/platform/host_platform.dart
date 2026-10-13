import 'dart:io';

/// The operating system the app runs on, with the behavior that differs
/// between them. Everything platform specific asks this instead of checking
/// `Platform.isWindows` itself, so tests can pick a platform.
enum HostPlatform {
  windows,
  linux;

  /// Linux when running there; Windows otherwise (the original target).
  static HostPlatform get current =>
      Platform.isLinux ? HostPlatform.linux : HostPlatform.windows;

  /// Windows refuses an IPv4 address that another adapter already holds,
  /// also a disconnected one. Linux allows the same address on two
  /// interfaces.
  bool get allowsAddressOnOneAdapterOnly => this == HostPlatform.windows;

  /// Windows keeps DHCP enabled when a disconnected adapter is switched to a
  /// static address. NetworkManager stores the static settings in the
  /// connection and uses them once the cable is plugged in.
  bool get needsConnectedAdapterForDhcpToStatic => this == HostPlatform.windows;

  /// Windows adapter names ("Ethernet 2") ignore case; Linux interface names
  /// ("enp3s0") do not.
  bool isSameAdapterName(String first, String second) =>
      this == HostPlatform.windows
      ? first.toLowerCase() == second.toLowerCase()
      : first == second;
}
