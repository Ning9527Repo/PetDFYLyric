#import "PDLyricController.h"
#import "PDLyricLogic.h"
#import <QuartzCore/QuartzCore.h>
#import <os/log.h>

@interface PDLyricWindow : UIWindow
@property(nonatomic) BOOL allowKey;
@end
@implementation PDLyricWindow
- (BOOL)canBecomeKeyWindow { return self.allowKey; }
- (BOOL)_canBecomeKeyWindow { return self.allowKey; }
- (BOOL)_disableAutomaticKeyboardUI { return YES; }
- (BOOL)_disableAutomaticKeyboardBehavior { return YES; }
@end

@interface PDLyricController () {
    NSString *_cachedIdentity,*_fetchingIdentity,*_failureIdentity;
    NSArray *_timeline;
    NSTimeInterval _nextRetry;
    NSUInteger _generation;
}
@property(nonatomic,strong) PDLyricWindow *window;
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,copy) NSString *currentLine;
@end
@implementation PDLyricController
+ (instancetype)shared { static id instance; static dispatch_once_t once; dispatch_once(&once,^{ instance=[self new]; }); return instance; }
- (instancetype)init {
    if(!(self=[super init])) return nil;
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest=12; config.timeoutIntervalForResource=15;
    config.URLCache=nil; config.HTTPCookieStorage=nil; config.URLCredentialStorage=nil;
    _session=[NSURLSession sessionWithConfiguration:config];
    return self;
}
- (void)start {
    // A tiny overlay near the bottom edge that is always above app windows but below status bar.
    self.window=[[PDLyricWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.windowLevel=UIWindowLevelStatusBar-1;
    self.window.backgroundColor=UIColor.clearColor;
    self.window.userInteractionEnabled=NO;
    UIViewController *vc=[UIViewController new]; vc.view.backgroundColor=UIColor.clearColor;
    self.window.rootViewController=vc;
    self.label=[UILabel new];
    self.label.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.label.textColor=UIColor.whiteColor;
    self.label.backgroundColor=[UIColor colorWithWhite:0 alpha:.55];
    self.label.textAlignment=NSTextAlignmentCenter;
    self.label.layer.cornerRadius=14; self.label.clipsToBounds=YES;
    self.label.hidden=YES; self.label.userInteractionEnabled=NO;
    self.label.numberOfLines=2;
    self.label.frame=CGRectMake(24,0,self.window.bounds.size.width-48,52);
    [self.label setCenter:CGPointMake(self.window.bounds.size.width/2,self.window.bounds.size.height-54)];
    [vc.view addSubview:self.label];
    self.window.hidden=NO;
    os_log(os_log_create("com.ning.petdfylyric","lyric"),"Overlay ready");
}
- (NSString *)identityForTitle:(NSString *)title artist:(NSString *)artist duration:(double)duration {
    if(![title isKindOfClass:NSString.class] || !title.length) return nil;
    NSString *h=[NSString stringWithFormat:@"%@|%@|%.1f",title,[artist isKindOfClass:NSString.class]?artist:@"",duration];
    return h.length>260?nil:h;
}
- (void)startFetchIdentity:(NSString *)identity title:(NSString *)title artist:(NSString *)artist duration:(double)duration {
    if(!identity || [_fetchingIdentity isEqual:identity]) return;
    CFTimeInterval now=CACurrentMediaTime();
    if([_failureIdentity isEqual:identity] && now<_nextRetry) return;
    NSURL *url=PDLyric_searchURL(title,artist);
    if(!url) return;
    _fetchingIdentity=identity;
    NSUInteger generation=++_generation;
    __weak typeof(self) weak=self;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];
    [request setValue:@"PetDFYLyric-Minis/1.0" forHTTPHeaderField:@"User-Agent"];
    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{
            typeof(self) self=weak; if(!self || generation!=self->_generation) return;
            self->_fetchingIdentity=nil;
            NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
            if(error || status!=200 || !data || data.length>1<<20) {
                self->_failureIdentity=identity; self->_nextRetry=CACurrentMediaTime()+60;
                [self show:@"歌词获取失败（网络）"]; return;
            }
            id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *timeline=PDLyric_pickTimeline(json,duration);
            if(!timeline.count) { self->_failureIdentity=identity; self->_nextRetry=CACurrentMediaTime()+120; [self show:@"未找到同步歌词"]; return; }
            self->_cachedIdentity=identity; self->_timeline=timeline; self->_failureIdentity=nil;
        });
    }] resume];
}
- (void)updateWithInfo:(NSDictionary *)info {
    id title=info[@"kMRMediaRemoteNowPlayingInfoTitle"], artist=info[@"kMRMediaRemoteNowPlayingInfoArtist"], duration=info[@"kMRMediaRemoteNowPlayingInfoDuration"];
    double dur=[duration isKindOfClass:NSNumber.class]?[duration doubleValue]:0;
    NSString *identity=[self identityForTitle:title artist:artist duration:dur];
    if(!identity) { [self hide]; return; }
    if([identity isEqual:_cachedIdentity] && _timeline.count) {
        id elapsed=info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"], timestamp=info[@"kMRMediaRemoteNowPlayingInfoTimestamp"], rateObj=info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
        if(![elapsed isKindOfClass:NSNumber.class] || ![timestamp isKindOfClass:NSDate.class] || ![rateObj isKindOfClass:NSNumber.class]) { [self hide]; return; }
        NSTimeInterval wallNow=NSDate.date.timeIntervalSince1970;
        double rate=[rateObj doubleValue];
        if(!isfinite(rate) || rate<0.5 || rate>2) { [self hide]; return; }
        double wallDelta=wallNow-[timestamp timeIntervalSince1970];
        if(wallDelta < -2 || wallDelta > 8) { [self hide]; return; }
        double position=[elapsed doubleValue]+MAX(0,wallDelta)*rate;
        NSString *line=PDLyric_lineAt(_timeline,position);
        [self show:line ?: @""];
        return;
    }
    [self startFetchIdentity:identity title:title artist:artist duration:dur];
    [self hide];
}
- (void)show:(NSString *)text {
    if(!self.window || !text.length) { [self hide]; return; }
    self.label.text=text;
    self.label.accessibilityLabel=[@"歌词：" stringByAppendingString:text];
    self.label.hidden=NO;
}
- (void)hide { if(self.label) self.label.hidden=YES; }
- (void)debugLog:(NSString *)line { os_log(os_log_create("com.ning.petdfylyric","lyric"),"%{public}@",line); }
@end
