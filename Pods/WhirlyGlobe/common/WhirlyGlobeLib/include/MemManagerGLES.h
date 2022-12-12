/*  MemManagerGLES.h
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 2/1/11.
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

#import "WrapperGLES.h"
#import "ChangeRequest.h"
#import <mutex>
#import <unordered_set>

namespace WhirlyKit
{
    
/// We'll only keep this many buffers or textures around for reuse
#define WhirlyKitOpenGLMemCacheMax 32
/// Number of buffers we allocate at once
#define WhirlyKitOpenGLMemCacheAllocUnit 32
    
// Maximum of 8 textures for the moment
#define WhirlyKitMaxTextures 8
    
/// Used to manage OpenGL buffer IDs and such.
/// They're expensive to create and delete, so we try to do it
///  outside the renderer.
class OpenGLMemManager
{
public:
    OpenGLMemManager();
    ~OpenGLMemManager();
    
    /// Pick a buffer ID off the list or ask OpenGL for one
    GLuint getBufferID(unsigned int size=0,GLenum drawType=GL_STATIC_DRAW);
    /// Toss the given buffer ID back on the list for reuse
    void removeBufferID(GLuint bufID);
    
    /// Pick a texture ID off the list or ask OpenGL for one
    GLuint getTexID();
    /// Toss the given texture ID back on the list for reuse
    void removeTexID(GLuint texID);
    
    /// Clear out any and all buffer IDs that we may have sitting around
    void clearBufferIDs();
    
    /// Clear out any and all texture IDs that we have sitting around
    void clearTextureIDs();
    
    /// Print out stats about what's in the cache
    void dumpStats();

    /// Clean up resources, don't cache anything else
    void teardown();

    /// Globally enable/disable buffer reuse, 0 to disable
    static void setBufferReuse(int maxBuffers);

    /// Globally enable/disable texture reuse, 0 to disable
    static void setTextureReuse(int maxTextures);

protected:
    std::mutex idLock;
    
    std::unordered_set<GLuint> buffIDs;
    std::unordered_set<GLuint> texIDs;

    bool shutdown = false;

    static int maxCachedBuffers;
    static int maxCachedTextures;
};
    
/** This is the configuration info passed to setupGL for each
 drawable.  Sometimes this will be render thread side, sometimes
 layer thread side.  The defaults should be valid.
 */
struct RenderSetupInfoGLES : public RenderSetupInfo
{
    RenderSetupInfoGLES(Scene *scene = nullptr);
    
    /// If we're using drawOffset, this is the units
    float minZres = 0.0f;
    /// Version of OpenGL ES we're using
    int glesVersion = 3;

    /// GL memory manager
    OpenGLMemManager *memManager = nullptr;
};

}
