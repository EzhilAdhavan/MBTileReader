/*
 *  QuadSamplingController.h
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 2/15/19.
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

#import "QuadSamplingParams.h"
#import "QuadDisplayControllerNew.h"
#import "QuadTileBuilder.h"

namespace WhirlyKit
{

/** The Quad Sampling Controller runs the quad tree and related
    data structures, figuring out what to load and loading it.
    It needs a native interface to call its various methods.
 */
class QuadSamplingController : public QuadDataStructure, public QuadTileBuilderDelegate
{
public:
    QuadSamplingController() = default;
    virtual ~QuadSamplingController() = default;
    
    // Number of clients using this sampler
    int getNumClients() const { return builderDelegates.size(); }
    
    // Return the Display Controller we're using
    QuadDisplayControllerNewRef getDisplayControl() const { return displayControl; }
    
    // Return the builder we're using
    QuadTileBuilderRef getBuilder() const { return builder; }
    
    // Add a new builder delegate to watch tile related events
    // Returns true if we need to notify the delegate
    bool addBuilderDelegate(PlatformThreadInfo *, QuadTileBuilderDelegateRef delegate);
    
    // Remove the given builder delegate that was watching tile related events
    void removeBuilderDelegate(PlatformThreadInfo *, const QuadTileBuilderDelegateRef &delegate);

    // Called right before we start using the controller
    void start(const SamplingParams &params,Scene *scene,SceneRenderer *renderer);

    // About to stop, cancel operations in progress and don't start any new ones
    void stopping();

    // Unhook everything and shut it down
    void stop();
    
    // Called on the layer thread to initialize a new builder
    void notifyDelegateStartup(PlatformThreadInfo *threadInfo,SimpleIdentity delegateID,ChangeSet &changes);
    
    /// **** QuadDataStructure methods ****
    
    /// Return the coordinate system we're working in
    virtual CoordSystem *getCoordSystem() const override { return params.coordSys.get(); }
    
    /// Bounding box used to calculate quad tree nodes.  In local coordinate system.
    virtual MbrD getTotalExtents() const override { return params.coordBounds; }
    
    /// Bounding box of data you actually want to display.  In local coordinate system.
    /// Unless you're being clever, make this the same as totalExtents.
    virtual MbrD getValidExtents() const override;
    
    /// Return the minimum quad tree zoom level (usually 0)
    virtual int getMinZoom() const override { return params.minZoom; }
    
    /// Return the maximum quad tree zoom level.  Must be at least minZoom
    virtual int getMaxZoom() const override { return params.maxZoom; }
    
    /// Max zoom level we want reportable (beyond the loaded max zoom)
    virtual int getReportedMaxZoom() const override { return params.reportedMaxZoom; }
    
    /// Return an importance value for the given tile
    virtual double importanceForTile(const QuadTreeIdentifier &ident,
                                     const Mbr &mbr,
                                     const ViewStateRef &viewState,
                                     const Point2f &frameSize) override;
    
    /// Called when the view state changes.  If you're caching info, do it here.
    virtual void newViewState(ViewStateRef viewState) override;
    
    /// Return true if the tile is visible, false otherwise
    virtual bool visibilityForTile(const QuadTreeIdentifier &ident,
                                   const Mbr &mbr,
                                   const ViewStateRef &viewState,
                                   const Point2f &frameSize) override;
    
    /// **** QuadTileBuilderDelegate methods ****

    /// Called when the builder first starts up.  Keep this around if you need it.
    virtual void setBuilder(QuadTileBuilder *inBuilder, QuadDisplayControllerNew *control) override;
    
    /// Before we tell the delegate to unload tiles, see if they want to keep them around
    /// Returns the tiles we want to preserve after all
    virtual QuadTreeNew::NodeSet builderUnloadCheck(QuadTileBuilder *inBuilder,
                                                    const WhirlyKit::QuadTreeNew::ImportantNodeSet &loadTiles,
                                                    const WhirlyKit::QuadTreeNew::NodeSet &unloadTiles,
                                                    int targetLevel) override;
    
    /// Load the given group of tiles.  If you don't load them immediately, up to you to cancel any requests
    virtual void builderLoad(PlatformThreadInfo *threadInfo,
                             QuadTileBuilder *inBuilder,
                             const WhirlyKit::TileBuilderDelegateInfo &updates,
                             ChangeSet &changes) override;
    
    /// Called right before the layer thread flushes all its current changes
    virtual void builderPreSceneFlush(QuadTileBuilder *inBuilder, ChangeSet &changes) override;
    
    /// Shutdown called on the layer thread if you have stuff to clean up
    virtual void builderShutdown(PlatformThreadInfo *threadInfo, QuadTileBuilder *inBuilder, ChangeSet &changes) override;

    /// Quick loading status check
    virtual bool builderIsLoading() const override;

protected:
    bool debugMode = false;

    mutable std::mutex lock;
    
    SamplingParams params;
    QuadDisplayControllerNewRef displayControl;

    WhirlyKit::Scene *scene = nullptr;
    SceneRenderer *renderer = nullptr;

    QuadTileBuilderRef builder;
    std::vector<QuadTileBuilderDelegateRef> builderDelegates;
    
    bool builderStarted = false;
    bool valid = true;
};
    
}
