---
title: "Milestone 1: Disabling Kernel Level IP Checksum Verification"
...

# Introduction

The purpose of this project is to disable the kernel's function to drop packets with an invalid IP header checksum. This goes against [how IP should operate](https://tools.ietf.org/html/rfc791#section-1.4), but was required as a result of one of CIARA's partner's appliance producing reports with the IP header checksum set to 0.

# Research and Implementation

Initial planning was conducted with research into if there is an already existing, or similar solution.
I found that linux has options for ignoring UDP checksums, but not IP header checksums.
In order to disable IP header checksums, I would have to start editing the kernel source.

## Modifying The Linux Kernel

The kernel version I used for this project is `v4.14`.
First I identified the section of code that checks the IP header checksum. Located in `net/ipv4/ip_input.c` is the `ip_rcv` function, which handles receiving IP packets.
This function checks for any problems with the packets, and will drop them if they may be considered invalid.
One of the conditions it considers for dropping a packet is the header checksum which is checked in these few lines of code:

```c
int ip_rcv(...)
{
	...
	if (unlikely(ip_fast_csum((u8 *)iph, iph->ihl)))
		goto csum_error;
	...
	csum_error:
	...
	return NET_RX_DROP;
}
```

One of the requirements set by CIARA was that we should be able to enable and disable checksum verification through sysctl.
To do so I added a new variable `int sysctl_ip_ignore_csum`, which if set to `1` or `true` would make the system skip evaluating the checksum. The change makes the code look like this:

```c
int sysctl_ip_ignore_csum __read_mostly = 0;
EXPORT_SYMBOL(sysctl_ip_ignore_csum);

int ip_rcv(...)
{
	...
	if (!sysctl_ip_ignore_csum && unlikely(ip_fast_csum((u8 *)iph, iph->ihl)) )
	 	goto csum_error;
	...
	csum_error:
	...
	return NET_RX_DROP;
}
```

To control this variable through sysctl, it would need to be linked to an entry in an existing sysctl `ctl_table`.
I modified `net/ipv4/sysctl_net_ipv4.c`, which contains various sysctl entries for tuning the IPv4 module.
I added a new entry to `ctl_table ipv4_table[]` which would expose the variable through `/proc/sys/net/ipv4/ip_ignore_csum` and `sysctl net.ipv4.ip_ignore_csum`.
The new entry was exposed through the following code:

```c
static struct ctl_table ipv4_table[] = {
	...
	{
		.procname	= "ip_ignore_csum",
		.data		= &sysctl_ip_ignore_csum,
		.maxlen		= sizeof(int),
		.mode		= 0644,
		.proc_handler	= proc_dointvec
	},
	...
};
```

# Testing

