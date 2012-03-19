#include <DHCPLite.h>
#include <RedFly.h>
#include <EEPROM.h>

byte serverIP[]  = { 192, 168, 0, 1 }; 
byte netmask[]   = { 255,255,255,  0 }; 
byte gateway[]   = {   0,  0,  0,  0 }; // ip from gateway/router (not needed)
byte broadcast[] = { 255,255,255, 255 };
byte *currentIP  = serverIP;
char domainName[] = "mshome.net";
char serverName[] = "arduino\x06mshome\x03net";

uint8_t hDHCP, hDNSTCP, hDNSUDP, hHTTPUDP, hHTTPTCP = 0xFF; // socket handles; 0xFF means closed/not used; only needed here for HTTP

#define LEDPIN 13

#define HTTP_SERVER_PORT 80
#define SERVER_PORT 4444

#define CONFIG_VERSION "ar1"
#define CONFIG_START 0

struct WiFiStorageStruct {
  char version[4];
  char ssid[24];
  char pwd[16];
  byte addr[4];
  unsigned int id;
} WiFiConfig = {
  CONFIG_VERSION,
  "NetworkConnectTo",
  "",
  {0, 0, 0, 0},
  0
};

void loadConfig() {
  if (EEPROM.read(CONFIG_START + 0) == CONFIG_VERSION[0] &&
      EEPROM.read(CONFIG_START + 1) == CONFIG_VERSION[1] &&
      EEPROM.read(CONFIG_START + 2) == CONFIG_VERSION[2])
    for (unsigned int t=0; t<sizeof(WiFiConfig); t++)
      *((char*)&WiFiConfig + t) = EEPROM.read(CONFIG_START + t);
}

void saveConfig() {
  for (unsigned int t=0; t<sizeof(WiFiConfig); t++)
    EEPROM.write(CONFIG_START + t, *((char*)&WiFiConfig + t));
}

void blink(int pin, int n) {
  for (int i = 0; i < n; i++) {
    digitalWrite(pin, HIGH); delay(200);
    digitalWrite(pin, LOW);  delay(200);
  }
}

byte adhoc = 0; // 1 - adhoc connection or 0 - connected to AP

void setup() {
  uint8_t ret;

  loadConfig();

  blink(LEDPIN, 1);

  //init the WiFi module on the shield
  ret = RedFly.init(115200, HIGH_POWER); //LOW_POWER MED_POWER HIGH_POWER
  if (!ret) {
    RedFly.scan();
    adhoc = ret = RedFly.join(WiFiConfig.ssid, WiFiConfig.pwd, INFRASTRUCTURE);
    if (ret) {
      char network[16];
      sprintf(network, "TestNetwork%d", WiFiConfig.id);
      ret = RedFly.join(network, IBSS_CREATOR, 10);
    }
    if (!ret) {
      currentIP = adhoc ? serverIP : WiFiConfig.addr;
      ret = RedFly.begin(currentIP, gateway, netmask);
    }
  }

  if (adhoc) { // only open DHCP/DNS ports in adhoc config
    // listen for DHCP messages on DHCP_SERVER_PORT (UDP)
    hDHCP = RedFly.socketListen(PROTO_UDP, DHCP_SERVER_PORT);
    // listen for DNS messages on DNS_SERVER_PORT (both UDP and TCP on the same port)
    hDNSTCP = RedFly.socketListen(PROTO_TCP, DNS_SERVER_PORT);
    hDNSUDP = RedFly.socketListen(PROTO_UDP, DNS_SERVER_PORT);
  }

  // listen for UDP messages on port 80 (to test echo)
  hHTTPUDP = RedFly.socketListen(PROTO_UDP, HTTP_SERVER_PORT);

  // 10 blinks on error, 5 blinks on AP connection and 3 blinks on adhoc connection
  blink(LEDPIN, ret ? 10 : (adhoc ? 3 : 5));
}

