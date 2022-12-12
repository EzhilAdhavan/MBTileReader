/*  SceneRendererMTL.mm
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

#import "SceneRendererMTL.h"
#import "BasicDrawableBuilderMTL.h"
#import "BasicDrawableInstanceBuilderMTL.h"
#import "BillboardDrawableBuilderMTL.h"
#import "ScreenSpaceDrawableBuilderMTL.h"
#import "WideVectorDrawableBuilderMTL.h"
#import "RenderTargetMTL.h"
#import "DynamicTextureAtlasMTL.h"
#import "MaplyView.h"
#import "WhirlyKitLog.h"
#import "DefaultShadersMTL.h"
#import "RawData_NSData.h"
#import "RenderTargetMTL.h"

// Capture a range of frames to the developer tools (frames are 1-based)
#define CAPTURE_FRAME_START 0
#define CAPTURE_FRAME_END (CAPTURE_FRAME_START+0)

using namespace Eigen;

namespace WhirlyKit
{

WorkGroupMTL::WorkGroupMTL(GroupType inGroupType) :
    WorkGroupMTL(inGroupType, std::string())
{
}

WorkGroupMTL::WorkGroupMTL(GroupType inGroupType, std::string inName)
{
    groupType = inGroupType;
    name = std::move(inName);
    
    switch (groupType) {
        case Calculation:
            // For calculation we don't really have a render target
            renderTargetContainers.push_back(WorkGroupMTL::makeRenderTargetContainer(nullptr));
            break;
        case Offscreen:
            break;
        case ReduceOps:
            break;
        case ScreenRender:
            break;
    }
}

RenderTargetContainerMTL::RenderTargetContainerMTL(RenderTargetRef renderTarget) :
    RenderTargetContainer(std::move(renderTarget))
{
}

RenderTargetContainerRef WorkGroupMTL::makeRenderTargetContainer(RenderTargetRef renderTarget)
{
    return std::make_shared<RenderTargetContainerMTL>(std::move(renderTarget));
}

SceneRendererMTL::SceneRendererMTL(id<MTLDevice> mtlDevice,id<MTLLibrary> mtlLibrary, float inScale) :
    setupInfo(mtlDevice,mtlLibrary),
    cmdQueue([mtlDevice newCommandQueue]),
    _isShuttingDown(std::make_shared<bool>(false)),
    lastRenderNo(0),
    renderEvent(nil)
{
    offscreenBlendEnable = false;
    indirectRender = false;
#if !TARGET_OS_MACCATALYST
    if (@available(iOS 13.0, *)) {
        if ([mtlDevice supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily3_v4])
            indirectRender = true;
    }
#endif
#if TARGET_OS_SIMULATOR
    indirectRender = false;
#endif

    MTLCaptureManager* captureMgr = [MTLCaptureManager sharedCaptureManager];
    cmdCaptureScope = [captureMgr newCaptureScopeWithCommandQueue:cmdQueue];
    cmdCaptureScope.label = label.empty() ? @"Maply SceneRenderer" : [NSString stringWithUTF8String:label.c_str()];
    if (!captureMgr.defaultCaptureScope)
    {
        captureMgr.defaultCaptureScope = cmdCaptureScope;
    }

    init();

    // Calculation shaders
    workGroups.push_back(std::make_shared<WorkGroupMTL>(WorkGroup::Calculation, "Calc"));
    // Offscreen target render group
    workGroups.push_back(std::make_shared<WorkGroupMTL>(WorkGroup::Offscreen, "Offscreen"));
    // Middle one for weird stuff
    workGroups.push_back(std::make_shared<WorkGroupMTL>(WorkGroup::ReduceOps, "Reduce"));
    // Last workgroup is used for on screen rendering
    workGroups.push_back(std::make_shared<WorkGroupMTL>(WorkGroup::ScreenRender, "Screen"));

    setScale(inScale);
    setupInfo.mtlDevice = mtlDevice;
    for (unsigned int ii=0;ii<MaxViewWrap;ii++) {
        setupInfo.uniformBuff[ii] = setupInfo.heapManage.allocateBuffer(HeapManagerMTL::Drawable,sizeof(WhirlyKitShader::Uniforms));
        setupInfo.uniformBuff[ii].buffer.label = [NSString stringWithFormat:@"uniforms %d", ii];
    }
    setupInfo.lightingBuff = setupInfo.heapManage.allocateBuffer(HeapManagerMTL::Drawable,sizeof(WhirlyKitShader::Lighting));
    setupInfo.lightingBuff.buffer.label = @"lighting";
    releaseQueue = dispatch_queue_create("Maply release queue", DISPATCH_QUEUE_SERIAL);
}

SceneRendererMTL::~SceneRendererMTL()
{
}

SceneRendererMTL::Type SceneRendererMTL::getType()
{
    return RenderMetal;
}

const RenderSetupInfo *SceneRendererMTL::getRenderSetupInfo() const
{
    return &setupInfo;
}

void SceneRendererMTL::setView(View *newView)
{
    SceneRenderer::setView(newView);
}

void SceneRendererMTL::setScene(Scene *newScene)
{
    SceneRenderer::setScene(newScene);
    
    // Slots we need to refer to on the C++ side
    slotMap[a_maskNameID] = WhirlyKitShader::WKSVertexMaskAttribute;
    for (unsigned int ii=0;ii<WhirlyKitMaxMasks;ii++)
        slotMap[a_maskNameIDs[ii]] = WhirlyKitShader::WKSVertexMaskAttribute+ii;
}

bool SceneRendererMTL::setup(int sizeX,int sizeY,bool offscreen)
{
    // Set up a default render target
    RenderTargetMTLRef defaultTarget = RenderTargetMTLRef(new RenderTargetMTL(EmptyIdentity));
    defaultTarget->width = sizeX;
    defaultTarget->height = sizeY;
    defaultTarget->clearEveryFrame = true;
    if (offscreen)
    {
        setFramebufferSize(sizeX, sizeY);
        
        // Create the texture we'll use right here
        TextureMTLRef fbTexMTL = TextureMTLRef(new TextureMTL("Framebuffer Texture"));
        fbTexMTL->setWidth(sizeX);
        fbTexMTL->setHeight(sizeY);
        fbTexMTL->setIsEmptyTexture(true);
        fbTexMTL->setFormat(TexTypeUnsignedByte);
        fbTexMTL->createInRenderer(&setupInfo);
        framebufferTex = fbTexMTL;
        
        // And one for depth
        TextureMTLRef depthTexMTL = TextureMTLRef(new TextureMTL("Framebuffer Depth Texture"));
        depthTexMTL->setWidth(sizeX);
        depthTexMTL->setHeight(sizeY);
        depthTexMTL->setIsEmptyTexture(true);
        depthTexMTL->setFormat(TexTypeDepthFloat32);
        depthTexMTL->createInRenderer(&setupInfo);

        // Note: Should make this optional
        defaultTarget->blendEnable = offscreenBlendEnable;
        defaultTarget->setTargetTexture(fbTexMTL.get());
        defaultTarget->setTargetDepthTexture(depthTexMTL.get());
    } else {
        if (sizeX > 0 && sizeY > 0)
            defaultTarget->init(this,NULL,EmptyIdentity);
        defaultTarget->blendEnable = true;
    }
    renderTargets.push_back(defaultTarget);
    
    workGroups[WorkGroup::ScreenRender]->addRenderTarget(defaultTarget);
    
    return true;
}
    
void SceneRendererMTL::setClearColor(const RGBAColor &color)
{
    if (renderTargets.empty())
        return;
    
    auto defaultTarget = renderTargets.back();
    defaultTarget->setClearColor(color);
}

bool SceneRendererMTL::resize(int sizeX,int sizeY)
{
    // Don't want to deal with it for offscreen rendering
    if (framebufferTex)
        return false;
    
    setFramebufferSize(sizeX, sizeY);
    
    RenderTargetRef defaultTarget = renderTargets.back();
    defaultTarget->width = sizeX;
    defaultTarget->height = sizeY;
    defaultTarget->init(this, NULL, EmptyIdentity);
    
    return true;
}

void SceneRendererMTL::setupUniformBuffer(RendererFrameInfoMTL *frameInfo,int oi,id<MTLBlitCommandEncoder> bltEncode,CoordSystemDisplayAdapter *coordAdapter)
{
    const SceneRendererMTL *sceneRender = (SceneRendererMTL *)frameInfo->sceneRenderer;
    const auto *mapView = dynamic_cast<Maply::MapView*>(theView);
    const bool viewWrap = mapView && mapView->getWrap();
    const Point2f frameSize = frameInfo->sceneRenderer->getFramebufferSize();

    WhirlyKitShader::Uniforms uniforms;
    bzero(&uniforms,sizeof(uniforms));
    CopyIntoMtlFloat4x4Pair(uniforms.mvpMatrix,uniforms.mvpMatrixDiff,frameInfo->mvpMat4d);
    CopyIntoMtlFloat4x4(uniforms.mvpInvMatrix,frameInfo->mvpInvMat);
    CopyIntoMtlFloat4x4Pair(uniforms.mvMatrix,uniforms.mvMatrixDiff,frameInfo->viewAndModelMat4d);
    CopyIntoMtlFloat4x4(uniforms.mvNormalMatrix,frameInfo->viewModelNormalMat);
    CopyIntoMtlFloat4x4(uniforms.pMatrix,frameInfo->projMat);
    CopyIntoMtlFloat4x4(uniforms.offsetMatrix,frameInfo->offsetMatrices[oi]);
    CopyIntoMtlFloat4x4(uniforms.offsetInvMatrix,Matrix4d(frameInfo->offsetMatrices[oi].inverse()));
    CopyIntoMtlFloat3(uniforms.eyePos,frameInfo->eyePos);
    CopyIntoMtlFloat3(uniforms.eyeVec,frameInfo->eyeVec);
    CopyIntoMtlFloat2(uniforms.screenSizeInDisplayCoords,Point2f(frameInfo->screenSizeInDisplayCoords.x(),frameInfo->screenSizeInDisplayCoords.y()));
    CopyIntoMtlFloat2(uniforms.frameSize, frameSize);
    uniforms.offsetView = oi;
    uniforms.offsetViews = viewWrap ? frameInfo->offsetMatrices.size() : 0;
    uniforms.globeMode = !coordAdapter->isFlat();
    uniforms.isPanning = theView->getIsPanning();
    uniforms.isZooming = theView->getIsZooming();
    uniforms.isRotating = theView->getIsRotating();
    uniforms.isTilting = theView->getIsTilting();
    uniforms.isAnimating = theView->getIsAnimating();
    uniforms.userMotion = theView->getUserMotion();
    uniforms.didMove = theView->getHasMoved();
    uniforms.didZoom = theView->getHasZoomed();
    uniforms.didRotate = theView->getHasRotated();
    uniforms.didTilt = theView->getHasTilted();
    uniforms.frameCount = frameCount;
    uniforms.currentTime = frameInfo->currentTime - scene->getBaseTime();
    frameInfo->scene->copyZoomSlots(uniforms.zoomSlots);

    // resets each frame
    theView->setHasMoved(false);
    theView->setHasZoomed(false);
    theView->setHasRotated(false);
    theView->setHasTilted(false);

    // Copy this to a buffer and then blit that buffer into place
    // TODO: Try to reuse these
    auto buff = setupInfo.heapManage.allocateBuffer(HeapManagerMTL::HeapType::Drawable, &uniforms, sizeof(uniforms));
    [bltEncode copyFromBuffer:buff.buffer
                 sourceOffset:buff.offset
                     toBuffer:sceneRender->setupInfo.uniformBuff[oi].buffer
            destinationOffset:sceneRender->setupInfo.uniformBuff[oi].offset
                         size:sizeof(uniforms)];
}

void SceneRendererMTL::setupLightBuffer(SceneMTL *scene,RendererFrameInfoMTL *frameInfo,id<MTLBlitCommandEncoder> bltEncode)
{
    SceneRendererMTL *sceneRender = (SceneRendererMTL *)frameInfo->sceneRenderer;

    WhirlyKitShader::Lighting lighting;
    lighting.numLights = lights.size();
    for (unsigned int ii=0;ii<lighting.numLights;ii++)
    {
        DirectionalLight &dirLight = lights[ii];
        
        const Eigen::Vector3f dir = dirLight.getPos().normalized();
        const Eigen::Vector3f halfPlane = (dir + Eigen::Vector3f(0,0,1)).normalized();
        
        WhirlyKitShader::Light &light = lighting.lights[ii];
        CopyIntoMtlFloat3(light.direction,dir);
        CopyIntoMtlFloat3(light.halfPlane,halfPlane);
        CopyIntoMtlFloat4(light.ambient,dirLight.getAmbient());
        CopyIntoMtlFloat4(light.diffuse,dirLight.getDiffuse());
        CopyIntoMtlFloat4(light.specular,dirLight.getSpecular());
        light.viewDepend = dirLight.getViewDependent() ? 0.0f : 1.0f;
    }
    CopyIntoMtlFloat4(lighting.mat.ambient,defaultMat.getAmbient());
    CopyIntoMtlFloat4(lighting.mat.diffuse,defaultMat.getDiffuse());
    CopyIntoMtlFloat4(lighting.mat.specular,defaultMat.getSpecular());
    lighting.mat.specularExponent = defaultMat.getSpecularExponent();
    
    // Copy this to a buffer and then blit that buffer into place
    // TODO: Try to reuse these
    auto buff = setupInfo.heapManage.allocateBuffer(HeapManagerMTL::HeapType::Drawable, &lighting, sizeof(lighting));
    [bltEncode copyFromBuffer:buff.buffer sourceOffset:buff.offset toBuffer:sceneRender->setupInfo.lightingBuff.buffer destinationOffset:sceneRender->setupInfo.lightingBuff.offset size:sizeof(lighting)];
}
    
void SceneRendererMTL::setupDrawStateA(WhirlyKitShader::UniformDrawStateA &drawState)
{
    // That was anti-climactic
    bzero(&drawState,sizeof(drawState));
    drawState.zoomSlot = -1;
}
    
MTLRenderPipelineDescriptor *SceneRendererMTL::defaultRenderPipelineState(SceneRendererMTL *sceneRender,ProgramMTL *program,RenderTargetMTL *renderTarget)
{
    MTLRenderPipelineDescriptor *renderDesc = [[MTLRenderPipelineDescriptor alloc] init];
    renderDesc.vertexFunction = program->vertFunc;
    renderDesc.fragmentFunction = program->fragFunc;
    
    renderDesc.colorAttachments[0].pixelFormat = renderTarget->getPixelFormat();
    if (renderTarget->getRenderPassDesc().depthAttachment.texture)
        renderDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    
    if (renderTarget->blendEnable) {
        renderDesc.colorAttachments[0].blendingEnabled = true;
        renderDesc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        renderDesc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        renderDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        renderDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        renderDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        renderDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    } else {
        renderDesc.colorAttachments[0].blendingEnabled = false;
    }
    
    if (@available(iOS 13.0, *)) {
        if (indirectRender)
            renderDesc.supportIndirectCommandBuffers = true;
    }
    
    return renderDesc;
}
    
void SceneRendererMTL::addSnapshotDelegate(NSObject<WhirlyKitSnapshot> *newDelegate)
{
    snapshotDelegates.push_back(newDelegate);
}

void SceneRendererMTL::removeSnapshotDelegate(NSObject<WhirlyKitSnapshot> *oldDelegate)
{
    snapshotDelegates.erase(std::remove(snapshotDelegates.begin(), snapshotDelegates.end(), oldDelegate), snapshotDelegates.end());
}

void SceneRendererMTL::updateWorkGroups(RendererFrameInfo *inFrameInfo,int numViewOffsets)
{
    RendererFrameInfoMTL *frameInfo = (RendererFrameInfoMTL *)inFrameInfo;
    RenderTeardownInfoMTLRef teardownInfoMTL = std::dynamic_pointer_cast<RenderTeardownInfoMTL>(teardownInfo);
    SceneRenderer::updateWorkGroups(frameInfo,numViewOffsets);
    
    if (!indirectRender)
        return;
    
    //bool viewOffsetsChanged = numViewOffsets != lastNumViewOffsets;
    lastNumViewOffsets = numViewOffsets;
    
    // Build the indirect command buffers if they're available
    if (@available(iOS 13.0, *)) {
        const bool isCapturing = [MTLCaptureManager sharedCaptureManager].isCapturing;

        int workGroupIndex = -1;
        for (const auto &workGroup : workGroups) {
            ++workGroupIndex;
            int targetContainerIndex = -1;
            for (const auto &targetContainer : workGroup->renderTargetContainers) {
                ++targetContainerIndex;
                if (targetContainer->drawables.empty() && !targetContainer->modified)
                    continue;
                RenderTargetContainerMTLRef targetContainerMTL = std::dynamic_pointer_cast<RenderTargetContainerMTL>(targetContainer);
                teardownInfoMTL->releaseDrawGroups(this,targetContainerMTL->drawGroups);
                targetContainerMTL->drawGroups.clear();

                RenderTargetMTLRef renderTarget;
                if (!targetContainer->renderTarget) {
                    // Need some sort of render target even if we're not really rendering
                    renderTarget = std::dynamic_pointer_cast<RenderTargetMTL>(renderTargets.back());
                } else {
                    renderTarget = std::dynamic_pointer_cast<RenderTargetMTL>(targetContainer->renderTarget);
                }
                if (!renderTarget)
                {
                    continue;
                }

                // Sort the drawables into draw groups by Z buffer usage
                DrawGroupMTLRef drawGroup;
                bool dgZBufferRead = false, dgZBufferWrite = false;
                for (const auto &draw : targetContainer->drawables) {
                    DrawableMTL *drawMTL = dynamic_cast<DrawableMTL *>(draw.get());
                    if (!drawMTL) {
                        wkLogLevel(Error, "SceneRendererMTL: Invalid drawable.  Skipping.");
                        continue;
                    }

                    // Off screen render targets don't like z buffering
                    bool zBufferWrite = false;
                    bool zBufferRead = false;
                    if (renderTarget->getTex() == nil) {
                        // The drawable itself gets a say
                        zBufferRead = drawMTL->getRequestZBuffer();
                        zBufferWrite = drawMTL->getWriteZbuffer();
                    }

                    // If this isn't compatible with the draw group, create a new one
                    if (!drawGroup || zBufferRead != dgZBufferRead || zBufferWrite != dgZBufferWrite) {
                        // It's not, so we need to make a new draw group
                        drawGroup = std::make_shared<DrawGroupMTL>();

                        // Depth stencil, which goes in the command encoder later
                        MTLDepthStencilDescriptor *depthDesc = [[MTLDepthStencilDescriptor alloc] init];
                        if (zBufferRead)
                            depthDesc.depthCompareFunction = MTLCompareFunctionLess;
                        else
                            depthDesc.depthCompareFunction = MTLCompareFunctionAlways;
                        depthDesc.depthWriteEnabled = zBufferWrite;
                        
                        drawGroup->depthStencil = [setupInfo.mtlDevice newDepthStencilStateWithDescriptor:depthDesc];
                        
                        targetContainerMTL->drawGroups.push_back(drawGroup);
                        
                        dgZBufferRead = zBufferRead;
                        dgZBufferWrite = zBufferWrite;
                    }
                    drawGroup->drawables.push_back(draw);
                }

                // Command buffer description should be the same
                MTLIndirectCommandBufferDescriptor *cmdBuffDesc = [[MTLIndirectCommandBufferDescriptor alloc] init];
                cmdBuffDesc.commandTypes = MTLIndirectCommandTypeDraw | MTLIndirectCommandTypeDrawIndexed;
                cmdBuffDesc.inheritBuffers = false;
                if (@available(iOS 13.0, *)) {
                    cmdBuffDesc.inheritPipelineState = false;
                }
                // TODO: Should query the drawables to get this maximum number
                cmdBuffDesc.maxVertexBufferBindCount = WhirlyKitShader::WKSVertMaxBuffer;
                cmdBuffDesc.maxFragmentBufferBindCount = WhirlyKitShader::WKSFragMaxBuffer;

                // Build up indirect buffers for each draw group
                int drawGroupIndex = -1;
                for (const auto &drawGroup : targetContainerMTL->drawGroups) {
                    ++drawGroupIndex;
                    int curCommand = 0;
                    drawGroup->numCommands = numViewOffsets*drawGroup->drawables.size();
                    drawGroup->indCmdBuff = [setupInfo.mtlDevice newIndirectCommandBufferWithDescriptor:cmdBuffDesc maxCommandCount:drawGroup->numCommands options:0];
                    if (!drawGroup->indCmdBuff) {
                        wkLogLevel(Error, "SceneRendererMTL: Failed to allocate indirect command buffer.  Skipping.");
                        continue;
                    }

                    if (isCapturing)
                    {
                        drawGroup->indCmdBuff.label = [NSString stringWithFormat:@"Workgroup=%d \"%s\" Target=%d Group=%d",
                                                       workGroupIndex, workGroup->name.c_str(), targetContainerIndex, drawGroupIndex];
                    }

                    // Just run the calculation portion
                    if (workGroup->groupType == WorkGroup::Calculation) {
                        // Work through the drawables
                        for (const auto &draw : targetContainer->drawables) {
                            DrawableMTL *drawMTL = dynamic_cast<DrawableMTL *>(draw.get());
                            if (!drawMTL) {
                                wkLogLevel(Error, "SceneRendererMTL: Invalid drawable.  Skipping.");
                                continue;
                            }
                            SimpleIdentity calcProgID = drawMTL->getCalculationProgram();
                            
                            // Figure out the program to use for drawing
                            if (calcProgID == EmptyIdentity || calcProgID == Program::NoProgramID)
                                continue;
                            ProgramMTL *calcProgram = (ProgramMTL *)scene->getProgram(calcProgID);
                            if (!calcProgram) {
                                wkLogLevel(Error, "SceneRendererMTL: Invalid calculation program for drawable.  Skipping.");
                                continue;
                            }
                            
                            id<MTLIndirectRenderCommand> cmdEncode = [drawGroup->indCmdBuff indirectRenderCommandAtIndex:curCommand++];
                            drawMTL->encodeIndirectCalculate(cmdEncode,this,scene,renderTarget.get());
                            drawMTL->enumerateResources(frameInfo, drawGroup->resources);
                        }
                    } else {
                        // Work through the drawables
                        for (const auto &draw : drawGroup->drawables) {
                            DrawableMTL *drawMTL = dynamic_cast<DrawableMTL *>(draw.get());
                            if (!drawMTL) {
                                wkLogLevel(Error, "SceneRendererMTL: Invalid drawable");
                                continue;
                            }
                            if (drawMTL->getProgram() == Program::NoProgramID) {
                                continue;
                            }
                            
                            // Draw once for each matrix, unless the drawable uses
                            // clip coordinates and doesn't need to be transformed.
                            const int numDraws = drawMTL->getClipCoords() ? 1 : numViewOffsets;
                            for (int oi=0;oi<numDraws;oi++) {
                                id<MTLIndirectRenderCommand> cmdEncode = [drawGroup->indCmdBuff indirectRenderCommandAtIndex:curCommand++];
                                drawMTL->encodeIndirect(cmdEncode,oi,this,scene,renderTarget.get());
                            }
                            drawMTL->enumerateResources(frameInfo, drawGroup->resources);
                        }
                    }
                }
                
                targetContainer->modified = false;
            }
        }
    }
}

RendererFrameInfoMTLRef SceneRendererMTL::makeFrameInfo()
{
    if (!theView || !scene)
    {
        return RendererFrameInfoMTLRef();
    }

    // Get the model and view matrices
    const Eigen::Matrix4d modelTrans4d = theView->calcModelMatrix();
    const Eigen::Matrix4d viewTrans4d = theView->calcViewMatrix();
    const Eigen::Matrix4f modelTrans = Matrix4dToMatrix4f(modelTrans4d);
    const Eigen::Matrix4f viewTrans = Matrix4dToMatrix4f(viewTrans4d);
    
    // Set up a projection matrix
    const Point2f frameSize = getFramebufferSize();
    const Eigen::Matrix4d projMat4d = theView->calcProjectionMatrix(frameSize,0.0);

    const Eigen::Matrix4d modelAndViewMat4d = viewTrans4d * modelTrans4d;
    const Eigen::Matrix4d pvMat4d = projMat4d * viewTrans4d;
    const Eigen::Matrix4d modelAndViewNormalMat4d = modelAndViewMat4d.inverse().transpose();
    const Eigen::Matrix4d mvpMat4d = projMat4d * modelAndViewMat4d;

    const Eigen::Matrix4f projMat = Matrix4dToMatrix4f(projMat4d);
    const Eigen::Matrix4f modelAndViewMat = Matrix4dToMatrix4f(modelAndViewMat4d);
    const Eigen::Matrix4f mvpMat = Matrix4dToMatrix4f(mvpMat4d);
    const Eigen::Matrix4f mvpNormalMat4f = Matrix4dToMatrix4f(mvpMat4d.inverse().transpose());
    const Eigen::Matrix4f modelAndViewNormalMat = Matrix4dToMatrix4f(modelAndViewNormalMat4d);

    auto frameInfo = std::make_shared<RendererFrameInfoMTL>();

    frameInfo->sceneRenderer = this;
    frameInfo->theView = theView;
    frameInfo->viewTrans = viewTrans;
    frameInfo->viewTrans4d = viewTrans4d;
    frameInfo->modelTrans = modelTrans;
    frameInfo->modelTrans4d = modelTrans4d;
    frameInfo->scene = scene;
    frameInfo->frameLen = 1.0 / 60.0;
    frameInfo->currentTime = scene->getCurrentTime();
    frameInfo->projMat = projMat;
    frameInfo->projMat4d = projMat4d;
    frameInfo->mvpMat = mvpMat;
    frameInfo->mvpMat4d = mvpMat4d;
    frameInfo->mvpInvMat = mvpMat.inverse();
    frameInfo->mvpNormalMat = mvpNormalMat4f;
    frameInfo->viewModelNormalMat = modelAndViewNormalMat;
    frameInfo->viewAndModelMat = modelAndViewMat;
    frameInfo->viewAndModelMat4d = modelAndViewMat4d;
    frameInfo->pvMat = Matrix4dToMatrix4f(pvMat4d);
    frameInfo->pvMat4d = pvMat4d;
    frameInfo->screenSizeInDisplayCoords = theView->screenSizeInDisplayCoords(frameSize);
    frameInfo->lights = &lights;
    frameInfo->renderTarget = nullptr;

    return frameInfo;
}

void SceneRendererMTL::render(TimeInterval duration, RenderInfo *renderInfo)
{
    if (!scene)
        return;
    SceneMTL *sceneMTL = (SceneMTL *)scene;
 
    auto renderPassDesc = renderInfo ? ((RenderInfoMTL*)renderInfo)->renderPassDesc : nil;
    const id<SceneRendererMTLDrawableGetter> drawGetter = renderInfo ? ((RenderInfoMTL*)renderInfo)->drawGetter : nil;

    frameCount++;
    
    const TimeInterval now = scene->getCurrentTime();

    teardownInfo.reset();

    const Point2f frameSize = getFramebufferSize();
    if (frameSize.x() <= 0 || frameSize.y() <= 0)
    {
        // Process the scene even if the window isn't up
        processScene(now);
        return;
    }
    
    lastDraw = now;
    
    if (perfInterval > 0)
        perfTimer.startTiming("Render Frame");
    
    if (perfInterval > 0)
        perfTimer.startTiming("Render Setup");

    // See if we're dealing with a globe or map view
    Maply::MapView *mapView = dynamic_cast<Maply::MapView *>(theView);
    float overlapMarginX = 0.0;
    if (mapView) {
        overlapMarginX = scene->getOverlapMargin();
    }

    if (!theView) {
        return;
    }
    
    // Get the model and view matrices
    Eigen::Matrix4d modelTrans4d = theView->calcModelMatrix();
    Eigen::Matrix4d viewTrans4d = theView->calcViewMatrix();
    Eigen::Matrix4f modelTrans = Matrix4dToMatrix4f(modelTrans4d);
    
    // Set up a projection matrix
    Eigen::Matrix4d projMat4d = theView->calcProjectionMatrix(frameSize,0.0);

    Eigen::Matrix4d modelAndViewMat4d = viewTrans4d * modelTrans4d;
    Eigen::Matrix4d pvMat4d = projMat4d * viewTrans4d;
    Eigen::Matrix4d modelAndViewNormalMat4d = modelAndViewMat4d.inverse().transpose();
    Eigen::Matrix4d mvpMat4d = projMat4d * modelAndViewMat4d;

    Eigen::Matrix4f modelAndViewMat = Matrix4dToMatrix4f(modelAndViewMat4d);
    Eigen::Matrix4f mvpNormalMat4f = Matrix4dToMatrix4f(mvpMat4d.inverse().transpose());
    Eigen::Matrix4f modelAndViewNormalMat = Matrix4dToMatrix4f(modelAndViewNormalMat4d);

    if (perfInterval > 0)
        perfTimer.stopTiming("Render Setup");

    RenderTargetMTL *defaultTarget = (RenderTargetMTL *)renderTargets.back().get();
    if (renderPassDesc)
        defaultTarget->setRenderPassDesc(renderPassDesc);
    auto clearColor = defaultTarget->clearColor;
    renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(clearColor[0],clearColor[1],clearColor[2],clearColor[3]);

    // Send the command buffer and encoders
    id<MTLDevice> mtlDevice = setupInfo.mtlDevice;

    bool isCapturing = false;
#if CAPTURE_FRAME_START && CAPTURE_FRAME_END >= CAPTURE_FRAME_START
    if (@available(iOS 13.0, *))
    {
        // "When you capture a frame programmatically, you can capture Metal commands that span multiple
        //  frames by using a custom capture scope. For example, by calling begin() at the start of frame
        //  1 and end() after frame 3, the trace will contain command data from all the buffers that were
        //  committed in the three frames."
        // https://developer.apple.com/documentation/metal/debugging_tools/capturing_gpu_command_data_programmatically
        MTLCaptureManager *captureMgr = [MTLCaptureManager sharedCaptureManager];
        if (frameCount == CAPTURE_FRAME_START && !captureMgr.isCapturing &&
            [captureMgr supportsDestination:MTLCaptureDestination::MTLCaptureDestinationDeveloperTools])
        {
            MTLCaptureDescriptor *desc = [MTLCaptureDescriptor new];
            desc.captureObject = cmdCaptureScope;
            desc.destination = MTLCaptureDestination::MTLCaptureDestinationDeveloperTools;
            NSError *err = nil;
            if ([captureMgr startCaptureWithDescriptor:desc error:&err])
            {
                [cmdCaptureScope beginScope];
            }
            else if (err)
            {
                NSLog(@"Failed to start Metal capture: %@", err);
            }
        }
        isCapturing = captureMgr.isCapturing;
        if (isCapturing)
        {
            wkLog("Capturing frame %d", frameCount);
        }
    }
#endif

    const auto frameInfoRef = makeFrameInfo();
    auto &baseFrameInfo = *frameInfoRef;
    baseFrameInfo.frameLen = duration;
    baseFrameInfo.currentTime = now;
    theView->getOffsetMatrices(baseFrameInfo.offsetMatrices, frameSize, overlapMarginX);

    lastFrameInfo = frameInfoRef;

    // We need a reverse of the eye vector in model space
    // We'll use this to determine what's pointed away
    Eigen::Matrix4f modelTransInv = modelTrans.inverse();
    Vector4f eyeVec4 = modelTransInv * Vector4f(0,0,1,0);
    Vector3f eyeVec3(eyeVec4.x(),eyeVec4.y(),eyeVec4.z());
    baseFrameInfo.eyeVec = eyeVec3;
    Eigen::Matrix4f fullTransInv = modelAndViewMat.inverse();
    Vector4f fullEyeVec4 = fullTransInv * Vector4f(0,0,1,0);
    Vector3f fullEyeVec3(fullEyeVec4.x(),fullEyeVec4.y(),fullEyeVec4.z());
    baseFrameInfo.fullEyeVec = -fullEyeVec3;
    Matrix4d modelTransInv4d = modelTrans4d.inverse();
    Vector4d eyeVec4d = modelTransInv4d * Vector4d(0,0,1,0.0);
    baseFrameInfo.heightAboveSurface = theView->heightAboveSurface();
    const bool isFlat = scene->getCoordAdapter()->isFlat();
    if (isFlat) {
        Vector4d eyePos4d = modelTransInv4d * Vector4d(0.0,0.0,0.0,1.0);
        eyePos4d /= eyePos4d.w();
        baseFrameInfo.eyePos = Vector3d(eyePos4d.x(),eyePos4d.y(),eyePos4d.z());
    } else
        baseFrameInfo.eyePos = Vector3d(eyeVec4d.x(),eyeVec4d.y(),eyeVec4d.z()) * (1.0+baseFrameInfo.heightAboveSurface);
    
    if (perfInterval > 0)
        perfTimer.startTiming("Scene preprocessing");
    
    const auto frameTeardownInfo = std::make_shared<RenderTeardownInfoMTL>();
    teardownInfo = frameTeardownInfo;
    
    // Run the preprocess for the changes.  These modify things the active models need.
    int numPreProcessChanges = preProcessScene(now);;
    
    if (perfInterval > 0)
        perfTimer.addCount("Preprocess Changes", numPreProcessChanges);
    
    if (perfInterval > 0)
        perfTimer.stopTiming("Scene preprocessing");
    
    if (perfInterval > 0)
        perfTimer.startTiming("Active Model Runs");
    
    // Let the active models to their thing
    // That thing had better not take too long
    auto activeModels = scene->getActiveModels();
    for (auto activeModel : activeModels) {
        activeModel->updateForFrame(&baseFrameInfo);
    }
    if (perfInterval > 0)
        perfTimer.addCount("Active Models", (int)activeModels.size());
    
    if (perfInterval > 0)
        perfTimer.stopTiming("Active Model Runs");
    
    if (perfInterval > 0)
        perfTimer.addCount("Scene changes", scene->getNumChangeRequests());
    
    if (perfInterval > 0)
        perfTimer.startTiming("Scene processing");
    
    // Merge any outstanding changes into the scenegraph
    processScene(now);
    
    // Update our work groups accordingly
    updateWorkGroups(&baseFrameInfo,baseFrameInfo.offsetMatrices.size());
    
    if (perfInterval > 0)
        perfTimer.stopTiming("Scene processing");
    
    // Work through the available offset matrices (only 1 if we're not wrapping)
    const Matrix4dVector &offsetMats = baseFrameInfo.offsetMatrices;
    std::vector<RendererFrameInfoMTL> offFrameInfos;
    // Turn these drawables in to a vector
    std::vector<Matrix4d> mvpMats;
    std::vector<Matrix4d> mvpInvMats;
    std::vector<Matrix4f> mvpMats4f;
    std::vector<Matrix4f> mvpInvMats4f;
    mvpMats.resize(offsetMats.size());
    mvpInvMats.resize(offsetMats.size());
    mvpMats4f.resize(offsetMats.size());
    mvpInvMats4f.resize(offsetMats.size());
    for (unsigned int off=0;off<offsetMats.size();off++)
    {
        RendererFrameInfoMTL offFrameInfo(baseFrameInfo);
        // Tweak with the appropriate offset matrix
        modelAndViewMat4d = viewTrans4d * offsetMats[off] * modelTrans4d;
        pvMat4d = projMat4d * viewTrans4d * offsetMats[off];
        modelAndViewMat = Matrix4dToMatrix4f(modelAndViewMat4d);
        mvpMats[off] = projMat4d * modelAndViewMat4d;
        mvpInvMats[off] = (Eigen::Matrix4d)mvpMats[off].inverse();
        mvpMats4f[off] = Matrix4dToMatrix4f(mvpMats[off]);
        mvpInvMats4f[off] = Matrix4dToMatrix4f(mvpInvMats[off]);
        modelAndViewNormalMat4d = modelAndViewMat4d.inverse().transpose();
        modelAndViewNormalMat = Matrix4dToMatrix4f(modelAndViewNormalMat4d);
        offFrameInfo.mvpMat = mvpMats4f[off];
        offFrameInfo.mvpMat4d = mvpMats[off];
        offFrameInfo.mvpInvMat = mvpInvMats4f[off];
        mvpNormalMat4f = Matrix4dToMatrix4f(mvpMats[off].inverse().transpose());
        offFrameInfo.mvpNormalMat = mvpNormalMat4f;
        offFrameInfo.viewModelNormalMat = modelAndViewNormalMat;
        offFrameInfo.viewAndModelMat4d = modelAndViewMat4d;
        offFrameInfo.viewAndModelMat = modelAndViewMat;
        Matrix4f pvMat4f = Matrix4dToMatrix4f(pvMat4d);
        offFrameInfo.pvMat = pvMat4f;
        offFrameInfo.pvMat4d = pvMat4d;
        offFrameInfos.push_back(offFrameInfo);
    }
    
    // Keeps us from stomping on the last frame's uniforms
    if (renderEvent == nil && drawGetter)
        renderEvent = [mtlDevice newEvent];
    
    // Workgroups force us to draw things in order
    int workGroupIndex = -1;
    for (auto &workGroup : workGroups) {
        ++workGroupIndex;

        if (perfInterval > 0)
            perfTimer.startTiming("Work Group: " + workGroup->name);

        int targetContainerIndex = -1;
        for (auto &targetContainer : workGroup->renderTargetContainers) {
            ++targetContainerIndex;

            // We'll skip empty render targets, except for the default one which we need at least to clear
            // Otherwise we get stuck on the last render, rather than a blank screen
            if (targetContainer->drawables.empty() &&
                !(targetContainer && targetContainer->renderTarget))
                continue;
            RenderTargetContainerMTL *targetContainerMTL = (RenderTargetContainerMTL *)targetContainer.get();
            
            RenderTargetMTLRef renderTarget;
            if (!targetContainer->renderTarget) {
                // Need some sort of render target even if we're not really rendering
                renderTarget = std::dynamic_pointer_cast<RenderTargetMTL>(renderTargets.back());
            } else {
                renderTarget = std::dynamic_pointer_cast<RenderTargetMTL>(targetContainer->renderTarget);
            }

            // Render pass descriptor might change from frame to frame if we're clearing sporadically
            renderTarget->makeRenderPassDesc();
            baseFrameInfo.renderTarget = renderTarget.get();

            // Each render target needs its own buffer and command queue
            if (lastCmdBuff) {
                // Otherwise we'll commit twice
                if (drawGetter)
                    [lastCmdBuff commit];
                lastCmdBuff = nil;
            }
            id<MTLCommandBuffer> cmdBuff = [cmdQueue commandBuffer];

            // Keeps us from stomping on the last frame's uniforms
            if (lastRenderNo > 0 && drawGetter)
                [cmdBuff encodeWaitForEvent:renderEvent value:lastRenderNo];

            // Ask all the drawables to set themselves up.  Mostly memory stuff.
            id<MTLFence> preProcessFence = [mtlDevice newFence];
            id<MTLBlitCommandEncoder> bltEncode = [cmdBuff blitCommandEncoder];

            if (isCapturing)
            {
                preProcessFence.label = bltEncode.label =
                    [NSString stringWithFormat:@"Workgroup=%d \"%s\" Target=%d Preprocessing",
                        workGroupIndex, workGroup->name.c_str(), targetContainerIndex];
            }

            // Resources used by this container
            ResourceRefsMTL resources;

            if (indirectRender) {
                // Run pre-process on the draw groups
                for (const auto &drawGroup : targetContainerMTL->drawGroups) {
                    if (drawGroup->numCommands > 0) {
                        bool resourcesChanged = false;
                        for (auto &draw : drawGroup->drawables) {
                            DrawableMTL *drawMTL = dynamic_cast<DrawableMTL *>(draw.get());
                            if (!drawMTL) {
                                wkLogLevel(Error, "SceneRendererMTL: Invalid drawable.  Skipping.");
                                continue;
                            }
                            drawMTL->runTweakers(&baseFrameInfo);
                            if (drawMTL->preProcess(this, cmdBuff, bltEncode, sceneMTL))
                                resourcesChanged = true;
                        }
                        // At least one of the drawables is pointing at different resources, so we need to redo this
                        if (resourcesChanged) {
                            drawGroup->resources.clear();
                            for (auto &draw : drawGroup->drawables) {
                                if (const auto drawMTL = dynamic_cast<DrawableMTL *>(draw.get())) {
                                    drawMTL->enumerateResources(&baseFrameInfo, drawGroup->resources);
                                }
                            }
                        }
                        resources.addResources(drawGroup->resources);
                    }
                }
            } else {
                // Run pre-process ahead of time
                for (const auto &draw : targetContainer->drawables) {
                    if (const auto drawMTL = dynamic_cast<DrawableMTL *>(draw.get())) {
                        drawMTL->runTweakers(&baseFrameInfo);
                        drawMTL->preProcess(this, cmdBuff, bltEncode, sceneMTL);
                        drawMTL->enumerateResources(&baseFrameInfo, resources);
                    }
                }
            }

            // TODO: Just set these up once and copy it into position
            setupLightBuffer(sceneMTL,&baseFrameInfo,bltEncode);
            for (unsigned oi=0;oi<offFrameInfos.size();oi++) {
                setupUniformBuffer(&offFrameInfos[oi],oi,bltEncode,scene->getCoordAdapter());
            }
            [bltEncode updateFence:preProcessFence];
            [bltEncode endEncoding];
            
            // If we're forcing a mipmap calculation, then we're just going to use this render target once
            // If not, then we run some program over it multiple times
            // TODO: Make the reduce operation more explicit
            int numLevels = renderTarget->numLevels();
            if (renderTarget->mipmapType != RenderTargetMipmapNone)
                numLevels = 1;

            for (unsigned int level=0;level<numLevels;level++) {
                // TODO: Pass the level into the draw call
                //       Also do something about the offset matrices
                // Set up the encoder
                id<MTLRenderCommandEncoder> cmdEncode = nil;
                if (renderTarget->getTex() == nil) {
                    // This happens if the dev wants an instantaneous render
                    if (!renderPassDesc)
                        renderPassDesc = renderTarget->getRenderPassDesc(level);

                    baseFrameInfo.renderPassDesc = renderPassDesc;
                } else {
                    baseFrameInfo.renderPassDesc = renderTarget->getRenderPassDesc(level);
                }
                cmdEncode = [cmdBuff renderCommandEncoderWithDescriptor:baseFrameInfo.renderPassDesc];
                if (isCapturing)
                {
                    cmdEncode.label = [NSString stringWithFormat:@"Workgroup=%d \"%s\" Target=%d Level=%d",
                                       workGroupIndex, workGroup->name.c_str(), targetContainerIndex, level];
                }

                // Uncomment to draw wireframes for troubleshooting
                //[cmdEncode setTriangleFillMode:MTLTriangleFillModeLines];

                [cmdEncode waitForFence:preProcessFence beforeStages:MTLRenderStageVertex];

                resources.use(cmdEncode);

                if (indirectRender) {
                    if (@available(iOS 12.0, *)) {
                        if (isCapturing) {
                            [cmdEncode pushDebugGroup:@"Indirect"];
                        }
                        // Front-face culling on by default for globes
                        // Note: Would like to not set this every time
                        if (!isFlat) {
                            [cmdEncode setCullMode:MTLCullModeFront];
                        }
                        int drawGroupIndex = -1;
                        for (const auto &drawGroup : targetContainerMTL->drawGroups) {
                            ++drawGroupIndex;
                            if (drawGroup->numCommands > 0) {
                                if (isCapturing) {
                                    [cmdEncode pushDebugGroup:[NSString stringWithFormat:@"DrawGroup%d", drawGroupIndex]];
                                }
                                [cmdEncode setDepthStencilState:drawGroup->depthStencil];
                                [cmdEncode executeCommandsInBuffer:drawGroup->indCmdBuff withRange:NSMakeRange(0,drawGroup->numCommands)];
                                if (isCapturing) {
                                    [cmdEncode popDebugGroup];
                                }
                            }
                        }
                        if (isCapturing) {
                            [cmdEncode popDebugGroup];
                        }
                    }
                } else {
                    // Just run the calculation portion
                    if (workGroup->groupType == WorkGroup::Calculation) {
                        if (isCapturing) {
                            [cmdEncode pushDebugGroup:@"Calculation"];
                        }
                        // Work through the drawables
                        for (const auto &draw : targetContainer->drawables) {
                            DrawableMTL *drawMTL = dynamic_cast<DrawableMTL *>(draw.get());
                            if (!drawMTL) {
                                wkLogLevel(Error, "SceneRendererMTL: Invalid drawable.  Skipping.");
                                continue;
                            }
                            const SimpleIdentity calcProgID = drawMTL->getCalculationProgram();
                            
                            // Figure out the program to use for drawing
                            if (calcProgID == EmptyIdentity || calcProgID == Program::NoProgramID)
                                continue;

                            ProgramMTL *calcProgram = (ProgramMTL *)scene->getProgram(calcProgID);
                            if (!calcProgram) {
                                wkLogLevel(Error, "SceneRendererMTL: Invalid calculation program for drawable.  Skipping.");
                                continue;
                            }
                            baseFrameInfo.program = calcProgram;
                            
                            // Tweakers probably not necessary, but who knows
                            draw->runTweakers(&baseFrameInfo);
                            
                            // Run the calculation phase
                            drawMTL->encodeDirectCalculate(&baseFrameInfo,cmdEncode,scene);
                        }
                    } else {
                        if (isCapturing) {
                            [cmdEncode pushDebugGroup:@"Direct"];
                        }

                        // Keep track of state changes for z buffer state
                        bool firstDepthState = true;
                        bool zBufferWrite = (zBufferMode == zBufferOn);
                        bool zBufferRead = (zBufferMode == zBufferOn);

                        bool lastZBufferWrite = zBufferWrite;
                        bool lastZBufferRead = zBufferRead;

                        // Front-face culling on by default for globes
                        // Note: Would like to not set this every time
                        if (!isFlat) {
                            [cmdEncode setCullMode:MTLCullModeFront];
                        }

                        // Work through the drawables
                        for (const auto &draw : targetContainer->drawables) {
                            auto drawMTL = std::dynamic_pointer_cast<DrawableMTL>(draw);
                            if (!drawMTL) {
                                wkLogLevel(Error, "SceneRendererMTL: Invalid drawable.  Skipping.");
                                continue;
                            }

                            // Figure out the program to use for drawing
                            if (drawMTL->getProgram() == Program::NoProgramID &&
                                drawMTL->getCalculationProgram() == Program::NoProgramID) {
                                continue;
                            }
                            ProgramMTL *program = (ProgramMTL *)scene->getProgram(drawMTL->getProgram());
                            if (!program) {
                                program = (ProgramMTL *)scene->getProgram(drawMTL->getCalculationProgram());
                                if (!program) {
                                    wkLogLevel(Error, "SceneRendererMTL: Drawable without Program");
                                    continue;
                                }
                            }

                            // For a reduce operation, we want to draw into the first level of the render
                            //  target texture and then run the reduce over the rest of those levels
                            if (level > 0 && program->getReduceMode() == Program::None)
                                continue;

                            // For this mode we turn the z buffer off until we get a request to turn it on
                            zBufferRead = drawMTL->getRequestZBuffer();
                            
                            // If we're drawing lines or points we don't want to update the z buffer
                            zBufferWrite = drawMTL->getWriteZbuffer();
                            
                            // Off screen render targets don't like z buffering
                            if (renderTarget->getTex() != nil) {
                                zBufferRead = false;
                                zBufferWrite = false;
                            }
                            
                            // TODO: Optimize this a bit
                            if (firstDepthState ||
                                (zBufferRead != lastZBufferRead) ||
                                (zBufferWrite != lastZBufferWrite)) {
                                
                                MTLDepthStencilDescriptor *depthDesc = [[MTLDepthStencilDescriptor alloc] init];
                                if (zBufferRead)
                                    depthDesc.depthCompareFunction = MTLCompareFunctionLess;
                                else
                                    depthDesc.depthCompareFunction = MTLCompareFunctionAlways;
                                depthDesc.depthWriteEnabled = zBufferWrite;
                                
                                lastZBufferRead = zBufferRead;
                                lastZBufferWrite = zBufferWrite;
                                
                                id<MTLDepthStencilState> depthStencil = [mtlDevice newDepthStencilStateWithDescriptor:depthDesc];
                                
                                [cmdEncode setDepthStencilState:depthStencil];
                                firstDepthState = false;
                            }

                            // Draw once for each matrix, unless the drawable uses
                            // clip coordinates and doesn't need to be transformed.
                            const size_t numDraws = drawMTL->getClipCoords() ? 1 : offFrameInfos.size();
                            for (size_t off=0;off<numDraws;off++) {
                                baseFrameInfo.program = program;

                                // "Draw" using the given program
                                drawMTL->encodeDirect(&baseFrameInfo,off,cmdEncode,scene);
                            }
                        }
                    }
                }

                [cmdEncode endEncoding];
            }

            // Some render targets like to do extra work on their images
            renderTarget->addPostProcessing(mtlDevice,cmdBuff);

            // Main screen has to be committed
            if (drawGetter != nil && workGroup->groupType == WorkGroup::ScreenRender) {
                id<CAMetalDrawable> drawable = [drawGetter getDrawable];
                [cmdBuff presentDrawable:drawable];
            }

            // Capture shutdown signal in case `this` is destroyed before the blocks below execute.
            // This isn't 100% because we could still be destroyed while the blocks are executing,
            // unless we can be guaranteed that we're always destroyed on the main queue?
            // We might need `std::enable_shared_from_this` here so that we can keep `this` alive
            // within the blocks we create here.
            const auto shuttingDown = this->_isShuttingDown;

            // This particular target may want a snapshot
            [cmdBuff addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull) {
                if (*shuttingDown)
                    return;

                // TODO: Sort these into the render targets
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (*shuttingDown)
                        return;

                    // Look for the snapshot delegate that wants this render target
                    for (auto snapshotDelegate : snapshotDelegates) {
                        if (*shuttingDown) {
                            break;
                        }
                        
                        if (![snapshotDelegate needSnapshot:now])
                            continue;
                        
                        if (renderTarget->getId() != [snapshotDelegate renderTargetID]) {
                            continue;
                        }
                        
                        [snapshotDelegate snapshotData:nil];
                    }
                    
//                    targetContainerMTL->lastRenderFence = nil;
                    
                    // We can do the free-ing on a low priority queue
                    // But it has to be a single queue, otherwise we'll end up deleting things at the same time.  Oops.
                    dispatch_async(releaseQueue, ^{
                        frameTeardownInfo->clear();
                    });
                });
            }];
            lastCmdBuff = cmdBuff;

            // This happens for offline rendering and we want to wait until the render finishes to return it
            if (!drawGetter) {
                [cmdBuff commit];
                [cmdBuff waitUntilCompleted];
                lastCmdBuff = nil;
            }
        }
                
        if (perfInterval > 0)
            perfTimer.stopTiming("Work Group: " + workGroup->name);
    }
    
    // Notify anyone waiting that this frame is complete
    if (lastCmdBuff) {
        if (drawGetter) {
            [lastCmdBuff encodeSignalEvent:renderEvent value:lastRenderNo+1];
            [lastCmdBuff commit];
        }
        lastCmdBuff = nil;
    }
    lastRenderNo++;

#if CAPTURE_FRAME_START && CAPTURE_FRAME_END >= CAPTURE_FRAME_START
    if (@available(iOS 13.0, *))
    {
        MTLCaptureManager *captureMgr = [MTLCaptureManager sharedCaptureManager];
        if (frameCount == CAPTURE_FRAME_END && captureMgr.isCapturing)
        {
            [cmdCaptureScope endScope];
            //[captureMgr stopCapture];
        }
    }
#endif

    if (perfInterval > 0)
        perfTimer.stopTiming("Render Frame");
    
    // Update the frames per sec
    if (perfInterval > 0 && frameCount > perfInterval)
    {
        const TimeInterval now = TimeGetCurrent();
        const TimeInterval howLong =  now - frameCountStart;
        framesPerSec = (howLong > 0) ? frameCount / howLong : 0.;
        frameCountStart = now;
        frameCount = 0;
        
        wkLogLevel(Verbose,"---Rendering Performance---");
        wkLogLevel(Verbose," Frames per sec = %.2f",framesPerSec);
        perfTimer.log();
        perfTimer.clear();
    }
    
    // Mark any programs that changed as now caught up
    scene->markProgramsUnchanged();
    
    // No teardown info available between frames
    if (teardownInfo)
    {
        teardownInfo.reset();
    }
    
    setupInfo.heapManage.updateHeaps();
}

void SceneRendererMTL::shutdown()
{
    *_isShuttingDown = true;
    
    [lastCmdBuff waitUntilCompleted];
    lastCmdBuff = nil;
    
    snapshotDelegates.clear();
    
    for (auto &draw: scene->getDrawables())
    {
        draw->teardownForRenderer(nullptr, nullptr, nullptr);
    }

    MTLCaptureManager* captureMgr = [MTLCaptureManager sharedCaptureManager];
    if (captureMgr.defaultCaptureScope == cmdCaptureScope)
    {
        captureMgr.defaultCaptureScope = nil;
    }

    cmdCaptureScope = nil;
    cmdQueue = nil;

    SceneRenderer::shutdown();
}

RenderTargetMTLRef SceneRendererMTL::getRenderTarget(SimpleIdentity renderTargetID)
{
    if (renderTargetID == EmptyIdentity) {
        return std::dynamic_pointer_cast<RenderTargetMTL>(renderTargets.back());
    } else {
        for (auto target : renderTargets) {
            if (target->getId() == renderTargetID) {
                return std::dynamic_pointer_cast<RenderTargetMTL>(target);
            }
        }
    }
    return RenderTargetMTLRef();
}

RawDataRef SceneRendererMTL::getSnapshot(SimpleIdentity renderTargetID)
{
    const auto renderTarget = getRenderTarget(renderTargetID);
    return renderTarget ? renderTarget->snapshot() : nil;
}

RawDataRef SceneRendererMTL::getSnapshotAt(SimpleIdentity renderTargetID,int x,int y)
{
    const auto renderTarget = getRenderTarget(renderTargetID);
    return renderTarget ? renderTarget->snapshot(x, y, 1, 1) : nil;
}

RawDataRef SceneRendererMTL::getSnapshotMinMax(SimpleIdentity renderTargetID)
{
    const auto renderTarget = getRenderTarget(renderTargetID);
    return renderTarget ? renderTarget->snapshotMinMax() : nil;
}
    
BasicDrawableBuilderRef SceneRendererMTL::makeBasicDrawableBuilder(const std::string &name) const
{
    return std::make_shared<BasicDrawableBuilderMTL>(name,scene);
}

BasicDrawableInstanceBuilderRef SceneRendererMTL::makeBasicDrawableInstanceBuilder(const std::string &name) const
{
    return std::make_shared<BasicDrawableInstanceBuilderMTL>(name,scene);
}

BillboardDrawableBuilderRef SceneRendererMTL::makeBillboardDrawableBuilder(const std::string &name) const
{
#if !MAPLY_MINIMAL
    return std::make_shared<BillboardDrawableBuilderMTL>(name,scene);
#else
    // need a stub for the vtable
    return nullptr;
#endif //!MAPLY_MINIMAL
}

ScreenSpaceDrawableBuilderRef SceneRendererMTL::makeScreenSpaceDrawableBuilder(const std::string &name) const
{
#if !MAPLY_MINIMAL
    return std::make_shared<ScreenSpaceDrawableBuilderMTL>(name,scene);
#else
    return nullptr;
#endif //!MAPLY_MINIMAL
}

ParticleSystemDrawableBuilderRef  SceneRendererMTL::makeParticleSystemDrawableBuilder(const std::string &name) const
{
    return nullptr;
}

WideVectorDrawableBuilderRef SceneRendererMTL::makeWideVectorDrawableBuilder(const std::string &name) const
{
#if !MAPLY_MINIMAL
    return std::make_shared<WideVectorDrawableBuilderMTL>(name,this,scene);
#else
    return nullptr;
#endif //!MAPLY_MINIMAL
}

RenderTargetRef SceneRendererMTL::makeRenderTarget() const
{
    return std::make_shared<RenderTargetMTL>();
}

DynamicTextureRef SceneRendererMTL::makeDynamicTexture(const std::string &name) const
{
#if !MAPLY_MINIMAL
    return std::make_shared<DynamicTextureMTL>(name);
#else
    return nullptr;
#endif //!MAPLY_MINIMAL
}


}
