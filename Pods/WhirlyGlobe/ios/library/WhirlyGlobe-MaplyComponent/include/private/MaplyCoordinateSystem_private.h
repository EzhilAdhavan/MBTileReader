/*
 *  MaplyCoordinateSystem_private.h
 *  WhirlyGlobe-MaplyComponent
 *
 *  Created by Steve Gifford on 5/13/13.
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
 *
 */

#import "math/MaplyCoordinateSystem.h"
#import "math/MaplyCoordinate.h"
#import "WhirlyGlobeLib.h"

@interface MaplyCoordinateSystem()
{
@public
    WhirlyKit::CoordSystemRef coordSystem;
}

@property(nonatomic,readonly) MaplyCoordinate ll;
@property(nonatomic,readonly) MaplyCoordinate ur;

- (instancetype)initWithCoordSystem:(WhirlyKit::CoordSystemRef)newCoordSystem;

/// Return the low level Maply Coordinate system that represents this one.
/// The object owns this and must clean it up.
- (WhirlyKit::CoordSystemRef)getCoordSystem;

/// Bounding box we're working within
- (void)getBoundsLL:(MaplyCoordinate *)ll ur:(MaplyCoordinate *)ur;

@end
