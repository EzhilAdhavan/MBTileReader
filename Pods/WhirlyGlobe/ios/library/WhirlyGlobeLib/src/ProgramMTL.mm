/*  ProgramMTL.mm
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 5/16/19.
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

#import <MetalKit/MetalKit.h>
#import "ProgramMTL.h"
#import "TextureMTL.h"
#import "DefaultShadersMTL.h"
#import "SceneRendererMTL.h"
#import "WhirlyKitLog.h"

namespace WhirlyKit
{
    
ProgramMTL::ProgramMTL(const std::string &inName,id<MTLFunction> vertFunc,id<MTLFunction> fragFunc) :
    vertFunc(vertFunc),
    fragFunc(fragFunc),
    lightsLastUpdated(0.0),
    valid(vertFunc)     // fragment program is not mandatory (for calc shaders)
{
    name = inName;
}

bool ProgramMTL::isValid() const
{
    return valid;
}

bool ProgramMTL::hasLights() const
{
    // Lights are set up once for the renderer, so this makes no difference
    return true;
}

bool ProgramMTL::setLights(const std::vector<DirectionalLight> &lights, TimeInterval lastUpdated,
                           const Material *mat, const Eigen::Matrix4f &modelMat) const
{
    // We don't do lights this way, so it's all good
    return true;
}
    
bool ProgramMTL::setTexture(StringIdentity nameID,TextureBase *tex,int textureSlot)
{
    TextureBaseMTL *texMTL = dynamic_cast<TextureBaseMTL *>(tex);
    if (!texMTL)
        return false;

    // If it's already there, then just overwrite it
    for (auto &texEntry: textures)
        if (texEntry.slot == textureSlot) {
            texEntry.texBuf = texMTL->getMTLTex();
            texEntry.texID = tex->getId();

            texturesChanged = true;
            return true;
        }
    
    TextureEntry texEntry;
    texEntry.slot = textureSlot;
    texEntry.texBuf = texMTL->getMTLTex();
    texEntry.texID = tex->getId();
    textures.push_back(texEntry);
    
    texturesChanged = true;
    
    return true;
}

void ProgramMTL::clearTexture(SimpleIdentity texID)
{
    std::vector<int> entries;

    int which = 0;
    for (auto texEntry: textures) {
        if (texEntry.texID == texID) {
            entries.push_back(which);
        }
        which++;
    }
    
    for (auto entry = entries.rbegin(); entry != entries.rend(); entry++) {
        textures.erase(textures.begin()+*entry);
    }
    
    texturesChanged = true;
}

const std::string &ProgramMTL::getName() const
{ return name; }

void ProgramMTL::teardownForRenderer(const RenderSetupInfo *setupInfo,Scene *scene,RenderTeardownInfoRef inTeardown)
{
    RenderTeardownInfoMTLRef teardown = std::dynamic_pointer_cast<RenderTeardownInfoMTL>(inTeardown);

    textures.clear();
}
    
}
