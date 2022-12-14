/*  UIColor+Stuff.h
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 3/15/11.
 *  Copyright 2011-2022 mousebird consulting
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

#import <UIKit/UIKit.h>
#import "WhirlyVector.h"

@interface UIColor(Stuff)

- (UIColor *)lighterColor;
- (UIColor *)lighterColor:(float)withFactor;

/// Build a UIColor from a hex value (#RRGGBB)
+ (UIColor *) colorFromHexRGB:(int)hexColor;

/// Build a UIColor from a hex value (#RGB)
+ (UIColor *) colorFromShortHexRGB:(int)hexColor;

/// Build a UIColor from an RGBAColor
+ (UIColor *) colorFromRGBA:(const WhirlyKit::RGBAColor &)color;

/// Convert a UIColor to the RBGA color we use internally
- (WhirlyKit::RGBAColor) asRGBAColor;

/// Convert a UIColor to Vector4, which we also use internally
- (Eigen::Vector4f) asVec4;

////Convert a UIColor to a hex value
- (int) asHexRGB;

/// Convert UIColor to a #color string
- (NSString *) asHexRGBAString;

@end

// A function we can call to force the linker to bring in categories
#ifdef __cplusplus
extern "C"
#endif
void UIColorDummyFunc();
