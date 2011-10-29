#include <DHCPLite.h>
#include <RedFly.h>

//serial format: 9600 Baud, 8N2
void debugout(char *s)  { RedFly.disable(); Serial.print(s);   RedFly.enable(); }
void debugoutln(char *s){ RedFly.disable(); Serial.println(s); RedFly.enable(); }
void debugout(int s)  { RedFly.disable(); Serial.print(s);   RedFly.enable(); }
void debugoutln(int s){ RedFly.disable(); Serial.println(s); RedFly.enable(); }

byte serverIP[]  = { 192, 168, 2, 1 }; 
byte netmask[]   = { 255,255,255,  0 }; 
byte gateway[]   = {   0,  0,  0,  0 }; //ip from gateway/router (not needed)
byte broadcast[] = { 255,255,255, 255 };

uint8_t hUDP=0xFF; //socket handles

void setup() {
  uint8_t ret;

  //init the WiFi module on the shield
  ret = RedFly.init(115200, HIGH_POWER); //LOW_POWER MED_POWER HIGH_POWER
  if(ret) debugoutln("INIT ERR"); //there are problems with the communication between the Arduino and the RedFly
  else {
    ret = RedFly.join("TestNetwork", IBSS_CREATOR, 10);
    if(ret) { debugoutln("JOIN ERR"); for(;;); //do nothing forevermore
    }
    else {
      //set ip config
      //ret = RedFly.begin(); //dhcp
      //ret = RedFly.begin(ip);
      //ret = RedFly.begin(ip, gateway);
      ret = RedFly.begin(serverIP, gateway, netmask);
      if(ret) { debugoutln("BEGIN ERR"); RedFly.disconnect(); for(;;); //do nothing forevermore
      }
    }
  }

  //check if sockets are opened
  hUDP = RedFly.socketListen(PROTO_UDP, DHCP_SERVER_PORT);
  if(hUDP == 0xFF) {
    debugoutln("SOCKET UDP ERR");
    RedFly.disconnect();
    for(;;); //do nothing forevermore
  }
  debugoutln("Setup completed");
}

void loop()
{
  uint8_t sock, buf[590], *ptr;
  uint16_t buf_len, rd, len;
  uint16_t port; //incoming UDP port
  uint8_t ip[4]; //incoming UDP ip

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
    if(sock == hUDP) {
      buf_len = DHCPreply((RIP_MSG*)buf, buf_len, serverIP);
      RedFly.socketSend(hUDP, buf, buf_len, broadcast, DHCP_CLIENT_PORT);
    }
  }
}
