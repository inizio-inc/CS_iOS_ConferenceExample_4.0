/*
 * Copyright © 2016 Intel Corporation. All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


#import <AVFoundation/AVFoundation.h>
#import <AFNetworking/AFNetworking.h>
#import <ICS/ICS.h>
#import "ConferenceStreamViewController.h"
#import "HorizontalSegue.h"
#import "BrightenFilter.h"

@interface ConferenceStreamViewController () <StreamViewDelegate, ICSRemoteMixedStreamDelegate>

@property(strong, nonatomic) ICSRemoteStream* remoteStream;
@property(strong, nonatomic) ICSRemoteStream* screenStream;
@property(strong, nonatomic) ICSConferenceClient* conferenceClient;
@property(strong, nonatomic) ICSConferencePublication* publication;
@property(strong, nonatomic) ICSConferenceSubscription* subscription;

- (void)handleLocalPreviewOrientation;
- (void)handleSwipeGuesture:(UIScreenEdgePanGestureRecognizer*)sender;


@end

@implementation ConferenceStreamViewController{
  NSTimer* _getStatsTimer;
  RTCVideoSource* _source;
  RTCPeerConnectionFactory* _factory;
  RTCCameraVideoCapturer* _capturer;
  BOOL _subscribedMix;
  BrightenFilter* _filter;
  NSString* _url;
}

- (void)showMsg: (NSString *)msg
{
  UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"" message:msg preferredStyle:UIAlertControllerStyleAlert];
  UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
  [alertController addAction:okAction];
  [self presentViewController:alertController animated:YES completion:nil];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor clearColor];
  appDelegate = (AppDelegate*)[[UIApplication sharedApplication]delegate];
  _conferenceClient=[appDelegate conferenceClient];
  _factory = [[RTCPeerConnectionFactory alloc] init];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onStreamAddedNotification:) name:@"OnStreamAdded" object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onOrientationChangedNotification:) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
  UIScreenEdgePanGestureRecognizer *edgeGestureRecognizer = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeGuesture:)];
  edgeGestureRecognizer.delegate=self;
  edgeGestureRecognizer.edges=UIRectEdgeLeft;
  [self.view addGestureRecognizer:edgeGestureRecognizer];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [self doPublish];
  });
  if (@available(iOS 11.0, *)) {
    [self setNeedsUpdateOfHomeIndicatorAutoHidden];
  }
}

- (void)viewWillAppear:(BOOL)animated {
  [self handleLocalPreviewOrientation];
}


-(void)loadView {
  [super loadView];
  _streamView=[[StreamView alloc]init];
  _streamView.delegate=self;
  self.view=_streamView;
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}

- (void)handleSwipeGuesture:(UIScreenEdgePanGestureRecognizer*)sender{
  if(sender.state==UIGestureRecognizerStateEnded){
    [_conferenceClient leaveWithOnSuccess:^{
      [self quitConference];
    } onFailure:^(NSError* err){
      [self quitConference];
      NSLog(@"Failed to leave. %@",err);
    }];
  }
}

- (void)handleLocalPreviewOrientation{
  UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
  switch(orientation){
      case UIInterfaceOrientationLandscapeLeft:
      [self.streamView.localVideoView setTransform:CGAffineTransformMakeRotation(M_PI_2)];
      break;
      case UIInterfaceOrientationLandscapeRight:
      [self.streamView.localVideoView setTransform:CGAffineTransformMakeRotation(M_PI+M_PI_2)];
      break;
    default:
      NSLog(@"Unsupported orientation.");
      break;
  }
}

- (void)quitConference{
  dispatch_async(dispatch_get_main_queue(), ^{
    _localStream = nil;
    [_getStatsTimer invalidate];
    if(_capturer){
      [_capturer stopCapture];
    }
    _conferenceClient=nil;
    [self performSegueWithIdentifier:@"Back" sender:self];
  });
}

- (void) quitBtnDidTouchedDown:(StreamView *)view {
  [_conferenceClient leaveWithOnSuccess:^{
    [self quitConference];
  } onFailure:^(NSError* err){
    [self quitConference];
    NSLog(@"Failed to leave. %@",err);
  }];
}

- (void)onStreamRemovedNotification:(NSNotification*)notification {
  NSDictionary* userInfo = notification.userInfo;
  ICSRemoteStream* stream = userInfo[@"stream"];
  NSLog(@"A stream was removed from %@", stream.origin);
  [self onRemoteStreamRemoved:stream];
}

- (void)onStreamAddedNotification:(NSNotification*)notification {
  NSDictionary* userInfo = notification.userInfo;
  ICSRemoteStream* stream = userInfo[@"stream"];
  NSLog(@"New stream add from %@", stream.origin);
  [self onRemoteStreamAdded:stream];
}

-(void)onOrientationChangedNotification:(NSNotification*)notification{
  [self handleLocalPreviewOrientation];
}

- (void)onRemoteStreamRemoved:(ICSRemoteStream*)remoteStream {
  if (remoteStream.source.video==ICSVideoSourceInfoScreenCast) {
    _screenStream = nil;
    [self subscribe];
  }
}

- (void)onRemoteStreamAdded:(ICSRemoteStream*)remoteStream {
  if (remoteStream.source.video==ICSVideoSourceInfoScreenCast) {
    _screenStream = remoteStream;
    [self subscribe];
  }
}

// Try to subscribe screen sharing stream is available, otherwise, subscribe
// mixed stream.
- (void)subscribe {
  if (_screenStream) {
    [_conferenceClient subscribe:_screenStream withOptions: nil
                       onSuccess:^(ICSConferenceSubscription* _Nonnull subscription) {
                         subscription.delegate=self;
                         dispatch_async(dispatch_get_main_queue(), ^{
                           NSLog(@"Subscribe screen stream success.");
                           //[_screenStream attach:((StreamView*)self.view).remoteVideoView];
                           [_streamView.act stopAnimating];
                         });
                       }
                       onFailure:^(NSError* _Nonnull err) {
                         NSLog(@"Subscribe screen stream failed. Error: %@",
                               [err localizedDescription]);
                       }];
  } else {
    ICSConferenceSubscribeOptions* subOption =
    [[ICSConferenceSubscribeOptions alloc] init];
    subOption.video=[[ICSConferenceVideoSubscriptionConstraints alloc]init];
    int width = INT_MAX;
    int height = INT_MAX;
    for (NSValue* value in appDelegate.mixedStream.capabilities.video.resolutions) {
      CGSize resolution=[value CGSizeValue];
      if (resolution.width == 640 && resolution.height == 480) {
        width = resolution.width;
        height = resolution.height;
        break;
      }
      if (resolution.width < width && resolution.height != 0) {
        width = resolution.width;
        height = resolution.height;
      }
    }
    [[AVAudioSession sharedInstance]
     overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker
     error:nil];
    [_conferenceClient subscribe:appDelegate.mixedStream
                     withOptions:subOption
                       onSuccess:^(ICSConferenceSubscription* subscription) {
                         _subscription=subscription;
                         _subscription.delegate=self;
                         _getStatsTimer = [NSTimer timerWithTimeInterval:1.0
                                                                  target:self
                                                                selector:@selector(printStats)
                                                                userInfo:nil
                                                                 repeats:YES];
                         [[NSRunLoop mainRunLoop] addTimer:_getStatsTimer
                                                   forMode:NSDefaultRunLoopMode];
                         dispatch_async(dispatch_get_main_queue(), ^{
                           _remoteStream = appDelegate.mixedStream;
                           NSLog(@"Subscribe stream success.");
                           [_remoteStream attach:((StreamView*)self.view).remoteVideoView];
                           [_streamView.act stopAnimating];
                           _subscribedMix = YES;
                         });
                       }
                       onFailure:^(NSError* err) {
                         NSLog(@"Subscribe stream failed. %@", [err localizedDescription]);
                       }];
  }
}

-(void)doPublish{
  if (_localStream == nil) {
#if TARGET_IPHONE_SIMULATOR
    NSLog(@"Camera is not supported on simulator");
    ICSStreamConstraints* constraints=[[ICSStreamConstraints alloc]init];
    constraints.audio=YES;
    constraints.video=nil;
#else
    /* Create LocalStream with constraints */
    ICSStreamConstraints* constraints=[[ICSStreamConstraints alloc] init];
    constraints.audio=YES;
    constraints.video=[[ICSVideoTrackConstraints alloc] init];
    constraints.video.frameRate=24;
    constraints.video.resolution=CGSizeMake(640,480);
    constraints.video.devicePosition=AVCaptureDevicePositionFront;
