/*  MaplyBaseViewController.mm
 *  MaplyComponent
 *
 *  Created by Steve Gifford on 12/14/12.
 *  Copyright 2012-2022 mousebird consulting
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

#import "control/MaplyBaseViewController.h"
#import "private/MaplyBaseViewController_private.h"
#import "UIKit/NSData+Zlib.h"

#import "MaplyTexture_private.h"
#import "UIKit/NSDictionary+StyleRules.h"
#import "MaplyTexture_private.h"
#import "MaplyRenderTarget_private.h"
#import "UIColor+Stuff.h"
#import "MTLView.h"
#import "WorkRegion_private.h"
#import "MaplyURLSessionManager+Private.h"
#import <sys/utsname.h>

#if !MAPLY_MINIMAL
# import "MaplyAnnotation_private.h"
# import "gestures/Maply3dTouchPreviewDelegate.h"
# import "FontTextureManager_iOS.h"
#endif //!MAPLY_MINIMAL

using namespace Eigen;
using namespace WhirlyKit;

@implementation MaplySelectedObject
@end

// Target for screen snapshot
@interface SnapshotTarget : NSObject<WhirlyKitSnapshot>
@property (nonatomic,weak) MaplyBaseViewController *viewC;
@property (nonatomic) NSData *data;
@property (nonatomic) SimpleIdentity renderTargetID;
@property (nonatomic) CGRect subsetRect;
@property (nonatomic) NSObject<MaplySnapshotDelegate> *outsideDelegate;
@end

@implementation SnapshotTarget

- (instancetype)initWithViewC:(MaplyBaseViewController *)inViewC
{
    self = [super init];
    
    _viewC = inViewC;
    _data = nil;
    _renderTargetID = EmptyIdentity;
    _subsetRect = CGRectZero;
    
    return self;
}

- (instancetype)initWithOutsideDelegate:(NSObject<MaplySnapshotDelegate> *)inOutsideDelegate viewC:(MaplyBaseViewController *)inViewC
{
    self = [super init];
    _outsideDelegate = inOutsideDelegate;
    
    return self;
}

- (void)setSubsetRect:(CGRect)subsetRect
{
    _subsetRect = subsetRect;
}

- (CGRect)snapshotRect
{
    if (_outsideDelegate)
        return [_outsideDelegate snapshotRect];
    
    return _subsetRect;
}

- (void)snapshotData:(NSData *)snapshotData {
    if (_outsideDelegate)
        [_outsideDelegate snapshot:snapshotData];
    else
        _data = snapshotData;
}

- (bool)needSnapshot:(NSTimeInterval)now {
    if (_outsideDelegate)
        return [_outsideDelegate needSnapshot:now viewC:_viewC];
    return true;
}

- (SimpleIdentity)renderTargetID
{
    if (_outsideDelegate) {
        MaplyRenderTarget *renderTarget = [_outsideDelegate renderTarget];
        if (renderTarget) {
            return [renderTarget renderTargetID];
        }
        return EmptyIdentity;
    }
    
    return _renderTargetID;
}

@end

@implementation MaplyBaseViewController
{
    MaplyLocationTracker *_locationTracker;
    bool _layoutFade;
    NSMutableArray<InitCompletionBlock> *_postInitCalls;
}

- (instancetype)init{
    self = [super init];
    _layoutFade = false;
    _postInitCalls = [NSMutableArray new];
    return self;
}

- (void) clear
{
    if (!renderControl)
        return;
    
    if (!renderControl->scene)
        return;
        
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(periodicPerfOutput) object:nil];

    [wrapView stopAnimation];
    
//    NSLog(@"BaseViewController: Shutting down layers");
    
    [wrapView teardown];
    
    [renderControl teardown];

    [renderControl->baseLayerThread addThingToRelease:wrapView];
    wrapView = nil;
    renderControl->scene = NULL;
    renderControl->sceneRenderer = NULL;
    
#if !MAPLY_MINIMAL
    viewTrackers = nil;
    annotations = nil;
#endif //!MAPLY_MINIMAL

    [renderControl clear];
    renderControl = nil;
}

- (void) dealloc
{
    if (renderControl && renderControl->scene)
        [self teardown];
}

- (ViewRef) loadSetup_view
{
    return ViewRef(NULL);
}

- (void)loadSetup_mtlView
{
    SceneRendererMTL *renderMTL = (SceneRendererMTL *)renderControl->sceneRenderer.get();
    RenderSetupInfoMTL *setupInfo = (RenderSetupInfoMTL *) renderMTL->getRenderSetupInfo();

    WhirlyKitMTLView *mtlView = [[WhirlyKitMTLView alloc] initWithDevice:setupInfo->mtlDevice];
    mtlView.preferredFramesPerSecond = (_frameInterval > 0) ? (60.0 / _frameInterval) : 120;
    mtlView.wrapperDelegate = self;

    wrapView = mtlView;
}

- (MaplyBaseInteractionLayer *) loadSetup_interactionLayer
{
    return [[MaplyBaseInteractionLayer alloc] initWithView:renderControl->visualView];
}

- (void)setScreenObjectDrawPriorityOffset:(int)screenObjectDrawPriorityOffset
{
    renderControl.screenObjectDrawPriorityOffset = screenObjectDrawPriorityOffset;
}

- (int)screenObjectDrawPriorityOffset
{
    return renderControl.screenObjectDrawPriorityOffset;
}

#if !MAPLY_MINIMAL
- (void)setLayoutFade:(bool)enable
{
    _layoutFade = enable;
    if (auto rc = renderControl)
    if (auto scene = rc->scene)
    if (auto layoutManager = scene->getManager<LayoutManager>(kWKLayoutManager))
    {
        layoutManager->setFadeEnabled(enable);
    }
}

- (bool)layoutFade
{
    return _layoutFade;
}
#endif //!MAPLY_MINIMAL

// Kick off the analytics logic.  First we need the server name.
- (void)startAnalytics
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    // This is completely random.  We can't track it in any useful way
    NSString *userID = [userDefaults stringForKey:@"wgmaplyanalyticuser"];
    if (!userID) {
        // This means we only send this information once
        // As a result we know nothing about the user, not even if they've run the app again
        userID = [[NSUUID UUID] UUIDString];
        [userDefaults setObject:userID forKey:@"wgmaplyanalyticuser"];

        [self sendAnalytics:@"analytics.mousebirdconsulting.com:8081"];
    }
}

// Send the actual analytics data
// There's nothing unique in here to identify the user
// The user ID is completely made up and we don't get it more than once per week
- (void)sendAnalytics:(NSString *)serverName
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *userID = [userDefaults stringForKey:@"wgmaplyanalyticuser"];

    // Model number
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *model = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    NSDictionary *infoDict = [NSBundle mainBundle].infoDictionary;
    // Bundle ID, version and build
    NSString *bundleID = infoDict[@"CFBundleIdentifier"];
    NSString *bundleName = infoDict[@"CFBundleName"];
    NSString *build = infoDict[@"CFBundleVersion"];
    NSString *bundleVersion = infoDict[@"CFBundleShortVersionString"];
    // WGMaply version
    NSString *wgmaplyVersion = @"3.5";
    // OS version
    NSOperatingSystemVersion osversionID = [[NSProcessInfo processInfo] operatingSystemVersion];
    NSString *osversion = [NSString stringWithFormat:@"%d.%d.%d",(int)osversionID.majorVersion,(int)osversionID.minorVersion,(int) osversionID.patchVersion];

    // We're not recording anything that can identify the user, just the app
    // create table register( userid VARCHAR(50), bundleid VARCHAR(100), bundlename VARCHAR(100), bundlebuild VARCHAR(100), bundleversion VARCHAR(100), osversion VARCHAR(20), model VARCHAR(100), wgmaplyversion VARCHAR(20));
    NSString *postArgs = [NSString stringWithFormat:@"{ \"userid\":\"%@\", \"bundleid\":\"%@\", \"bundlename\":\"%@\", \"bundlebuild\":\"%@\", \"bundleversion\":\"%@\", \"osversion\":\"%@\", \"model\":\"%@\", \"wgmaplyversion\":\"%@\" }",
                          userID,bundleID,bundleName,build,bundleVersion,osversion,model,wgmaplyVersion];
    NSMutableURLRequest *req = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@/register", serverName]]];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setHTTPMethod:@"POST"];
    [req setHTTPBody:[postArgs dataUsingEncoding:NSASCIIStringEncoding]];
    
#if !MAPLY_MINIMAL
    NSURLSession *session = [[MaplyURLSessionManager sharedManager] createURLSession];
#else
    NSURLSession *session = [NSURLSession sharedSession];
#endif //!MAPLY_MINIMAL

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        TimeInterval now = TimeGetCurrent();
        NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
        if (resp.statusCode == 200) {
            [userDefaults setDouble:now forKey:@"wgmaplyanalytictime"];
        }
    }];
    [dataTask resume];
}

// Create the Maply or Globe view.
// For specific parts we'll call our subclasses
- (void) loadSetup
{
#if !TARGET_OS_SIMULATOR
    [self startAnalytics];
#endif
    
    if (!renderControl)
        renderControl = [[MaplyRenderController alloc] init];
    
    renderControl->renderType = SceneRenderer::RenderMetal;
    
    allowRepositionForAnnnotations = true;
        
    [renderControl loadSetup];
    [self loadSetup_mtlView];
    
    // Set up the GL View to display it in
    [wrapView setRenderer:renderControl->sceneRenderer.get()];
    [self.view insertSubview:wrapView atIndex:0];
    self.view.backgroundColor = [UIColor blackColor];
    self.view.opaque = YES;
	self.view.autoresizesSubviews = YES;
	wrapView.frame = self.view.bounds;
    wrapView.backgroundColor = [UIColor blackColor];
        
    [renderControl loadSetup_view:[self loadSetup_view]];
    [renderControl loadSetup_scene:[self loadSetup_interactionLayer]];
    [self loadSetup_lighting];

#if !MAPLY_MINIMAL
    viewTrackers = [NSMutableArray array];
    annotations = [NSMutableArray array];
        
    // View placement manager
    viewPlacementModel = std::make_shared<ViewPlacementActiveModel>();
    renderControl->scene->addActiveModel(viewPlacementModel);
#endif //!MAPLY_MINIMAL

    // Apply layout fade option set before init to the newly-created manager
    [self setLayoutFade:_layoutFade];

    // Set up defaults for the hints
    NSDictionary *newHints = [NSDictionary dictionary];
    [self setHints:newHints];

    _selection = true;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
}

- (void)loadSetup_lighting
{
    [renderControl resetLights];
}

- (id<MTLDevice>)getMetalDevice
{
    if (!renderControl)
        return nil;
    
    return [renderControl getMetalDevice];
}

- (id<MTLLibrary>)getMetalLibrary
{
    if (!renderControl)
        return nil;
    
    return [renderControl getMetalLibrary];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self loadSetup];
}

- (void)startAnimation
{
    [wrapView startAnimation];
}

- (void)stopAnimation
{
    [wrapView stopAnimation];
}

- (void)teardown
{
    if (renderControl)
        [renderControl->interactLayer lockingShutdown];
    
    if (wrapView)
        [wrapView teardown];
    
    [self clear];
}

- (void)appBackground:(NSNotification *)note
{
    if(!wasAnimating || wrapView.isAnimating)
    {
        wasAnimating = wrapView.isAnimating;
        if (wasAnimating)
            [self stopAnimation];
    }
    
    if (!renderControl)
        return;
    for(WhirlyKitLayerThread *t in renderControl->layerThreads)
    {
        [t pause];
    }
}

- (void)appForeground:(NSNotification *)note
{
    if (!renderControl)
        return;

    for(WhirlyKitLayerThread *t in renderControl->layerThreads)
    {
        [t unpause];
    }
    if (wasAnimating)
    {
        [self startAnimation];
        wasAnimating = false;
    }
}

- (void)viewWillAppear:(BOOL)animated
{
	[self startAnimation];
	
	[super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];

	[self stopAnimation];
}

- (void)viewWillLayoutSubviews
{
    if (wrapView)
    {
        wrapView.frame = self.view.bounds;
    }
}

- (void)viewDidLayoutSubviews
{
    // The layout hasn't actually run yet, it's only been kicked off
    // See `layoutDidRun:`
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)setFrameInterval:(int)frameInterval
{
    _frameInterval = frameInterval;
    
    WhirlyKitMTLView *mtlView = (WhirlyKitMTLView *)wrapView;
    if (mtlView) {
        if (frameInterval <= 0)
            mtlView.preferredFramesPerSecond = 120;
        else {
            mtlView.preferredFramesPerSecond = 60 / frameInterval;
        }
    }
}

static const float PerfOutputDelay = 15.0;

- (void)setPerformanceOutput:(bool)performanceOutput
{
    if (_performanceOutput == performanceOutput)
        return;
    
    _performanceOutput = performanceOutput;
    if (_performanceOutput)
    {
        renderControl->sceneRenderer->setPerfInterval(100);
        [self performSelector:@selector(periodicPerfOutput) withObject:nil afterDelay:PerfOutputDelay];
    } else {
        renderControl->sceneRenderer->setPerfInterval(0);
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(periodicPerfOutput) object:nil];
    }
}

#if !MAPLY_MINIMAL
- (void)setShowDebugLayoutBoundaries:(bool)show
{
    self->_showDebugLayoutBoundaries = show;
    if (renderControl && renderControl->scene)
    {
        if (const auto layoutManager = renderControl->scene->getManager<LayoutManager>(kWKLayoutManager))
        {
            layoutManager->setShowDebugBoundaries(show);
            [renderControl->layoutLayer scheduleUpdateNow];
        }
    }
}
#endif //!MAPLY_MINIMAL

// Run every so often to dump out stats
- (void)periodicPerfOutput
{
    if (!renderControl || !renderControl->scene)
        return;
    
    renderControl->scene->dumpStats();
    [renderControl->interactLayer dumpStats];
    for (MaplyRemoteTileFetcher *tileFetcher : renderControl->tileFetchers) {
        MaplyRemoteTileFetcherStats *stats = [tileFetcher getStats:false];
        [stats dump];
        [tileFetcher resetStats];
    }
    NSLog(@"Sampling layers: %lu",renderControl->samplingLayers.size());
    
    [self performSelector:@selector(periodicPerfOutput) withObject:nil afterDelay:PerfOutputDelay];
}

- (bool)performanceOutput
{
    return _performanceOutput;
}

#if !MAPLY_MINIMAL
// Build an array of lights and send them down all at once
- (void)updateLights
{
    [renderControl updateLights];
}

- (void)clearLights
{
    [renderControl clearLights];
}

- (void)resetLights
{
    [renderControl resetLights];
}

- (void)addLight:(MaplyLight *)light
{
    [renderControl addLight:light];
}

- (void)removeLight:(MaplyLight *)light
{
    [renderControl removeLight:light];
}
#endif //!MAPLY_MINIMAL

- (void)addShaderProgram:(MaplyShader *)shader
{
    [renderControl addShaderProgram:shader];
}

- (MaplyShader *)getShaderByName:(const NSString *)name
{
    return [renderControl getShaderByName:name];
}

- (void)removeShaderProgram:(MaplyShader *__nonnull)shader
{
    [renderControl removeShaderProgram:shader];
}

- (void)startMaskTarget:(NSNumber * __nullable)inScale
{
    [renderControl startMaskTarget:inScale];
}

- (void)stopMaskTarget
{
    [renderControl stopMaskTarget];
}

#pragma mark - Defaults and descriptions

// Set new hints and update any related settings
- (void)setHints:(NSDictionary *)changeDict
{
    [renderControl setHints:changeDict];
}

#pragma mark - Geometry related methods

#if !MAPLY_MINIMAL
- (MaplyComponentObject *)addScreenMarkers:(NSArray *)markers desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode;
{
    MaplyComponentObject *compObj = [renderControl addScreenMarkers:markers desc:desc mode:threadMode];
    
    return compObj;
}

- (MaplyComponentObject *)addScreenMarkers:(NSArray *)markers desc:(NSDictionary *)desc
{
    return [self addScreenMarkers:markers desc:desc mode:MaplyThreadAny];
}

- (void)addClusterGenerator:(NSObject <MaplyClusterGenerator> *)clusterGen
{
    if (!renderControl)
        return;
    
    [renderControl addClusterGenerator:clusterGen];
}


- (MaplyComponentObject *)addMarkers:(NSArray *)markers desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    MaplyComponentObject *compObj = [renderControl addMarkers:markers desc:desc mode:threadMode];
    
    return compObj;
}

- (MaplyComponentObject *)addMarkers:(NSArray *)markers desc:(NSDictionary *)desc
{
    return [self addMarkers:markers desc:desc mode:MaplyThreadAny];
}

- (MaplyComponentObject *)addScreenLabels:(NSArray *)labels desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    MaplyComponentObject *compObj = [renderControl addScreenLabels:labels desc:desc mode:threadMode];
    
    return compObj;
}

- (MaplyComponentObject *)addScreenLabels:(NSArray *)labels desc:(NSDictionary *)desc
{
    return [self addScreenLabels:labels desc:desc mode:MaplyThreadAny];
}

- (MaplyComponentObject *)addLabels:(NSArray *)labels desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    MaplyComponentObject *compObj = [renderControl addLabels:labels desc:desc mode:threadMode];
    
    return compObj;
}

- (MaplyComponentObject *)addLabels:(NSArray *)labels desc:(NSDictionary *)desc
{
    return [self addLabels:labels desc:desc mode:MaplyThreadAny];
}

- (MaplyComponentObject *)addVectors:(NSArray *)vectors desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    MaplyComponentObject *compObj = [renderControl addVectors:vectors desc:desc mode:threadMode];
    
    return compObj;
}

- (MaplyComponentObject *)addVectors:(NSArray *)vectors desc:(NSDictionary *)desc
{
    return [self addVectors:vectors desc:desc mode:MaplyThreadAny];
}

- (MaplyComponentObject *)instanceVectors:(MaplyComponentObject *)baseObj desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    MaplyComponentObject *compObj = [renderControl instanceVectors:baseObj desc:desc mode:threadMode];
    
    return compObj;
}

- (MaplyComponentObject *)addWideVectors:(NSArray *)vectors desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    MaplyComponentObject *compObj = [renderControl addWideVectors:vectors desc:desc mode:threadMode];
    
    return compObj;
}

- (MaplyComponentObject *)addWideVectors:(NSArray *)vectors desc:(NSDictionary *)desc
{
    return [self addWideVectors:vectors desc:desc mode:MaplyThreadAny];
}


- (MaplyComponentObject *)addBillboards:(NSArray *)billboards desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    MaplyComponentObject *compObj = [renderControl addBillboards:billboards desc:desc mode:threadMode];
    
    return compObj;
}

- (MaplyComponentObject *)addParticleSystem:(MaplyParticleSystem *)partSys desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    return [renderControl addParticleSystem:partSys desc:desc mode:threadMode];
}

- (void)changeParticleSystem:(MaplyComponentObject *__nonnull)compObj renderTarget:(MaplyRenderTarget *__nullable)target
{
    return [renderControl changeParticleSystem:compObj renderTarget:target];
}

- (void)addParticleBatch:(MaplyParticleBatch *)batch mode:(MaplyThreadMode)threadMode
{
    [renderControl addParticleBatch:batch mode:threadMode];
}

- (MaplyComponentObject *)addSelectionVectors:(NSArray *)vectors
{
    if (auto wr = WorkRegion(renderControl)) {
        return [renderControl->interactLayer addSelectionVectors:vectors desc:nil];
    }
    return nil;
}

- (void)changeVector:(MaplyComponentObject *)compObj desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    [renderControl changeVector:compObj desc:desc mode:threadMode];
}

- (void)changeVector:(MaplyComponentObject *)compObj desc:(NSDictionary *)desc
{
    [self changeVector:compObj desc:desc mode:MaplyThreadAny];
}
#endif //!MAPLY_MINIMAL

- (MaplyComponentObject *)addShapes:(NSArray *)shapes desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    return [renderControl addShapes:shapes desc:desc mode:threadMode];
}

- (MaplyComponentObject *)addShapes:(NSArray *)shapes desc:(NSDictionary *)desc
{
    return [self addShapes:shapes desc:desc mode:MaplyThreadAny];
}

- (MaplyComponentObject * _Nullable)addShapes:(NSArray * _Nonnull)shapes
                                         info:(WhirlyKit::ShapeInfo &)shapeInfo
                                         desc:(NSDictionary * _Nullable)desc
                                         mode:(MaplyThreadMode)threadMode
{
    return [renderControl addShapes:shapes info:shapeInfo desc:desc mode:threadMode];
}

#if !MAPLY_MINIMAL
- (MaplyComponentObject *)addModelInstances:(NSArray *)modelInstances desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    MaplyComponentObject *compObj = [renderControl addModelInstances:modelInstances desc:desc mode:threadMode];
    
    return compObj;
}

- (MaplyComponentObject *)addGeometry:(NSArray *)geom desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    MaplyComponentObject *compObj = [renderControl addGeometry:geom desc:desc mode:threadMode];
    
    return compObj;
}

- (MaplyComponentObject *)addStickers:(NSArray *)stickers desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    MaplyComponentObject *compObj = [renderControl addStickers:stickers desc:desc mode:threadMode];
    
    return compObj;
}

- (MaplyComponentObject *)addStickers:(NSArray *)stickers desc:(NSDictionary *)desc
{
    return [self addStickers:stickers desc:desc mode:MaplyThreadAny];
}

- (void)changeSticker:(MaplyComponentObject *)compObj desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    [renderControl changeSticker:compObj desc:desc mode:threadMode];
}

- (MaplyComponentObject *)addLoftedPolys:(NSArray *)polys desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    MaplyComponentObject *compObj = [renderControl addLoftedPolys:polys desc:desc mode:threadMode];
    
    return compObj;
}

- (MaplyComponentObject *)addLoftedPolys:(NSArray *)polys desc:(NSDictionary *)desc
{
    return [self addLoftedPolys:polys desc:desc mode:MaplyThreadAny];
}

- (MaplyComponentObject *)addPoints:(NSArray *)points desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    MaplyComponentObject *compObj = [renderControl addPoints:points desc:desc mode:threadMode];
    
    return compObj;
}

/// Add a view to track to a particular location
- (void)addViewTracker:(WGViewTracker *)viewTrack
{
    if (!renderControl)
        return;
    
    // Make sure we're not duplicating and add the object
    [self removeViewTrackForView:viewTrack.view];

    @synchronized(self)
    {
        [viewTrackers addObject:viewTrack];
    }
    
    // Hook it into the renderer
    ViewPlacementManager *vpManage = viewPlacementModel->getManager();
    if (vpManage) {
        vpManage->addView(GeoCoord(viewTrack.loc.x,viewTrack.loc.y),Point2d(viewTrack.offset.x,viewTrack.offset.y),viewTrack.view,viewTrack.minVis,viewTrack.maxVis);
    }
    renderControl->sceneRenderer->setTriggerDraw();
    
    // And add it to the view hierarchy
    // Can only do this on the main thread anyway
    if ([viewTrack.view superview] == nil)
        [wrapView addSubview:viewTrack.view];
}

- (void)moveViewTracker:(MaplyViewTracker *)viewTrack moveTo:(MaplyCoordinate)newPos
{
    ViewPlacementManager *vpManage = viewPlacementModel->getManager();
    if (vpManage) {
        vpManage->moveView(GeoCoord(newPos.x,newPos.y),Point2d(0,0),viewTrack.view,viewTrack.minVis,viewTrack.maxVis);
    }
    renderControl->sceneRenderer->setTriggerDraw();
}

/// Remove the view tracker associated with the given UIView
- (void)removeViewTrackForView:(UIView *)view
{
    @synchronized(self)
    {
        // Look for the entry
        WGViewTracker *theTracker = nil;
        for (WGViewTracker *viewTrack in viewTrackers)
            if (viewTrack.view == view)
            {
                theTracker = viewTrack;
                break;
            }
        
        if (theTracker)
        {
            [viewTrackers removeObject:theTracker];
            ViewPlacementManager *vpManage = viewPlacementModel->getManager();
            if (vpManage) {
                vpManage->removeView(theTracker.view);
            }
            if ([theTracker.view superview] == wrapView)
                [theTracker.view removeFromSuperview];
            renderControl->sceneRenderer->setTriggerDraw();
        }
    }
}
#endif //!MAPLY_MINIMAL

// Overridden by the subclasses
- (CGPoint)screenPointFromGeo:(MaplyCoordinate)geoCoord
{
    return CGPointZero;
}

// Overridden by the subclasses
- (bool)animateToPosition:(MaplyCoordinate)newPos onScreen:(CGPoint)loc time:(TimeInterval)howLong
{
    return false;
}

#if !MAPLY_MINIMAL
- (void)addAnnotation:(MaplyAnnotation *)annotate forPoint:(MaplyCoordinate)coord offset:(CGPoint)offset
{
    [self addAnnotation:annotate forPoint:coord offset:offset arrowDirection:SMCalloutArrowDirectionDown];
}

- (void)addAnnotation:(MaplyAnnotation *)annotate forPoint:(MaplyCoordinate)coord offset:(CGPoint)offset arrowDirection:(NSInteger)arrowDirection
{
    if (!renderControl)
        return;

    annotate.calloutView.permittedArrowDirection = arrowDirection;

    // See if we're already representing the annotation
    bool alreadyHere = [annotations containsObject:annotate];
    
    // Let's put it in the right place so the callout can do its layout logic
    CGPoint pt = [self screenPointFromGeo:coord];

    // Fix for bad screen point return (courtesy highlander)
    if (isnan(pt.x) || isnan(pt.y))
        pt = CGPointMake(-2000.0,-2000.0);
    
    CGRect rect = CGRectMake(pt.x+offset.x, pt.y+offset.y, 0.0, 0.0);
    annotate.loc = coord;
    if (!alreadyHere)
    {
        annotate.calloutView.delegate = self;
        [annotations addObject:annotate];
        [annotate.calloutView presentCalloutFromRect:rect inView:wrapView constrainedToView:wrapView animated:YES];
    } else {
        annotate.calloutView.delegate = nil;
        [annotate.calloutView presentCalloutFromRect:rect inView:wrapView constrainedToView:wrapView animated:NO];
    }
    
    // But then we move it back because we're controlling its positioning
    CGRect frame = annotate.calloutView.frame;
    annotate.calloutView.frame = CGRectMake(frame.origin.x-pt.x+offset.x, frame.origin.y-pt.y+offset.y, frame.size.width, frame.size.height);

    ViewPlacementManager *vpManage = viewPlacementModel->getManager();
    if (vpManage) {
        if (alreadyHere)
        {
            vpManage->moveView(GeoCoord(coord.x,coord.y),Point2d(0,0),annotate.calloutView,annotate.minVis,annotate.maxVis);
        } else
        {
            vpManage->addView(GeoCoord(coord.x,coord.y),Point2d(0,0),annotate.calloutView,annotate.minVis,annotate.maxVis);
        }
    }
    renderControl->sceneRenderer->setTriggerDraw();
}

// Delegate callback for annotation placement
- (TimeInterval)calloutView:(SMCalloutView *)calloutView delayForRepositionWithSize:(CGSize)offset
{
    // Need to find the annotation this belongs to
    for (const MaplyAnnotation *annotation in annotations)
    {
        if (annotation.calloutView == calloutView && annotation.repositionForVisibility && allowRepositionForAnnnotations)
        {
            const CGPoint pt = [self screenPointFromGeo:annotation.loc];
            const CGPoint newPt = CGPointMake(pt.x+offset.width, pt.y+offset.height);
            [self animateToPosition:annotation.loc onScreen:newPt time:0.25];
            break;
        }
    }

    return 0.0;
}

- (void)removeAnnotation:(MaplyAnnotation *)annotate
{
    if (!renderControl)
        return;
    
    ViewPlacementManager *vpManage = viewPlacementModel->getManager();
    if (vpManage) {
        vpManage->removeView(annotate.calloutView);
    }
    
    [annotations removeObject:annotate];
    
    [annotate.calloutView dismissCalloutAnimated:YES];
}

- (void)freezeAnnotation:(MaplyAnnotation *)annotate
{
    if (!renderControl)
        return;
    
    ViewPlacementManager *vpManage = viewPlacementModel->getManager();
    if (vpManage) {
        for (MaplyAnnotation *annotation in annotations)
            if (annotate == annotation)
            {
                vpManage->freezeView(annotate.calloutView);
            }
    }
}

- (void)unfreezeAnnotation:(MaplyAnnotation *)annotate
{
    if (!renderControl)
        return;
    
    ViewPlacementManager *vpManage = viewPlacementModel->getManager();
    if (vpManage) {
        for (MaplyAnnotation *annotation in annotations)
            if (annotate == annotation)
            {
                vpManage->unfreezeView(annotate.calloutView);
            }
    }
    renderControl->sceneRenderer->setTriggerDraw();
}

- (NSArray *)annotations
{
    return annotations;
}

- (void)clearAnnotations
{
    NSArray *allAnnotations = [NSArray arrayWithArray:annotations];
    for (MaplyAnnotation *annotation in allAnnotations)
        [self removeAnnotation:annotation];
}
#endif //!MAPLY_MINIMAL

- (MaplyTexture *)addTexture:(UIImage *)image imageFormat:(MaplyQuadImageFormat)imageFormat wrapFlags:(int)wrapFlags mode:(MaplyThreadMode)threadMode
{
    return [self addTexture:image desc:@{kMaplyTexFormat: @(imageFormat),
                                         kMaplyTexWrapX: @(wrapFlags & MaplyImageWrapX),
                                         kMaplyTexWrapY: @(wrapFlags & MaplyImageWrapY)}
                                         mode:threadMode];
}

- (MaplyTexture *)addTexture:(UIImage *)image desc:(NSDictionary *)desc mode:(MaplyThreadMode)threadMode
{
    MaplyTexture *maplyTex = [renderControl addTexture:image desc:desc mode:threadMode];
    
    return maplyTex;
}

#if !MAPLY_MINIMAL
- (MaplyTexture *__nullable)addSubTexture:(MaplyTexture *__nonnull)tex xOffset:(int)x yOffset:(int)y width:(int)width height:(int)height mode:(MaplyThreadMode)threadMode
{
    MaplyTexture *maplyTex = [renderControl addSubTexture:tex xOffset:x yOffset:y width:width height:height mode:threadMode];
    
    return maplyTex;
}
#endif //!MAPLY_MINIMAL

- (MaplyTexture *__nullable)createTexture:(NSDictionary * _Nullable)inDesc sizeX:(int)sizeX sizeY:(int)sizeY mode:(MaplyThreadMode)threadMode
{
    MaplyTexture *maplyTex = [renderControl createTexture:inDesc sizeX:sizeX sizeY:sizeY mode:threadMode];
    
    return maplyTex;
}

- (void)removeTexture:(MaplyTexture *)texture mode:(MaplyThreadMode)threadMode
{
    [renderControl removeTextures:@[texture] mode:threadMode];
}

- (void)removeTextures:(NSArray *)textures mode:(MaplyThreadMode)threadMode
{
    [renderControl removeTextures:textures mode:threadMode];
}

#if !MAPLY_MINIMAL
- (MaplyTexture *)addTextureToAtlas:(UIImage *)image mode:(MaplyThreadMode)threadMode
{
    MaplyTexture *maplyTex = [self addTextureToAtlas:image imageFormat:MaplyImageIntRGBA wrapFlags:0 mode:threadMode];
    
    return maplyTex;
}

- (MaplyTexture *)addTextureToAtlas:(UIImage *)image imageFormat:(MaplyQuadImageFormat)imageFormat wrapFlags:(int)wrapFlags mode:(MaplyThreadMode)threadMode
{
    return [self addTexture:image desc:@{kMaplyTexFormat: @(imageFormat),
                                         kMaplyTexWrapX: @(wrapFlags & MaplyImageWrapX),
                                         kMaplyTexWrapY: @(wrapFlags & MaplyImageWrapY),
                                         kMaplyTexAtlas: @(YES)} mode:threadMode];
}
#endif //!MAPLY_MINIMAL

- (void)addRenderTarget:(MaplyRenderTarget *)renderTarget
{
    [renderControl addRenderTarget:renderTarget];
}

- (void)changeRenderTarget:(MaplyRenderTarget *)renderTarget tex:(MaplyTexture *)tex
{
    [renderControl changeRenderTarget:renderTarget tex:tex];
}

- (void)clearRenderTarget:(MaplyRenderTarget *)renderTarget mode:(MaplyThreadMode)threadMode
{
    [renderControl clearRenderTarget:renderTarget mode:threadMode];
}

- (void)removeRenderTarget:(MaplyRenderTarget *)renderTarget
{
    [renderControl removeRenderTarget:renderTarget];
}

#if !MAPLY_MINIMAL
- (void)setMaxLayoutObjects:(int)maxLayoutObjects
{
    if (const auto layoutManager = renderControl->scene->getManager<LayoutManager>(kWKLayoutManager))
    {
        layoutManager->setMaxDisplayObjects(maxLayoutObjects);
    }
}

- (void)setLayoutOverrideIDs:(NSArray *)uuids
{
    std::set<std::string> uuidSet;
    for (NSString *uuid in uuids) {
        std::string uuidStr = [uuid cStringUsingEncoding:NSASCIIStringEncoding];
        if (!uuidStr.empty())
            uuidSet.insert(uuidStr);
    }
    
    if (const auto layoutManager = renderControl->scene->getManager<LayoutManager>(kWKLayoutManager))
    {
        layoutManager->setOverrideUUIDs(uuidSet);
    }
}

- (void)runLayout
{
    [renderControl runLayout];
}

- (void)removeObject:(MaplyComponentObject *)theObj
{
    if (!theObj)
        return;

    [self removeObjects:@[theObj] mode:MaplyThreadAny];
}

- (void)removeObjects:(NSArray *)theObjs mode:(MaplyThreadMode)threadMode
{
    if (!theObjs)
        return;

    // All objects must be MaplyComponentObject.  Yes, this happens.
    for (id obj in theObjs)
        if (![obj isKindOfClass:[MaplyComponentObject class]]) {
            NSLog(@"User passed an invalid objects into removeOjbects:mode:  All objects must be MaplyComponentObject.  Ignoring.");
            return;
        }

    [renderControl removeObjects:[NSArray arrayWithArray:theObjs] mode:threadMode];
}

- (void)removeObjects:(NSArray *)theObjs
{
    if (!theObjs)
        return;
    
    [self removeObjects:theObjs mode:MaplyThreadAny];
}

- (void)disableObjects:(NSArray *)theObjs mode:(MaplyThreadMode)threadMode
{
    if (!theObjs)
        return;

    [renderControl disableObjects:theObjs mode:threadMode];
}

- (void)enableObjects:(NSArray *)theObjs mode:(MaplyThreadMode)threadMode
{
    if (!theObjs)
        return;

    [renderControl enableObjects:theObjs mode:threadMode];
}

- (void)setRepresentation:(NSString *__nullable)repName
                  ofUUIDs:(NSArray<NSString *> *__nonnull)uuids
{
    if (uuids.count)
    {
        [renderControl setRepresentation:repName ofUUIDs:uuids mode:MaplyThreadAny];
    }
}

- (void)setRepresentation:(NSString *__nullable)repName
          fallbackRepName:(NSString *__nullable)fallbackRepName
                  ofUUIDs:(NSArray<NSString *> *__nonnull)uuids
{
    if (uuids.count)
    {
        [renderControl setRepresentation:repName fallbackRepName:fallbackRepName ofUUIDs:uuids mode:MaplyThreadAny];
    }
}

- (void)setRepresentation:(NSString *__nullable)repName
                  ofUUIDs:(NSArray<NSString *> *__nonnull)uuids
                     mode:(MaplyThreadMode)threadMode
{
    if (uuids.count)
    {
        [renderControl setRepresentation:repName ofUUIDs:uuids mode:threadMode];
    }
}

- (void)setRepresentation:(NSString *__nullable)repName
          fallbackRepName:(NSString *__nullable)fallbackRepName
                  ofUUIDs:(NSArray<NSString *> *__nonnull)uuids
                     mode:(MaplyThreadMode)threadMode
{
    if (uuids.count)
    {
        [renderControl setRepresentation:repName fallbackRepName:fallbackRepName ofUUIDs:uuids mode:threadMode];
    }
}

- (void)setRepresentation:(NSString *__nullable)repName
                ofObjects:(NSArray<MaplyComponentObject *> *__nonnull)objs
{
    [self setRepresentation:repName ofObjects:objs mode:MaplyThreadAny];
}

- (void)setRepresentation:(NSString *__nullable)repName
          fallbackRepName:(NSString *__nullable)fallbackRepName
                ofObjects:(NSArray<MaplyComponentObject *> *__nonnull)objs
{
    [self setRepresentation:repName fallbackRepName:fallbackRepName ofObjects:objs mode:MaplyThreadAny];
}

- (void)setRepresentation:(NSString *__nullable)repName
                ofObjects:(NSArray<MaplyComponentObject *> *__nonnull)objs
                     mode:(MaplyThreadMode)threadMode
{
    [self setRepresentation:repName fallbackRepName:nil ofObjects:objs mode:threadMode];
}

- (void)setRepresentation:(NSString *__nullable)repName
          fallbackRepName:(NSString *__nullable)fallbackRepName
                ofObjects:(NSArray<MaplyComponentObject *> *__nonnull)objs
                     mode:(MaplyThreadMode)threadMode
{
    if (!objs.count)
    {
        return;
    }
    NSMutableArray<NSString *> *theUUIDs = [NSMutableArray new];
    for (const MaplyComponentObject *obj in objs)
    {
        if (auto uuid = [obj getUUID])
        {
            [theUUIDs addObject:uuid];
        }
    }
    if (![theUUIDs count])
    {
        return;
    }
    [renderControl setRepresentation:repName fallbackRepName:fallbackRepName ofUUIDs:theUUIDs mode:threadMode];
}
#endif //!MAPLY_MINIMAL

- (void)setUniformBlock:(NSData *__nonnull)uniBlock buffer:(int)bufferID forObjects:(NSArray<MaplyComponentObject *> *__nonnull)compObjs mode:(MaplyThreadMode)threadMode
{
    if (!compObjs)
        return;

    [renderControl setUniformBlock:uniBlock buffer:bufferID forObjects:compObjs mode:threadMode];
}


- (void)startChanges
{
    if (auto wr = WorkRegion(renderControl)) {
        [renderControl->interactLayer startChanges];
    }
}

- (void)endChanges
{
    if (auto wr = WorkRegion(renderControl)) {
        [renderControl->interactLayer endChanges];
    }
}

#if !MAPLY_MINIMAL
- (NSArray*)objectsAtCoord:(MaplyCoordinate)coord
{
    if (!renderControl)
        return nil;

    return [renderControl->interactLayer findVectorsInPoint:Point2f(coord.x,coord.y) inView:self multi:true];
}

- (NSArray*)labelsAndMarkersAtCoord:(MaplyCoordinate)coord
{
    if (!renderControl)
        return nil;

    return [renderControl->interactLayer selectMultipleLabelsAndMarkersForScreenPoint:[self screenPointFromGeo:coord]];
}
#endif //!MAPLY_MINIMAL

#pragma mark - Properties

- (UIColor *)clearColor
{
    if (!renderControl)
        return nil;
    
    return renderControl->theClearColor;
}

- (void)setClearColor:(UIColor *)clearColor
{
    [renderControl setClearColor:clearColor];
    
    // This is a hack for clear color
    RGBAColor theColor = [clearColor asRGBAColor];
    if (theColor.a < 255)
    {
        [self.view setBackgroundColor:[UIColor clearColor]];
        [wrapView setBackgroundColor:[UIColor clearColor]];
    }
}

- (MaplyCoordinate3d)displayPointFromGeo:(MaplyCoordinate)geoCoord
{
    if (!renderControl)
        return { 0, 0, 0 };
    
    const auto adapter = renderControl->visualView->getCoordAdapter();
    const Point3f pt = adapter->localToDisplay(adapter->getCoordSystem()->geographicToLocal(GeoCoord(geoCoord.x,geoCoord.y)));

    return { pt.x(), pt.y(), pt.z() };
}

- (MaplyCoordinate3dD)displayPointFromGeoD:(MaplyCoordinate)geoCoord
{
    if (!renderControl)
        return { 0, 0, 0 };
    
    const auto adapter = renderControl->visualView->getCoordAdapter();
    const Point3d pt = adapter->localToDisplay(adapter->getCoordSystem()->geographicToLocal3d(GeoCoord(geoCoord.x,geoCoord.y)));
    
    return { pt.x(), pt.y(), pt.z() };
}

- (MaplyCoordinate3dD)displayPointFromGeoDD:(MaplyCoordinateD)geoCoord
{
    if (!renderControl)
        return { 0, 0, 0 };
    
    const auto adapter = renderControl->visualView->getCoordAdapter();
    const Point3d pt = adapter->localToDisplay(adapter->getCoordSystem()->geographicToLocal(Point2d(geoCoord.x,geoCoord.y)));
    
    return { pt.x(), pt.y(), pt.z() };
}

- (float)currentMapScale
{
    if (!renderControl)
        return 0.0;
    
    const Point2f frameSize = renderControl->sceneRenderer->getFramebufferSize();
    if (frameSize.x() == 0)
        return MAXFLOAT;
    return (float)renderControl->visualView->currentMapScale(frameSize);
}

- (float)heightForMapScale:(float)scale
{
    if (!renderControl)
        return 0.0;
    
    const Point2f frameSize = renderControl->sceneRenderer->getFramebufferSize();
    if (frameSize.x() == 0)
        return -1.0;
    return (float)renderControl->visualView->heightForMapScale(scale,frameSize);
}

- (void)addSnapshotDelegate:(NSObject<MaplySnapshotDelegate> *)snapshotDelegate
{
    if (!renderControl)
        return;
    
    SnapshotTarget *newTarget = [[SnapshotTarget alloc] initWithOutsideDelegate:snapshotDelegate viewC:self];
    switch ([self getRenderType])
    {
        case MaplyRenderMetal:
        {
            SceneRendererMTLRef sceneRenderMTL = std::dynamic_pointer_cast<SceneRendererMTL>(renderControl->sceneRenderer);
            sceneRenderMTL->addSnapshotDelegate(newTarget);
        }
            break;
        default:
            break;
    }
}

- (void)removeSnapshotDelegate:(NSObject<MaplySnapshotDelegate> *)snapshotDelegate
{
    if (!renderControl)
        return;
    
    switch ([self getRenderType])
    {
        case MaplyRenderMetal:
        {
            SceneRendererMTLRef sceneRenderMTL = std::dynamic_pointer_cast<SceneRendererMTL>(renderControl->sceneRenderer);
            for (auto delegate : sceneRenderMTL->snapshotDelegates) {
                if ([delegate isKindOfClass:[SnapshotTarget class]]) {
                    SnapshotTarget *thisTarget = (SnapshotTarget *)delegate;
                    if (thisTarget.outsideDelegate == snapshotDelegate) {
                        sceneRenderMTL->removeSnapshotDelegate(thisTarget);
                        break;
                    }
                }
            }
        }
            break;
        default:
            break;
    }
}

- (UIImage *)snapshot
{
    if (!renderControl)
        return nil;

    // TODO: Implement this for Metal
    //       We have the data version.
    return nil;
    
//    // Courtesy: https://developer.apple.com/library/ios/qa/qa1704/_index.html
//    // Create a CGImage with the pixel data
//    // If your OpenGL ES content is opaque, use kCGImageAlphaNoneSkipLast to ignore the alpha channel
//    // otherwise, use kCGImageAlphaPremultipliedLast
//    CGDataProviderRef ref = CGDataProviderCreateWithData(NULL, [target.data bytes], [target.data length], NULL);
//    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
//    int framebufferWidth = renderControl->sceneRenderer->framebufferWidth;
//    int framebufferHeight = renderControl->sceneRenderer->framebufferHeight;
//    CGImageRef iref = CGImageCreate(framebufferWidth, framebufferHeight, 8, 32, framebufferWidth * 4, colorspace, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast,
//                                    ref, NULL, true, kCGRenderingIntentDefault);
//
//    // OpenGL ES measures data in PIXELS
//    // Create a graphics context with the target size measured in POINTS
//    NSInteger widthInPoints, heightInPoints;
//    {
//        // On iOS 4 and later, use UIGraphicsBeginImageContextWithOptions to take the scale into consideration
//        // Set the scale parameter to your OpenGL ES view's contentScaleFactor
//        // so that you get a high-resolution snapshot when its value is greater than 1.0
//        CGFloat scale = sceneRenderGLES->scale;
//        widthInPoints = framebufferWidth / scale;
//        heightInPoints = framebufferHeight / scale;
//        UIGraphicsBeginImageContextWithOptions(CGSizeMake(widthInPoints, heightInPoints), NO, scale);
//    }
//
//    CGContextRef cgcontext = UIGraphicsGetCurrentContext();
//
//    // UIKit coordinate system is upside down to GL/Quartz coordinate system
//    // Flip the CGImage by rendering it to the flipped bitmap context
//    // The size of the destination area is measured in POINTS
//    CGContextSetBlendMode(cgcontext, kCGBlendModeCopy);
//    CGContextDrawImage(cgcontext, CGRectMake(0.0, 0.0, widthInPoints, heightInPoints), iref);
//
//    // Retrieve the UIImage from the current context
//    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
//
//    UIGraphicsEndImageContext();
//
//    // Clean up
//    CFRelease(ref);
//    CFRelease(colorspace);
//    CGImageRelease(iref);
//
//    return image;
}

- (NSData *)shapshotRenderTarget:(MaplyRenderTarget *)renderTarget
{
    if ([NSThread currentThread] != renderControl->mainThread)
        return NULL;

    SnapshotTarget *target = [[SnapshotTarget alloc] init];
    target.renderTargetID = renderTarget.renderTargetID;

    SceneRendererMTLRef sceneRenderMTL = std::dynamic_pointer_cast<SceneRendererMTL>(renderControl->sceneRenderer);
    
    sceneRenderMTL->addSnapshotDelegate(target);
    sceneRenderMTL->forceDrawNextFrame();
    sceneRenderMTL->render(0.0, nil);
    sceneRenderMTL->removeSnapshotDelegate(target);
    
    return target.data;
}

- (NSData *)shapshotRenderTarget:(MaplyRenderTarget *)renderTarget rect:(CGRect)rect
{
    if ([NSThread currentThread] != renderControl->mainThread)
        return NULL;
    
    // TODO: Get rid of this.
    return nil;
    
//    SnapshotTarget *target = [[SnapshotTarget alloc] init];
//    target.renderTargetID = renderTarget.renderTargetID;
//    target.subsetRect = rect;
//    sceneRenderGLES->addSnapshotDelegate(target);
//
//    sceneRenderGLES->forceDrawNextFrame();
//    sceneRenderGLES->render(0.0);
//
//    sceneRenderGLES->removeSnapshotDelegate(target);
//
//    return target.data;
}


- (float)currentMapZoom:(MaplyCoordinate)coordinate
{
    if (!renderControl)
        return 0.0;
    
    const Point2f frameSize = renderControl->sceneRenderer->getFramebufferSize();
    if (frameSize.x() == 0)
        return MAXFLOAT;
    return (float)renderControl->visualView->currentMapZoom(frameSize,coordinate.y);
}

- (MaplyCoordinateSystem *)coordSystem
{
    // Note: Hack.  Should wrap the real coordinate system
    MaplyCoordinateSystem *coordSys = [[MaplySphericalMercator alloc] initWebStandard];
    
    return coordSys;
}

- (MaplyCoordinate3d)displayCoordFromLocal:(MaplyCoordinate3d)localCoord
{
    const auto adapter = renderControl->visualView->getCoordAdapter();
    const Point3f pt = adapter->localToDisplay(Point3d(localCoord.x,localCoord.y,localCoord.z)).cast<float>();
    return { pt.x(), pt.y(), pt.z() };
}

- (MaplyCoordinate3d)displayCoord:(MaplyCoordinate3d)localCoord fromSystem:(MaplyCoordinateSystem *)coordSys
{
    const auto adapter = renderControl->visualView->getCoordAdapter();
    const Point3d loc3d = CoordSystemConvert3d(coordSys->coordSystem.get(), adapter->getCoordSystem(), Point3d(localCoord.x,localCoord.y,localCoord.z));
    const Point3f pt = adapter->localToDisplay(loc3d).cast<float>();
    return { pt.x(), pt.y(), pt.z() };
}

- (MaplyCoordinate3dD)displayCoordD:(MaplyCoordinate3dD)localCoord fromSystem:(MaplyCoordinateSystem *)coordSys
{
    const auto adapter = renderControl->visualView->getCoordAdapter();
    const Point3d loc3d = CoordSystemConvert3d(coordSys->coordSystem.get(), adapter->getCoordSystem(), Point3d(localCoord.x,localCoord.y,localCoord.z));
    const Point3d pt = adapter->localToDisplay(loc3d);
    return { pt.x(), pt.y(), pt.z() };
}

- (MaplyCoordinate3dD)displayCoordFromLocalD:(MaplyCoordinate3dD)localCoord
{
    const auto adapter = renderControl->visualView->getCoordAdapter();
    const Point3d pt = adapter->localToDisplay(Point3d(localCoord.x,localCoord.y,localCoord.z));
    return { pt.x(), pt.y(), pt.z() };
}

#if !MAPLY_MINIMAL
- (BOOL)enable3dTouchSelection:(NSObject<Maply3dTouchPreviewDatasource>*)previewDataSource
{
    if (!renderControl)
        return false;
    
    if(previewingContext)
    {
        [self disable3dTouchSelection];
    }
    
    if([self respondsToSelector:@selector(traitCollection)] &&
       [self.traitCollection respondsToSelector:@selector(forceTouchCapability)] &&
       self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable)
    {
        previewTouchDelegate = [Maply3dTouchPreviewDelegate touchDelegate:self
                                                            interactLayer:renderControl->interactLayer
                                                               datasource:previewDataSource];
        previewingContext = [self registerForPreviewingWithDelegate:previewTouchDelegate
                                                         sourceView:self.view];
        return YES;
    }
    return NO;
}

- (void)disable3dTouchSelection {
    if(previewingContext)
    {
        [self unregisterForPreviewingWithContext:previewingContext];
        previewingContext = nil;
    }
}
#endif //!MAPLY_MINIMAL

- (void)requirePanGestureRecognizerToFailForGesture:(UIGestureRecognizer *__nullable)other {
    // Implement in derived class.
}

#if !MAPLY_MINIMAL

- (void)handleStartMoving:(bool)userMotion
{
    if (renderControl && renderControl->visualView)
    {
        renderControl->visualView->setUserMotion(userMotion);
    }
}

- (void)handleStopMoving:(bool)userMotion
{
    if (renderControl && renderControl->visualView)
    {
        renderControl->visualView->setUserMotion(false);
    }
}

- (void)startLocationTrackingWithDelegate:(NSObject<MaplyLocationTrackerDelegate> *)delegate
                               useHeading:(bool)useHeading
                                useCourse:(bool)useCourse {
    [self startLocationTrackingWithDelegate:delegate
                                  simulator:nil
                                simInterval:0
                                 useHeading:useHeading
                                  useCourse:useCourse];
}

- (void)startLocationTrackingWithDelegate:(NSObject<MaplyLocationTrackerDelegate> *)delegate
                                simulator:(NSObject<MaplyLocationSimulatorDelegate> *__nullable)simulator
                              simInterval:(NSTimeInterval)simInterval
                               useHeading:(bool)useHeading
                                useCourse:(bool)useCourse {
    [self stopLocationTracking];
    _locationTracker = [[MaplyLocationTracker alloc] initWithViewC:self
                                                          delegate:delegate
                                                         simulator:simulator
                                                       simInterval:simInterval
                                                        useHeading:useHeading
                                                         useCourse:useCourse];
}

- (MaplyLocationTracker *)getLocationTracker
{
    return _locationTracker;
}

- (void)changeLocationTrackingLockType:(MaplyLocationLockType)lockType {
    [self changeLocationTrackingLockType:lockType forwardTrackOffset:0];
}

- (void)changeLocationTrackingLockType:(MaplyLocationLockType)lockType forwardTrackOffset:(int)forwardTrackOffset {
    if (!_locationTracker)
        return;
    [_locationTracker changeLockType:lockType forwardTrackOffset:forwardTrackOffset];
}

- (void)stopLocationTracking {
    [_locationTracker teardown];
    _locationTracker = nil;
}

- (MaplyCoordinate)getDeviceLocation {
    if (!_locationTracker)
        return kMaplyNullCoordinate;
    return [_locationTracker getLocation];
}

- (CLLocationManager *)getTrackingLocationManager {
    if (!_locationTracker)
        return nil;
    return _locationTracker.locationManager;
}
#endif //!MAPLY_MINIMAL

-(NSArray *)loadedLayers
{
    return [NSArray arrayWithArray:renderControl->userLayers];
}

- (MaplyRenderController * __nullable)getRenderControl
{
    return renderControl;
}

- (CGSize)getFramebufferSize
{
    if (!renderControl || !renderControl->sceneRenderer)
        return CGSizeZero;
    
    const Point2f frameSize = renderControl->sceneRenderer->getFramebufferSize();
    return CGSizeMake(frameSize.x(), frameSize.y());
}

- (MaplyRenderType)getRenderType
{
    if (!renderControl || !renderControl->sceneRenderer)
        return MaplyRenderUnknown;
    
    switch (renderControl->sceneRenderer->getType())
    {
        case WhirlyKit::SceneRenderer::RenderMetal:
            return MaplyRenderMetal;
        default:
            return MaplyRenderUnknown;
    }
}

- (void)addActiveObject:(MaplyActiveObject *__nonnull)theObj
{
    [renderControl addActiveObject:theObj];
}

- (void)removeActiveObject:(MaplyActiveObject *__nonnull)theObj
{
    [renderControl removeActiveObject:theObj];
}

- (void)removeActiveObjects:(NSArray *__nonnull)theObjs
{
    [renderControl removeActiveObjects:theObjs];
}

- (bool)addLayer:(MaplyControllerLayer *__nonnull)layer
{
    return [renderControl addLayer:layer];
}

- (void)removeLayer:(MaplyControllerLayer *__nonnull)layer
{
    [renderControl removeLayer:layer];
}

- (void)removeLayers:(NSArray *__nonnull)layers
{
    [renderControl removeLayers:layers];
}

- (void)removeAllLayers
{
    [renderControl removeAllLayers];
}

- (int)getTileFetcherConnections
{
    return renderControl.tileFetcherConnections;
}

- (void)setTileFetcherConnections:(int)value
{
    renderControl.tileFetcherConnections = value;
}

- (MaplyRemoteTileFetcher *)addTileFetcher:(NSString * __nonnull)name
{
    return [renderControl addTileFetcher:name];
}

- (MaplyRemoteTileFetcher * _Nullable)addTileFetcher:(NSString * _Nonnull)name withMaxConnections:(int)maxConnections {
    return [renderControl addTileFetcher:name withMaxConnections:maxConnections];
}

- (MaplyRemoteTileFetcher * __nullable)getTileFetcher:(NSString * __nonnull)name
{
    return [renderControl getTileFetcher:name];
}

- (void)layoutDidRun
{
    // Layout complete, we can do stuff like `findHeightToViewBounds` now
    for (InitCompletionBlock block in _postInitCalls)
    {
        block();
    }
    _postInitCalls = nil;
}

- (void)addPostInitBlock:(_Nonnull InitCompletionBlock)block
{
    if (block)
    {
        if (_postInitCalls)
        {
            [_postInitCalls addObject:block];
        }
        else
        {
            block();
        }
    }
}

- (int)retainZoomSlotMinZoom:(double)minZoom
                   maxHeight:(double)maxHeight
                     maxZoom:(double)maxZoom
                   minHeight:(double)minHeight
{
    if (const auto render = renderControl ? renderControl->sceneRenderer : nullptr)
    {
        return render->retainZoomSlot(minZoom, maxHeight, maxZoom, minHeight);
    }
    return -1;
}

- (void)releaseZoomSlotIndex:(int)index
{
    if (const auto render = renderControl ? renderControl->sceneRenderer : nullptr)
    {
        render->releaseZoomSlot(index);
    }
}

@end
