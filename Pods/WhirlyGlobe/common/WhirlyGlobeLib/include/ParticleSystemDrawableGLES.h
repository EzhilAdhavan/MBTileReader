/*  ParticleSystemDrawableGLES.h
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 4/28/15.
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

#import "ParticleSystemDrawable.h"
#import "ProgramGLES.h"
#import "WrapperGLES.h"
#import "BasicDrawableGLES.h"
#import "VertexAttributeGLES.h"

namespace WhirlyKit
{

// Shader name
//#define kParticleSystemShaderName "Default Part Sys (Point)"

// Build the particle system default shader
ProgramGLES *BuildParticleSystemProgramGLES(const std::string &name,SceneRenderer *renderer);

// Maximum size of particle buffers (8MB)
#define kMaxParticleMemory (8*1024*1024)

/// OpenGL ES version of the particle system drawable
struct ParticleSystemDrawableGLES : virtual public ParticleSystemDrawable, virtual public DrawableGLES
{
    friend struct ParticleSystemDrawableBuilderGLES;

    ParticleSystemDrawableGLES(std::string name);
    virtual ~ParticleSystemDrawableGLES() = default;
    
    /// Add the vertex data (all of it) at once
    void addAttributeData(const RenderSetupInfo *setupInfo,const std::vector<AttributeData> &attrData,const Batch &batch) override;

    /// Create our buffers in GL
    virtual void setupForRenderer(const RenderSetupInfo *,Scene *scene) override;
    
    /// Destroy GL buffers
    virtual void teardownForRenderer(const RenderSetupInfo *setupInfo,Scene *scene,RenderTeardownInfoRef teardown) override;

    /// Particles can calculate their positions
    void calculate(RendererFrameInfoGLES *frameInfo,Scene *scene) override;
    
    /// Called on the rendering thread to draw
    void draw(RendererFrameInfoGLES *frameInfo,Scene *scene) override;

protected:
    std::vector<SingleVertexAttributeInfoGLES> vertAttrs;
    std::vector<SingleVertexAttributeInfoGLES> varyAttrs;
    
    struct VaryBufferPair {
        GLuint buffers[2];
    };
    std::vector<VaryBufferPair> varyBuffers;
    std::vector<SimpleIdentity> varyNames;

    GLuint pointBuffer = 0;
    GLuint rectBuffer = 0;

    float pointSize = 0.0f;

    void drawSetupTextures(RendererFrameInfo *frameInfo,Scene *scene,ProgramGLES *prog,bool hasTexture[],int &progTexBound);
    void drawTeardownTextures(RendererFrameInfo *frameInfo,Scene *scene,ProgramGLES *prog,bool hasTexture[],int progTexBound);
    void drawSetupUniforms(RendererFrameInfo *frameInfo,Scene *scene,ProgramGLES *prog);
    void drawBindAttrs(RendererFrameInfo *frameInfo,Scene *scene,ProgramGLES *prog,const BufferChunk &chunk,int pointsSoFar,bool useInstancingHere);
    void drawUnbindAttrs(ProgramGLES *prog);
};
    
}
