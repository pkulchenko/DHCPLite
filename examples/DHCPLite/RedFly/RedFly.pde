#include <DHCPLite.h>
#include <RedFly.h>

//serial format: 9600 Baud, 8N2
void debugout(char *s)  { RedFly.disable(); Serial.print(s);   RedFly.enable(); }
void debugoutln(char *s){ RedFly.disable(); Serial.println(s); RedFly.enable(); }
void debugout(int s)  { RedFly.disable(); Serial.print(s);   RedFly.enable(); }
void debugoutln(int s){ RedFly.disable(); Serial.println(s); RedFly.enable(); }

byte serverIP[]  = { 192, 168, 0, 1 }; 
byte netmask[]   = { 255,255,255,  0 }; 
byte gateway[]   = {   0,  0,  0,  0 }; // ip from gateway/router (not needed)
byte broadcast[] = { 255,255,255, 255 };
char domainName[] = "mshome.net";
char serverName[] = "arduino\x06mshome\x03net";

uint8_t hDHCP, hDNSTCP, hDNSUDP, hHTTPUDP, hHTTPTCP = 0xFF; // socket handles; 0xFF means closed/not used; only needed here for HTTP

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

  // listen for UDP messages on port 80 (to test echo)
  hHTTPUDP = RedFly.socketListen(PROTO_UDP, 80);

  debugoutln("Setup completed");
}

void loop()
{
  uint8_t sock, *ptr, buf[DHCP_MESSAGE_SIZE]; 
  uint16_t buf_len, rd, len;
  uint16_t port; //incoming UDP port
  uint8_t ip[4]; //incoming UDP ip

  //check if socket is closed and start listening
  if (hHTTPTCP == 0xFF || RedFly.socketClosed(hHTTPTCP)) hHTTPTCP = RedFly.socketListen(PROTO_TCP, 80); // start listening on port 80

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
    else if (sock == hHTTPUDP) {
      sprintf((char*)buf+buf_len, " %d", millis());
      RedFly.socketSend(hHTTPUDP, buf, strlen((char*)buf), ip, port);
    }  
    else if (sock == hHTTPTCP) {
      const char *OK = PSTR("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n");
      const char *ContentLengthHeader = PSTR("Content-Length: %d\r\n\r\n");
      int pin, value;
      char mode, ignore;
      char *out = (char *)buf;

      if (strncmp_P(out, PSTR("GET / HTTP"), 10) == 0) {
        RedFly.socketSendPGM(sock, OK);
        RedFly.socketSendPGM(sock, PSTR("\r\nHello, World! <a href='/D13=1'>Turn LED on digital pin #13 on</a> or <a href='/A1'>read analog input from pin #1</a>"));
        RedFly.socketClose(sock);      
      }
      else if (sscanf_P(out, PSTR("GET /D%2d=%1d HTTP"), &pin, &value) == 2) {
        pinMode(pin, OUTPUT);
        digitalWrite(pin, value ? HIGH : LOW);

        const char * SetPinMessage = PSTR("Set digital pin %d to %d; <a href='/D%d=%d'>toggle</a>");
        sprintf_P(out, SetPinMessage, pin, !!value, pin, !value);
        int contentLength = strlen(out);

        sprintf_P(out, OK);
        sprintf_P(out+strlen(out), ContentLengthHeader, contentLength);
        sprintf_P(out+strlen(out), SetPinMessage, pin, !!value, pin, !value);

        RedFly.socketSend(sock, out);
      } 
      else if (sscanf_P(out, PSTR("GET /%1[AD]%2d= %1[H]"), &mode, &pin, &ignore) == 3) {
        // get the value         
        pinMode(pin, INPUT);
        int value = (mode == 'A' ? analogRead(pin) : digitalRead(pin));
       
        // calculate content length
        itoa(value, out, 10); 
        int contentLength = strlen(out);

        sprintf_P(out, OK);
        sprintf_P(out+strlen(out), ContentLengthHeader, contentLength);
        itoa(value, out + strlen(out), 10);

        RedFly.socketSend(sock, out); // push the actual content out
      }
      else {
        RedFly.socketSendPGM(sock, OK);
        RedFly.socketSendPGM(sock, PSTR("\r\n<html><head><title>Arduino</title><script type='text/javascript'>var SIDE=200;var DELAY=100;var request=new XMLHttpRequest();function getUrl(a,b){request.onreadystatechange=function(){if(request.readyState==4){b(request.responseText);request.onreadystatechange=function(){}}};request.open('GET',a,true);request.send(null)}function doit(){var d=document.getElementById('info');var b=document.getElementById('out');b.width=b.height=SIDE;var a=b.getContext('2d');function c(e){a.clearRect(0,0,SIDE,SIDE);a.beginPath();a.arc(SIDE/2,SIDE/2,e/10,0,Math.PI*2,true);a.fillStyle='#002D80';a.fill();d.innerHTML=e;getMore=function(){getUrl(window.location.pathname+'=',c)};setTimeout('getMore()',DELAY)}c(0)};</script>"));
        RedFly.socketSendPGM(sock, PSTR("<style type='text/css'>html,body{width:100%;height:100%}html{overflow:hidden}body{margin:0;font-family:Verdana,Geneva,Georgia,Chicago,Arial,Sans-serif,'MS Sans Serif'}#info{position:absolute;padding:4px;left:10px;top:10px;background-color:#fff;border:1px solid #002d80;color:#002d80;opacity:.8;-moz-border-radius:5px;-webkit-border-radius:5px}</style></head><body onload='doit()'><canvas id='out'></canvas><div id='info'/></body></html>"));
        RedFly.socketClose(sock);      
      }
    }  
  }
}

