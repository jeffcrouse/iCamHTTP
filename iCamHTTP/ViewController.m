//
//  ViewController.m
//  iPhoneCamHTTP
//
//  Created by Jeffrey Crouse on 5/27/16.
//  Copyright © 2016 Jeffrey Crouse. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

@synthesize PreviewLayer;
@synthesize outputPath;
@synthesize WeAreSaving;
@synthesize WeAreRecording;

- (void)viewDidLoad {
    [super viewDidLoad];

    //---------------------------------
    //----- SETUP CAPTURE SESSION -----
    //---------------------------------
    NSLog(@"Setting up capture session");
    CaptureSession = [[AVCaptureSession alloc] init];
    
    //----- ADD INPUTS -----
    NSLog(@"Adding video input");
    
    //----- ADD VIDEO INPUT ----- 
    AVCaptureDevice *VideoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (VideoDevice)
    {
        NSError *error;
        VideoInputDevice = [AVCaptureDeviceInput deviceInputWithDevice:VideoDevice error:&error];
        if (!error)
        {
            if ([CaptureSession canAddInput:VideoInputDevice])
                [CaptureSession addInput:VideoInputDevice];
            else
                NSLog(@"Couldn't add video input");
        }
        else
        {
            NSLog(@"Couldn't create video input");
        }
    }
    else
    {
        NSLog(@"Couldn't create video capture device");
    }
    
    //ADD AUDIO INPUT
    NSLog(@"Adding audio input");
    AVCaptureDevice *audioCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    NSError *error = nil;
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioCaptureDevice error:&error];
    if (audioInput)
    {
        [CaptureSession addInput:audioInput];
    }

    
    //----- ADD OUTPUTS -----
    
    //ADD VIDEO PREVIEW LAYER
    NSLog(@"Adding video preview layer");
    [self setPreviewLayer: [[AVCaptureVideoPreviewLayer alloc] initWithSession:CaptureSession]];
    
    [[PreviewLayer connection] setVideoOrientation: AVCaptureVideoOrientationLandscapeRight];
    [PreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    
    
    //ADD MOVIE FILE OUTPUT
    NSLog(@"Adding movie file output");
    MovieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
    
    Float64 TotalSeconds = 60;			//Total seconds
    int32_t preferredTimeScale = 30;	//Frames per second
    CMTime maxDuration = CMTimeMakeWithSeconds(TotalSeconds, preferredTimeScale); //<<SET MAX DURATION
    MovieFileOutput.maxRecordedDuration = maxDuration;
    
    MovieFileOutput.minFreeDiskSpaceLimit = 1024 * 1024; //<<SET MIN FREE SPACE IN BYTES FOR RECORDING TO CONTINUE ON A VOLUME
    
    if ([CaptureSession canAddOutput:MovieFileOutput])
        [CaptureSession addOutput:MovieFileOutput];
    
    //SET THE CONNECTION PROPERTIES (output properties)
    [self CameraSetOutputProperties];			//(We call a method as it also has to be done after changing camera)
    
    
    //----- SET THE IMAGE QUALITY / RESOLUTION -----
    NSLog(@"Setting image quality");
    if ([CaptureSession canSetSessionPreset:AVCaptureSessionPreset1920x1080]) //Check size based configs are supported before setting them
        [CaptureSession setSessionPreset:AVCaptureSessionPreset1920x1080];
    
    
    //----- DISPLAY THE PREVIEW LAYER -----
    //Display it full screen under out view controller existing controls
    NSLog(@"Display the preview layer");
    CGRect layerRect = [[[self view] layer] bounds];
    [PreviewLayer setBounds:layerRect];
    [PreviewLayer setPosition:CGPointMake(CGRectGetMidX(layerRect),
                                          CGRectGetMidY(layerRect))];
    //[[[self view] layer] addSublayer:[[self CaptureManager] previewLayer]];
    //We use this instead so it goes on a layer behind our UI controls (avoids us having to manually bring each control to the front):
    UIView *CameraView = [[UIView alloc] init];
    [[self view] addSubview:CameraView];
    [self.view sendSubviewToBack:CameraView];
    
    [[CameraView layer] addSublayer:PreviewLayer];
    
    
    
    _webServer = [[GCDWebServer alloc] init];
    __weak typeof(self) weakSelf = self;
    
    [_webServer addHandlerForMethod:@"GET" path:@"/record"
                       requestClass:[GCDWebServerRequest class]
                       processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
                           if([weakSelf WeAreRecording]) {
                               return [GCDWebServerDataResponse responseWithHTML:@"ALREADY RECORDING"];
                           } else {
                               [weakSelf Record];
                               return [GCDWebServerDataResponse responseWithHTML:@"OK"];
                           }
                       }];
    
    
    [_webServer addHandlerForMethod:@"GET" path:@"/finish" requestClass:[GCDWebServerRequest class]
                  asyncProcessBlock:^(GCDWebServerRequest* request, GCDWebServerCompletionBlock completionBlock) {
                      GCDWebServerResponse* response;
                      
                      if([weakSelf WeAreRecording]) {
                          [weakSelf Finish];
                          
                          NSDictionary* query = [request query];
                          if(query && [query objectForKey:@"abort"]) {
                              response = [GCDWebServerDataResponse responseWithHTML:@"OK"];
                          } else {
                              while([weakSelf WeAreSaving] == YES){
                                  NSLog(@"waiting for save to complete");
                                  [NSThread sleepForTimeInterval:0.25f];
                              }
                              NSLog(@"Sending file %@", [weakSelf outputPath]);
                              response = [GCDWebServerFileResponse responseWithFile:[weakSelf outputPath] byteRange:request.byteRange];
                          }
                      } else {
                          response = [GCDWebServerDataResponse responseWithHTML:@"NOT RECORDING"];
                      }
        
                      completionBlock(response);
                  }];
    

    // Start server on port 8080
    [_webServer startWithPort:8080 bonjourName:@"iCam"];
    NSLog(@"Visit %@ in your web browser", _webServer.serverURL);
    
    //----- START THE CAPTURE SESSION RUNNING -----
    [CaptureSession startRunning];
    
    overlay = [CAShapeLayer layer];
    [overlay setFrame:[PreviewLayer frame]];
    [overlay setDelegate:self];
    [PreviewLayer addSublayer:overlay];
    
    [NSTimer scheduledTimerWithTimeInterval:0.5f
                                     target:self
                                    selector:@selector(drawme:)
                                   userInfo:nil
                                    repeats:YES];
    
    UIFont* font = [UIFont fontWithName:@"Helvetica-Bold" size:20];
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    paragraphStyle.alignment = NSTextAlignmentCenter;
    
    textAttrs = @{ NSFontAttributeName: font,
                   NSParagraphStyleAttributeName: paragraphStyle,
                   NSForegroundColorAttributeName: [UIColor whiteColor]};
}

