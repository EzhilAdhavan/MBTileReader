/*  MapboxVectorStyleRaster.cpp
 *  WhirlyGlobe-MaplyComponent
 *
 *  Created by Steve Gifford on 2/17/15.
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

#import "MapboxVectorStyleRaster.h"

namespace WhirlyKit
{

bool MapboxVectorLayerRaster::parse(PlatformThreadInfo *inst,
                                    const DictionaryRef &styleEntry,
                                    const MapboxVectorStyleLayerRef &refLayer,
                                    int drawPriority)
{
    return MapboxVectorStyleLayer::parse(inst, styleEntry, refLayer, drawPriority);
}

MapboxVectorStyleLayerRef MapboxVectorLayerRaster::clone() const
{
    auto layer = std::make_shared<MapboxVectorLayerRaster>(styleSet);
    layer->copy(*this);
    return layer;
}

MapboxVectorStyleLayer& MapboxVectorLayerRaster::copy(const MapboxVectorStyleLayer& that)
{
    this->MapboxVectorStyleLayer::copy(that);
    if (const auto line = dynamic_cast<const MapboxVectorLayerRaster*>(&that))
    {
        operator=(*line);
    }
    return *this;
}

void MapboxVectorLayerRaster::buildObjects(__unused PlatformThreadInfo *inst,
                                           __unused const std::vector<VectorObjectRef> &vecObjs,
                                           __unused const VectorTileDataRef &tileInfo,
                                           __unused const Dictionary *desc,
                                           __unused const CancelFunction &cancelFn)
{
}

}
