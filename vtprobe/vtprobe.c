// vtprobe: which codecs VideoToolbox thinks are hardware-decodable here, and whether a decoder session opens.
#include <VideoToolbox/VideoToolbox.h>
#include <stdio.h>
static void probe(const char *name, CMVideoCodecType t) {
    Boolean hw = VTIsHardwareDecodeSupported(t);
    CMVideoFormatDescriptionRef fd = NULL;
    OSStatus s = CMVideoFormatDescriptionCreate(NULL, t, 1920, 1080, NULL, &fd);
    OSStatus sw = -1, hwreq = -1;
    if (s == noErr) {
        VTDecompressionSessionRef ses = NULL;
        sw = VTDecompressionSessionCreate(NULL, fd, NULL, NULL, NULL, &ses);   // default: HW if available, else SW
        if (ses) { VTDecompressionSessionInvalidate(ses); CFRelease(ses); ses = NULL; }
        const void *k[] = { kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder };
        const void *v[] = { kCFBooleanTrue };
        CFDictionaryRef spec = CFDictionaryCreate(NULL, k, v, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        hwreq = VTDecompressionSessionCreate(NULL, fd, spec, NULL, NULL, &ses);
        if (ses) { VTDecompressionSessionInvalidate(ses); CFRelease(ses); }
        CFRelease(spec); CFRelease(fd);
    }
    printf("%-5s HW supported=%d  session(default)=%d  session(HW required)=%d\n", name, hw, (int)sw, (int)hwreq);
}
int main(void) {
    probe("H264", kCMVideoCodecType_H264);
    probe("HEVC", kCMVideoCodecType_HEVC);
    probe("VP9", 'vp09');
    probe("AV1", 'av01');
    return 0;
}