#endif
    NSError *err=[[NSError alloc]init];
    _localStream=[[ICSLocalStream alloc] initWithConstratins:constraints error:&err];
#if TARGET_IPHONE_SIMULATOR
    NSLog(@"Stream does not have video track.");
#else
    _source = [_factory videoSource];
    _capturer = [[RTCCameraVideoCapturer alloc] initWithDelegate:_source];
    
    dispatch_async(dispatch_get_main_queue(), ^{
      [((StreamView *)self.view).localVideoView setCaptureSession:[_capturer captureSession] ];
    });
    
//    [self startCapture];
#endif
    ICSPublishOptions* options=[[ICSPublishOptions alloc] init];
    ICSAudioCodecParameters* opusParameters=[[ICSAudioCodecParameters alloc] init];
    opusParameters.name=ICSAudioCodecOpus;
    ICSAudioEncodingParameters *audioParameters=[[ICSAudioEncodingParameters alloc] init];
    audioParameters.codec=opusParameters;
    options.audio=[NSArray arrayWithObjects:audioParameters, nil];
    ICSVideoCodecParameters *h264Parameters=[[ICSVideoCodecParameters alloc] init];
    h264Parameters.name=ICSVideoCodecH264;
    ICSVideoEncodingParameters *videoParameters=[[ICSVideoEncodingParameters alloc]init];
    videoParameters.codec=h264Parameters;
    options.video=[NSArray arrayWithObjects:videoParameters, nil];
    [_conferenceClient publish:_localStream withOptions:nil onSuccess:^(ICSConferencePublication* p) {
      _publication=p;
      _publication.delegate=self;
      [self mixToCommonView:p];
      dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"publish success!");
      });
    } onFailure:^(NSError* err) {
      NSLog(@"publish failure!");
      [self showMsg:[err localizedFailureReason]];
    }];
    _screenStream=appDelegate.screenStream;
    _remoteStream=appDelegate.mixedStream;
    [self subscribe];
  }
}

