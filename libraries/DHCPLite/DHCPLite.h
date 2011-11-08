// DHCP Lite header

#ifndef	DHCP_LITE_H
#define DHCP_LITE_H

#include <WProgram.h>

#define DHCP_MESSAGE_SIZE	576     /* a DHCP client must be prepared to receive a message of up to 576 octets */

/* UDP port numbers for DHCP */
#define	DHCP_SERVER_PORT	67	/* port for server to listen on */
#define DHCP_CLIENT_PORT	68	/* port for client to use */

#define DNS_SERVER_PORT		53	/* port for server to listed on */

/* DHCP message OP code */
#define DHCP_BOOTREQUEST	1
#define DHCP_BOOTREPLY		2

/* DHCP message type */
#define	DHCP_DISCOVER		1
#define DHCP_OFFER		2
#define	DHCP_REQUEST		3
#define	DHCP_DECLINE		4
#define	DHCP_ACK		5
#define DHCP_NAK		6
#define	DHCP_RELEASE		7
#define DHCP_INFORM		8

#define DHCP_LEASETIME ((long)60*60*24) // Lease Time: 1 day == { 00, 01, 51, 80 }

/* DHCP lease status */
#define DHCP_LEASE_AVAIL	0
#define DHCP_LEASE_OFFER	1
#define DHCP_LEASE_ACK		2

struct Lease {
	unsigned long maccrc;
	long expires;
	byte status;
	unsigned long hostcrc;
};

#define LEASESNUM 12

/**
 * @brief	DHCP option and value (cf. RFC1533)
 */
enum {
	dhcpPadOption			=	0,
	dhcpSubnetMask			=	1,
	dhcpTimerOffset			=	2,
	dhcpRoutersOnSubnet		=	3,
	dhcpTimeServer			=	4,
	dhcpNameServer			=	5,
	dhcpDns				=	6,
	dhcpLogServer			=	7,
	dhcpCookieServer		=	8,
	dhcpLprServer			=	9,
	dhcpImpressServer		=	10,
	dhcpResourceLocationServer	=	11,
	dhcpHostName			=	12,
	dhcpBootFileSize		=	13,
	dhcpMeritDumpFile		=	14,
	dhcpDomainName			=	15,
	dhcpSwapServer			=	16,
	dhcpRootPath			=	17,
	dhcpExtentionsPath		=	18,
	dhcpIPforwarding		=	19,
	dhcpNonLocalSourceRouting	=	20,
	dhcpPolicyFilter		=	21,
	dhcpMaxDgramReasmSize		=	22,
	dhcpDefaultIPTTL		=	23,
	dhcpPathMTUagingTimeout		=	24,
	dhcpPathMTUplateauTable		=	25,
	dhcpIfMTU			=	26,
	dhcpAllSubnetsLocal		=	27,
	dhcpBroadcastAddr		=	28,
	dhcpPerformMaskDiscovery	=	29,
	dhcpMaskSupplier		=	30,
	dhcpPerformRouterDiscovery	=	31,
	dhcpRouterSolicitationAddr	=	32,
	dhcpStaticRoute			=	33,
	dhcpTrailerEncapsulation	=	34,
	dhcpArpCacheTimeout		=	35,
	dhcpEthernetEncapsulation	=	36,
	dhcpTcpDefaultTTL		=	37,
	dhcpTcpKeepaliveInterval	=	38,
	dhcpTcpKeepaliveGarbage		=	39,
	dhcpNisDomainName		=	40,
	dhcpNisServers			=	41,
	dhcpNtpServers			=	42,
	dhcpVendorSpecificInfo		=	43,
	dhcpNetBIOSnameServer		=	44,
	dhcpNetBIOSdgramDistServer	=	45,
	dhcpNetBIOSnodeType		=	46,
	dhcpNetBIOSscope		=	47,
	dhcpXFontServer			=	48,
	dhcpXDisplayManager		=	49,
	dhcpRequestedIPaddr		=	50,
	dhcpIPaddrLeaseTime		=	51,
	dhcpOptionOverload		=	52,
	dhcpMessageType			=	53,
	dhcpServerIdentifier		=	54,
	dhcpParamRequest		=	55,
	dhcpMsg				=	56,
	dhcpMaxMsgSize			=	57,
	dhcpT1value			=	58,
	dhcpT2value			=	59,
	dhcpClassIdentifier		=	60,
	dhcpClientIdentifier		=	61,
	dhcpEndOption			=	255
};

/**
 * @brief		for the DHCP message
 */
typedef struct RIP_MSG {
	byte		op;
	byte		htype;
	byte		hlen;
	byte		hops;
	uint32_t	xid;
	uint16_t	secs;
#define DHCP_FLAG_BROADCAST (0x8000)
        uint16_t	flags;
	byte		ciaddr[4];  // Client IP
	byte		yiaddr[4];  // Your IP
	byte		siaddr[4];  // Server IP
	byte		giaddr[4];  // Gateway IP
	byte		chaddr[16]; // Client hardware address (zero padded)
	byte		sname[64];
	byte		file[128];
#define DHCP_MAGIC (0x63825363)
        byte    	magic[4]; 
	byte		OPT[]; // 240 offset
};

#define DNS_QR_MASK (0b10000000)
typedef struct DNS_MSG {
	uint16_t	msgid;
	byte		opflags; // QR + OPCODE (4bits) + AA + TC + RD
	byte		rarcode; // RA + res (3 bits) + RCODE (4bits)
	uint16_t	qdCount;
	uint16_t	anCount;
	uint16_t	nsCount;
	uint16_t	arCount;
	byte	BODY[]; 
};

enum {
   dnsOpQuery     = 0,
   dnsOpIQuery    = 1,
   dnsOpStatus    = 2,
   dnsOpNotify    = 4,
   dnsOpUpdate    = 5
};

enum {
   dnsRetNoError	= 0,
   dnsRetFormatError	= 1,
   dnsRetServerError	= 2,
   dnsRetNameError 	= 3,
   dnsRetNotImplemented	= 4,
   dnsRetRefused	= 5
};

int DHCPreply(RIP_MSG *packet, int packetSize, byte *serverIP, char *domainName);

int DNSreply(DNS_MSG *packet, int packetSize, byte *serverIP, char *serverName);

#endif
