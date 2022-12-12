/* MapboxVectorStyleCircle.cpp
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

#import "MapboxVectorStyleCircle.h"

namespace WhirlyKit
{

extern const int ScreenDrawPriorityOffset;

bool MapboxVectorCirclePaint::parse(PlatformThreadInfo *,
                                    MapboxVectorStyleSetImpl *styleSet,
                                    const DictionaryRef &styleEntry)
{
    if (!styleSet)
        return false;
    
    radius = styleSet->transDouble("circle-radius", styleEntry, 5.0);
    fillColor = MapboxVectorStyleSetImpl::colorValue("circle-color",nullptr,styleEntry,RGBAColor::black(),false);
    opacity = styleSet->transDouble("circle-opacity",styleEntry,1.0);
    strokeWidth = styleSet->transDouble("circle-stroke-width",styleEntry,0.0);
    strokeColor = MapboxVectorStyleSetImpl::colorValue("circle-stroke-color",nullptr,styleEntry,RGBAColor::black(),false);
    strokeOpacity = styleSet->transDouble("circle-stroke-opacity",styleEntry,1.0);
    
    return true;
}

bool MapboxVectorLayerCircle::parse(PlatformThreadInfo *inst,
                                    const DictionaryRef &styleEntry,
                                    const MapboxVectorStyleLayerRef &refLayer,
                                    int drawPriority)
{
    if (!MapboxVectorStyleLayer::parse(inst,styleEntry,refLayer,drawPriority) ||
        !paint.parse(inst, styleSet, styleEntry->getDict("paint")))
    {
        return false;
    }

    const double maxRadius = paint.radius->maxVal();
    const auto maxStrokeWidth = (float)paint.strokeWidth->maxVal();

    // todo: have to evaluate these dynamically to support expressions
    const auto theFillColor = paint.opacity ?
            paint.fillColor->withAlpha((float)paint.opacity->valForZoom(0)) :
            *paint.fillColor;
    const auto theStrokeColor = paint.strokeOpacity ?
            paint.strokeColor->withAlpha((float)paint.strokeOpacity->valForZoom(0)) :
            *paint.strokeColor;

    circleTexID = styleSet->makeCircleTexture(inst,maxRadius,theFillColor,theStrokeColor,maxStrokeWidth,&circleSize);

    // Larger circles are slightly more important
    importance = (float)(drawPriority/1000.0 + styleSet->tileStyleSettings->markerImportance + maxRadius / 100000.0);

    repUUIDField = MapboxVectorStyleSetImpl::stringValue("X-Maply-RepresentationUUIDField", styleEntry, std::string());

    uuidField = styleSet->tileStyleSettings->uuidField;
    uuidField = MapboxVectorStyleSetImpl::stringValue("X-Maply-UUIDField", styleEntry, uuidField);

    return true;
}

MapboxVectorStyleLayerRef MapboxVectorLayerCircle::clone() const
{
    auto layer = std::make_shared<MapboxVectorLayerCircle>(styleSet);
    layer->copy(*this);
    return layer;
}

MapboxVectorStyleLayer& MapboxVectorLayerCircle::copy(const MapboxVectorStyleLayer& that)
{
    this->MapboxVectorStyleLayer::copy(that);
    if (const auto fill = dynamic_cast<const MapboxVectorLayerCircle*>(&that))
    {
        operator=(*fill);
    }
    return *this;
}

void MapboxVectorLayerCircle::cleanup(PlatformThreadInfo *inst,ChangeSet &changes)
{
    if (circleTexID != EmptyIdentity)
    {
        changes.push_back(new RemTextureReq(circleTexID));
    }
}

void MapboxVectorLayerCircle::buildObjects(PlatformThreadInfo *inst,
                                           const std::vector<VectorObjectRef> &vecObjs,
                                           const VectorTileDataRef &tileInfo,
                                           const Dictionary *desc,
                                           const CancelFunction &cancelFn)
{
    // If a representation is set, we produce results for non-visible layers
    if ((!visible  && (representation.empty() || repUUIDField.empty())) || circleTexID == EmptyIdentity)
    {
        return;
    }

    using MarkerPtrVec = std::vector<WhirlyKit::Marker*>;
    using VecObjRefVec = std::vector<VectorObjectRef>;
    auto const capacity = vecObjs.size() * 5;  // ?
    std::unordered_map<std::string,std::pair<MarkerPtrVec,VecObjRefVec>> markersByUUID(capacity);

    const double opacity = paint.opacity->valForZoom(tileInfo->ident.level);
    const double radius = paint.radius->valForZoom(tileInfo->ident.level);

    // Default settings
    MarkerInfo markerInfo(/*screenObject=*/true);
    markerInfo.zoomSlot = styleSet->zoomSlot;
    markerInfo.color = RGBAColor(255,255,255,(int)(opacity*255));
    markerInfo.drawPriority = drawPriority + ScreenDrawPriorityOffset +
        tileInfo->ident.level * std::max(0, styleSet->tileStyleSettings->drawPriorityPerLevel) + 1;
    markerInfo.programID = styleSet->screenMarkerProgramID;
    
    if (minzoom != 0 || maxzoom < 1000)
    {
        markerInfo.minZoomVis = minzoom;
        markerInfo.maxZoomVis = maxzoom;
    }

    VectorRing tmpRing;

    std::vector<std::unique_ptr<WhirlyKit::Marker>> markerOwner; // automatic cleanup of local temporary allocations
    const auto emptyVal = std::make_pair(MarkerPtrVec(), VecObjRefVec());
    for (const auto &vecObj : vecObjs)
    {
        if (cancelFn(inst))
        {
            return;
        }
        if (vecObj->getVectorType() != VectorPointType &&
            vecObj->getVectorType() != VectorLinearType)
        {
            continue;
        }

        const auto attrs = vecObj->getAttributes();
        const auto &settings = *styleSet->tileStyleSettings;

        for (const VectorShapeRef &shape : vecObj->shapes)
        {
            VectorRing* pts;
            if (const auto vecPts = dynamic_cast<VectorPoints*>(shape.get()))
            {
                pts = &vecPts->pts;
            }
            else if (const auto vecLin = dynamic_cast<VectorLinear*>(shape.get()))
            {
                tmpRing.clear();
                const auto area = CalcLoopArea(vecLin->pts);
                if (area == 0)
                {
                    tmpRing.push_back(vecLin->calcGeoMbr().mid());
                }
                else
                {
                    tmpRing.push_back(CalcLoopCentroid(vecLin->pts, area));
                }
                pts = &tmpRing;
            }
            else
            {
                continue;
            }

            for (const auto &pt : *pts)
            {
                if (markerOwner.empty())
                {
                    markerOwner.reserve(pts->size() * vecObj->shapes.size());
                }

                // Add a marker per point
                markerOwner.emplace_back(std::make_unique<WhirlyKit::Marker>());
                auto marker = markerOwner.back().get();
                marker->loc = GeoCoord(pt.x(),pt.y());
                marker->texIDs.push_back(circleTexID);
                marker->width = (float)(2*radius * settings.markerScale * settings.circleScale);
                marker->height = (float)(2*radius * settings.markerScale * settings.circleScale);
                marker->layoutWidth = marker->width;
                marker->layoutHeight = marker->height;
                marker->layoutImportance = MAXFLOAT;    //importance + (101-tileInfo->ident.level)/100.0;
                marker->uniqueID = uuidField.empty() ? std::string() : attrs->getString(uuidField);

                const std::string repUUID = repUUIDField.empty() ? std::string() : attrs->getString(repUUIDField);

                // Look up the vectors of markers/objects for this uuid (including blank), inserting empty ones if necessary
                const auto result = markersByUUID.insert(std::make_pair(repUUID, emptyVal));

                auto &markers = result.first->second.first;
                auto &markerObjs = result.first->second.second;

                if (markers.empty())
                {
                    markers.reserve(pts->size());
                    markerObjs.reserve(pts->size());
                }
                markers.push_back(marker);
                markerObjs.push_back(vecObj);
            }
        }
    }

    for (const auto &kvp : markersByUUID)
    {
        const auto &uuid = kvp.first;
        const auto &markers = kvp.second.first;
        const auto &markerObjs = kvp.second.second;

        if (markers.empty())
        {
            continue;
        }
        if (cancelFn(inst))
        {
            break;
        }

        // Generate one component object per unique UUID (including blank)
        auto compObj = styleSet->makeComponentObject(inst, desc);

        // Keep the vector objects around if they need to be selectable
        if (selectable)
        {
            assert(markers.size() == markerObjs.size());
            const auto count = std::min(markers.size(), markerObjs.size());
            for (auto i = (size_t)0; i < count; ++i)
            {
                auto *marker = markers[i];
                const auto &vecObj = markerObjs[i];

                marker->isSelectable = true;
                marker->selectID = Identifiable::genId();
                styleSet->addSelectionObject(marker->selectID, vecObj, compObj);
                compObj->selectIDs.insert(marker->selectID);
                compObj->isSelectable = true;
            }
        }

        // Set up the markers and get a change set
        if (const auto markerID = styleSet->markerManage->addMarkers(markers, markerInfo, tileInfo->changes))
        {
            compObj->uuid = uuid;
            compObj->representation = representation;
            compObj->markerIDs.insert(markerID);
            styleSet->compManage->addComponentObject(compObj, tileInfo->changes);
            tileInfo->compObjs.push_back(std::move(compObj));
        }
    }
}

}
