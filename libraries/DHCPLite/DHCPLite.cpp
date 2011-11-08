// Copyright (C) 2011 by Paul Kulchenko

#include "DHCPLite.h"

unsigned short htons(unsigned short x) { /** A 16-bit number in host byte order. */
#if ( SYSTEM_ENDIAN == _ENDIAN_LITTLE_ )
        return ((x)<<8) | (((x)>>8)&0xFF);
#else
        return x;
#endif          
}

unsigned long computeChecksum(byte *buf, int length) {
  unsigned long h = 0;
  unsigned long highorder;

  // based on CRC algorithm from http://www.cs.hmc.edu/~geoff/classes/hmc.cs070.200101/homework10/hashfuncs.html
  for (int i = 0; i < length; i++) {
    highorder = h & 0xf8000000;    // extract high-order 5 bits from h
    h = h << 5;                    // shift h left by 5 bits
    h = h ^ (highorder >> 27);     // move the highorder 5 bits to the low-order end
    h = h ^ tolower(buf[i]);       // this is to allow "MyPC" and "mypc" to be the same
  }
  return h;
}

byte quads[4];
byte * long2quad(unsigned long value) {
  for (int k = 0; k < 4; k++) quads[3-k] = value >> (k * 8);
  return quads;
}

Lease Leases[LEASESNUM];

// leases are numbered 1..LEASENUM (to use 0 to signal no lease)
void setLease(byte lease, unsigned long crc, long expires, byte status, unsigned long hostcrc) {
  if (lease > 0 && lease <= LEASESNUM) {
    Leases[lease-1].maccrc = crc;
    Leases[lease-1].expires = expires; 
    Leases[lease-1].status = status;
    Leases[lease-1].hostcrc = hostcrc;
  }
}

byte getLease(unsigned long crc) {
  for (byte lease = 0; lease < LEASESNUM; lease++)
    if (Leases[lease].maccrc == crc) return lease+1;
  
  // Clean up expired leases; need to do after we check for existing leases because of this iOS bug
  // http://www.net.princeton.edu/apple-ios/ios41-allows-lease-to-expire-keeps-using-IP-address.html
  // Don't need to check again AFTER the clean up as for DHCP REQUEST the client should already have the lease
  // and for DHCP DISCOVER we will check once more to assign a new lease
  long currTime = millis();
  for (byte lease = 0; lease < LEASESNUM; lease++)
    if (Leases[lease].expires < currTime) setLease(lease+1, 0, 0, DHCP_LEASE_AVAIL, 0);

  return 0;
}

byte getLeaseByHost(unsigned long crc) {
  for (byte lease = 0; lease < LEASESNUM; lease++)
    if (Leases[lease].hostcrc == crc && Leases[lease].status == DHCP_LEASE_ACK) 
      return lease+1;
  return 0;
}

