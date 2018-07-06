//
//  ViewController.m
//  drone-cv
//
//  Created by Zhiyuan Li on 7/6/17.
//  Copyright © 2017 dji. All rights reserved.
//

#import <opencv2/opencv.hpp>
#import "ViewController.h"
#import <DJISDK/DJISDK.h>
#import <VideoPreviewer/VideoPreviewer.h>
#import "OpenCVConversion.h"
#import "DroneHelper.h"
#ifdef __cplusplus
  #include <vector>
  #include <opencv2/imgproc/imgproc.hpp>
  #include <opencv2/objdetect/objdetect.hpp>
  #include <opencv2/video/tracking.hpp>
#include "MagicInAir.h"
using namespace std;
#endif

#define PHOTO_NUMBER 4
#define ROTATE_ANGLE 90

#define weakSelf(__TARGET__) __weak typeof(self) __TARGET__=self
#define weakReturn(__TARGET__) if(__TARGET__==nil)return;


@interface ViewController()<DJIVideoFeedListener, DJISDKManagerDelegate>
{
    SimpleFaceDetector* myFaceDetector;
}

@property (weak, nonatomic) IBOutlet UIView *viewLive;
@property (weak, nonatomic) IBOutlet UIImageView *viewProcessed;

@property (weak, nonatomic) IBOutlet UILabel *debug1;
@property (weak, nonatomic) IBOutlet UILabel *debug2;
@property (weak, nonatomic) IBOutlet UILabel *telemetry;

@property (weak, nonatomic) NSTimer *myTimer;

@property (nonatomic, copy, nullable) void (^processFrame)(UIImage *frame);
@property (nonatomic, copy) void (^defaultProcess)(UIImage *frame);

@property (strong, nonatomic) DroneHelper *spark;

@property (atomic) enum ImgProcess_Mode imgProcType;

// Buttons
@property (weak, nonatomic) IBOutlet UIButton *btnLaplace;
@property (weak, nonatomic) IBOutlet UIButton *btnBlur;
@property (weak, nonatomic) IBOutlet UIButton *btnFaceDetect;
@property (weak, nonatomic) IBOutlet UIButton *btnGimbal;
@property (weak, nonatomic) IBOutlet UIButton *btnTakeoffLand;
@property (weak, nonatomic) IBOutlet UIButton *btnMoveTest;
@property (weak, nonatomic) IBOutlet UIButton *btnArucoTag;

@property (atomic) double aircraftAltitude;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view, typically from a nib.
    [self registerApp];
    self.viewProcessed.contentMode = UIViewContentModeScaleAspectFit;
    [self.viewProcessed setBackgroundColor:[UIColor redColor]];
    
    UIImage *image = [UIImage imageNamed:@"mavic.jpg"];
    if(image != nil)
        self.viewProcessed.image = image;

    self.myTimer=nil;
    
    // We define the default frame processing function (block)
    // to be just add a "Default" label on the resized image
    self.defaultProcess = ^(UIImage *frame){
        cv::Mat colorImg = [OpenCVConversion cvMatFromUIImage:frame];
        if(colorImg.cols == 0) {
            NSLog(@"Invalid frame!");
            return;
        }
        cv::resize(colorImg, colorImg, cv::Size(480, 360));
        
        // The default image processing routine just put a text to the resized image
        putText(colorImg, "Default" , cv::Point(150, 40), 1, 4, cv::Scalar(255, 255, 255), 2, 8, 0);
        
        [self.viewProcessed setImage:[OpenCVConversion UIImageFromCVMat:colorImg]];
    };
    
    self.imgProcType = IMG_PROC_DEFAULT;

    myFaceDetector = new SimpleFaceDetector("lbpcascade_frontalface");
    self.spark = [[DroneHelper alloc] init];

}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self resetVideoPreview];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark App Register
- (void)registerApp
{
    //Please enter your App key in the "DJISDKAppKey" key in info.plist file.
    [DJISDKManager registerAppWithDelegate:self];
}