- (void)drawme: (NSTimer *)timer {
    //NSLog(@"drawme");
    //[label setNeedsDisplay];
    [overlay setNeedsDisplay];
}

//delegate function that draws to a CALayer
- (void)drawLayer:(CALayer*)layer inContext:(CGContextRef)ctx {
    
    blink = !blink;
    if(WeAreRecording && blink) {
        CGContextSetRGBFillColor (ctx, 1, 0, 0, 1);
        CGContextFillEllipseInRect(ctx, CGRectMake (20, 20, 40, 40));
    }

    
    UIGraphicsPushContext(ctx);
    NSString* sstr = [[_webServer bonjourServerURL] absoluteString];//its right
    [sstr drawInRect:[PreviewLayer frame] withAttributes:textAttrs];
    UIGraphicsPopContext();

}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIDeviceOrientationLandscapeLeft);
}

//********** VIEW WILL APPEAR **********
//View about to be added to the window (called each time it appears)
//Occurs after other view's viewWillDisappear
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    WeAreRecording = NO;
    WeAreSaving = NO;
}

//********** CAMERA SET OUTPUT PROPERTIES **********
- (void) CameraSetOutputProperties
{
    //SET THE CONNECTION PROPERTIES (output properties)
    AVCaptureConnection *CaptureConnection = [MovieFileOutput connectionWithMediaType:AVMediaTypeVideo];
    
    //Set landscape (if required)
    if ([CaptureConnection isVideoOrientationSupported])
    {
        AVCaptureVideoOrientation orientation = AVCaptureVideoOrientationLandscapeRight;		//<<<<<SET VIDEO ORIENTATION IF LANDSCAPE
        [CaptureConnection setVideoOrientation:orientation];
    }
    
    //Set frame rate (if requried)
//    CMTimeShow(CaptureConnection.videoMinFrameDuration);
//    CMTimeShow(CaptureConnection.videoMaxFrameDuration);
//    
//    if (CaptureConnection.supportsVideoMinFrameDuration)
//        CaptureConnection.videoMinFrameDuration = CMTimeMake(1, CAPTURE_FRAMES_PER_SECOND);
//    if (CaptureConnection.supportsVideoMaxFrameDuration)
//        CaptureConnection.videoMaxFrameDuration = CMTimeMake(1, CAPTURE_FRAMES_PER_SECOND);
//    
//    CMTimeShow(CaptureConnection.videoMinFrameDuration);
//    CMTimeShow(CaptureConnection.videoMaxFrameDuration);
}

