/*
 *  MaplyCoordinate.h
 *  WhirlyGlobe-MaplyComponent
 *
 *  Created by Steve Gifford on 7/21/12.
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

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

/** 
    A 2D coordinate representation.
    
    The Maply Coordinate is a simple 2 dimensional coordinate
    passed around to numerous methods.  For geo-coordinates x
    maps to longitude and y to latitude and the values are
    in radians.
  */
typedef struct
{
    float x,y;
} MaplyCoordinate;


extern const MaplyCoordinate kMaplyNullCoordinate;


/** 
    Double precision version of 2D coordinate.
    
    This works the same was as the MaplyCoordinate, but has
    more precision.
  */
typedef struct
{
    double x,y;
} MaplyCoordinateD;

extern const MaplyCoordinateD kMaplyNullCoordinateD;


/** 
    A 3D coordinate representation.
    
    The 3D version of the Maply Coordinate adds a z values, often
    in meters, but not always.  Consult the appropriate method to
    be sure.
  */
typedef struct
{
    float x,y,z;
} MaplyCoordinate3d;

extern const MaplyCoordinate3d kMaplyNullCoordinate3d;

/** 
    An NSObject based wrapper for 3D coordinates.
    
    This wrapper encapsulates a MaplyCoordinate3d so we can pass them around in NSDictionary objects.
  */
@interface MaplyCoordinate3dWrapper : NSObject

/// Initialize with a 3D coordinate
- (instancetype)initWithCoord:(MaplyCoordinate3d)coord;

/// 3D coordinate
@property (nonatomic,readonly) MaplyCoordinate3d coord;

@end

typedef struct
{
    double x,y,z;
} MaplyCoordinate3dD;

extern const MaplyCoordinate3dD kMaplyNullCoordinate3dD;

/** 
    An NSObject based wrapper for 3D coordinates.
 
    This wrapper encapsulates a MaplyCoordinate3d so we can pass them around in NSDictionary objects.
 */
@interface MaplyCoordinate3dDWrapper : NSObject

/// Initialize with a 3D coordinate
- (instancetype)initWithCoord:(MaplyCoordinate3dD)coord;

/// 3D coordinate
@property (nonatomic,readonly) MaplyCoordinate3dD coord;

@end

/** 
    Represents a bounding box in a particular coordinate system.
    
    ll is the lower left and ur is the upper right.
  */
typedef struct
{
    MaplyCoordinate ll;
    MaplyCoordinate ur;
} MaplyBoundingBox;

extern const MaplyBoundingBox kMaplyNullBoundingBox;

/**
    A category that uses NSValue to store MaplyCoordinate data
 */
@interface NSValue (MaplyCoordinate)
+ (instancetype)valueWithMaplyCoordinate:(MaplyCoordinate)value;
@property (readonly) MaplyCoordinate maplyCoordinateValue;
@end

/**
    A category that uses NSValue to store MaplyCoordinateD data
 */
@interface NSValue (MaplyCoordinateD)
+ (instancetype)valueWithMaplyCoordinateD:(MaplyCoordinateD)value;
@property (readonly) MaplyCoordinateD maplyCoordinateDValue;
@end

/**
    A category that uses NSValue to store MaplyBoundingBox data
 */
@interface NSValue (MaplyBoundingBox)
+ (instancetype)valueWithMaplyBoundingBox:(MaplyBoundingBox)value;
@property (readonly) MaplyBoundingBox maplyBoundingBoxValue;
@end

/** 
    Represents a bounding box in a particular coordinate system.
    
    ll is the lower left and ur is the upper right.
 */
typedef struct
{
	MaplyCoordinateD ll;
	MaplyCoordinateD ur;
} MaplyBoundingBoxD;

extern const MaplyBoundingBoxD kMaplyNullBoundingBoxD;