- (AVCaptureDevice *) getDevice {
  for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]){
    if (d.position == AVCaptureDevicePositionFront){
      return d;
    }
  }
  return nil;
}

- (void) startCapture {
  AVCaptureDevice* device = [self getDevice];
  AVCaptureDeviceFormat* format=nil;
  NSArray<AVCaptureDeviceFormat*> *formats=[RTCCameraVideoCapturer supportedFormatsForDevice:device];
  for(AVCaptureDeviceFormat* f in formats){
    CMVideoDimensions dimension=CMVideoFormatDescriptionGetDimensions(f.formatDescription);
    if(dimension.width==1920&&dimension.height==1080){
      format=f;
      break;
    }
  }
  
  Float64 maxFramerate=0;
  for(AVFrameRateRange *fpsRange in format.videoSupportedFrameRateRanges){
    maxFramerate=fmax(maxFramerate,fpsRange.maxFrameRate);
  }
  [_capturer startCaptureWithDevice:device format:format fps:maxFramerate];
}

-(void)printStats{
  [_subscription statsWithOnSuccess:^(NSArray<RTCLegacyStatsReport *> * _Nonnull stats) {
    NSLog(@"%@", stats);
  } onFailure:^(NSError * _Nonnull e) {
    NSLog(@"%@",e);
  }];
}

-(void)mixToCommonView:(ICSConferencePublication* )publication{
  AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
  manager.requestSerializer = [AFJSONRequestSerializer serializer];
  [manager.requestSerializer setValue:@"*/*" forHTTPHeaderField:@"Accept"];
  [manager.requestSerializer setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  manager.responseSerializer = [AFHTTPResponseSerializer serializer];
  manager.securityPolicy.allowInvalidCertificates=NO;
  manager.securityPolicy.validatesDomainName=YES;
  NSDictionary *params = [[NSDictionary alloc]initWithObjectsAndKeys:@"add", @"op", @"/info/inViews", @"path", @"common", @"value", nil];
  NSArray* paramsArray=[NSArray arrayWithObjects:params, nil];
  [manager PATCH:[NSString stringWithFormat:@"%@rooms/%@/streams/%@", appDelegate.serverUrl, appDelegate.conferenceId, publication.publicationId ] parameters:paramsArray success:nil failure:^(AFHTTPRequestOperation *operation, NSError *error) {
    NSLog(@"Error: %@", error);
  }];
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
  HorizontalSegue *s = (HorizontalSegue *)segue;
  s.isDismiss = YES;
}

-(void)onVideoLayoutChanged{
  NSLog(@"OnVideoLayoutChanged.");
}

-(void)subscriptionDidMute:(ICSConferenceSubscription *)subscription trackKind:(ICSTrackKind)kind{
  NSLog(@"Subscription is muted.");
}

-(void)subscriptionDidUnmute:(ICSConferenceSubscription *)subscription trackKind:(ICSTrackKind)kind{
  NSLog(@"Subscription is unmuted.");
}

-(void)subscriptionDidEnd:(ICSConferenceSubscription *)subscription{
  NSLog(@"Subscription is ended.");
}

-(void)publicationDidMute:(ICSConferencePublication *)publication trackKind:(ICSTrackKind)kind{
  NSLog(@"Publication is muted.");
}

-(void)publicationDidUnmute:(ICSConferencePublication *)publication trackKind:(ICSTrackKind)kind{
  NSLog(@"Publication is unmuted.");
}

-(void)publicationDidEnd:(ICSConferencePublication *)publication{
  NSLog(@"Publication is ended.");
}

@end
