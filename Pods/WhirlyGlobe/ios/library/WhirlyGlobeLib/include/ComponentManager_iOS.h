/*
 *  ComponentManager_iOS.h
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

#import "ComponentManager.h"
#import "MaplyTexture_private.h"

namespace WhirlyKit
{
// iOS version of ComponentObject
class ComponentObject_iOS : public ComponentObject
{
public:
    ComponentObject_iOS();

    // Create the component object with the specified defaults and
    // apply the properties from the descriptor dictionary, if present.
    // (i.e., `kMaplyEnabled` in `desc` overrides `enable`)
    ComponentObject_iOS(bool enable, bool isSelectable, const NSDictionary *_Nullable desc);

    // Textures we're holding on to
    // If we let them release, they go away
    std::set<MaplyTexture *> texs;
};

typedef std::shared_ptr<ComponentObject_iOS> ComponentObject_iOSRef;

// Used to map IDs to individual user objects (e.g. markers, labels)
class SelectObject
{
public:
    SelectObject(WhirlyKit::SimpleIdentity selID) : selID(selID), obj(nullptr) { }
    SelectObject(WhirlyKit::SimpleIdentity selID,NSObject *__nullable obj) : selID(selID), obj(obj) { }
    
    // Comparison operator sorts on select ID
    bool operator < (const SelectObject &that) const
    {
        return selID < that.selID;
    }
    
    WhirlyKit::SimpleIdentity selID;
    NSObject *__nullable __strong obj;
};

typedef std::set<SelectObject> SelectObjectSet;

/** Component Manager for iOS.
    Contains a few iOS related methods based on the regular ComponentManager.
  */
class ComponentManager_iOS : public ComponentManager
{
public:
    ComponentManager_iOS();
    virtual ~ComponentManager_iOS();
    
    /// Associate the given object with the selection ID
    void addSelectObject(SimpleIdentity selectID,NSObject *_Nonnull obj);
    
    /// Return the NSObject (marker, label) corresponding to a selection
    NSObject *_Nonnull getSelectObject(SimpleIdentity selID);

    /// Need to remove select IDs before we let the superclass clean up
    virtual void removeComponentObjects(PlatformThreadInfo *_Nullable threadInfo,
                                        const SimpleIDSet &compIDs,
                                        ChangeSet &changes,
                                        bool disposeAfterRemove = true) override;
    
    /// Clear out anything we're holding
    void clear();
    
    /// Print out statistics
    void dumpStats();
    
protected:
    virtual ComponentObjectRef makeComponentObject(const Dictionary *_Nullable desc) override;
    
    /// Remove the given selectable object
    void removeSelectObjects(SimpleIDSet selID);

    std::mutex selectLock;
    // Use to map IDs in the selection layer to objects the user passed in
    SelectObjectSet selectObjectSet;
};
typedef std::shared_ptr<ComponentManager_iOS> ComponentManager_iOSRef;
    
}
