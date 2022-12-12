/*  TextureAtlas.mm
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 3/28/11.
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

#import "TextureAtlas.h"
#import "WhirlyGeometry.h"
#import "GlobeMath.h"

using namespace Eigen;
using namespace WhirlyKit;

// Set up the texture mapping matrix from the destination texture coords
void SubTexture::setFromTex(const TexCoord &texOrg,const TexCoord &texDest)
{
    trans = decltype(trans)::Identity();
    trans.translate(texOrg);
    trans.scale(texDest - texOrg);
}

// Calculate a destination texture coordinate
TexCoord SubTexture::processTexCoord(const TexCoord &inCoord) const
{
    return Slice(trans * Pad(inCoord, 1.0f));
}

// Calculate destination texture coords for a while group
void SubTexture::processTexCoords(std::vector<TexCoord> &coords) const
{
    for (auto &coord : coords)
    {
        const Vector3f res = trans * Vector3f(coord.x(),coord.y(),1.0f);
        coord.x() = res.x();
        coord.y() = res.y();
    }
}
