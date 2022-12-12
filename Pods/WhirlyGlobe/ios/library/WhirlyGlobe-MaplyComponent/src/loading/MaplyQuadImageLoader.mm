/*
 *  MaplyQuadImageLoader.mm
 *
 *  Created by Steve Gifford on 4/10/18.
 *  Copyright 2012-2018 Saildrone Inc
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

#import "MaplyQuadImageLoader_private.h"
#import "QuadTileBuilder.h"
#import "MaplyImageTile_private.h"
#import "MaplyRenderController_private.h"
#import "MaplyQuadSampler_private.h"
#import "MaplyRenderTarget_private.h"
#import "MaplyRenderTarget_private.h"
#import "MaplyRenderController_private.h"
#import "MaplyQuadSampler_private.h"
#import "MaplyComponentObject_private.h"

#if !MAPLY_MINIMAL
#import "visual_objects/MaplyScreenLabel.h"
#endif //!MAPLY_MINIMAL

using namespace WhirlyKit;

@implementation MaplyImageLoaderReturn

- (id)initWithLoader:(MaplyQuadLoaderBase *)loader
{
    return [super initWithLoader:loader];
}

- (void)addImageTile:(MaplyImageTile *)image
{
    if (!image)
        return;
    loadReturn->images.push_back(image->imageTile);
}

- (void)addImage:(UIImage *)image
{
    if (const auto __strong vc = viewC) {
        ImageTile_iOSRef imageTile = std::make_shared<ImageTile_iOS>(vc.getRenderControl->renderType);
        imageTile->type = MaplyImgTypeImage;
        imageTile->components = 4;
        imageTile->width = (int)(image.size.width * image.scale);
        imageTile->height = (int)(image.size.height * image.scale);
        imageTile->borderSize = 0;
        imageTile->imageStuff = image;

        loadReturn->images.push_back(imageTile);
    }
}

- (NSArray<MaplyImageTile *> *)getImages
{
    NSMutableArray *ret = [[NSMutableArray alloc] init];
    for (auto imageTile : loadReturn->images) {
        ImageTile_iOSRef imageTileiOS = std::dynamic_pointer_cast<ImageTile_iOS>(imageTile);
        MaplyImageTile *imgTileObj = [[MaplyImageTile alloc] init];
        imgTileObj->imageTile = imageTileiOS;
        [ret addObject:imgTileObj];
    }
    
    return ret;
}

- (void)clearImages
{
    loadReturn->images.clear();
}

- (void)addCompObjs:(NSArray<MaplyComponentObject *> *)compObjs
{
    for (MaplyComponentObject *compObj in compObjs)
        loadReturn->compObjs.push_back(compObj->contents);
}

- (NSArray<MaplyComponentObject *> *)getCompObjs
{
    NSMutableArray *ret = [[NSMutableArray alloc] init];
    for (auto compObj : loadReturn->compObjs) {
        MaplyComponentObject *compObjWrap = [[MaplyComponentObject alloc] init];
        compObjWrap->contents = std::dynamic_pointer_cast<ComponentObject_iOS>(compObj);
        [ret addObject:compObjWrap];
    }
    
    return ret;
}

- (void)clearCompObjs
{
    loadReturn->compObjs.clear();
}

- (void)addOvlCompObjs:(NSArray<MaplyComponentObject *> *)compObjs
{
    for (MaplyComponentObject *compObj in compObjs)
        loadReturn->ovlCompObjs.push_back(compObj->contents);
}

- (NSArray<MaplyComponentObject *> *)getOvlCompObjs
{
    NSMutableArray *ret = [[NSMutableArray alloc] init];
    for (auto compObj : loadReturn->ovlCompObjs) {
        MaplyComponentObject *compObjWrap = [[MaplyComponentObject alloc] init];
        compObjWrap->contents = std::dynamic_pointer_cast<ComponentObject_iOS>(compObj);
        [ret addObject:compObjWrap];
    }
    
    return ret;
}

- (void)clearOvlCompObjs
{
    loadReturn->ovlCompObjs.clear();
}

@end

@implementation MaplyImageLoaderInterpreter

- (void)setLoader:(MaplyQuadLoaderBase *)loader
{
}

- (void)dataForTile:(MaplyImageLoaderReturn *)loadReturn loader:(MaplyQuadLoaderBase *)loader
{
    const auto tileID = loadReturn.tileID;
    if (const auto __strong vc = loadReturn->viewC) {
        NSArray *tileDatas = [loadReturn getTileData];
        
        for (NSData *tileData in tileDatas) {
            MaplyImageTile *imageTile = [[MaplyImageTile alloc] initWithPNGorJPEGData:tileData viewC:vc];
#if DEBUG
            imageTile.label = [NSString stringWithFormat:@"%@ interp %d:(%d,%d) %d",
                               loader.label, tileID.level, tileID.x, tileID.y, loadReturn.frame];
#endif
            [loadReturn addImageTile:imageTile];
        }
    }
}

- (void)tileUnloaded:(MaplyTileID)tileID {
}

@end

#if !MAPLY_MINIMAL
@implementation MaplyOvlDebugImageLoaderInterpreter
{
    NSObject<MaplyRenderControllerProtocol>* __weak viewC;
    UIFont *font;
}

- (id)initWithViewC:(NSObject<MaplyRenderControllerProtocol> *)inViewC
{
    self = [super init];
    viewC = inViewC;
    font = [UIFont systemFontOfSize:12.0];
    
    return self;
}

- (void)dataForTile:(MaplyImageLoaderReturn *)loadReturn loader:(MaplyQuadLoaderBase *)loader
{
    auto const __strong vc = viewC;
    
    [super dataForTile:loadReturn loader:loader];
    
    MaplyBoundingBox bbox = [loader geoBoundsForTile:loadReturn.tileID];
    MaplyScreenLabel *label = [[MaplyScreenLabel alloc] init];
    MaplyCoordinate center;
    center.x = (bbox.ll.x+bbox.ur.x)/2.0;  center.y = (bbox.ll.y+bbox.ur.y)/2.0;
    label.loc = center;
    label.text = [NSString stringWithFormat:@"%d: (%d,%d)",loadReturn.tileID.level,loadReturn.tileID.x,loadReturn.tileID.y];
    label.layoutImportance = MAXFLOAT;
    
    MaplyComponentObject *labelObj = [vc addScreenLabels:@[label] desc:
                                      @{kMaplyFont: font,
                                        kMaplyTextColor: UIColor.blackColor,
                                        kMaplyTextOutlineColor: UIColor.whiteColor,
                                        kMaplyTextOutlineSize: @(2.0),
                                        kMaplyEnable: @(false),
                                        }
                                      mode:MaplyThreadCurrent];
    
    MaplyCoordinate coords[5];
    coords[0] = bbox.ll;  coords[1] = MaplyCoordinateMake(bbox.ur.x, bbox.ll.y);
    coords[2] = bbox.ur;  coords[3] = MaplyCoordinateMake(bbox.ll.x, bbox.ur.y);
    coords[4] = coords[0];
    MaplyVectorObject *vecObj = [[MaplyVectorObject alloc] initWithLineString:coords numCoords:5 attributes:nil];
    [vecObj subdivideToGlobe:0.001];
    MaplyComponentObject *outlineObj = [vc addVectors:@[vecObj] desc:@{kMaplyEnable: @(false)} mode:MaplyThreadCurrent];
    
    [loadReturn addCompObjs:@[labelObj,outlineObj]];
}

@end
#endif //!MAPLY_MINIMAL

@implementation MaplyRawPNGImageLoaderInterpreter
{
    std::vector<int> valueMap;
}

- (void)addMappingFrom:(int)inVal to:(int)outVal
{
    if (valueMap.empty())
        valueMap.resize(256,-1);
    if (inVal < 256)
        valueMap[inVal] = outVal;
}

- (void)dataForTile:(MaplyImageLoaderReturn *)loadReturn loader:(MaplyQuadLoaderBase *)loader
{
    const auto __strong vc = loader.viewC;
    NSArray<id> *tileData = [loadReturn getTileData];
    for (unsigned int ii=0;ii<[tileData count];ii++)
    {
        if (loadReturn.isCancelled)
        {
            return;
        }

        NSData *inData = [tileData objectAtIndex:ii];
        if (![inData isKindOfClass:[NSData class]])
        {
            continue;
        }

        const auto bytes = (const unsigned char *)[inData bytes];
        const auto length = inData.length;
        if (!bytes || !length)
        {
            continue;
        }

        unsigned width = 0, height = 0, err = 0, depth = 0, channels = 0;
        std::string errStr;
        const auto *valPtr = (valueMap.size() >= 256) ? &valueMap[0] : nullptr;
        const auto outData = RawPNGImageLoaderInterpreter(width, height, bytes, length, valPtr,
                                                          &depth, &channels, &err, &errStr);

        if (err != 0 || !outData)
        {
            wkLogLevel(Warn, "Failed to read PNG (err %d: %s) for %d:(%d,%d) frame %d",
                       err, errStr.c_str(), loadReturn.tileID.level,
                       loadReturn.tileID.x,loadReturn.tileID.y,loadReturn.frame);
            continue;
        }

        const auto dataSize = width * height * channels * depth / 8;

        if (NSData *retData = [[NSData alloc] initWithBytesNoCopy:outData
                                                           length:dataSize
                                                     freeWhenDone:YES])
        {
            // Build a wrapper around the data and pass it on
            if (MaplyImageTile *tileData = [[MaplyImageTile alloc] initWithRawImage:retData
                                                                              width:width
                                                                             height:height
                                                                              depth:depth
                                                                         components:channels
                                                                              viewC:vc])
            {
                const auto tileID = loadReturn.tileID;
#if DEBUG
                tileData.label = [NSString stringWithFormat:@"%@ %d:(%d,%d) %d",
                                  loader.label, tileID.level, tileID.x, tileID.y, loadReturn.frame];
#endif
                loadReturn->loadReturn->images.push_back(tileData->imageTile);
            }
        }
        else
        {
            // NSData won't free the data, so we need to.
            free(outData);
        }
    }
}

@end

#if !MAPLY_MINIMAL || DEBUG
@implementation MaplyDebugImageLoaderInterpreter
{
    NSObject<MaplyRenderControllerProtocol> * __weak viewC;
}

- (instancetype)initWithViewC:(NSObject<MaplyRenderControllerProtocol> *)inViewC
{
    self = [super init];
    
    viewC = inViewC;
    
    return self;
}

static const int MaxDebugColors = 10;
static const int debugColors[MaxDebugColors] = {0x86812D, 0x5EB9C9, 0x2A7E3E, 0x4F256F, 0xD89CDE, 0x773B28, 0x333D99, 0x862D52, 0xC2C653, 0xB8583D};

- (void)dataForTile:(MaplyImageLoaderReturn *)loadReturn loader:(MaplyQuadLoaderBase *)loader
{
    MaplyTileID tileID = loadReturn.tileID;
    
    CGSize size;  size = CGSizeMake(256,256);
    UIGraphicsBeginImageContext(size);
    
    // Draw into the image context
    int hexColor = debugColors[loadReturn.tileID.level % MaxDebugColors];
    float red = (((hexColor) >> 16) & 0xFF)/255.0;
    float green = (((hexColor) >> 8) & 0xFF)/255.0;
    float blue = (((hexColor) >> 0) & 0xFF)/255.0;
    UIColor *backColor = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.7];
    UIColor *fillColor = [UIColor colorWithRed:red green:green blue:blue alpha:0.7];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    // Draw a rectangle around the edges for testing
    [backColor setFill];
    CGContextFillRect(ctx, CGRectMake(0, 0, size.width, size.height));
    [fillColor setFill];
    CGContextFillRect(ctx, CGRectMake(1, 1, size.width-2, size.height-2));
    
    [fillColor setStroke];
    [fillColor setFill];
    CGContextSetTextDrawingMode(ctx, kCGTextFill);
    NSString *textStr = nil;
    if (loadReturn.frame == -1) {
        textStr = [NSString stringWithFormat:@"%d: (%d,%d)",tileID.level,tileID.x,tileID.y];
    }
    else
        textStr = [NSString stringWithFormat:@"%d: (%d,%d); %d",tileID.level,tileID.x,tileID.y,loadReturn.frame];
    
    if (loader.label.length > 0)
    {
        textStr = [NSString stringWithFormat:@"%@\n%@", textStr, loader.label];
    }
    
    [[UIColor whiteColor] setStroke];
    [[UIColor whiteColor] setFill];
    [textStr drawInRect:CGRectMake(0,0,size.width,size.height) withAttributes:@{
        NSFontAttributeName:[UIFont systemFontOfSize:24.0]
    }];
    
    // Grab the image and shut things down
    UIImage *retImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    [loadReturn addImage:retImage];
}

@end
#endif //!MAPLY_MINIMAL

@implementation MaplyQuadImageLoaderBase
{
    bool _enable;
}

- (instancetype)initWithViewC:(NSObject<MaplyRenderControllerProtocol> *)inViewC
{
    self = [super initWithViewC:inViewC];
    
    _enable = true;
    _zBufferRead = false;
    _zBufferWrite = true;
    _baseDrawPriority = kMaplyImageLayerDrawPriorityDefault;
    _drawPriorityPerLevel = 1;
    _color = [UIColor whiteColor];
    _imageFormat = MaplyImageIntRGBA;

    // Start things out after a delay
    // This lets the caller mess with settings
    [self performSelector:@selector(delayedInit) withObject:nil afterDelay:0.0];

    return self;
}

- (bool)delayedInit
{
    if (![super delayedInit])
    {
        return false;
    }
    
    auto const __strong vc = self.viewC;
    if (![vc getRenderControl])
        return false;
    
    if (!tileFetcher) {
        tileFetcher = [[vc getRenderControl] addTileFetcher:MaplyQuadImageLoaderFetcherName];
    }
    loader->tileFetcher = tileFetcher;
    loader->setDebugMode(self.debugMode);

    if (auto lbl = [self.accessibilityLabel UTF8String])
    {
        loader->setLabel(lbl);
    }

    samplingLayer = [[vc getRenderControl] findSamplingLayer:params forUser:self->loader];
    samplingLayer.debugMode = self.debugMode;
    // Do this again in case they changed them
    loader->setSamplingParams(params);
    loader->setMasterEnable(_enable);
    
    [loadInterp setLoader:self];
    
    // Sort out the texture format
    switch (self.imageFormat) {
        case MaplyImageIntRGBA:
        case MaplyImage4Layer8Bit:
        default:
            loader->setTexType(TexTypeUnsignedByte);
            break;
        case MaplyImageUShort565:
            loader->setTexType(TexTypeShort565);
            break;
        case MaplyImageUShort4444:
            loader->setTexType(TexTypeShort4444);
            break;
        case MaplyImageUShort5551:
            loader->setTexType(TexTypeShort5551);
            break;
        case MaplyImageUByteRed:
            loader->setTexType(TexTypeSingleChannel);
            loader->setTexByteSource(WKSingleByteSource::WKSingleRed);
            break;
        case MaplyImageUByteGreen:
            loader->setTexType(TexTypeSingleChannel);
            loader->setTexByteSource(WKSingleByteSource::WKSingleGreen);
            break;
        case MaplyImageUByteBlue:
            loader->setTexType(TexTypeSingleChannel);
            loader->setTexByteSource(WKSingleByteSource::WKSingleBlue);
            break;
        case MaplyImageUByteAlpha:
            loader->setTexType(TexTypeSingleChannel);
            loader->setTexByteSource(WKSingleByteSource::WKSingleAlpha);
            break;
        case MaplyImageUByteRGB:
            loader->setTexType(TexTypeSingleChannel);
            loader->setTexByteSource(WKSingleByteSource::WKSingleRGB);
            break;
        case MaplyImageSingleFloat16:
            loader->setTexType(TexTypeSingleFloat16);
            break;
        case MaplyImageSingleFloat32:
            loader->setTexType(TexTypeSingleFloat32);
            break;
        case MaplyImageDoubleFloat16:
            loader->setTexType(TexTypeDoubleFloat16);
            break;
        case MaplyImageDoubleFloat32:
            loader->setTexType(TexTypeDoubleFloat32);
            break;
        case MaplyImageQuadFloat16:
            loader->setTexType(TexTypeQuadFloat16);
            break;
        case MaplyImageQuadFloat32:
            loader->setTexType(TexTypeQuadFloat32);
            break;
        case MaplyImageInt16:
            loader->setTexType(TexTypeSingleInt16);
            break;
        case MaplyImageUInt16:
            loader->setTexType(TexTypeSingleUInt16);
            break;
        case MaplyImageDoubleUInt16:
            loader->setTexType(TexTypeDoubleUInt16);
            break;
        case MaplyImageUInt32:
            loader->setTexType(TexTypeSingleUInt32);
            break;
        case MaplyImageDoubleUInt32:
            loader->setTexType(TexTypeDoubleUInt32);
            break;
        case MaplyImageQuadUInt32:
            loader->setTexType(TexTypeQuadUInt32);
            break;
    }
    
    for (unsigned int ii=0;ii<loader->getNumFocus();ii++) {
        if (loader->getShaderID(ii) == EmptyIdentity) {
            MaplyShader *theShader = [vc getShaderByName:kMaplyShaderDefaultTriMultiTex];
            if (theShader)
                loader->setShaderID(ii,[theShader getShaderID]);
        }
    }
    
    // These might be changed by the setup call
    loader->setFlipY(self.flipY);
    loader->setBaseDrawPriority(_baseDrawPriority);
    loader->setDrawPriorityPerLevel(_drawPriorityPerLevel);

    const RGBAColor color = [_color asRGBAColor];
    loader->setColor(color,NULL);

    [super postDelayedInit];

    return true;
}

- (void)setShader:(MaplyShader *)shader
{
    if (!loader)
        return;
    
    loader->setShaderID(0,[shader getShaderID]);
}

- (void)setRenderTarget:(MaplyRenderTarget *__nonnull)renderTarget
{
    if (!loader)
        return;
    
    loader->setRenderTarget(0,[renderTarget renderTargetID]);
}

- (void)setTextureSize:(int)texSize borderSize:(int)borderSize
{
    if (!loader)
        return;
    
    loader->setTexSize(texSize, borderSize);
}

- (void)setColor:(UIColor *)newColor
{
    _color = newColor;
    
    const auto __strong thread = samplingLayer.layerThread;
    if (thread)
        [self performSelector:@selector(setColorThread:) onThread:thread withObject:_color waitUntilDone:NO];
    else if (loader) {
        const RGBAColor color = [_color asRGBAColor];
        loader->setColor(color, NULL);
    }
}

// Run on the layer thread
- (void)setColorThread:(UIColor *)newColor
{
    ChangeSet changes;
    const RGBAColor color = [_color asRGBAColor];
    loader->setColor(color,&changes);
    
    [samplingLayer.layerThread addChangeRequests:changes];
}
         
- (void)setEnable:(bool)newEnable
{
    if (_enable == newEnable)
        return;
    _enable = newEnable;
    if (loader) {
        loader->setMasterEnable(newEnable);
        [samplingLayer.layerThread addChangeRequest:nullptr];
    }
}

- (bool)enable
{
    return _enable;
}

@end

@implementation MaplyQuadImageLoader

- (instancetype)initWithParams:(MaplySamplingParams *)inParams tileInfo:(NSObject<MaplyTileInfoNew> *)tileInfo viewC:(NSObject<MaplyRenderControllerProtocol> *)inViewC
{
    if (!inParams.singleLevel) {
        NSLog(@"MaplyQuadImageLoader only supports samplers with singleLevel set to true");
        return nil;
    }
    self = [super initWithViewC:inViewC];
    
    params = inParams->params;
    params.generateGeom = true;
    
    // Loader does all the work.  The Obj-C version is just a wrapper
    self->loader = std::make_shared<QuadImageFrameLoader_ios>(params,
                                                              tileInfo,
                                                              QuadImageFrameLoader::SingleFrame);

    self.baseDrawPriority = kMaplyImageLayerDrawPriorityDefault;
    self.drawPriorityPerLevel = 100;
    
    self.flipY = true;
    self->minLevel = tileInfo.minZoom;
    self->maxLevel = tileInfo.maxZoom;
    self->valid = true;
    
    return self;
}

- (instancetype)initWithParams:(MaplySamplingParams *)inParams tileInfos:(NSArray<NSObject<MaplyTileInfoNew> *> *)tileInfos viewC:(NSObject<MaplyRenderControllerProtocol> *)inViewC
{
    if (!inParams.singleLevel) {
        NSLog(@"MaplyQuadImageLoader only supports samplers with singleLevel set to true");
        return nil;
    }
    self = [super initWithViewC:inViewC];
    
    params = inParams->params;
    params.generateGeom = true;
    
    // Loader does all the work.  The Obj-C version is just a wrapper
    self->loader = std::make_shared<QuadImageFrameLoader_ios>(params,
                                                              tileInfos,
                                                              QuadImageFrameLoader::SingleFrame);
    
    self.baseDrawPriority = kMaplyImageLayerDrawPriorityDefault;
    self.drawPriorityPerLevel = 100;
    
    self.flipY = true;
    self.debugMode = false;
    self->minLevel = tileInfos[0].minZoom;
    self->maxLevel = tileInfos[0].maxZoom;
    self->valid = true;
    
    return self;
}

- (bool)delayedInit
{
    if (!loadInterp)
    {
        loadInterp = [[MaplyImageLoaderInterpreter alloc] init];
    }
    loader->layer = self;

    if (![super delayedInit])
        return false;

    [super postDelayedInit];

    return true;
}

- (MaplyLoaderReturn *)makeLoaderReturn
{
    return [[MaplyImageLoaderReturn alloc] initWithLoader:self];
}

- (void)changeTileInfo:(NSObject<MaplyTileInfoNew> *)tileInfo
{
    NSArray *tileInfos = @[tileInfo];
    
    [super changeTileInfos:tileInfos];
}

- (void)reload
{
    [super reload];
}

@end