- (void)showAlertViewWithTitle:(NSString *)title withMessage:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}


#pragma mark DJISDKManagerDelegate Method
- (void)appRegisteredWithError:(NSError *)error
{
    NSString* message = @"Register:OK!";
    if (error) {
        message = [NSString stringWithFormat:@"Register:Failed. %@"];
    }
    
    self.debug1.text = message;
    NSLog(message);
    
    [DJISDKManager startConnectionToProduct];
    
    //Use the following line if you are debugging with bridge
    //[DJISDKManager enableBridgeModeWithBridgeAppIP:@"192.168.0.107"];
}

- (void)productConnected:(DJIBaseProduct* _Nullable)product
{
    if(product)
    {
        [self setupVideoPreviewer]; // Implemented below
        
        DJICamera * myCamera = [self fetchCamera];
        DJIGimbal * myGimbal = [self fetchGimbal];
        DJIFlightController * myFC = [self fetchFlightController];
        
        if(myCamera == nil){
            [self showAlertViewWithTitle:@"Product Connected" withMessage:@"Failed to fetch camera"];
        }
        else if(myGimbal == nil){
            [self showAlertViewWithTitle:@"Product Connected" withMessage:@"Failed to fetch gimbal"];
        }
        else if(myFC == nil){
            [self showAlertViewWithTitle:@"Product Connected" withMessage:@"Failed to fetch FC"];
        }
        else{
            [self showAlertViewWithTitle:@"Product Connected" withMessage:@"All components fetched"];
            myFC.delegate = self.spark;
        }
    }
    else
    {
        [self showAlertViewWithTitle:@"Product Connected" withMessage:@"Error!"];
    }
}

- (void) productDisconnected
{
    [self resetVideoPreview]; // Implemented below
}

#pragma mark Get Drone Components
- (DJICamera*) fetchCamera {
    if (![DJISDKManager product]) {
        return nil;
    }
    return [DJISDKManager product].camera;
}

- (DJIFlightController*) fetchFlightController {
    if (![DJISDKManager product]) {
        return nil;
    }
    
    if ([[DJISDKManager product] isKindOfClass:[DJIAircraft class]]) {
        return ((DJIAircraft*)[DJISDKManager product]).flightController;
    }
    
    return nil;
}

- (DJIGimbal*) fetchGimbal {
    if (![DJISDKManager product]) {
        return nil;
    }
    
    if ([[DJISDKManager product] isKindOfClass:[DJIAircraft class]]) {
        return ((DJIAircraft*)[DJISDKManager product]).gimbal;
    }
    else if ([[DJISDKManager product] isKindOfClass:[DJIHandheld class]]) {
        return ((DJIHandheld*)[DJISDKManager product]).gimbal;
    }
    
    return nil;
}


// Called by productConnected
- (void) setupVideoPreviewer
{
    self.debug1.text = @"Connected!";
    self.debug2.text = @"Init-ed";
    [[VideoPreviewer instance] setView:self.viewLive];
    [[DJISDKManager videoFeeder].primaryVideoFeed addListener:self withQueue:nil];
    [[VideoPreviewer instance] start];
    
    self.myTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                    target:self
                                                  selector:@selector(timerCallback)
                                                  userInfo:nil
                                                   repeats:YES];
    
    self.processFrame = self.defaultProcess;
}

// Called by productDisconnected
- (void) resetVideoPreview
{
    self.debug1.text = @"Disconnected!";
    [[VideoPreviewer instance] unSetView];
    [[DJISDKManager videoFeeder].primaryVideoFeed removeListener:self];
    [self.myTimer invalidate];
}

#pragma mark - DJIVideoFeedListener
-(void)videoFeed:(DJIVideoFeed *)videoFeed didUpdateVideoData:(NSData *)videoData {
    [[VideoPreviewer instance] push:(uint8_t *)videoData.bytes length:(int)videoData.length];
}


