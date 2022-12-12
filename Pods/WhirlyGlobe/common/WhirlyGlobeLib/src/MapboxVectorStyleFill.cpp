/*  MapboxVectorStyleFill.cpp
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

#import "MapboxVectorStyleFill.h"
#import "VectorObject.h"
#import "Tesselator.h"
#import "WhirlyKitLog.h"

namespace WhirlyKit
{

bool MapboxVectorFillPaint::parse(PlatformThreadInfo *,
                                  MapboxVectorStyleSetImpl *styleSet,
                                  const DictionaryRef &styleEntry)
{
    MapboxVectorStyleSetImpl::unsupportedCheck("fill-antialias","paint_fill",styleEntry);
    MapboxVectorStyleSetImpl::unsupportedCheck("fill-translate","paint_fill",styleEntry);
    MapboxVectorStyleSetImpl::unsupportedCheck("fill-translate-anchor","paint_fill",styleEntry);
    MapboxVectorStyleSetImpl::unsupportedCheck("fill-image","paint_fill",styleEntry);
    
    opacity = styleSet->transDouble("fill-opacity",styleEntry,1.0);
    color = styleSet->transColor("fill-color",styleEntry,nullptr);
    outlineColor = styleSet->transColor("fill-outline-color",styleEntry,nullptr);
    
    // We're also handling fill-extrusion as a hack
    if (styleEntry && styleEntry->hasField("fill-extrusion-color"))
        color = styleSet->transColor("fill-extrusion-color",styleEntry,nullptr);
    if (styleEntry && styleEntry->hasField("fill-extrusion-opacity"))
        opacity = styleSet->transDouble("fill-extrusion-opacity",styleEntry,1.0);

    return true;
}

bool MapboxVectorLayerFill::parse(PlatformThreadInfo *inst,
                                  const DictionaryRef &styleEntry,
                                  const MapboxVectorStyleLayerRef &refLayer,
                                  int inDrawPriority)
{
    if (!MapboxVectorStyleLayer::parse(inst,styleEntry,refLayer,drawPriority) ||
        !paint.parse(inst,styleSet,styleEntry->getDict("paint")))
    {
        return false;
    }
    
    arealShaderID = styleSet->tileStyleSettings->settingsArealShaderID;
    
    // Mess directly with the opacity because we're using it for other purposes
    if (styleEntry && styleEntry->hasField("alphaoverride"))
    {
        paint.color->setAlphaOverride(styleEntry->getDouble("alphaoverride"));
    }
    
    drawPriority = inDrawPriority;
    
    return true;
}

MapboxVectorStyleLayerRef MapboxVectorLayerFill::clone() const
{
    auto layer = std::make_shared<MapboxVectorLayerFill>(styleSet);
    layer->copy(*this);
    return layer;
}

MapboxVectorStyleLayer& MapboxVectorLayerFill::copy(const MapboxVectorStyleLayer& that)
{
    this->MapboxVectorStyleLayer::copy(that);
    if (const auto fill = dynamic_cast<const MapboxVectorLayerFill*>(&that))
    {
        operator=(*fill);
    }
    return *this;
}

void MapboxVectorLayerFill::buildObjects(PlatformThreadInfo *inst,
                                         const std::vector<VectorObjectRef> &vecObjs,
                                         const VectorTileDataRef &tileInfo,
                                         const Dictionary *desc,
                                         const CancelFunction &cancelFn)
{
    // If a representation is set, we produce results for non-visible layers
    if (!visible /*&& representation.empty()*/)
    {
        return;
    }

    if (!paint.color && !paint.outlineColor)
    {
        return;
    }

    auto compObj = styleSet->makeComponentObject(inst, desc);

    // not currently supported
    //compObj->representation = representation;

    // Gather all the areal features for fill and/or outline
    std::vector<VectorShapeRef> shapes;
    for (const auto& vecObj : vecObjs)
    {
        if (vecObj->getVectorType() == VectorArealType)
        {
            if (shapes.empty())
            {
                shapes.reserve(vecObjs.size() * 20);
            }
            std::copy(vecObj->shapes.begin(),vecObj->shapes.end(),std::back_inserter(shapes));
        }
    }

    // Filled polygons
    if (paint.color)
    {
        // tessellate the area features
        std::vector<VectorShapeRef> tessShapes;
        tessShapes.reserve(shapes.size());
        for (const auto &it : shapes)
        {
            if (cancelFn(inst))
            {
                return;
            }
            if (const auto ar = dynamic_cast<VectorAreal*>(it.get()))
            {
                auto scene = styleSet->vecManage->getScene();
                auto coordAdapter = scene->getCoordAdapter();
                auto coordSys = coordAdapter->getCoordSystem();

                // Convert to local to make tessellation work better (#1392)
                for (auto &loop : ar->loops)
                {
                    for (auto &pt : loop)
                    {
                        pt = coordSys->geographicToLocal2(pt.cast<double>()).cast<float>();
                    }
                }

                const auto trisRef = VectorTriangles::createTriangles();
                trisRef->localCoords = true;
                TesselateLoops(ar->loops, trisRef);
                trisRef->setAttrDict(ar->getAttrDict());

                // Generate MBR in local, that's what the builders will expect when we've
                // converted to local triangles.
                trisRef->initGeoMbr();

                tessShapes.push_back(trisRef);
            }
        }

        MBResolveColorType resolveMode = MBResolveColorOpacityComposeAlpha;
#ifdef __ANDROID__
        // On Android, pre-multiply the alpha on static colors.
        // When the color or opacity is dynamic, we need to do it in the tweaker.
        if ((!paint.color || !paint.color->isExpression()) &&
            (!paint.opacity || !paint.opacity->isExpression()))
        {
            resolveMode = MBResolveColorOpacityMultiply;
        }
#endif
        if (const auto color = MapboxVectorStyleSetImpl::resolveColor(paint.color, paint.opacity,
                                                                      tileInfo->ident.level, resolveMode))
        {
            // Set up the description for constructing vectors
            VectorInfo vecInfo;
            vecInfo.hasExp = true;
            vecInfo.filled = true;
            vecInfo.centered = true;
            vecInfo.color = *color;
            vecInfo.zoomSlot = styleSet->zoomSlot;
            vecInfo.zBufferWrite = styleSet->tileStyleSettings->zBufferWrite;
            vecInfo.zBufferRead = styleSet->tileStyleSettings->zBufferRead;
            vecInfo.colorExp = paint.color->expression();
            vecInfo.opacityExp = paint.opacity->expression();
            vecInfo.programID = (arealShaderID != EmptyIdentity) ? arealShaderID : styleSet->vectorArealProgramID;
            vecInfo.drawPriority = drawPriority + tileInfo->ident.level * std::max(0, styleSet->tileStyleSettings->drawPriorityPerLevel) + 1;
            // TODO: Switch to stencils
//            vecInfo.drawOrder = tileInfo->tileNumber();

//            wkLogLevel(Debug, "fill: tileID = %d: (%d,%d)  drawOrder = %d, drawPriority = %d",tileInfo->ident.level, tileInfo->ident.x, tileInfo->ident.y, vecInfo.drawOrder,vecInfo.drawPriority);

            if (minzoom != 0 || maxzoom < 1000)
            {
                vecInfo.minZoomVis = minzoom;
                vecInfo.maxZoomVis = maxzoom;
            }

            //wkLogLevel(Debug, "Color: %s %d %d %d %d",ident.c_str(),(int)color->r,(int)color->g,(int)color->b,(int)color->a);

            const SimpleIdentity vecID = styleSet->vecManage->addVectors(&tessShapes, vecInfo, tileInfo->changes);
            if (vecID != EmptyIdentity)
            {
                compObj->vectorIDs.insert(vecID);
                
                if (selectable)
                {
                    compObj->isSelectable = selectable;
                    compObj->vecObjs = vecObjs;
                }
            }
        }
    }
    
    // Outlines
    if (paint.outlineColor)
    {
        if (const auto color = WhirlyKit::MapboxVectorStyleSetImpl::resolveColor(
                paint.outlineColor, paint.opacity,
                tileInfo->ident.level, MBResolveColorOpacityComposeAlpha))
        {
            // Set up the description for constructing vectors
            VectorInfo vecInfo;
            vecInfo.hasExp = true;
            vecInfo.filled = false;
            vecInfo.centered = true;
            vecInfo.colorExp = paint.outlineColor->expression();
            vecInfo.opacityExp = paint.opacity->expression();
            vecInfo.programID = (arealShaderID != EmptyIdentity) ? arealShaderID : styleSet->vectorArealProgramID;
            vecInfo.color = *color;
            vecInfo.zoomSlot = styleSet->zoomSlot;
            vecInfo.drawPriority = drawPriority + tileInfo->ident.level * std::max(0, styleSet->tileStyleSettings->drawPriorityPerLevel) + 1;
            vecInfo.drawOrder = tileInfo->tileNumber();

            if (minzoom != 0 || maxzoom < 1000)
            {
                vecInfo.zoomSlot = styleSet->zoomSlot;
                vecInfo.minZoomVis = minzoom;
                vecInfo.maxZoomVis = maxzoom;
            }

            const SimpleIdentity vecID = styleSet->vecManage->addVectors(&shapes, vecInfo, tileInfo->changes);
            if (vecID != EmptyIdentity)
            {
                compObj->vectorIDs.insert(vecID);
            }
        }
    }
    
    if (!compObj->vectorIDs.empty())
    {
        styleSet->compManage->addComponentObject(compObj, tileInfo->changes);
        tileInfo->compObjs.push_back(std::move(compObj));
    }
}

}
