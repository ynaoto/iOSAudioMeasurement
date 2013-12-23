//
//  LabeledSlider.m
//
//  Created by Naoto Yoshioka on 2013/12/23.
//  Copyright (c) 2013年 Naoto Yoshioka. All rights reserved.
//

#import "LabeledSlider.h"

@implementation LabeledSlider

- (void)setupValueLabel
{
    CGFloat w = self.frame.size.width;
    CGFloat h = self.frame.size.height;
    _valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, w, h/2)];
    [self addSubview:_valueLabel];
}

#pragma mark override

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self setupValueLabel];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self setupValueLabel];
    }
    return self;
}

- (CGRect)thumbRectForBounds:(CGRect)bounds trackRect:(CGRect)rect value:(float)value
{
    CGRect result = [super thumbRectForBounds:bounds trackRect:rect value:value];
    _valueLabel.text = [NSString stringWithFormat:@"%g", value];
    return result;
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

@end