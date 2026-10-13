/// `nmcli -t` output for a laptop with a connected onboard port on DHCP, a
/// USB adapter without cable that has a static connection, an unconnected
/// Wi-Fi card without a saved connection, and loopback.
///
/// Written from nmcli(1), not captured from a machine; replace with real
/// output once a Linux machine is available.
const nmcliDeviceOutput = r'''
GENERAL.DEVICE:enp3s0
GENERAL.TYPE:ethernet
GENERAL.STATE:100 (connected)
GENERAL.CONNECTION:Wired connection 1
IP4.ADDRESS[1]:192.168.1.20/24
IP4.GATEWAY:192.168.1.1
IP4.DNS[1]:192.168.1.1
IP4.DNS[2]:8.8.8.8

GENERAL.DEVICE:enx001122334455
GENERAL.TYPE:ethernet
GENERAL.STATE:20 (unavailable)
GENERAL.CONNECTION:
IP4.GATEWAY:

GENERAL.DEVICE:wlp2s0
GENERAL.TYPE:wifi
GENERAL.STATE:30 (disconnected)
GENERAL.CONNECTION:
IP4.GATEWAY:

GENERAL.DEVICE:lo
GENERAL.TYPE:loopback
GENERAL.STATE:100 (connected (externally))
GENERAL.CONNECTION:lo
IP4.ADDRESS[1]:127.0.0.1/8
IP4.GATEWAY:
''';

const wiredUuid = '5f1c7a3e-0000-4000-8000-000000000001';
const machineUuid = '5f1c7a3e-0000-4000-8000-000000000002';

// "Machine: line 1" shows how terse mode escapes a colon in a value.
const nmcliConnectionListOutput =
    '''
Wired connection 1:$wiredUuid:802-3-ethernet:enp3s0
Machine\\: line 1:$machineUuid:802-3-ethernet:
lo:5f1c7a3e-0000-4000-8000-000000000003:loopback:lo
''';

const nmcliConnectionDetails = {
  wiredUuid: '''
connection.interface-name:
ipv4.method:auto
ipv4.addresses:
ipv4.gateway:--
ipv4.dns:
''',
  machineUuid: '''
connection.interface-name:enx001122334455
ipv4.method:manual
ipv4.addresses:10.100.10.4/24
ipv4.gateway:10.100.10.1
ipv4.dns:10.100.10.1,8.8.8.8
''',
};