For testing I created two python programs, one for sending packets, the other
for receiving packets. Both of these programs are highly configurable to the
needs of our tests.
Please see [Using `sender.py`](#using-sender.py) and
[Using `receiver.py`](#using-receiver.py) for more details.

For testing the following variables were changed throughout the test:

 - `net.ipv4.ip_ignore_csum` value was set to either 0 or 1 for all tests.
 - IP header checksum: value was either 0 or left for the software to automatically calculate the correct value.
 - The source of the packet: packets where either received internally from another program on the same system or externally from another system.

For all tests hardware checksum verification and insertion was disabled.
Please see [Disabling Checksum Offload](#disabling-checksum-offload).

## Test Results

What I discovered, is that a locally delivered packet would be accepted no matter what, ignoring the checksum even when `net.ipv4.ip_ignore_csum=0`. However, for packets received from another system, `net.ipv4.ip_ignore_csum` worked as expected, accepting packets with invalid checksums when `net.ipv4.ip_ignore_csum=1`, and dropping them when `net.ipv4.ip_ignore_csum=0`.

| `net.ipv4.ip_ignore_csum` | Valid Checksum? | Source   | Expected | Result   |
|---------------------------|-----------------|----------|----------|----------|
| 0                         | No              | Internal | Dropped  | <span style="background-color:red">Accepted</span> |
| 0                         | Yes             | Internal | Accepted | <span style="background-color:green">Accepted</span> |
| 0                         | No              | External | Dropped  | <span style="background-color:green">Dropped</span>  |
| 0                         | Yes             | External | Accepted | <span style="background-color:green">Accepted</span> |
| 1                         | No              | Internal | Accepted | <span style="background-color:green">Accepted</span> |
| 1                         | Yes             | Internal | Accepted | <span style="background-color:green">Accepted</span> |
| 1                         | No              | External | Accepted | <span style="background-color:green">Accepted</span> |
| 1                         | Yes             | External | Accepted | <span style="background-color:green">Accepted</span> |

## Test Conclusion

While `net.ipv4.ip_ignore_csum` may not function as expected in the case of packets sent through the loopback interface,
it meets the requirement for receiving packets from external sources, which was the primary concern with this project. Additionally, packets with an invalid checksum where able to be received by a python program, so theoretically, a proxy program could be created that would forward the packet with a valid checksum.

## Additional Notes

While all tests where conducted with checksum offloading disabled, enabling it,
didn't change the results.

# Guides

The following are a set of guides to using the programs produced
during this project. This may be

## Changing `ip_ignore_csum`

To ignore the header checksum of all incoming IP packets, execute the following command:

```bash
echo 1 > /proc/sys/net/ipv4/ip_ignore_csum
```
or alternatively execute:
```bash
sysctl -w net.ipv4.ip_ignore_csum=1
```

To re-enable verification of IP header checksums, execute the following command:

```bash
echo 0 > /proc/sys/net/ipv4/ip_ignore_csum
```
or alternatively execute:
```bash
sysctl -w net.ipv4.ip_ignore_csum=0
```

## Disabling Checksum Offload

Some network interface cards have the ability to calculate and verify
checksum of incoming and outgoing packets. For this project
to work as intended, this functionality needs to be disabled.

To disable verification of the checksum of incoming packets enter
the following command:

```bash
ethtool -K $IFACE rx off
```

Where `$IFACE` is the network interface device to disable the feature for.


To disable checksum insertion by the hardware enter the following command:

```bash
ethtool -K $IFACE tx off
```

Where `$IFACE` is the network interface device to disable the feature for.

## Using `sender.py`

The sender python script that was created for this project will send a single packet to a specified address and port. To run it enter the following command:

```bash
python receiver.py $MSG [-p $PORT] [-d $DEST] [-c $CHKS]
```

`$MSG` can be replaced with any string. This string will be the data sent with the packet.

By replacing `$PORT` with an integer, you can specify what port you want to send the packet to. If you exclude `-p` the system will default to port `53`.

By replacing `$DEST` with an IP string, you can specify the destination IP of the packet. If you exclude `-d` the system will default to `'127.0.0.1'`.

By replacing `$CHKS` with an integer, you can specify the checksum of
the IP header of the packet. Excluding it will default to generating a valid
checksum.


## Using `receiver.py`

The receiver python script that was created for this project will listen to all packets received on a particular port. To run it enter the following command:

```bash
python receiver.py [-p $PORT] [-i $IP]
```

By replacing `$PORT` with an integer, you can specify what port you want to listen at. If you exclude `-p` the system will default to port `53`.

By replacing `$IP` with an IP string, you can specify which host interface to listen at based on its IP. If you exclude `-i` the system will default to listening to all host interfaces.

# References

The following code has been referenced throughout this doc.

## Linux Kernel source

The produced kernel is a fork of linux `v4.14` from https://github.com/torvalds/linux.
The source code for the produced kernel can be found at https://github.com/Ktmi/linux/tree/no-checksum.

The following is the diff for the source code `a` is `v4.14`, `b` is `no-checksum`.

```diff
diff --git a/Documentation/networking/ip-sysctl.txt b/Documentation/networking/ip-sysctl.txt
index 77f4de59dc9c..86e0a32e6de1 100644
--- a/Documentation/networking/ip-sysctl.txt
+++ b/Documentation/networking/ip-sysctl.txt
@@ -10,6 +10,12 @@ ip_forward - BOOLEAN
 	parameters to their default state (RFC1122 for hosts, RFC1812
 	for routers)
 
+ip_ignore_csum - BOOLEAN
+	0 - disabled (default)
+	not 0 - enabled
+
+	Ignore checking the header checksum of incoming IP packets.
+
 ip_default_ttl - INTEGER
 	Default value of TTL field (Time To Live) for outgoing (but not
 	forwarded) IP packets. Should be between 1 and 255 inclusive.
diff --git a/include/net/ip.h b/include/net/ip.h
index 9896f46cbbf1..4d875dff59b6 100644
--- a/include/net/ip.h
+++ b/include/net/ip.h
@@ -299,6 +299,9 @@ extern int inet_peer_threshold;
 extern int inet_peer_minttl;
 extern int inet_peer_maxttl;
 
+/* From ip_input.c */
+extern int sysctl_ip_ignore_csum;
+
 void ipfrag_init(void);
 
 void ip_static_sysctl_init(void);
diff --git a/net/ipv4/ip_input.c b/net/ipv4/ip_input.c
index 57fc13c6ab2b..d53d8a9a5ab6 100644
--- a/net/ipv4/ip_input.c
+++ b/net/ipv4/ip_input.c
@@ -406,6 +406,9 @@ static int ip_rcv_finish(struct net *net, struct sock *sk, struct sk_buff *skb)
 	goto drop;
 }
 
+int sysctl_ip_ignore_csum __read_mostly = 0;
+EXPORT_SYMBOL(sysctl_ip_ignore_csum);
+
 /*
  * 	Main IP Receive routine.
  */
@@ -462,8 +465,8 @@ int ip_rcv(struct sk_buff *skb, struct net_device *dev, struct packet_type *pt,
 
 	iph = ip_hdr(skb);
 
-	if (unlikely(ip_fast_csum((u8 *)iph, iph->ihl)))
-		goto csum_error;
+	if (!sysctl_ip_ignore_csum && unlikely(ip_fast_csum((u8 *)iph, iph->ihl)) )
+	 	goto csum_error;
 
 	len = ntohs(iph->tot_len);
 	if (skb->len < len) {
diff --git a/net/ipv4/sysctl_net_ipv4.c b/net/ipv4/sysctl_net_ipv4.c
index 0989e739d098..543e4396d8ac 100644
--- a/net/ipv4/sysctl_net_ipv4.c
+++ b/net/ipv4/sysctl_net_ipv4.c
@@ -753,6 +753,13 @@ static struct ctl_table ipv4_table[] = {
 		.proc_handler	= proc_dointvec_minmax,
 		.extra1		= &one
 	},
+	{
+		.procname	= "ip_ignore_csum",
+		.data		= &sysctl_ip_ignore_csum,
+		.maxlen		= sizeof(int),
+		.mode		= 0644,
+		.proc_handler	= proc_dointvec
+	},
 	{ }
 };
 

```


## `sender.py` source


```python
from scapy.all import IP, UDP, Raw, conf, send, L3RawSocket

import argparse

def send_packet(message, port = 53, destination = '127.0.0.1', checksum = None):
	conf.L3socket = L3RawSocket # Needed for transmission through loopback

	ip_header = IP(dst = destination, chksum = checksum) # IP header

	udp_header = UDP(dport = port, sport = 1024) # UDP header

	data = Raw(load=message)                     # Payload

	packet = ip_header / udp_header / data       # Construct packet

	send(packet)                                 # Transmit

def main():
	parser = argparse.ArgumentParser(description='Send raw UDP packets')

	parser.add_argument('message', help = 'message to send in packet')

	parser.add_argument('-p', '--port', type = int, default = 53,
	                    help = 'port number to send packet over')

	parser.add_argument('-d', '--destination', default = '127.0.0.1',
	                    help = 'destination of packet')

	parser.add_argument('-c', '--checksum', type = int, default = None,
	                    help = 'ip header checksum')

	args = parser.parse_args()

	send_packet(args.message, args.port, args.destination, args.checksum)

if __name__ == '__main__':
	main()
```

## `receiver.py` Source

```python
import socket
import argparse

def main():
	parser = argparse.ArgumentParser(description='Receive raw UDP packets')
	
	parser.add_argument('-i', '--ip', default = '',
	                    help = "ip address to listen at")
	
	parser.add_argument('-p', '--port', type = int, default = 53,
	                    help = "port to listen at")
	
	args = parser.parse_args()
	
	sock = socket.socket(socket.AF_INET,
	                     socket.SOCK_DGRAM)
	
	sock.bind((args.ip, args.port))
	
	while True:
		data, addr = sock.recvfrom(1024)
		print("Message:", data)
		print("Address:", addr)

if __name__ == '__main__':
	main()

```