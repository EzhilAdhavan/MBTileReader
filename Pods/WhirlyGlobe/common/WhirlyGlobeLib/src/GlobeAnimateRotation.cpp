/*  GlobeAnimateRotation.cpp
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 5/23/11.
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

#import "Platform.h"
#import "GlobeAnimateRotation.h"

using namespace WhirlyKit;
using namespace Eigen;

namespace WhirlyGlobe
{

AnimateViewRotation::AnimateViewRotation(GlobeView *globeView,
                                         const Eigen::Quaterniond &newRot,
                                         TimeInterval howLong) :
    startDate(TimeGetCurrent()),
    startRot(globeView->getRotQuat()),
    endRot(newRot)
{
    endDate = startDate + howLong;
}

// Called by the view when it's time to update
void AnimateViewRotation::updateView(WhirlyKit::View *view)
{
    auto globeView = (GlobeView *)view;
	if (startDate == 0.0)
		return;
	
	const TimeInterval now = TimeGetCurrent();
    const double span = endDate-startDate;
    const double remain = endDate - now;
    
	// All done.  Snap to the end
	if (remain < 0)
	{
        globeView->setRotQuat(endRot);
        startDate = 0;
        endDate = 0;
        globeView->cancelAnimation();
	}
    else
    {
		// Interpolate somewhere along the path
        const double t = (span-remain)/span;
		globeView->setRotQuat(startRot.slerp(t,endRot));
	}
}

}