-(void) timerCallback
{
    [[VideoPreviewer instance] snapshotPreview:self.processFrame];
    self.telemetry.text = [NSString stringWithFormat:@"h=%.2f\n\
                                                       vx=%.2f\n\
                                                       vy=%.2f\n\
                                                       vz=%.2f\n\
                                                       yaw=%.2f\n\
                                                       pitch=%.2f\
                                                       roll=%.2f",
                           self.spark.heightAboveHome,
                           self.spark.NEDVelocityX, self.spark.NEDVelocityY, self.spark.NEDVelocityZ,
                           self.spark.yaw, self.spark.pitch, self.spark.roll];
}

// Filter Buttons
- (IBAction)doLaplace:(id)sender;
{
    if(self.imgProcType == IMG_PROC_LAPLACIAN)
    {
        self.imgProcType = IMG_PROC_DEFAULT;
        self.processFrame = self.defaultProcess;
        self.debug2.text = @"Default";
    }
    else
    {
        self.imgProcType = IMG_PROC_LAPLACIAN;
        self.processFrame =
        ^(UIImage *frame){
            cv::Mat grayImg = [OpenCVConversion cvMatGrayFromUIImage:frame];
            if(grayImg.cols == 0)
            {
                NSLog(@"Invalid frame!");
                return;
            }
            cv::resize(grayImg, grayImg, cv::Size(480, 360));
            
            //TODO CMU: insert the image processing function call here
            //Implement the function in MagicInAir.mm.
            filterLaplace(grayImg, 3);
            
            [self.viewProcessed setImage:[OpenCVConversion UIImageFromCVMat:grayImg]];
        };
        self.debug2.text = @"Laplace";
    }
}

- (IBAction)doGaussian:(id)sender;
{
    if(self.imgProcType == IMG_PROC_BLUR_GAUSSIAN)
    {
        self.imgProcType = IMG_PROC_DEFAULT;
        self.processFrame = self.defaultProcess;
        self.debug2.text = @"Default";
    }
    else
    {
        self.imgProcType = IMG_PROC_BLUR_GAUSSIAN;
        self.processFrame =
        ^(UIImage *frame){
            cv::Mat grayImg = [OpenCVConversion cvMatGrayFromUIImage:frame];
            if(grayImg.cols == 0)
            {
                NSLog(@"Invalid frame!");
                return;
            }
            cv::resize(grayImg, grayImg, cv::Size(480, 360));

            //TODO CMU: insert the image processing function call here
            //Implement the function in MagicInAir.mm.
            filterBlurHomogeneousAccelerated(grayImg, 21);
            
            [self.viewProcessed setImage:[OpenCVConversion UIImageFromCVMat:grayImg]];
        };
        self.debug2.text = @"Blur";
    }
}


- (IBAction)doDetectFace:(id)sender;
{
    if(self.imgProcType == IMG_PROC_FACE_DETECT)
    {
        self.imgProcType = IMG_PROC_DEFAULT;
        self.processFrame = self.defaultProcess;
        self.debug2.text = @"Default";
    }
    else
    {
        self.imgProcType = IMG_PROC_FACE_DETECT;
        self.processFrame =
        ^(UIImage *frame){
            cv::Mat grayImg = [OpenCVConversion cvMatGrayFromUIImage:frame];
            if(grayImg.cols == 0)
            {
                NSLog(@"Invalid frame!");
                return;
            }
            cv::resize(grayImg, grayImg, cv::Size(480, 360));
            
            //TODO CMU: insert the image processing function call here
            //Implement the function in MagicInAir.mm.
            NSInteger f = myFaceDetector->detectFaceInMat(grayImg);
            
            [self.viewProcessed setImage:[OpenCVConversion UIImageFromCVMat:grayImg]];
            self.debug2.text = [NSString stringWithFormat:@"%d faces", f];
        };
    }
}