//********** GET CAMERA IN SPECIFIED POSITION IF IT EXISTS **********
- (AVCaptureDevice *) CameraWithPosition:(AVCaptureDevicePosition) Position
{
    NSArray *Devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *Device in Devices)
    {
        if ([Device position] == Position)
        {
            return Device;
        }
    }
    return nil;
}



//********** CAMERA TOGGLE **********
- (void)CameraToggle
{
    if ([[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count] > 1)		//Only do if device has multiple cameras
    {
        NSLog(@"Toggle camera");
        NSError *error;
        //AVCaptureDeviceInput *videoInput = [self videoInput];
        AVCaptureDeviceInput *NewVideoInput;
        AVCaptureDevicePosition position = [[VideoInputDevice device] position];
        if (position == AVCaptureDevicePositionBack)
        {
            NewVideoInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self CameraWithPosition:AVCaptureDevicePositionFront] error:&error];
        }
        else if (position == AVCaptureDevicePositionFront)
        {
            NewVideoInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self CameraWithPosition:AVCaptureDevicePositionBack] error:&error];
        }
        
        if (NewVideoInput != nil)
        {
            [CaptureSession beginConfiguration];		//We can now change the inputs and output configuration.  Use commitConfiguration to end
            [CaptureSession removeInput:VideoInputDevice];
            if ([CaptureSession canAddInput:NewVideoInput])
            {
                [CaptureSession addInput:NewVideoInput];
                VideoInputDevice = NewVideoInput;
            }
            else
            {
                [CaptureSession addInput:VideoInputDevice];
            }
            
            //Set the connection properties again
            [self CameraSetOutputProperties];
            
            [CaptureSession commitConfiguration];
        }
    }
}




//********** START STOP RECORDING BUTTON **********
- (void)Record
{
    if (WeAreRecording) return;

    //----- START RECORDING -----
    NSLog(@"START RECORDING");
    WeAreRecording = YES;
    
    //Create temporary URL to record to
    outputPath = [[NSString alloc] initWithFormat:@"%@%@", NSTemporaryDirectory(), @"output.mov"];
    NSURL *outputURL = [[NSURL alloc] initFileURLWithPath:outputPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:outputPath])
    {
        NSError *error;
        if ([fileManager removeItemAtPath:outputPath error:&error] == NO)
        {
            //Error - handle if requried
        }
    }
    
    //Start recording
    [MovieFileOutput startRecordingToOutputFileURL:outputURL recordingDelegate:self];
}

- (void)Finish
{
    //----- STOP RECORDING -----
    NSLog(@"STOP RECORDING");
    WeAreRecording = NO;
    WeAreSaving = YES;
    [MovieFileOutput stopRecording];
}


//********** DID FINISH RECORDING TO OUTPUT FILE AT URL **********
- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
      fromConnections:(NSArray *)connections
                error:(NSError *)error
{
    NSLog(@"didFinishRecordingToOutputFileAtURL - enter");
    WeAreSaving = NO;
    
    BOOL RecordedSuccessfully = YES;
    if ([error code] != noErr)
    {
        // A problem occurred: Find out if the recording was successful.
        id value = [[error userInfo] objectForKey:AVErrorRecordingSuccessfullyFinishedKey];
        if (value)
        {
            RecordedSuccessfully = [value boolValue];
        }
    }
    
    /*
    if (RecordedSuccessfully)
    {
        //----- RECORDED SUCESSFULLY -----
        NSLog(@"didFinishRecordingToOutputFileAtURL - success");
        
        ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
        if ([library videoAtPathIsCompatibleWithSavedPhotosAlbum:outputFileURL])
        {
            [library writeVideoAtPathToSavedPhotosAlbum:outputFileURL
                                        completionBlock:^(NSURL *assetURL, NSError *error)
             {
                 if (error)
                 {
                    
                 }
             }];
        }
    }
     */
}


//********** VIEW DID UNLOAD **********
- (void)viewDidUnload
{
    [super viewDidUnload];
    
    CaptureSession = nil;
    MovieFileOutput = nil;
    VideoInputDevice = nil;
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
