/*
 *  WhirlyGlobe.h
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 1/12/11.
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

#import "ActiveModel.h"
#import "BaseInfo.h"
#import "BasicDrawable.h"
#import "BasicDrawableBuilder.h"
#import "BasicDrawableInstance.h"
#import "BasicDrawableInstanceBuilder.h"
#import "ComponentManager.h"
#import "CoordSystem.h"
#import "Dictionary.h"
#import "DictionaryC.h"
#import "Drawable.h"
#import "DynamicTextureAtlas.h"
#import "FlatMath.h"
#import "GridClipper.h"
#import "Identifiable.h"
#import "ImageTile.h"
#import "LabelManager.h"
#import "LabelRenderer.h"
#import "Lighting.h"
#import "LoadedTileNew.h"
#import "MaplyAnimateTranslateMomentum.h"
#import "MaplyAnimateTranslation.h"
#import "MaplyFlatView.h"
#import "MaplyView.h"
#import "OverlapHelper.h"
#import "PerformanceTimer.h"
#import "Platform.h"
#import "Program.h"
#import "Proj4CoordSystem.h"
#import "QuadDisplayControllerNew.h"
#import "QuadImageFrameLoader.h"
#import "QuadLoaderReturn.h"
#import "QuadSamplingController.h"
#import "QuadSamplingParams.h"
#import "QuadTileBuilder.h"
#import "QuadTreeNew.h"
#import "RawData.h"
#import "RawPNGImage.h"
#import "RenderTarget.h"
#import "Scene.h"
#import "SceneGraphManager.h"
#import "SceneRenderer.h"
#import "ScreenImportance.h"
#import "ScreenObject.h"
#import "ScreenSpaceBuilder.h"
#import "ScreenSpaceDrawableBuilder.h"
#import "SelectionManager.h"
#import "ShapeDrawableBuilder.h"
#import "ShapeManager.h"
#import "ShapeReader.h"
#import "SharedAttributes.h"
#import "SphericalEarthChunkManager.h"
#import "SphericalMercator.h"
#import "StringIndexer.h"
#import "Tesselator.h"
#import "Texture.h"
#import "TextureAtlas.h"
#import "WhirlyGeometry.h"
#import "WhirlyKitLog.h"
#import "WhirlyKitView.h"
#import "WhirlyOctEncoding.h"
#import "WhirlyTypes.h"
#import "WhirlyVector.h"
#import "WideVectorDrawableBuilder.h"
#import "WideVectorManager.h"

#if !MAPLY_MINIMAL
# import "BillboardDrawableBuilder.h"
# import "BillboardManager.h"
# import "FontTextureManager.h"
# import "GeometryManager.h"
# import "GeometryOBJReader.h"
# import "GlobeAnimateHeight.h"
# import "GlobeAnimateRotation.h"
# import "GlobeAnimateViewMomentum.h"
# import "GlobeMath.h"
# import "GlobeView.h"
# import "LoftManager.h"
# import "IntersectionManager.h"
# import "MapboxVectorTileParser.h"
# import "MapboxVectorStyleSetC.h"
# import "MapboxVectorStyleBackground.h"
# import "MapboxVectorStyleCircle.h"
# import "MapboxVectorStyleFill.h"
# import "MapboxVectorStyleLine.h"
# import "MapboxVectorStyleRaster.h"
# import "MapboxVectorStyleSymbol.h"
# import "MapboxVectorStyleSpritesImpl.h"
# import "MaplyVectorStyleC.h"
# import "LayoutManager.h"
# import "MarkerManager.h"
# import "Moon.h"
# import "ParticleSystemDrawable.h"
# import "ParticleSystemDrawableBuilder.h"
# import "ParticleSystemManager.h"
# import "Sun.h"
# import "VectorData.h"
# import "VectorManager.h"
# import "VectorObject.h"
#endif //!MAPLY_MINIMAL

// OpenGL ES Specific includes

#ifdef __ANDROID__
#import "UtilsGLES.h"
#import "WrapperGLES.h"
#import "MemManagerGLES.h"

#import "TextureGLES.h"
#import "DynamicTextureAtlasGLES.h"

#import "ProgramGLES.h"
#import "RenderTargetGLES.h"
#import "SceneGLES.h"
#import "SceneRendererGLES.h"

#import "BasicDrawableGLES.h"
#import "BasicDrawableBuilderGLES.h"
#import "BasicDrawableInstanceGLES.h"
#import "BasicDrawableInstanceBuilderGLES.h"
#import "BillboardDrawableBuilderGLES.h"
#import "WideVectorDrawableBuilderGLES.h"
#import "ScreenSpaceDrawableBuilderGLES.h"
#import "ParticleSystemDrawableGLES.h"
#import "ParticleSystemDrawableBuilderGLES.h"

#import "LineAndPointShadersGLES.h"
#import "TriangleShadersGLES.h"
#endif

