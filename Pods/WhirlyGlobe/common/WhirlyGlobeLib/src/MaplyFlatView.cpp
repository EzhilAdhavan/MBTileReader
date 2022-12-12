/*  MaplyFlatView.cpp
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 5/2/13.
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

#import "MaplyFlatView.h"

using namespace Eigen;
using namespace WhirlyKit;

namespace Maply
{
    
FlatView::FlatView(WhirlyKit::CoordSystemDisplayAdapter *coordAdapter) :
    MapView(coordAdapter)
{
    loc = Point3d(0,0,0);
    setPlanes(1, -1);
    extents = MbrD(Point2d(-M_PI,-M_PI/2.0),Point2d(M_PI,M_PI/2.0));
    windowSize = Point2d(1.0,1.0);
    contentOffset = Point2d(0,0);
}

Eigen::Matrix4d FlatView::calcModelMatrix() const
{
    Eigen::Affine3d scale(Eigen::AlignedScaling3d(2.0 / (extents.ur().x() - extents.ll().x()),2.0 / (extents.ur().y() - extents.ll().y()),1.0));
    
    return scale.matrix();
}

Eigen::Matrix4d FlatView::calcProjectionMatrix(Point2f frameBufferSize,float margin) const
{
    // If the framebuffer isn't set up, just return something simple
    if (frameBufferSize.x() == 0.0 || frameBufferSize.y() == 0.0)
    {
        Eigen::Matrix4d projMat;
        projMat.setIdentity();
        return projMat;
    }
    
    double left,right,top,bot,near,far;
    double contentOffsetY = windowSize.y() - frameBufferSize.y() - contentOffset.y();
    left = 2.0 * contentOffset.x() / (windowSize.x()) - 1.0;
    right = 2.0 * (contentOffset.x() + frameBufferSize.x()) / windowSize.x() - 1.0;
    top = 2.0 * (contentOffsetY + frameBufferSize.y()) / windowSize.y() - 1.0;
    bot = 2.0 * contentOffsetY / windowSize.y() - 1.0;
    near = getNearPlane();
    far = getFarPlane();
    
    // Borrowed from the "OpenGL ES 2.0 Programming" book
    // Orthogonal matrix
    const Point3d delta(right-left,top-bot,far-near);
    Eigen::Matrix4d projMat;
    projMat.setIdentity();
    projMat(0,0) = 2.0 / delta.x();
    projMat(0,3) = -(right + left) / delta.x();
    projMat(1,1) = 2.0 / delta.y();
    projMat(1,3) = -(top + bot) / delta.y();
    projMat(2,2) = -2.0 / delta.z();
    projMat(2,3) = - (near + far) / delta.z();
    
    return projMat;
}

double FlatView::heightAboveSurface() const
{
    return 0.0;
}

double FlatView::minHeightAboveSurface() const
{
    return 0.0;
}

double FlatView::maxHeightAboveSurface() const
{
    return 0.0;
}
    
void FlatView::setLoc(const WhirlyKit::Point3d &newLoc)
{
    loc = newLoc;
    loc.z() = 0.0;
}
    
void FlatView::setExtents(const WhirlyKit::MbrD &inExtents)
{
    extents = inExtents;
}

void FlatView::setWindow(const WhirlyKit::Point2d &inWindowSize,const WhirlyKit::Point2d &inContentOffset)
{
    windowSize = inWindowSize;
    contentOffset = inContentOffset;

    runViewUpdates();
}

Point2d FlatView::screenSizeInDisplayCoords(const Point2f &frameSize)
{
    Point2d screenSize(0,0);
    if (frameSize.x() == 0.0 || frameSize.y() == 0.0)
        return screenSize;
    
    screenSize = ur-ll;
    
    return screenSize;
}

}
