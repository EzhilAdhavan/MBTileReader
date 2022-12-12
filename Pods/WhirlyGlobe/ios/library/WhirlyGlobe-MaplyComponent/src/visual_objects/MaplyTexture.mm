/*
 *  MaplyTexture.mm
 *  WhirlyGlobe-MaplyComponent
 *
 *  Created by Steve Gifford on 10/25/13.
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

#import "MaplyTexture_private.h"
#import "MaplyRenderController_private.h"
#import "MaplyBaseInteractionLayer_private.h"
#import "WorkRegion_private.h"

using namespace WhirlyKit;

@implementation MaplyTexture

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;
    
    _interactLayer = nil;
    _image = nil;
    _isSubTex = false;
    _isBeingRemoved = false;
    _texID = EmptyIdentity;
    _width = _height = -1;

    return self;
}

- (void)clear
{
    if (_texID != EmptyIdentity)
    {
//        NSLog(@"Clearing texture %lx, for interactLayer %lx",(long)self,(long)_interactLayer);
        auto const __strong layer = _interactLayer;
        if (auto wr = WorkRegion(layer))
        {
            [layer clearTexture:self when:0.0];
        }
    }
}

- (void)dealloc
{
    [self clear];
}

@end