- (IBAction)doDetectAR:(id)sender
{
    // Not using here, just show how to use static variable
    static int counter= 0;

    if(self.imgProcType == IMG_PROC_USER_1)
    {
        self.imgProcType = IMG_PROC_DEFAULT;
        self.processFrame = self.defaultProcess;
        self.debug2.text = @"Default";
    }
    else
    {
        // Virtual stick mode is a control interface
        // allow user to progrmmatically control the drone's movement
        [self.spark enterVirtualStickMode];
        
        // This will change the behavior in the z-axis of the drone
        // If you call change set vertical mode to absolute height
        // Use MoveVxVyYawrateHeight(...)
        // Otherwise use MoveVxVyYawrateVz(...)
        [self.spark setVerticleModeToAbsoluteHeight];
        
        self.imgProcType = IMG_PROC_USER_1;
        
        // This is a timer callback function that will run repeatedly when button is clicked
        self.processFrame =
        ^(UIImage *frame){
            counter = counter+1;
            DroneHelper *spark_ptr = [self spark];
            
            // From here we get the image from the main camera of the drone
            cv::Mat grayImg = [OpenCVConversion cvMatGrayFromUIImage:frame];
            if(grayImg.cols == 0)
            {
                NSLog(@"Invalid frame!");
                return;
            }
            
            // Shrink the image for faster processing
            cv::resize(grayImg, grayImg, cv::Size(480, 360));
            
            // Call detectARTagIDs to get Aruco tag IDs and corner pixel location
            std::vector<std::vector<cv::Point2f> > corners;
            std::vector<int> ids = detectARTagIDs(corners,grayImg);
            NSInteger n = ids.size();

            // Implement your logic to decide where to move the drone
            // Below snippet is an example of how you can calcualte the center of the marker
//            cv::Point2f marker_center(0,0);
//            bool tag_for_takeoff = FALSE;
//            for(auto i=0;i<n;i++)
//            {
//                std::cout<<"\nID: "<<ids[i];
//                // This function calculate the average marker center from all the detected tags
//                marker_center = VectorAverage(corners[i]);
//            }
            
            // Codes commented below show how to drive the drone to move to the direction
            // such that desired tag is in the center of image frame
            
            // Calculate the image vector relative to the center of the image
//            cv::Point2f image_vector = marker_center-cv::Point2f(240,180);
            
            // Convert vector from image coordinate to drone navigation coordinate
//            cv::Point2f motion_vector = convertImageVectorToMotionVector(image_vector);
            
            // If there's no tag detected, no motion required
//            if(n==0){
//                motion_vector = cv::Point2f(0,0);
//            }
            
            // Use MoveVxVyYawrateVz(...) or MoveVxVyYawrateHeight(...)
            // depending on the mode you choose at the beginning of this function
//            if((image_vector.x*image_vector.x + image_vector.y*image_vector.y)<900)
//                MoveVxVyYawrateVz(spark_ptr, motion_vector.x, motion_vector.y, 0, -0.2);
//            else
//                MoveVxVyYawrateVz(spark_ptr, motion_vector.x, motion_vector.y, 0, 0);

//            std::cout<<"Moving By::"<<motion_vector<<"\n";
            
            // Move the camera to look down so you can see the tags
            PitchGimbal(spark_ptr,-75.0);
            
            // Sample function to help you control the drone
            // Such as takeoff and land
//            TakeOff(spark_ptr);
//            Land(spark_ptr);
            
            // Convert opencv image back to iOS UIImage
            [self.viewProcessed setImage:[OpenCVConversion UIImageFromCVMat:grayImg]];
            
            // Print some debug text on the App
            self.debug2.text = [NSString stringWithFormat:@"%d Tags", n];
        };
    }
}

/**
 Demo how to move the gimbal to face forward and down.
 */
