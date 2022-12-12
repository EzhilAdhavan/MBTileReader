/*  CoordSystem.cpp
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 9/14/11.
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
#import "CoordSystem.h"

using namespace Eigen;

namespace WhirlyKit
{

Point3f CoordSystemConvert(const CoordSystem *inSystem,const CoordSystem *outSystem,const Point3f &inCoord)
{
    // Easy if the coordinate systems are the same
    if (inSystem->isSameAs(outSystem))
        return inCoord;
    
    // We'll go through geocentric which isn't horrible, but obviously we're assuming the same datum
    return outSystem->geocentricToLocal(inSystem->localToGeocentric(inCoord));
}

Point3d CoordSystemConvert3d(const CoordSystem *inSystem,const CoordSystem *outSystem,const Point3d &inCoord)
{
    // Easy if the coordinate systems are the same
    if (inSystem->isSameAs(outSystem))
        return inCoord;
    
    // We'll go through geocentric which isn't horrible, but obviously we're assuming the same datum
    return outSystem->geocentricToLocal(inSystem->localToGeocentric(inCoord));
}

GeneralCoordSystemDisplayAdapter::GeneralCoordSystemDisplayAdapter(CoordSystem *coordSys,const Point3d &ll,const Point3d &ur,
                                                                   const Point3d &inCenter,const Point3d &inScale) :
    CoordSystemDisplayAdapter(coordSys,inCenter),
    ll(ll), ur(ur),
    coordSys(coordSys)
{
    scale = inScale;
    center = inCenter;
    dispLL = localToDisplay(ll);    //NOLINT derived virtual methods not called
    dispUR = localToDisplay(ur);    //NOLINT
    geoLL = coordSys->localToGeographicD(ll);
    geoUR = coordSys->localToGeographicD(ur);
}

bool GeneralCoordSystemDisplayAdapter::getBounds(Point3f &outLL,Point3f &outUR) const
{
    outLL = ll.cast<float>();
    outUR = ur.cast<float>();
    return true;
}
    
bool GeneralCoordSystemDisplayAdapter::getDisplayBounds(Point3d &inLL,Point3d &inUR) const
{
    inLL = dispLL;
    inUR = dispUR;
    return true;
}
    
bool GeneralCoordSystemDisplayAdapter::getGeoBounds(Point2d &inLL,Point2d &inUR) const
{
    inLL = geoLL;
    inUR = geoUR;
    return true;
}
    
Point3f GeneralCoordSystemDisplayAdapter::localToDisplay(const Point3f &localPt) const
{
    return (localPt.cast<double>().cwiseProduct(scale) - center).cast<float>();
}

Point3d GeneralCoordSystemDisplayAdapter::localToDisplay(const Point3d &localPt) const
{
    return localPt.cwiseProduct(scale) - center;
}
    
Point3f GeneralCoordSystemDisplayAdapter::displayToLocal(const Point3f &dispPt) const
{
    return (dispPt.cast<double>().cwiseQuotient(scale) + center).cast<float>();
}

Point3d GeneralCoordSystemDisplayAdapter::displayToLocal(const Point3d &dispPt) const
{
    return dispPt.cwiseQuotient(scale) + center;
}

}
