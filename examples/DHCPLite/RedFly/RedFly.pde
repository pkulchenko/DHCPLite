#include <DHCPLite.h>
#include <RedFly.h>

//serial format: 9600 Baud, 8N2
void debugout(char *s)  { RedFly.disable(); Serial.print(s);   RedFly.enable(); }
void debugoutln(char *s){ RedFly.disable(); Serial.println(s); RedFly.enable(); }
void debugout(int s)  { RedFly.disable(); Serial.print(s);   RedFly.enable(); }
void debugoutln(int s){ RedFly.disable(); Serial.println(s); RedFly.enable(); }

byte serverIP[]  = { 192, 168, 2, 1 }; 
byte netmask[]   = { 255,255,255,  0 }; 
byte gateway[]   = {   0,  0,  0,  0 }; // ip from gateway/router (not needed)
byte broadcast[] = { 255,255,255, 255 };
char domainName[] = "mshome.net";
char serverName[] = "arduino\x06mshome\x03net";

uint8_t hDHCP, hDNSTCP, hDNSUDP, hHTTP = 0xFF; // socket handles; 0xFF means closed/not used; only needed here for HTTP

void setup() {
  uint8_t ret;

  //init the WiFi module on the shield
  ret = RedFly.init(115200, HIGH_POWER); //LOW_POWER MED_POWER HIGH_POWER
  if(ret) debugoutln("INIT ERR"); //there are problems with the communication between the Arduino and the RedFly
  else {
    ret = RedFly.join("TestNetwork", IBSS_CREATOR, 10);
    if(ret) { debugoutln("JOIN ERR"); for(;;); }
    else {
      ret = RedFly.begin(serverIP, gateway, netmask);
      if(ret) { debugoutln("BEGIN ERR"); RedFly.disconnect(); for(;;); }
    }
  }

  // listen for DHCP messages on DHCP_SERVER_PORT (UDP)
  hDHCP = RedFly.socketListen(PROTO_UDP, DHCP_SERVER_PORT);
  if(hDHCP == 0xFF) { debugoutln("SOCKET DHCP/UDP ERR"); RedFly.disconnect(); for(;;); }
  
  // listen for DNS messages on DNS_SERVER_PORT (both UDP and TCP on the same port)
  hDNSTCP = RedFly.socketListen(PROTO_TCP, DNS_SERVER_PORT);
  if(hDNSTCP == 0xFF) { debugoutln("SOCKET DNS/TCP ERR"); RedFly.disconnect(); for(;;); }
  hDNSUDP = RedFly.socketListen(PROTO_UDP, DNS_SERVER_PORT);
  if(hDNSUDP == 0xFF) { debugoutln("SOCKET DNS/UDP ERR"); RedFly.disconnect(); for(;;); }

  debugoutln("Setup completed");
}

void loop()
{
  uint8_t sock, *ptr, buf[DHCP_MESSAGE_SIZE]; 
  uint16_t buf_len, rd, len;
  uint16_t port; //incoming UDP port
  uint8_t ip[4]; //incoming UDP ip

  //check if socket is closed and start listening
  if (hHTTP == 0xFF || RedFly.socketClosed(hHTTP)) hHTTP = RedFly.socketListen(PROTO_TCP, 80); // start listening on port 80

  // get data
  sock    = 0xFF; // 0xFF = return data from all open sockets
  ptr     = buf;
  buf_len = 0;
  do {
    rd = RedFly.socketRead(&sock, &len, ip, &port, ptr, sizeof(buf)-buf_len);
    if((rd != 0) && (rd != 0xFFFF)) { // 0xFFFF = connection closed
      ptr     += rd;
      buf_len += rd;
    }
  } while(len != 0);

  // process and send back data
  if (buf_len && (sock != 0xFF)) {
    if (sock == hDHCP) {
      buf_len = DHCPreply((RIP_MSG*)buf, buf_len, serverIP, domainName); // zero returned means the message was not recognized
      if (buf_len) RedFly.socketSend(sock, buf, buf_len, broadcast, port);
    }
    else if (sock == hDNSTCP || sock == hDNSUDP) {
      buf_len = DNSreply((DNS_MSG*)buf, buf_len, serverIP, serverName); // zero returned means the message was not recognized
      if (sock == hDNSTCP) {
        if (buf_len) RedFly.socketSend(sock, buf, buf_len);
      }
      else {
        if (buf_len) RedFly.socketSend(sock, buf, buf_len, ip, port); // send back to the same ip/port the message came from
      }
    }
    else if (sock == hHTTP) {
      RedFly.socketSendPGM(sock, PSTR("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n"));
      RedFly.socketSendPGM(sock, PSTR("Hello, World!"));
      RedFly.socketClose(sock);      
    }
  }
}
