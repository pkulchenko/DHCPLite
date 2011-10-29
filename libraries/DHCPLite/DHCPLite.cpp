// Copyright (C) 2011 by Paul Kulchenko

#include "DHCPLite.h"

// Lease Time: 1 day == { 00, 01, 51, 80 }
#define DHCP_LEASETIME ((long)60*60*24)

struct Lease {
	unsigned short mac;
	long expires;
	byte status;
};

#define LEASESNUM 12
Lease Leases[LEASESNUM];

byte ComputeChecksum(byte *buf, int length) {
  byte crc = 0;
  for (int i = 0; i < length; i++) crc = crc ^ *(buf+i);
  return crc;
}

byte quads[4];
byte * long2quad(unsigned long value) {
  for (int k = 0; k < 4; k++) quads[3-k] = value >> (k * 8);
  return quads;
}

byte getLease(unsigned short crc) {
  for (byte lease = 0; lease < LEASESNUM; lease++)
    if (Leases[lease].mac == crc) return lease+1;
  
  // Clean up expired leases; need to do after we check for existing leases because of this iOS bug
  // http://www.net.princeton.edu/apple-ios/ios41-allows-lease-to-expire-keeps-using-IP-address.html
  // Don't need to check again AFTER the clean up as for DHCP REQUEST the client should already have the lease
  // and for DHCP DISCOVER we will check once more to assign a new lease
  long currTime = millis();
  for (byte lease = 0; lease < LEASESNUM; lease++)
    if (Leases[lease].expires < currTime) {
      Leases[lease].mac = 0;
      Leases[lease].expires = 0; 
      Leases[lease].status = 0;
    }

  return 0;
}

void setLease(byte lease, unsigned short crc, long expires, byte status) {
  if (lease > 0 && lease <= LEASESNUM) {
    Leases[lease-1].mac = crc;
    Leases[lease-1].expires = expires; 
    Leases[lease-1].status = status;
  }
}

int GetOption(int dhcpOption, byte *options, int optionSize, int *optionLength) {
  for(int i=0; i<optionSize && (options[i] != endOption); i += 2 + options[i+1]) {
    if(options[i] == dhcpOption) {
      if (optionLength) *optionLength = (int)options[i+1];
      return i+2;
    }
  }
  if (optionLength) *optionLength = 0;
  return 0;
}

int populatePacket(byte *packet, int currLoc, byte marker, byte *what, int dataSize) {
  packet[currLoc] = marker;
  packet[currLoc+1] = dataSize;
  memcpy(packet+currLoc+2,what,dataSize);
  return dataSize + 2;
}

int DHCPreply(RIP_MSG *packet, int packetSize, byte *serverIP) {
  if (packet->op != DHCP_BOOTREQUEST) return 0; // limited check that we're dealing with DHCP/BOOTP request

  packet->op = DHCP_BOOTREPLY;
  packet->secs = 0; // some of the secs come malformed; don't want to send them back

  unsigned short crcd = ComputeChecksum(packet->chaddr, packet->hlen);

  int dhcpMessageOffset = GetOption(dhcpMessageType, packet->OPT, packetSize-240, NULL);
  byte dhcpMessage = packet->OPT[dhcpMessageOffset];

  byte lease = getLease(crcd);
  byte response = DHCP_NAK;
  if (dhcpMessage == DHCP_DISCOVER) {
    if (!lease) lease = getLease(0); // use existing lease or get a new one
    if (lease) {
      response = DHCP_OFFER;
      setLease(lease, crcd, millis() + 10000, 1); // 10s
    }
  }  
  else if (dhcpMessage == DHCP_REQUEST) {
    if (lease) {
      response = DHCP_ACK;
      setLease(lease, crcd, millis() + DHCP_LEASETIME * 1000, 1); // DHCP_LEASETIME is in seconds
    }
  }

  if (lease) { // Dynamic IP configuration
    memcpy(packet->yiaddr, serverIP, 4);
    packet->yiaddr[3] += lease; // lease starts with 1
  }  
      
  int currLoc = 0; 
  packet->OPT[currLoc++] = dhcpMessageType;
  packet->OPT[currLoc++] = 1;
  packet->OPT[currLoc++] = response;

  int reqLength; 
  int reqListOffset = GetOption(dhcpParamRequest, packet->OPT, packetSize-240, &reqLength);
  byte reqList[12]; if (reqLength > 12) reqLength = 12;
  memcpy(reqList, packet->OPT + reqListOffset, reqLength);

  // iPod with iOS 4 doesn't want to process DHCP OFFER if dhcpServerIdentifier does not follow dhcpMessageType
  // Windows Vista and Ubuntu 11.04 don't seem to care
  currLoc += populatePacket(packet->OPT, currLoc, dhcpServerIdentifier, serverIP, 4);

  // DHCP lease timers: http://www.tcpipguide.com/free/t_DHCPLeaseLifeCycleOverviewAllocationReallocationRe.htm
  currLoc += populatePacket(packet->OPT, currLoc, dhcpIPaddrLeaseTime, long2quad(DHCP_LEASETIME), 4); 

  for(int i=0; i<reqLength; i++) {
    switch(reqList[i]) {
      case subnetMask:
        currLoc += populatePacket(packet->OPT, currLoc, reqList[i], long2quad(0xFFFFFF00UL), 4); // 255.255.255.0
        break;
      case logServer:
        currLoc += populatePacket(packet->OPT, currLoc, reqList[i], long2quad(0), 4);
        break;
      case dns:
      case routersOnSubnet:
        currLoc += populatePacket(packet->OPT, currLoc, reqList[i], serverIP, 4);
        break;
    }
  }
  packet->OPT[currLoc++] = endOption;

  return (byte*)packet->OPT-(byte*)packet+currLoc;
} 
