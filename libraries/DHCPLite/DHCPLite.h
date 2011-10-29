// DHCP Lite header

#ifndef	DHCP_LITE_H
#define DHCP_LITE_H

#include <WProgram.h>

/* UDP port numbers for DHCP */
#define	DHCP_SERVER_PORT	67	/* from server to client */
#define DHCP_CLIENT_PORT	68	/* from client to server */

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

/**
 * @brief	DHCP option and value (cf. RFC1533)
 */
enum {
	padOption		=	0,
	subnetMask		=	1,
	timerOffset		=	2,
	routersOnSubnet		=	3,
	timeServer		=	4,
	nameServer		=	5,
	dns			=	6,
	logServer		=	7,
	cookieServer		=	8,
	lprServer		=	9,
	impressServer		=	10,
	resourceLocationServer	=	11,
	hostName		=	12,
	bootFileSize		=	13,
	meritDumpFile		=	14,
	domainName		=	15,
	swapServer		=	16,
	rootPath		=	17,
	extentionsPath		=	18,
	IPforwarding		=	19,
	nonLocalSourceRouting	=	20,
	policyFilter		=	21,
	maxDgramReasmSize	=	22,
	defaultIPTTL		=	23,
	pathMTUagingTimeout	=	24,
	pathMTUplateauTable	=	25,
	ifMTU			=	26,
	allSubnetsLocal		=	27,
	broadcastAddr		=	28,
	performMaskDiscovery	=	29,
	maskSupplier		=	30,
	performRouterDiscovery	=	31,
	routerSolicitationAddr	=	32,
	staticRoute		=	33,
	trailerEncapsulation	=	34,
	arpCacheTimeout		=	35,
	ethernetEncapsulation	=	36,
	tcpDefaultTTL		=	37,
	tcpKeepaliveInterval	=	38,
	tcpKeepaliveGarbage	=	39,
	nisDomainName		=	40,
	nisServers		=	41,
	ntpServers		=	42,
	vendorSpecificInfo	=	43,
	netBIOSnameServer	=	44,
	netBIOSdgramDistServer	=	45,
	netBIOSnodeType		=	46,
	netBIOSscope		=	47,
	xFontServer		=	48,
	xDisplayManager		=	49,
	dhcpRequestedIPaddr	=	50,
	dhcpIPaddrLeaseTime	=	51,
	dhcpOptionOverload	=	52,
	dhcpMessageType		=	53,
	dhcpServerIdentifier	=	54,
	dhcpParamRequest	=	55,
	dhcpMsg			=	56,
	dhcpMaxMsgSize		=	57,
	dhcpT1value		=	58,
	dhcpT2value		=	59,
	dhcpClassIdentifier	=	60,
	dhcpClientIdentifier	=	61,
	endOption		=	255
};

/**
 * @brief		for the DHCP message
 */
typedef struct RIP_MSG {
	byte	op;
	byte	htype;
	byte	hlen;
	byte	hops;
	unsigned long	xid;
	unsigned int	secs;
	unsigned int	flags;
	byte	ciaddr[4]; // Client IP
	byte	yiaddr[4]; // Your IP
	byte	siaddr[4]; // Server IP
	byte	giaddr[4]; // Gateway IP
	byte	chaddr[16]; // Client hardware address (zero padded)
	byte	sname[64];
	byte	file[128];
        byte    magic[4]; // 0x63825363
	byte	OPT[]; // 240 offset
};

int DHCPreply(RIP_MSG *packet, int packetSize, byte *serverIP);

#endif