void loop()
{
  uint8_t sock, *ptr, buf[DHCP_MESSAGE_SIZE]; 
  uint16_t buf_len, rd, len;
  uint16_t port; //incoming UDP port
  uint8_t ip[4]; //incoming UDP ip

  //check if socket is closed and start listening
  if (hHTTPTCP == 0xFF || RedFly.socketClosed(hHTTPTCP)) hHTTPTCP = RedFly.socketListen(PROTO_TCP, HTTP_SERVER_PORT); // start listening on port 80

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
      buf_len = DHCPreply((RIP_MSG*)buf, buf_len, currentIP, domainName); // zero returned means the message was not recognized
      if (buf_len) RedFly.socketSend(sock, buf, buf_len, broadcast, port);
    }
    else if (sock == hDNSTCP || sock == hDNSUDP) {
      buf_len = DNSreply((DNS_MSG*)buf, buf_len, currentIP, serverName); // zero returned means the message was not recognized
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
      const char *STYLE = PSTR("\r\n<html style='font-family:Verdana,Geneva,Georgia,Chicago,Arial,Sans-serif;color:#002d80'>");
      int pin, value;
      char mode, ignore;
      char *out = (char *)buf;

      if (strncmp_P(out, PSTR("GET / HTTP"), 10) == 0) {
        RedFly.socketSendPGM(sock, OK);
        RedFly.socketSendPGM(sock, STYLE);
        RedFly.socketSendPGM(sock, PSTR("Hello, World!<br/><br/>You can <a href='/wifi'>update wifi configuration</a>, <a href='/D13=1'>turn LED on (digital pin 13)</a>, or <a href='/A1'>display analog (A1) sensor values</a>"));
        RedFly.socketClose(sock);      
      }
      else if (strncmp_P(out, PSTR("GET /wifi HTTP"), 14) == 0) {
        RedFly.socketSendPGM(sock, OK);
        RedFly.socketSendPGM(sock, STYLE);
        RedFly.socketSendPGM(sock, PSTR("<form method='post'>Wifi configuration<p>SSID: <input style='margin-left:48px' value='"));
        RedFly.socketSend(sock, (uint8_t*)WiFiConfig.ssid, strlen(WiFiConfig.ssid));
        RedFly.socketSendPGM(sock, PSTR("' name='s'/><br/>Password: <input type='password' name='p' style='margin-left:10px'/><br/>IP address: <input name='a' value='"));
        sprintf(out, "%d.%d.%d.%d", WiFiConfig.addr[0], WiFiConfig.addr[1], WiFiConfig.addr[2], WiFiConfig.addr[3]);
        RedFly.socketSend(sock, (uint8_t*)out, strlen(out));
        RedFly.socketSendPGM(sock, PSTR("'/> (xxx.xxx.xxx.xxx)<br/><br/>Clicking <input type='submit' value='Update'/> will update the configuration and restart the board.</p></form></html>"));
        RedFly.socketClose(sock);
      }
      else if (strncmp_P(out, PSTR("POST /wifi HTTP"), 15) == 0) {
        char *st, *fi;
        char *a = NULL, *p = NULL, *s = NULL;
        out[buf_len] = '\0';
        if (st = strstr(out, "a="))
          if (sscanf(st+2, "%d.%d.%d.%d", WiFiConfig.addr, WiFiConfig.addr+1, WiFiConfig.addr+2, WiFiConfig.addr+3) == 4) a = st+2;
        if (st = strstr(out, "p="))
          if (fi = strstr(st, "&")) { fi[0] = '\0'; p = st+2; }
        if (st = strstr(out, "s="))
          if (fi = strstr(st, "&")) { fi[0] = '\0'; s = st+2; }

        RedFly.socketSendPGM(sock, OK);
        RedFly.socketSendPGM(sock, STYLE);
        if (a && p && s) {
          strcpy(WiFiConfig.pwd, p);
          strcpy(WiFiConfig.ssid, s);
          saveConfig();
          RedFly.socketSendPGM(sock, PSTR("Updated. The board has been restarted with the new configuration.</html>"));
          RedFly.socketClose(sock);

          // restart Arduino by calling a (pseudo)function at address 0
          void(* reset) (void) = 0; // declare reset function @ address 0
          reset();
        }
        else {
          RedFly.socketSendPGM(sock, PSTR("Error. Please return back and update the configuration.</html>"));
          RedFly.socketClose(sock);
        }
      }
      else if (sscanf_P(out, PSTR("GET /D%2d=%1d HTTP"), &pin, &value) == 2) {
        pinMode(pin, OUTPUT);
        digitalWrite(pin, value ? HIGH : LOW);

        const char * SetPinMessage = PSTR("Set digital pin %d to %d; <a href='/D%d=%d'>toggle</a>");
        sprintf_P(out, SetPinMessage, pin, !!value, pin, !value);

        RedFly.socketSendPGM(sock, OK);
        RedFly.socketSendPGM(sock, STYLE);
        RedFly.socketSend(sock, out);
        RedFly.socketClose(sock);
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

