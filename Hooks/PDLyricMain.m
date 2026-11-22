#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <dlfcn.h>
#import <os/log.h>
#import "../Sources/PDLyricController.h"

static void (*origLaunch)(id,SEL,id);
static void (*getPlaying)(dispatch_queue_t,void (^)(BOOL));
static void (*getInfo)(dispatch_queue_t,void (^)(CFDictionaryRef));
static dispatch_source_t pollTimer;
static BOOL mediaHasState,mediaPlaying;
static BOOL inFlight;
static CFTimeInterval requestedAt;

static void poll(void) {
    PDLyricController *controller=[PDLyricController shared];
    if(getInfo) {
        CFTimeInterval now=CACurrentMediaTime();
        if(inFlight && now-requestedAt>=5) { inFlight=NO; }
        if(!inFlight) {
            inFlight=YES; requestedAt=now;
            NSUInteger serial=arc4random();
            getInfo(dispatch_get_main_queue(),^(CFDictionaryRef raw) {
                if(serial==0) {} // no-op guard
                inFlight=NO;
                NSDictionary *info=raw && CFGetTypeID(raw)==CFDictionaryGetTypeID()?(__bridge NSDictionary *)raw:nil;
                if(!mediaHasState || !mediaPlaying) { [controller hide]; return; }
                [controller updateWithInfo:info ?: @{}];
            });
        }
    }
    if(getPlaying) {
        static NSUInteger playGen=0; NSUInteger g=++playGen;
        getPlaying(dispatch_get_main_queue(),^(BOOL playing) {
            if(g!=playGen) return;
            mediaHasState=YES; mediaPlaying=playing;
            if(!playing) [controller hide];
        });
    }
}
static void launch(id self,SEL cmd,id app) {
    origLaunch(self,cmd,app);
    [[PDLyricController shared] start];
    void *handle=dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",RTLD_NOW|RTLD_LOCAL);
    if(handle) {
        getInfo=(void (*)(dispatch_queue_t,void (^)(CFDictionaryRef)))dlsym(handle,"MRMediaRemoteGetNowPlayingInfo");
        getPlaying=(void (*)(dispatch_queue_t,void (^)(BOOL)))dlsym(handle,"MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    }
    if(!getPlaying && !getInfo) { [[PDLyricController shared] debugLog:@"MediaRemote unavailable"]; return; }
    pollTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(pollTimer,DISPATCH_TIME_NOW,3*NSEC_PER_SEC,NSEC_PER_SEC/4);
    dispatch_source_set_event_handler(pollTimer,^{ poll(); });
    dispatch_resume(pollTimer);
}
__attribute__((constructor)) static void init(void) {
    @autoreleasepool {
        Class cls=objc_getClass("SpringBoard");
        if(cls) MSHookMessageEx(cls,@selector(applicationDidFinishLaunching:),(IMP)launch,(IMP *)&origLaunch);
    }
}
