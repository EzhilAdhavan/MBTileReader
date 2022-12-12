/*
 *  MapboxVectorStyleSet.mm
 *  WhirlyGlobe-MaplyComponent
 *
 *  Created by Steve Gifford on 2/16/15.
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

#import <WhirlyGlobe.h>
#import "private/MapboxVectorStyleSet_private.h"
#import "private/MaplyVectorStyle_private.h"
#import "MaplyRenderController_private.h"
#import <map>

using namespace WhirlyKit;

@implementation MaplyLegendEntry
@end

@implementation MapboxVectorStyleSet
{
    UIImage *spriteImage;
}

- (id __nullable)initWithDict:(NSDictionary * __nonnull)styleDict
                    settings:(MaplyVectorStyleSettings * __nonnull)settings
                       viewC:(NSObject<MaplyRenderControllerProtocol> * __nonnull)viewC
{
    if (!(self = [super init]))
    {
        return nil;
    }

    if (!(_viewC = viewC))
    {
        return nil;
    }

    if (const auto *renderControl = [viewC getRenderControl])
    if (auto *scene = renderControl->scene)
    if (const auto &view = renderControl->visualView)
    if (const auto *coordAdapter = view->getCoordAdapter())
    if (auto *coordSys = coordAdapter->getCoordSystem())
    {
        const auto styleSettings = (settings && settings->impl) ? settings->impl :
            std::make_shared<VectorStyleSettingsImpl>([UIScreen mainScreen].scale);
        style = std::make_shared<MapboxVectorStyleSetImpl_iOS>(scene, coordSys, styleSettings);
        style->viewC = viewC;
    }
    if (!style)
    {
        return nil;
    }

    // Copy from NSDictionary to our internal version
    if (auto dictWrap = [styleDict toDictionaryC])
    {
        if (!style->parse(nullptr, dictWrap))
        {
            return nil;
        }
    }
    
    _spriteURL = styleDict[@"sprite"];
    
    // Sources tell us where to get tiles
    if (NSDictionary *sourceStyles = styleDict[@"sources"])
    {
        NSMutableArray *sources = [NSMutableArray array];
        for (NSString *sourceName in sourceStyles.allKeys)
        {
            NSDictionary *styleEntry = sourceStyles[sourceName];
            if (MaplyMapboxVectorStyleSource *source = [[MaplyMapboxVectorStyleSource alloc] initWithName:sourceName
                                                                                               styleEntry:styleEntry
                                                                                                 styleSet:self
                                                                                                    viewC:viewC])
            {
                [sources addObject:source];
            }
        }
        _sources = sources;
    }

    return self;
}

- (id)initWithJSON:(NSData *)styleJSON
          settings:(MaplyVectorStyleSettings *)settings
             viewC:(NSObject<MaplyRenderControllerProtocol> *)viewC
{
    NSError *error = nil;
    NSDictionary *styleDict = [NSJSONSerialization JSONObjectWithData:styleJSON options:NULL error:&error];
    if (!styleDict)
        return nil;
    
    return [self initWithDict:styleDict settings:settings viewC:viewC];
}

- (void)dealloc
{
    
}

- (bool)addSprites:(NSDictionary * __nonnull)spriteDict image:(UIImage * __nonnull)image
{
    // Make sure this wasn't alreayd added
    if (spriteImage)
        return true;

    spriteImage = image;
    MaplyTexture *wholeTex = [_viewC addTexture:image desc:nil mode:MaplyThreadCurrent];

    auto newSprites = std::make_shared<MapboxVectorStyleSprites>(wholeTex.texID,(int)image.size.width,(int)image.size.height);
    auto dictWrap = std::make_shared<iosDictionary>(spriteDict);
    if (newSprites->parse(style, dictWrap))
    {
        style->addSprites(newSprites,wholeTex);
        return true;
    }
    return false;
}

- (UIColor * __nullable)backgroundColorForZoom:(double)zoom
{
    RGBAColorRef color = style->backgroundColor(NULL,zoom);
    if (!color)
        return [UIColor blackColor];
    return [UIColor colorFromRGBA:*color];
}

- (NSArray<NSString *> *)layerNames
{
    NSMutableArray *names = [NSMutableArray array];
    
    for (auto layer : style->layers) {
        NSString *name = [NSString stringWithUTF8String:layer->ident.c_str()];
        if (name)
            [names addObject:name];
    }
    
    return names;
}

- (MapboxLayerType) layerType:(NSString * __nonnull)inLayerName
{
    std::string layerName = [inLayerName cStringUsingEncoding:NSUTF8StringEncoding];
    
    for (auto layer : style->layers) {
        if (layer->ident == layerName) {
            if (dynamic_cast<MapboxVectorLayerBackground *>(layer.get()))
                return MapboxLayerTypeBackground;
            else if (dynamic_cast<MapboxVectorLayerCircle *>(layer.get()))
                return MapboxLayerTypeCircle;
            else if (dynamic_cast<MapboxVectorLayerFill *>(layer.get()))
                return MapboxLayerTypeFill;
            else if (dynamic_cast<MapboxVectorLayerLine *>(layer.get()))
                return MapboxLayerTypeLine;
            else if (dynamic_cast<MapboxVectorLayerRaster *>(layer.get()))
                return MapboxLayerTypeRaster;
            else if (dynamic_cast<MapboxVectorLayerSymbol *>(layer.get()))
                return MapboxLayerTypeSymbol;
        }
    }
    
    return MapboxLayerTypeUnknown;
}

- (void)setLayerVisible:(NSString *__nonnull)inLayerName visible:(bool)visible
{
    std::string layerName = [inLayerName cStringUsingEncoding:NSUTF8StringEncoding];
    
    for (auto layer : style->layers) {
        if (layer->ident == layerName) {
            layer->visible = visible;
        }
    }
}

- (UIColor * __nullable) colorForLayer:(NSString *__nonnull)inLayerName
{
    std::string layerName = [inLayerName cStringUsingEncoding:NSUTF8StringEncoding];

    for (auto layer : style->layers) {
        if (layer->ident == layerName) {
            auto layerBack = std::dynamic_pointer_cast<MapboxVectorLayerBackground>(layer);
            if (layerBack) {
                auto color = layerBack->paint.color;
                if (!color)
                    return nil;
                return [UIColor colorFromRGBA:color->colorForZoom(0.0)];
            } else {
                auto layerSymbol = std::dynamic_pointer_cast<MapboxVectorLayerSymbol>(layer);
                if (layerSymbol) {
                    auto color = layerSymbol->paint.textColor;
                    if (!color)
                        return nil;
                    return [UIColor colorFromRGBA:color->colorForZoom(0.0)];
                } else {
                    auto layerCircle = std::dynamic_pointer_cast<MapboxVectorLayerCircle>(layer);
                    if (layerCircle) {
                        auto color = layerCircle->paint.fillColor;
                        if (!color)
                            return nil;
                        return [UIColor colorFromRGBA:*color];
                    } else {
                        auto layerLine = std::dynamic_pointer_cast<MapboxVectorLayerLine>(layer);
                        if (layerLine) {
                            auto color = layerLine->paint.color;
                            if (!color)
                                return nil;
                            return [UIColor colorFromRGBA:color->colorForZoom(0.0)];
                        } else {
                            auto layerFill = std::dynamic_pointer_cast<MapboxVectorLayerFill>(layer);
                            if (layerFill) {
                                auto color = layerFill->paint.color;
                                if (!color)
                                    return nil;
                                return [UIColor colorFromRGBA:color->colorForZoom(0.0)];
                            }
                        }
                    }
                }
            }
            return nil;
        }
    }
    
    return nil;
}

- (UIImage *)imageForText:(UIColor *)color size:(CGSize)size
{
    UIGraphicsBeginImageContext(size);
    CGFloat fontSize = size.width - 2.0;
    UIFont *font = [UIFont fontWithName:@"Arial-BoldMT" size:fontSize];
    NSString *text = @"T";
    CGFloat margin = 1.0;
    [text drawInRect:CGRectMake(margin,margin,size.width-2*margin,size.height-2*margin)
      withAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color}];
    
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return img;
}

- (UIImage *)imageForLinear:(UIColor *)color size:(CGSize)size
{
    UIGraphicsBeginImageContext(size);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(ctx, size.width/10.0);
    [color setStroke];
    CGContextMoveToPoint(ctx, 0.0, size.height);
    CGContextAddLineToPoint(ctx, size.width, 0.0);
    CGContextStrokePath(ctx);
    
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return img;
}

- (UIImage *)imageForSymbol:(const std::string &)symbolName size:(CGSize)size
{
    if (!style->sprites)
        return nil;
    
    auto sprite = style->sprites->getSprite(symbolName);
    if (sprite.name.empty())
        return nil;

    CGImageRef drawImage = CGImageCreateWithImageInRect(spriteImage.CGImage,
                                                        CGRectMake(sprite.x, sprite.y, sprite.width, sprite.height));
    UIImage *img = [UIImage imageWithCGImage:drawImage];
    CGImageRelease(drawImage);

    return img;
}

- (UIImage *)imageForPolygon:(UIColor *)color size:(CGSize)size
{
    UIGraphicsBeginImageContext(size);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat margin = 1.0;
    [color setFill];
    CGContextFillRect(ctx, CGRectMake(0.0, 0.0, size.width, size.height));
    [UIColor.blackColor setFill];
    CGContextStrokeRect(ctx, CGRectMake(margin, margin, size.width-2*margin, size.height-2*margin));

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return img;
}

- (UIImage *)imageForCircle:(UIColor *)color size:(CGSize)size
{
    UIGraphicsBeginImageContext(size);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [color setFill];
    CGFloat margin = 1.0;
    CGContextFillEllipseInRect(ctx, CGRectMake(margin, margin, size.width-2*margin, size.height-2*margin));
    [UIColor.blackColor setStroke];
    CGContextStrokeEllipseInRect(ctx, CGRectMake(margin, margin, size.width-2*margin, size.height-2*margin));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return img;
}

- (NSArray<MaplyLegendEntry *> * __nonnull)layerLegend:(CGSize)imageSize group:(bool)useGroups
{
    NSMutableArray *legend = [NSMutableArray arrayWithCapacity:(NSUInteger)style->layers.size()];
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    
    for (const auto &layer : style->layers) {
        if (!layer->representation.empty()) {
            // This is an alternate representation of another layer, e.g., "selected"
            continue;
        }
            
        UIImage *image = nil;
        if (auto layerBackground = dynamic_cast<MapboxVectorLayerBackground*>(layer.get())) {
            if (layerBackground->paint.color) {
                image = [self imageForPolygon:[UIColor colorFromRGBA:layerBackground->paint.color->colorForZoom(0.0)] size:imageSize];
            }
        } else if (auto layerSymbol = dynamic_cast<MapboxVectorLayerSymbol*>(layer.get())) {
            if (layerSymbol->layout.iconImageField) {
                MapboxRegexField textField = layerSymbol->layout.iconImageField->textForZoom(0.0);
                if (!textField.chunks.empty()) {
                    image = [self imageForSymbol:textField.chunks[0].str size:imageSize];
                }
            } else if (layerSymbol->paint.textColor) {
                image = [self imageForText:[UIColor colorFromRGBA:layerSymbol->paint.textColor->colorForZoom(0.0)] size:imageSize];
            }
        } else if (auto layerCircle = dynamic_cast<MapboxVectorLayerCircle*>(layer.get())) {
            if (const auto &color = layerCircle->paint.fillColor) {
                image = [self imageForCircle:[UIColor colorFromRGBA:*color] size:imageSize];
            }
        } else if (auto layerLine = dynamic_cast<MapboxVectorLayerLine*>(layer.get())) {
            if (const auto &color = layerLine->paint.color) {
                image = [self imageForLinear:[UIColor colorFromRGBA:color->colorForZoom(0.0)] size:imageSize];
            }
        } else if (auto layerFill = dynamic_cast<MapboxVectorLayerFill*>(layer.get())) {
            if (const auto &color = layerFill->paint.color) {
                image = [self imageForPolygon:[UIColor colorFromRGBA:color->colorForZoom(0.0)] size:imageSize];
            }
        }

        if (!layer->ident.empty()) {
            std::string groupName;
            std::string name = layer->ident;
            if (useGroups) {
                // Parse the name apart
                const auto pos = layer->ident.find_first_of('_');
                if (pos != std::string::npos) {
                    groupName = layer->ident.substr(0,pos);
                    name = layer->ident.substr(pos+1);
                }
            }
            if (NSString *nameStr = [NSString stringWithUTF8String:name.c_str()]) {
                MaplyLegendEntry *entry = [[MaplyLegendEntry alloc] init];
                entry.name = nameStr;
                entry.image = image;

                if (!groupName.empty()) {
                    if (NSString *groupNameStr = [NSString stringWithUTF8String:groupName.c_str()]) {
                        MaplyLegendEntry *group = groups[groupNameStr];
                        if (!group) {
                            group = [[MaplyLegendEntry alloc] init];
                            group.name = groupNameStr;
                            group.entries = [NSMutableArray array];
                            groups[groupNameStr] = group;
                            [legend addObject:group];
                        }
                        
                        [group.entries addObject:entry];
                    }
                } else {
                    [legend addObject:entry];
                }
            }
        }
    }
    
    return legend;
}

// These wrap the style if someone is using a non-standard path to call it
// We do that in at least one place

- (nullable NSArray *)stylesForFeatureWithAttributes:(NSDictionary *__nonnull)attributes
                                              onTile:(MaplyTileID)tileID
                                             inLayer:(NSString *__nonnull)layer
                                               viewC:(NSObject<MaplyRenderControllerProtocol> *__nonnull)viewC
{
    MutableDictionaryCRef dictWrap = [attributes toDictionaryC];
    const QuadTreeIdentifier tileIDc(tileID.x,tileID.y,tileID.level);
    const std::string layerName = [layer cStringUsingEncoding:NSUTF8StringEncoding];
    
    auto styles = style->stylesForFeature(nil, *(dictWrap.get()), tileIDc, layerName);
    
    // Build up a wrapper for each one
    NSMutableArray *retStyles = [NSMutableArray array];
    for (auto theStyle: styles) {
        [retStyles addObject:[[MaplyVectorStyleReverseWrapper alloc] initWithCStyle:theStyle]];
    }

    return retStyles;
}

- (BOOL)layerShouldDisplay:(NSString *__nonnull)layer tile:(MaplyTileID)tileID
{
    const std::string layerName = [layer cStringUsingEncoding:NSUTF8StringEncoding];
    const QuadTreeIdentifier tileIDc(tileID.x,tileID.y,tileID.level);
    return style->layerShouldDisplay(nil, layerName, tileIDc);
}

- (nullable NSObject<MaplyVectorStyle> *)styleForUUID:(long long)uuid viewC:(NSObject<MaplyRenderControllerProtocol> *__nonnull)viewC
{
    auto theStyle = style->styleForUUID(NULL, uuid);
    
    return [[MaplyVectorStyleReverseWrapper alloc] initWithCStyle:theStyle];
}

- (nullable NSObject<MaplyVectorStyle> *)backgroundStyleViewC:(NSObject<MaplyRenderControllerProtocol> *)viewC
{
    return nil;
}

- (NSArray * __nonnull)allStyles
{
    auto styles = style->allStyles(NULL);

    // Build up a wrapper for each one
    NSMutableArray *retStyles = [NSMutableArray array];
    for (auto theStyle: styles) {
        [retStyles addObject:[[MaplyVectorStyleReverseWrapper alloc] initWithCStyle:theStyle]];
    }

    return retStyles;
}

// Returns the C++ class that does the work
- (WhirlyKit::VectorStyleDelegateImplRef) getVectorStyleImpl
{
    return style;
}

- (void)setZoomSlot:(int)zoomSlot
{
    if (!style)
        return;
    
    style->setZoomSlot(zoomSlot);
}

@end

@implementation MaplyMapboxVectorStyleSource

- (id __nullable)initWithName:(NSString *)name styleEntry:(NSDictionary * __nonnull)styleEntry styleSet:(MapboxVectorStyleSet * __nonnull)styleSet viewC:(NSObject<MaplyRenderControllerProtocol> * __nonnull)viewC
{
    self = [super init];
    
    _name = name;
    
    NSString *typeStr = styleEntry[@"type"];
    if ([typeStr isEqualToString:@"vector"]) {
        _type = MapboxSourceVector;
    } else if ([typeStr isEqualToString:@"raster"]) {
        _type = MapboxSourceRaster;
    } else {
        NSLog(@"Unsupport source type %@",typeStr);
        return nil;
    }
    
    _url = styleEntry[@"url"];
    _tileSpec = styleEntry[@"tiles"];
    
    if (!_url && !_tileSpec) {
        NSLog(@"Expecting either URL or tileSpec in source %@",_name);
        return nil;
    }
    
    return self;
}

@end
