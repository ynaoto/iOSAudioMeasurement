//
//  ViewController.m
//  AVAudioRecorder
//
//  Created by Naoto Yoshioka on 2013/12/20.
//  Copyright (c) 2013年 Naoto Yoshioka. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface LevelMeter : UIView
@property (nonatomic) float value;

@end

@implementation LevelMeter
{
    UILabel *label;
    NSMutableArray *history;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        label = [[UILabel alloc] init];
        [self addSubview:label];
        history = [NSMutableArray array];
    }
    return self;
}

- (void)setValue:(float)value
{
    //NSLog(@"%s: value = %g", __FUNCTION__, value);
    
    label.text = [NSString stringWithFormat:@"%g", value];
    [label sizeToFit];

    if (self.bounds.size.height < history.count) {
        [history removeObjectAtIndex:0];
    }
    [history addObject:@(value)];
    
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    [super drawRect:rect];
    
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGFloat maxX = CGRectGetMaxX(rect);
    CGFloat maxY = CGRectGetMaxY(rect);

    CGContextSetLineWidth(context, 1.0);

    int n = history.count;
    for (int i = 0; i < n; i++) {
        float value = [history[n - i - 1] floatValue];
        
        // max: 0dB -> 0 (red)
        // min: -60dB -> 0.5 (sky)
        CGFloat h = 0.5 * MIN(-value, 60) / 60;
        CGFloat s = 1.0;
        CGFloat b = 1.0;
        UIColor *color = [UIColor colorWithHue:h saturation:s brightness:b alpha:1.0];
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        
        CGFloat y = maxY - i;
        CGContextMoveToPoint(context, 0, y);
        CGContextAddLineToPoint(context, maxX, y);
        CGContextStrokePath(context);
    }
}

@end

@interface ViewController () <AVCaptureAudioDataOutputSampleBufferDelegate>
@property (atomic) float average;
@property (weak, nonatomic) IBOutlet LevelMeter *averageMeter;
@property (atomic) float peak;
@property (weak, nonatomic) IBOutlet LevelMeter *peakMeter;
@property (atomic) BOOL running;
@property (weak, nonatomic) IBOutlet UISlider *inputGainSlider;

@end

@implementation ViewController
{
    AVCaptureSession *captureSession;
}

#pragma mark AVCaptureAudioDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    NSArray *audioChannels = connection.audioChannels;
    
    for (AVCaptureAudioChannel *channel in audioChannels) {
        self.average = channel.averagePowerLevel;
        self.peak = channel.peakHoldLevel;
    }
}

#pragma mark -

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
//    NSLog(@"%s: keyPath = %@, change = %@", __FUNCTION__, keyPath, change);
    if ([keyPath isEqualToString:@"average"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.averageMeter.value = self.average;
        });
    } else if ([keyPath isEqualToString:@"peak"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.peakMeter.value = self.peak;
        });
    } else if ([keyPath isEqualToString:@"running"]) {
        self.inputGainSlider.enabled = self.running;
        if (self.running) {
            [captureSession startRunning];
        } else {
            [captureSession stopRunning];
        }
    } else if ([keyPath isEqualToString:@"inputGain"]) {
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        self.inputGainSlider.value = audioSession.inputGain;
    } else {
        NSLog(@"unknown keyPath: %@", keyPath);
        abort();
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.

    BOOL result;
    NSError *error = nil;

    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    result = [audioSession setCategory:AVAudioSessionCategoryRecord error:&error];
    NSAssert(result, [error description]);
    result = [audioSession setMode:AVAudioSessionModeMeasurement error:&error];
    NSAssert(result, [error description]);
    
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    
    if (!input) {
        NSLog(@"%@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:@"No audio input device found."
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
        
        return;
    }
    
    AVCaptureAudioDataOutput *output = [[AVCaptureAudioDataOutput alloc] init];
//    dispatch_queue_t queue = dispatch_get_main_queue();
    dispatch_queue_t queue = dispatch_queue_create("AudioCaptureQueue", DISPATCH_QUEUE_SERIAL);
    [output setSampleBufferDelegate:self queue:queue];

    captureSession = [[AVCaptureSession alloc] init];
    [captureSession addInput:input];
    [captureSession addOutput:output];
    
    [self addObserver:self
           forKeyPath:@"average"
              options:NSKeyValueObservingOptionInitial|NSKeyValueObservingOptionNew
              context:nil];
    [self addObserver:self
           forKeyPath:@"peak"
              options:NSKeyValueObservingOptionInitial|NSKeyValueObservingOptionNew
              context:nil];
    [self addObserver:self
           forKeyPath:@"running"
              options:NSKeyValueObservingOptionInitial|NSKeyValueObservingOptionNew
              context:nil];
    [audioSession addObserver:self
           forKeyPath:@"inputGain"
              options:NSKeyValueObservingOptionInitial|NSKeyValueObservingOptionNew
              context:nil];
    
    self.running = YES;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)run:(UISwitch*)sender {
    self.running = sender.on;
}

- (IBAction)inputGainChanged:(UISlider *)sender {
    BOOL result;
    NSError *error = nil;
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    result = [audioSession setInputGain:sender.value error:&error];
    NSAssert(result, [error description]);
}

@end
