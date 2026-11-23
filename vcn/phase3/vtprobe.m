// 階段 3 可行性：只讀，問 VideoToolbox 這台機器每種 codec 有沒有硬解、實際建出來的解碼器是哪一個。
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreMedia/CoreMedia.h>
static const char *fcc(uint32_t c){static char s[5];s[0]=c>>24;s[1]=c>>16;s[2]=c>>8;s[3]=c;s[4]=0;return s;}
int main(void){@autoreleasepool{
  CMVideoCodecType cs[]={kCMVideoCodecType_H264,kCMVideoCodecType_HEVC,kCMVideoCodecType_VP9,'av01',kCMVideoCodecType_MPEG4Video,kCMVideoCodecType_AppleProRes422};
  for(int i=0;i<6;i++) printf("%s VTIsHardwareDecodeSupported=%d\n",fcc(cs[i]),VTIsHardwareDecodeSupported(cs[i]));
  extern OSStatus VTCopyVideoDecoderList(CFDictionaryRef,CFArrayRef*); CFArrayRef list=NULL; VTCopyVideoDecoderList(NULL,&list);
  printf("== decoder list (%ld)\n",list?CFArrayGetCount(list):0);
  for(CFIndex i=0;list&&i<CFArrayGetCount(list);i++) NSLog(@"%@",((__bridge NSArray*)list)[i]);
  // 實際建一個 H.264 / HEVC session（只用 format description，不送資料），看用了哪個解碼器
  for(int k=0;k<2;k++){
    CMVideoCodecType c=k?kCMVideoCodecType_HEVC:kCMVideoCodecType_H264;
    CMVideoFormatDescriptionRef fd=NULL;
    if(k==0){ // 1920x1080 High profile 最小 SPS/PPS
      const uint8_t sps[]={0x67,0x64,0x00,0x28,0xac,0xd9,0x40,0x78,0x02,0x27,0xe5,0x84,0x00,0x00,0x03,0x00,0x04,0x00,0x00,0x03,0x00,0xf0,0x3c,0x60,0xc6,0x58};
      const uint8_t pps[]={0x68,0xeb,0xe3,0xcb,0x22,0xc0};
      const uint8_t *p[]={sps,pps}; size_t n[]={sizeof sps,sizeof pps};
      OSStatus s=CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL,2,p,n,4,&fd); if(s){printf("fd err %d\n",(int)s);continue;}
    } else { CMVideoFormatDescriptionCreate(NULL,c,1920,1080,NULL,&fd); }
    for(int req=0;req<2;req++){
      NSDictionary *spec=req?@{(id)kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder:@YES}:@{};
      VTDecompressionSessionRef ses=NULL;
      OSStatus s=VTDecompressionSessionCreate(NULL,fd,(__bridge CFDictionaryRef)spec,NULL,NULL,&ses);
      printf("%s requireHW=%d create=%d\n",fcc(c),req,(int)s);
      if(!s){ CFBooleanRef hw=NULL; VTSessionCopyProperty(ses,kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,NULL,&hw);
        printf("  UsingHW=%d\n",hw==kCFBooleanTrue); VTDecompressionSessionInvalidate(ses); CFRelease(ses);}
    }
  }
}}
