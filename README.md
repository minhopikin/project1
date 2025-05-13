# project1

We have a vulnerability that points to the operating system/network configuration of the server hosting our 
database.
--------------------
Vulnerability Description:
The remote host answers to an ICMP timestamp request. This allows an attacker to know the date that is set on the targeted machine, which may assist an unauthenticated, remote attacker in defeating time-based authentication protocols.

Timestamps returned from machines running Windows Vista / 7 / 2008 / 2008 R2 are deliberately incorrect, but usually within 1000 seconds of the actual system time.'
------------------
Risk Analysis:

ICMP timestamp responses allow an attacker to infer the system time.

This can aid in attacks that rely on time synchronization, such as:

Defeating time-based authentication mechanisms and Coordinating replay attacks
--------------------------------------------------
Recommended Solution: Disable ICMP Timestamp Responses

Using iptables

- sudo iptables -A INPUT -p icmp --icmp-type timestamp-request -j DROP

- nft add rule inet filter input icmp type timestamp-request drop
