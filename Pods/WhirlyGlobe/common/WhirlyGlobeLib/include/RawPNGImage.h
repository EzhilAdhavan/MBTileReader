/*
 *  RawPNGImage.h
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 12/3/20.
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

#import <vector>

namespace WhirlyKit
{

/**
 Pulls the raw data out of a PNG image.
 Returns NULL on failure, check the err value.
 */
extern unsigned char *RawPNGImageLoaderInterpreter(unsigned int &width,
                                                   unsigned int &height,
                                                   const unsigned char *data,
                                                   size_t length,
                                                   const int valueMap[256],
                                                   unsigned *outDepth,
                                                   unsigned *outComponents,
                                                   unsigned int *outErr,
                                                   std::string *outErrStr);

}