#if __cplusplus
extern "C" {
#endif

/** 
    Construct a MaplyCoordiante with longitude and latitude values in radians.
    
    MaplyCoordinate's are in radians when they represent lon/lat values.  This constructs one with radians as input.
    
    @return A 2D MaplyCoordinate in radians (if representing a lon/lat value).
  */
MaplyCoordinate MaplyCoordinateMake(float radLon,float radLat);

/** 
    Construct a MaplyCoordianteD with longitude and latitude values in radians.
    
    MaplyCoordinate's are in radians when they represent lon/lat values.  This constructs one with radians as input.
    
    @return A 2D MaplyCoordinateD in radians (if representing a lon/lat value).
    */
MaplyCoordinateD MaplyCoordinateDMake(double radLon,double radLat);
    
/** 
    Construct a MaplyGeoCoordinate with longitude and latitude values in degrees.
    
    MaplyCoordinate's are in radians when they represent lon/lat values.  This function does that conversion for you.
    
    @param degLon The longitude value (east to west) in degrees.
    
    @param degLat The latitude value (north to south) in degrees.
    
    @return A 2D MaplyCoordinate in radians (if representing a lon/lat value).
  */
MaplyCoordinate MaplyCoordinateMakeWithDegrees(float degLon,float degLat);

/** 
    Construct a MaplyGeoCoordinate with longitude and latitude values in degrees.
 
    MaplyCoordinate's are in radians when they represent lon/lat values.  This function does that conversion for you.
 
    @param degLon The longitude value (east to west) in degrees.
 
    @param degLat The latitude value (north to south) in degrees.
 
    @return A 2D MaplyCoordinate in radians (if representing a lon/lat value).
 */
MaplyCoordinateD MaplyCoordinateDMakeWithDegrees(double degLon,double degLat);

/** 
    Construct a MaplyCoordinateD with a MaplyCoordinate.
    
    This function constructs a MaplyCoordinateD with the component values of the input MaplyCoordinate.
    
    @param c The input MaplyCoordinate value.
    
    @return A 2D MaplyCoordinateD in radians (if representing a lon/lat value).
  */
MaplyCoordinateD MaplyCoordinateDMakeWithMaplyCoordinate(MaplyCoordinate c);

/**
    Construct a MaplyCoordinate with a MaplyCoordinateD.
    
    This function constructs a MaplyCoordinate with the component values of the input MaplyCoordinateD.
    
    @param c The input MaplyCoordinateD value.
    
    @return A 2D MaplyCoordinate in radians (if representing a lon/lat value).
  */
MaplyCoordinate MaplyCoordinateMakeWithMaplyCoordinateD(MaplyCoordinateD c);

/**
    Construct a MaplyCoordinat3d from the values given.
    
    @param x The x value, or longitude in radians if we're making geo coordinates.
    
    @param y The y value, or latitude in radians if we're making geo coordinates.
    
    @param z The z value, sometimes this is display coordinates (radius == 1.0 for a sphere)
              and sometimes this is meters.  It depends on how you're using it.
    
    @return A 3D MaplyCoordinate3d in radians + other (if representing a lon/lat value).
  */
MaplyCoordinate3d MaplyCoordinate3dMake(float x,float y,float z);

/** 
    Construct a MaplyCoordinat3d from the values given.
    
    @param x The x value, or longitude in radians if we're making geo coordinates.
    
    @param y The y value, or latitude in radians if we're making geo coordinates.
    
    @param z The z value, sometimes this is display coordinates (radius == 1.0 for a sphere)
 and sometimes this is meters.  It depends on how you're using it.
    
    @return A 3D MaplyCoordinate3d in radians + other (if representing a lon/lat value).
 */
MaplyCoordinate3dD MaplyCoordinate3dDMake(double x,double y,double z);

/**
    Construct a float bounding box from a double bounding box
 */
MaplyBoundingBox MaplyBoundingBoxMakeFromBoundingBoxD(MaplyBoundingBoxD mbr);

/**
    Construct a double bounding box from a float bounding box
 */
MaplyBoundingBoxD MaplyBoundingBoxDMakeFromBoundingBox(MaplyBoundingBox mbr);


/** 
    Construct a MaplyBoundingBox from the values given.
    
    The inputs are in degrees and the order is longitude *then* latitude.
    
    @param degLon0 The left side of the bounding box in degrees.
    
    @param degLat0 The bottom of the bounding box in degrees.
    
    @param degLon1 The right side of the bounding box in degrees.
    
    @param degLat1 The top of the bounding box in degrees.
    
    @return A MaplyBoundingBox in radians.
  */
MaplyBoundingBox MaplyBoundingBoxMakeWithDegrees(float degLon0,float degLat0,float degLon1,float degLat1);

/** Double version of MaplyBoundingBoxMakeWithDegrees
  */
MaplyBoundingBoxD MaplyBoundingBoxDMakeWithDegrees(double degLon0,double degLat0,double degLon1,double degLat1);

/** 
    Check if two bounding boxes overlap.
     
    @return Returns true if they did overlap, false otherwise.
  */
bool MaplyBoundingBoxesOverlap(MaplyBoundingBox bbox0,MaplyBoundingBox bbox1);
    
/** 
    Check if a bounding contains a given coordinate.
     
    @return Returns true if the bounding box contains the coordinate.
  */
bool MaplyBoundingBoxContains(MaplyBoundingBox bbox, MaplyCoordinate c);

/**
  Set up a bounding box from a list of 2D locations.
 */
MaplyBoundingBox MaplyBoundingBoxFromLocations(const CLLocationCoordinate2D locs[], unsigned int numLocs);

/**
  Set up a bounding box from a list of 2D coordinates
 */
MaplyBoundingBox MaplyBoundingBoxFromCoordinates(const MaplyCoordinate coords[], unsigned int numCoords);
MaplyBoundingBox MaplyBoundingBoxFromCoordinatesD(const MaplyCoordinateD coords[], unsigned int numCoords);
MaplyBoundingBoxD MaplyBoundingBoxDFromCoordinates(const MaplyCoordinate coords[], unsigned int numCoords);
MaplyBoundingBoxD MaplyBoundingBoxDFromCoordinatesD(const MaplyCoordinateD coords[], unsigned int numCoords);

/**
  Expand a bounding box with a list of 2D coordinates
 */
MaplyBoundingBox MaplyBoundingBoxAddCoordinates(MaplyBoundingBox box, const MaplyCoordinate coords[], unsigned int numCoords);
MaplyBoundingBox MaplyBoundingBoxAddCoordinatesD(MaplyBoundingBox box, const MaplyCoordinateD coords[], unsigned int numCoords);
MaplyBoundingBoxD MaplyBoundingBoxDAddCoordinates(MaplyBoundingBoxD box, const MaplyCoordinate coords[], unsigned int numCoords);
MaplyBoundingBoxD MaplyBoundingBoxDAddCoordinatesD(MaplyBoundingBoxD box, const MaplyCoordinateD coords[], unsigned int numCoords);

/**
 Return the intersection of two bounding boxes.
 */
MaplyBoundingBox MaplyBoundingBoxIntersection(MaplyBoundingBox bbox0,MaplyBoundingBox bbox1);

/** 
    Expands a bounding box by a given fraction of its size.
     
    @return Returns the expanded bounding box.
  */
MaplyBoundingBox MaplyBoundingBoxExpandByFraction(MaplyBoundingBox bbox, float buffer);
    
/** 
    Calculate the great circle distance between two geo coordinates.
    
    This calculates the distance on a sphere between one point and another.
    
    @param p0 The starting point, lon/lat in radians.
    
    @param p1 The end point, lon/lat in radians.
    
    @return The distance between p0 and p1 in meters.
  */
double MaplyGreatCircleDistance(MaplyCoordinate p0,MaplyCoordinate p1);
    
#if __cplusplus
}
#endif

