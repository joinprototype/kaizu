// A standalone H.264 sender using public VideoToolbox APIs and generated NV12 frames.
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <stdatomic.h>
#import <unistd.h>

static _Atomic int frames, callbacks, callbackError, dropped;
static _Atomic unsigned long bytes;

static void encoded(void *context, void *frame, OSStatus status, VTEncodeInfoFlags flags, CMSampleBufferRef sample) {
    atomic_fetch_add(&callbacks, 1);
    if (status) atomic_store(&callbackError, status);
    if (flags & kVTEncodeInfo_FrameDropped) atomic_fetch_add(&dropped, 1);
    if (sample && CMSampleBufferDataIsReady(sample) && CMSampleBufferGetTotalSampleSize(sample) > 0) {
        atomic_fetch_add(&frames, 1);
        atomic_fetch_add(&bytes, CMSampleBufferGetTotalSampleSize(sample));
    }
}

static NSString *property(VTCompressionSessionRef session, CFStringRef key) {
    CFTypeRef value = NULL;
    if (VTSessionCopyProperty(session, key, NULL, &value) || !value) return @"unreported";
    return [CFBridgingRelease(value) description];
}

static OSStatus sendFrame(VTCompressionSessionRef session, int index, size_t width, size_t height) {
    CVPixelBufferRef buffer = NULL;
    NSDictionary *attributes = @{(__bridge id)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    OSStatus status = CVPixelBufferCreate(NULL, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                         (__bridge CFDictionaryRef)attributes, &buffer);
    if (status) return status;
    status = CVPixelBufferLockBaseAddress(buffer, 0);
    if (!status) {
        const size_t yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0);
        const size_t uvStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1);
        memset(CVPixelBufferGetBaseAddressOfPlane(buffer, 0), index % 2 ? 81 : 41, yStride * height);
        uint8_t *chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1);
        for (size_t row = 0; row < height / 2; row++) {
            for (size_t x = 0; x < width; x += 2) {
                chroma[row * uvStride + x] = index % 2 ? 90 : 240;
                chroma[row * uvStride + x + 1] = index % 2 ? 240 : 110;
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        status = VTCompressionSessionEncodeFrame(session, buffer, CMTimeMake(index, 10), CMTimeMake(1, 10),
                                                 NULL, NULL, NULL);
    }
    CVPixelBufferRelease(buffer);
    return status;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSString *size = [NSString stringWithUTF8String:argv[2]];
        if (!([size isEqual:@"160x90"] || [size isEqual:@"640x480"])) return 2;
        int width = [size isEqual:@"160x90"] ? 160 : 640;
        int height = [size isEqual:@"160x90"] ? 90 : 480;
        NSDictionary *spec = @{};
        if (!strcmp(argv[1], "low-latency")) {
            spec = @{(__bridge id)kVTVideoEncoderSpecification_EnableLowLatencyRateControl: @YES};
        } else if (strcmp(argv[1], "default")) {
            return 2;
        }
        VTCompressionSessionRef session = NULL;
        OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264,
            (__bridge CFDictionaryRef)spec, NULL, NULL, encoded, NULL, &session);
        if (status) {
            printf("VideoToolbox mode=%s size=%s create=%d\n", argv[1], argv[2], (int)status);
            return 1;
        }
        NSDictionary *properties = @{
            (__bridge id)kVTCompressionPropertyKey_RealTime: @YES,
            (__bridge id)kVTCompressionPropertyKey_AllowFrameReordering: @NO,
            (__bridge id)kVTCompressionPropertyKey_ProfileLevel: (__bridge id)kVTProfileLevel_H264_High_AutoLevel,
            (__bridge id)kVTCompressionPropertyKey_ExpectedFrameRate: @10,
            (__bridge id)kVTCompressionPropertyKey_AverageBitRate: @190000,
        };
        OSStatus settings = VTSessionSetProperties(session, (__bridge CFDictionaryRef)properties);
        OSStatus prepare = VTCompressionSessionPrepareToEncodeFrames(session);
        NSString *identifier = property(session, kVTCompressionPropertyKey_EncoderID);
        NSString *hardware = property(session, kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder);
        int submitted = 0;
        OSStatus firstError = 0;
        for (int i = 0; i < 15; i++) {
            OSStatus result = sendFrame(session, i, width, height);
            if (result && !firstError) firstError = result;
            if (!result) submitted++;
            usleep(100000);
        }
        OSStatus flush = VTCompressionSessionCompleteFrames(session, kCMTimeInvalid);
        VTCompressionSessionInvalidate(session);
        CFRelease(session);
        printf("VideoToolbox mode=%s size=%s encoder=%s hardware=%s settings=%d prepare=%d submitted=%d "
               "firstError=%d flush=%d callbacks=%d callbackError=%d dropped=%d frames=%d bytes=%lu\n",
               argv[1], argv[2], identifier.UTF8String, hardware.UTF8String, (int)settings, (int)prepare, submitted,
               (int)firstError, (int)flush, atomic_load(&callbacks), atomic_load(&callbackError),
               atomic_load(&dropped), atomic_load(&frames), atomic_load(&bytes));
        return settings || prepare || firstError || flush || atomic_load(&callbackError) || !atomic_load(&frames);
    }
}