int getOption(int dhcpOption, byte *options, int optionSize, int *optionLength) {
  for(int i=0; i<optionSize && (options[i] != dhcpEndOption); i += 2 + options[i+1]) {
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

int DHCPreply(RIP_MSG *packet, int packetSize, byte *serverIP, char *domainName) {
  if (packet->op != DHCP_BOOTREQUEST) return 0; // limited check that we're dealing with DHCP/BOOTP request

  byte OPToffset = (byte*)packet->OPT-(byte*)packet;

  packet->op = DHCP_BOOTREPLY;
  packet->secs = 0; // some of the secs come malformed; don't want to send them back

  unsigned long crc = computeChecksum(packet->chaddr, packet->hlen);

  int dhcpMessageOffset = getOption(dhcpMessageType, packet->OPT, packetSize-OPToffset, NULL);
  byte dhcpMessage = packet->OPT[dhcpMessageOffset];

  byte lease = getLease(crc);
  byte response = DHCP_NAK;
  if (dhcpMessage == DHCP_DISCOVER) {
    if (!lease) lease = getLease(0); // use existing lease or get a new one
    if (lease) {
      response = DHCP_OFFER;
      setLease(lease, crc, millis() + 10000, DHCP_LEASE_OFFER, 0); // 10s
    }
  }  
  else if (dhcpMessage == DHCP_REQUEST) {
    if (lease) {
      response = DHCP_ACK;

      // find hostname option in the request and store to provide DNS info
      int hostNameLength;
      int hostNameOffset = getOption(dhcpHostName, packet->OPT, packetSize-OPToffset, &hostNameLength);
      unsigned long crc = hostNameOffset 
        ? computeChecksum(packet->OPT + hostNameOffset, hostNameLength) 
        : 0;
      setLease(lease, crc, millis() + DHCP_LEASETIME * 1000, DHCP_LEASE_ACK, crc); // DHCP_LEASETIME is in seconds
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
  int reqListOffset = getOption(dhcpParamRequest, packet->OPT, packetSize-OPToffset, &reqLength);
  byte reqList[12]; if (reqLength > 12) reqLength = 12;
  memcpy(reqList, packet->OPT + reqListOffset, reqLength);

  // iPod with iOS 4 doesn't want to process DHCP OFFER if dhcpServerIdentifier does not follow dhcpMessageType
  // Windows Vista and Ubuntu 11.04 don't seem to care
  currLoc += populatePacket(packet->OPT, currLoc, dhcpServerIdentifier, serverIP, 4);

  // DHCP lease timers: http://www.tcpipguide.com/free/t_DHCPLeaseLifeCycleOverviewAllocationReallocationRe.htm
  // Renewal Timer (T1): This timer is set by default to 50% of the lease period.
  // Rebinding Timer (T2): This timer is set by default to 87.5% of the length of the lease.
  currLoc += populatePacket(packet->OPT, currLoc, dhcpIPaddrLeaseTime, long2quad(DHCP_LEASETIME), 4); 
  currLoc += populatePacket(packet->OPT, currLoc, dhcpT1value, long2quad(DHCP_LEASETIME*0.5), 4); 
  currLoc += populatePacket(packet->OPT, currLoc, dhcpT2value, long2quad(DHCP_LEASETIME*0.875), 4);

  for(int i=0; i<reqLength; i++) {
    switch(reqList[i]) {
      case dhcpSubnetMask:
        currLoc += populatePacket(packet->OPT, currLoc, reqList[i], long2quad(0xFFFFFF00UL), 4); // 255.255.255.0
        break;
      case dhcpLogServer:
        currLoc += populatePacket(packet->OPT, currLoc, reqList[i], long2quad(0), 4);
        break;
      case dhcpDns:
      case dhcpRoutersOnSubnet:
        currLoc += populatePacket(packet->OPT, currLoc, reqList[i], serverIP, 4);
        break;
      case dhcpDomainName:
        if (domainName && strlen(domainName))
          currLoc += populatePacket(packet->OPT, currLoc, reqList[i], (byte*)domainName, strlen(domainName));
        break;
    }
  }
  packet->OPT[currLoc++] = dhcpEndOption;

  return OPToffset+currLoc;
} 

int DNSreply(DNS_MSG *packet, int packetSize, byte *serverIP, char *serverName) {
  if ((packet->opflags & DNS_QR_MASK) != 0) return 0; // limited check for DNS Query message

  byte BODYoffset = (byte*)packet->BODY-(byte*)packet;

  packet->opflags |= DNS_QR_MASK;

  // check the opcode; only handles standard query
  // also check the number of questions; can only handle 1
  if (((packet->opflags & ~DNS_QR_MASK) >> 3) != dnsOpQuery
   || packet->qdCount != htons(1)) {
    packet->qdCount = packet->anCount = 0;
    packet->rarcode = dnsRetNotImplemented;
    return BODYoffset;
  }

  // calculate hostname CRC based on A query
  // assume an A query with a name of www.mydomain.com the hex representation is:
  // 03 77 77 77 08 6D 79 64 6F 6D 61 69 6E 03 63 6F 6D 00
  //  !  w  w  w  !  m  y  d  o  m  a  i  n  !  c  o  m  !
  int nameLength = packet->BODY[0] + 1;
  while (packet->BODY[nameLength] != 0 
     && (BODYoffset + nameLength) < packetSize)
    nameLength += packet->BODY[nameLength] + 1;

  unsigned long crc = computeChecksum(packet->BODY + 1, nameLength-1);

  // try to find a lease for this host name
  // if nothing, then check for the first segment of the name
  // if still nothing, then check the serverName for a match
  byte lease = getLeaseByHost(crc);
  if (!lease) lease = getLeaseByHost(computeChecksum(packet->BODY + 1, packet->BODY[0]));
  byte found = lease || crc == computeChecksum((byte*)serverName, strlen(serverName));

  packet->qdCount = packet->anCount = 0;

  // if nothing found, then return proper error code
  if (!found) {
    packet->rarcode = dnsRetNameError; // name not found
    return BODYoffset;
  }

  //               type = a    Class In    TTL                     Data Len
  byte answer[] = {0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04};
  byte answerOffset = nameLength + 1; // position behind last 0 

  memcpy(packet->BODY + answerOffset, answer, 10);
  memcpy(packet->BODY + answerOffset + 4, long2quad(DHCP_LEASETIME), 4);
  memcpy(packet->BODY + answerOffset + 10, serverIP, 4);
  packet->BODY[answerOffset + 10 + 3] += lease; // lease starts with 1
  packet->anCount = htons(1); // count of replies in packet
  packet->rarcode = dnsRetNoError;

  return BODYoffset + answerOffset + 14;
} 
