// 列出 AppleSMC（VirtualSMC）裡所有溫度（T*）、風扇（F*）、功耗（P*）key 的值。只讀。
// cc -O2 -framework IOKit -framework CoreFoundation tools/smcdump.c -o /tmp/smcdump && /tmp/smcdump
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
typedef struct { char major, minor, build, reserved[1]; uint16_t release; } V;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } P;
typedef struct { uint32_t dataSize, dataType; char dataAttributes; } K;
typedef struct { uint32_t key; V vers; P pLimitData; K keyInfo; char result, status, data8; uint32_t data32; uint8_t bytes[32]; } D;
static io_connect_t c;
static uint32_t s2k(const char *s){ return (s[0]<<24)|(s[1]<<16)|(s[2]<<8)|s[3]; }
static void k2s(uint32_t k, char *s){ s[0]=k>>24; s[1]=k>>16; s[2]=k>>8; s[3]=k; s[4]=0; }
static int call(D *in, D *out){ size_t o=sizeof(D); return IOConnectCallStructMethod(c, 2, in, sizeof(D), out, &o); }
static int info(uint32_t key, K *ki){ D i={0},o={0}; i.key=key; i.data8=9; if(call(&i,&o)||o.result) return -1; *ki=o.keyInfo; return 0; }
static int readk(uint32_t key, K *ki, uint8_t *b){ D i={0},o={0}; if(info(key,ki)) return -1; i.key=key; i.keyInfo.dataSize=ki->dataSize; i.data8=5; if(call(&i,&o)||o.result) return -1; memcpy(b,o.bytes,32); return 0; }
static double val(K *ki, uint8_t *b){
  char t[5]; k2s(ki->dataType,t);
  if(!strcmp(t,"sp78")) return (int16_t)((b[0]<<8)|b[1])/256.0;
  if(!strcmp(t,"fpe2")) return ((b[0]<<8)|b[1])/4.0;
  if(!strcmp(t,"flt ")) { float f; memcpy(&f,b,4); return f; }
  if(!strcmp(t,"ui8 ")) return b[0];
  if(!strcmp(t,"ui16")) return (b[0]<<8)|b[1];
  if(!strcmp(t,"ui32")) return (uint32_t)((b[0]<<24)|(b[1]<<16)|(b[2]<<8)|b[3]);
  return -9999;
}
int main(int argc, char **argv){
  io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
  if(!s || IOServiceOpen(s, mach_task_self(), 0, &c)) { fprintf(stderr,"open AppleSMC failed\n"); return 1; }
  K ki; uint8_t b[32];
  if(argc > 1){ for(int a=1;a<argc;a++){ if(!readk(s2k(argv[a]),&ki,b)) printf("%s=%.1f ", argv[a], val(&ki,b)); } printf("\n"); return 0; }
  if(readk(s2k("#KEY"),&ki,b)) { fprintf(stderr,"#KEY failed\n"); return 1; }
  uint32_t n=(b[0]<<24)|(b[1]<<16)|(b[2]<<8)|b[3];
  printf("%u keys\n", n);
  for(uint32_t i=0;i<n;i++){
    D in={0},out={0}; in.data8=8; in.data32=i; if(call(&in,&out)) continue;
    char ks[5]; k2s(out.key,ks);
    if(ks[0]!='T' && ks[0]!='F' && ks[0]!='P') continue;
    if(readk(out.key,&ki,b)) continue;
    char t[5]; k2s(ki.dataType,t);
    double v=val(&ki,b); if(v==-9999) continue;
    printf("%s [%s] %.2f\n", ks, t, v);
  }
  return 0;
}
