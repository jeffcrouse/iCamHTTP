//
//  ViewController.h
//  iPhoneCamHTTP
//
//  Created by Jeffrey Crouse on 5/27/16.
//  Copyright © 2016 Jeffrey Crouse. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "GCDWebServer.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerFileResponse.h"
#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>

@interface ViewController : UIViewController <AVCaptureFileOutputRecordingDelegate>
{
    GCDWebServer* _webServer;
    AVCaptureSession *CaptureSession;
    AVCaptureMovieFileOutput *MovieFileOutput;
    AVCaptureDeviceInput *VideoInputDevice;
    CAShapeLayer *overlay;
    NSDictionary *textAttrs;
    BOOL blink;
}

@property (retain) AVCaptureVideoPreviewLayer *PreviewLayer;
@property (retain) NSString *outputPath;
@property BOOL WeAreSaving;
@property BOOL WeAreRecording;
- (void) CameraSetOutputProperties;
- (AVCaptureDevice *) CameraWithPosition:(AVCaptureDevicePosition) Position;

- (void)drawme: (NSTimer *)timer;
- (void)Record;
- (void)Finish;
- (void)CameraToggle;
- (void)drawme;
- (void)drawLayer:(CALayer*)layer inContext:(CGContextRef)ctx;
@end