- (IBAction)onGimbalButtonClicked:(id)sender;
{
    enum {FORWARD=0, DOWN=1};
    static int action = FORWARD;
    
    if(action == FORWARD)
    {
        if([self.spark setGimbalPitchDegree: 0.0] == FALSE) {
            [self showAlertViewWithTitle:@"Move Gimbal" withMessage:@"Failed"];
        }
        action = DOWN;
    }
    else
    {
        if([self.spark setGimbalPitchDegree: -65.0] == FALSE) {
            [self showAlertViewWithTitle:@"Move Gimbal" withMessage:@"Failed"];
        }
        action = FORWARD;
    }
}

/**
 Demo how to take off and land.
 */
- (IBAction)onTakeoffButtonClicked:(id)sender
{
    enum {TAKEOFF=0, LAND=1};
    static int action = TAKEOFF;
    
    if(action == TAKEOFF)
    {
        if([self.spark takeoff] == FALSE) {
            [self showAlertViewWithTitle:@"Takeoff" withMessage:@"Failed"];
        }
        else {
            [self showAlertViewWithTitle:@"Takeoff" withMessage:@"Succeeded"];
        }
        [self.btnTakeoffLand setTitle:@"Land" forState:UIControlStateNormal];
        action = LAND;
    }
    else
    {
        if([self.spark land] == FALSE) {
            [self showAlertViewWithTitle:@"Land" withMessage:@"Failed"];
        }
        else {
            [self showAlertViewWithTitle:@"Land" withMessage:@"Succeeded"];
        }
        
        [self.btnTakeoffLand setTitle:@"Takeoff" forState:UIControlStateNormal];
        action = TAKEOFF;
    }
}

- (IBAction)onDroneMoveClicked:(id)sender
{
    if(self.imgProcType == IMG_PROC_USER_2)
    {
        self.imgProcType = IMG_PROC_DEFAULT;
        self.processFrame = self.defaultProcess;
        self.debug2.text = @"Default";
    }
    else
    {
        self.imgProcType = IMG_PROC_USER_2;
        [self.spark enterVirtualStickMode];
        [self.spark setVerticleModeToVelocity];

        self.processFrame =
        ^(UIImage *frame){
            cv::Mat colorImg = [OpenCVConversion cvMatFromUIImage:frame];
            if(colorImg.cols == 0)
            {
                NSLog(@"Invalid frame!");
                return;
            }
            cv::resize(colorImg, colorImg, cv::Size(480, 360));
            
            //TODO CMU: insert the image processing function call here
            //Implement the function in MagicInAir.mm.
            sampleMovement(colorImg, self.spark);
            
            [self.viewProcessed setImage:[OpenCVConversion UIImageFromCVMat:colorImg]];
            //self.debug2.text = [NSString stringWithFormat:@"%d Tags", n];
        };
    }
}


- (void) enableVS
{
    // disable gesture mode
    if([[DJISDKManager product].model isEqual: DJIAircraftModelNameSpark])
    {
        [[DJISDKManager missionControl].activeTrackMissionOperator setGestureModeEnabled:NO withCompletion:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"Set Gesture mode enabled failed");
            }
            else {
                NSLog(@"Set Gesture mode enabled Succeeded");
            }
        }];
    }

    // Enter the virtual stick mode with some default settings
    DJIFlightController *fc = [self fetchFlightController];
    //fc.yawControlMode = DJIVirtualStickYawControlModeAngle;
    fc.yawControlMode =DJIVirtualStickYawControlModeAngularVelocity;
    fc.rollPitchControlMode = DJIVirtualStickRollPitchControlModeVelocity;
    fc.rollPitchCoordinateSystem = DJIVirtualStickFlightCoordinateSystemBody;
    //DJIVirtualStickFlightCoordinateSystemBody;
    [fc setVirtualStickModeEnabled:YES withCompletion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Enable VirtualStickControlMode Failed");
        }
        else {
            NSLog(@"Enable VirtualStickControlMode Succeeded");
        }
    }];

}


@end
