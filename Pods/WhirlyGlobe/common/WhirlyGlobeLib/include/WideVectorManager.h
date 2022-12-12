/*  WideVectorManager.h
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 4/29/14.
 *  Copyright 2011-2022 mousebird consulting.
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

#import <math.h>
#import <set>
#import <map>
#import "Identifiable.h"
#import "BasicDrawableInstance.h"
#import "Scene.h"
#import "SelectionManager.h"
#import "VectorData.h"
#import "Dictionary.h"
#import "BaseInfo.h"

namespace WhirlyKit
{

class VectorInfo;

/// Vectors are widened in real world or screen coordinates
typedef enum {WideVecCoordReal,WideVecCoordScreen} WideVectorCoordsType;

/// How the lines are joined.  See: http://www.w3.org/TR/SVG/painting.html#StrokeLinejoinProperty
typedef enum WideVectorLineJoinType_t {
    WideVecMiterJoin,
    WideVecMiterClipJoin,
    WideVecMiterSimpleJoin,
    WideVecRoundJoin,
    WideVecBevelJoin,
    WideVecNoneJoin,
} WideVectorLineJoinType;

typedef enum WideVectorFallbackMode_t {
    WideVecFallbackNone,    // Just give up
    WideVecFallbackClip,    // Clip the intersection and continue
} WideVectorFallbackMode;

/// How the lines begin and end.  See: http://www.w3.org/TR/SVG/painting.html#StrokeLinecapProperty
typedef enum WideVectorLineCapType_t {
    WideVecButtCap,
    WideVecRoundCap,
    WideVecSquareCap
} WideVectorLineCapType;

/// Performance vs basic wide vector implementation
typedef enum {WideVecImplBasic,WideVecImplPerf} WideVecImplType;
    
/** Used to pass parameters for the wide vectors around.
  */
class WideVectorInfo : public BaseInfo
{
public:
    WideVectorInfo() = default;
    WideVectorInfo(const Dictionary &dict);
    virtual ~WideVectorInfo() = default;

    // Convert contents to a string for debugging
    virtual std::string toString() const override;

    WideVecImplType implType = WideVecImplBasic;
    RGBAColor color = RGBAColor::white();
    float width = 2.0f;
    float offset = 0.0f;
    float repeatSize = 32.0f;
    Point2f texOffset = { 0.0f, 0.0f };
    float edgeSize = 1.0f;
    float subdivEps = 0.0f;
    float miterLimit = 2.0f;
    bool closeAreals = true;
    bool selectable = true;

    WideVectorCoordsType coordType = WideVecCoordScreen;
    WideVectorLineJoinType joinType = WideVecMiterJoin;
    WideVectorFallbackMode fallbackMode = WideVecFallbackNone;
    WideVectorLineCapType capType = WideVecButtCap;

    SimpleIdentity texID = EmptyIdentity;

    FloatExpressionInfoRef widthExp;
    FloatExpressionInfoRef offsetExp;
    FloatExpressionInfoRef opacityExp;
    ColorExpressionInfoRef colorExp;
};
typedef std::shared_ptr<WideVectorInfo> WideVectorInfoRef;
    
/// Used to track the
struct WideVectorSceneRep : public Identifiable
{
    WideVectorSceneRep() = default;
    WideVectorSceneRep(SimpleIdentity inId) : Identifiable(inId), fadeOut(0.0) {
    }
    ~WideVectorSceneRep() = default;
    
    void enableContents(bool enable,ChangeSet &changes);
    void clearContents(ChangeSet &changes,TimeInterval when);
    
    SimpleIDSet drawIDs;
    SimpleIDSet instIDs;    // Instances if we're doing that
    float fadeOut = 0.0f;
};

typedef std::set<WideVectorSceneRep *,IdentifiableSorter> WideVectorSceneRepSet;

#define kWKWideVectorManager "WKWideVectorManager"

/** The Wide Vector Manager handles linear features that we widen into
    polygons and display in real world or screen size.
  */
class WideVectorManager : public SceneManager
{
public:
    WideVectorManager() = default;
    virtual ~WideVectorManager();

    /// Add widened vectors for display
    SimpleIdentity addVectors(const std::vector<VectorShapeRef> &shapes,const WideVectorInfo &desc,ChangeSet &changes);
    
    /// Enable/disable active vectors
    void enableVectors(SimpleIDSet &vecIDs,bool enable,ChangeSet &changes);
    
    /// Make an instance of the give vectors with the given attributes and return an ID to identify them.
    SimpleIdentity instanceVectors(SimpleIdentity vecID,const WideVectorInfo &desc,ChangeSet &changes);

    /// Change the vector(s) represented by the given ID
    void changeVectors(SimpleIdentity vecID,const WideVectorInfo &vecInfo,ChangeSet &changes);

    /// Remove a gruop of vectors named by the given ID
    void removeVectors(SimpleIDSet &vecIDs,ChangeSet &changes);
    
protected:
    WideVectorSceneRepSet sceneReps;
};
typedef std::shared_ptr<WideVectorManager> WideVectorManagerRef;
    
}
