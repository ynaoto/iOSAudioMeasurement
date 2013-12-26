//
//  ViewController.m
//  AVAudioRecorder
//
//  Created by Naoto Yoshioka on 2013/12/20.
//  Copyright (c) 2013年 Naoto Yoshioka. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>

@interface LevelMeter : UIView
@property (nonatomic) float value;

- (CGColorRef)valueToCGColorRef:(float)value;

@end

@implementation LevelMeter
{
    UILabel *label;
    NSMutableArray *history;
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

- (CGColorRef)valueToCGColorRef:(float)value
{
    UIColor *color = [UIColor colorWithHue:value saturation:1 brightness:1 alpha:1.0];
    return color.CGColor;
}

#pragma mark override

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

- (void)drawRect:(CGRect)rect
{
    [super drawRect:rect];
    
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGFloat maxX = CGRectGetMaxX(rect);
    CGFloat maxY = CGRectGetMaxY(rect);

    CGContextSetLineWidth(context, 1.0);

    NSUInteger n = history.count;
    for (NSUInteger i = 0; i < n; i++) {
        float value = [history[n - i - 1] floatValue];
        CGContextSetStrokeColorWithColor(context, [self valueToCGColorRef:value]);
        CGFloat y = maxY - i;
        CGContextMoveToPoint(context, 0, y);
        CGContextAddLineToPoint(context, maxX, y);
        CGContextStrokePath(context);
    }
}

@end

@interface dBLevelMeter : LevelMeter

@end

@implementation dBLevelMeter

#pragma mark override

- (CGColorRef)valueToCGColorRef:(float)value
{
    // max: 0dB -> 0 (red)
    // min: -60dB -> 0.5 (sky)
    CGFloat h = 0.5 * MIN(-value, 60) / 60;
    CGFloat s = 1.0;
    CGFloat b = 1.0;
    UIColor *color = [UIColor colorWithHue:h saturation:s brightness:b alpha:1.0];
    return color.CGColor;
}

@end

@interface SampleLevelMeter : LevelMeter

@end

@implementation SampleLevelMeter

#pragma mark override

- (CGColorRef)valueToCGColorRef:(float)value
{
    // In absolute value:
    // max: 10000 -> 0 (red)
    // min: 0 -> 0.5 (sky)
    CGFloat h = 0.5 * (1 - MIN(abs(value), 10000.0) / 10000);
    CGFloat s = 1.0;
    CGFloat b = 1.0;
    UIColor *color = [UIColor colorWithHue:h saturation:s brightness:b alpha:1.0];
    return color.CGColor;
}

@end

@interface ViewController () <AVCaptureAudioDataOutputSampleBufferDelegate>
@property (atomic) float average;
@property (weak, nonatomic) IBOutlet LevelMeter *averageMeter;
@property (atomic) float peak;
@property (weak, nonatomic) IBOutlet LevelMeter *peakMeter;
@property (atomic) float range;
@property (weak, nonatomic) IBOutlet LevelMeter *rangeMeter;
@property (atomic) BOOL running;
@property (weak, nonatomic) IBOutlet UISlider *inputGainSlider;
@property (weak, nonatomic) IBOutlet UISwitch *useVDSP;

@end

@implementation ViewController
{
    AVCaptureSession *captureSession;
}

#pragma mark AVCaptureAudioDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    NSArray *audioChannels = connection.audioChannels;
    if (0 < audioChannels.count) {
        AVCaptureAudioChannel *channel = audioChannels[0];
        self.average = channel.averagePowerLevel;
        self.peak = channel.peakHoldLevel;
        
        // http://stackoverflow.com/questions/14088290/passing-avcaptureaudiodataoutput-data-into-vdsp-accelerate-framework
        
        // get a pointer to the audio bytes
        CMItemCount numSamples = CMSampleBufferGetNumSamples(sampleBuffer);
        CMBlockBufferRef audioBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        size_t lengthAtOffset;
        size_t totalLength;
        int16_t *samples;
        CMBlockBufferGetDataPointer(audioBuffer, 0, &lengthAtOffset, &totalLength, (char**)&samples);
        
        // check what sample format we have
        // this should always be linear PCM
        // but may have 1 or 2 channels
        CMAudioFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        const AudioStreamBasicDescription *desc = CMAudioFormatDescriptionGetStreamBasicDescription(format);
        assert(desc->mFormatID == kAudioFormatLinearPCM);
        if (desc->mChannelsPerFrame == 1 && desc->mBitsPerChannel == 16) {

            float min, max;
            
            if (self.useVDSP.on) {
                float *convertedSamples = malloc(numSamples * sizeof(float));
                vDSP_vflt16(samples, 1, convertedSamples, 1, numSamples);
                vDSP_minv(convertedSamples, 1, &min, numSamples);
                vDSP_maxv(convertedSamples, 1, &max, numSamples);
                free(convertedSamples);
            } else {
                min = INFINITY;
                max = -INFINITY;
                for (int i = 0; i < numSamples; i++) {
                    int16_t a = samples[i];
                    if (a < min) {
                        min = a;
                    }
                    if (max < a) {
                        max = a;
                    }
                }
            }
            
            self.range = max - min;

        } else {
            // handle other cases as required
            NSLog(@"unexpected sampleBuffer format");
        }
        
        if (1 < audioChannels.count) {
            NSLog(@"warning: more than one audioChannels, ignored.");
        }
    } else {
        NSLog(@"warning: no audioChannels.");
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
    } else if ([keyPath isEqualToString:@"range"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.rangeMeter.value = self.range;
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
           forKeyPath:@"range"
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
