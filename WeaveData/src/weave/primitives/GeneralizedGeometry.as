/*
    Weave (Web-based Analysis and Visualization Environment)
    Copyright (C) 2008-2011 University of Massachusetts Lowell

    This file is a part of Weave.

    Weave is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License, Version 3,
    as published by the Free Software Foundation.

    Weave is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Weave.  If not, see <http://www.gnu.org/licenses/>.
*/

package weave.primitives
{
	import flash.utils.Dictionary;
	
	import weave.api.data.ISimpleGeometry;
	import weave.api.primitives.IBounds2D;
	import weave.utils.BLGTreeUtils;
	import weave.utils.VectorUtils;
	
	/**
	 * GeneralizedGeometry
	 * A generalized geometry is one that lends itself to be displayed at different quality levels.
	 * The geometry coordinates may be inserted individually through the "coordinates" property,
	 * or they can all be processed at once through the setCoordinates() function.
	 * The bounds object is separate from the coordinates, so if coordinates are inserted individually,
	 * the bounds object should be updated accordingly if you want it to be accurate.
	 * 
	 * @author adufilie
	 */
	public class GeneralizedGeometry 
	{
		/**
		 * Create an empty geometry.
		 * @param geomType The type of the geometry (GeometryType.LINE, GeometryType.POINT, or GeometryType.POLYGON).
		 */
		public function GeneralizedGeometry(geomType:String = GeometryType.POLYGON)
		{
			this.geomType = geomType;
			this.parts[0] = new BLGTree();
		}

		/**
		 * Each of these integers corresponds to a vertexID that separates the current part from the next part.
		 * For example, partMarkers[0] is the vertexID that marks the end of part 0 and the start of part 1.
		 * If there are no part markers, it is assumed that there is only one part.
		 */
		private const partMarkers:Vector.<int> = new Vector.<int>();
		/**
		 * This maps BLGTree from the parts Array to a Boolean.
		 * If there are multiple parts in this geometry, only parts that map to values of true will be included in getSimplifiedGeometry() results.
		 */
		private const receivedPartMarkers:Dictionary = new Dictionary(true);
		/**
		 * These are the coordinates associated with the geometry.
		 * Each element in this vector is a separate part of the geometry.
		 * Each could be either a new polygon or a hole in a previous polygon.
		 */
		private const parts:Vector.<BLGTree> = new Vector.<BLGTree>();
		/**
		 * This is a bounding box for the geometry.
		 * It is useful for spatial indexing when not all the points are available yet.
		 */
		public const bounds:IBounds2D = new Bounds2D();
		
		/**
		 * This is the type of the geometry.  Value should be one of the static geometry types listed in this class.
		 */
		public var geomType:String;

		/**
		 * geometry types
		 */
		public function isLine():Boolean { return geomType == GeometryType.LINE; }
		public function isPoint():Boolean { return geomType == GeometryType.POINT; }
		public function isPolygon():Boolean { return geomType == GeometryType.POLYGON; }

		/**
		 * @return true if the geometry has no information on its individual coordinates.
		 */
		public function get isEmpty():Boolean
		{
			if (partMarkers.length > 0)
				return false;
			return (parts[0] as BLGTree).isEmpty;
		}
		
		/**
		 * @param minImportance No points with importance less than this value will be returned.
		 * @param visibleBounds If not null, this bounds will be used to remove unnecessary offscreen points.
		 * @return An Array of ISimpleGeometry objects 
		 * @see weave.api.data.ISimpleGeometry
		 */		
		public function getSimpleGeometries(minImportance:Number = 0, visibleBounds:IBounds2D = null, output:Array = null):Array
		{
			var result:Array = output || [];
			var parts:Vector.<Vector.<BLGNode>> = getSimplifiedGeometry(minImportance, visibleBounds);
			for (var i:int = 0; i < parts.length; i++)
			{
				var part:Vector.<BLGNode> = parts[i] as Vector.<BLGNode>;
				var geom:ISimpleGeometry = result[i] as ISimpleGeometry || new SimpleGeometry(geomType); // re-use existing or create new
				geom.setVertices(VectorUtils.copy(part, []));
				result[i] = geom;
			}
			return result;
		}

		/**
		 * @param minImportance No points with importance less than this value will be returned.
		 * @param visibleBounds If not null, this bounds will be used to remove unnecessary offscreen points.
		 * @return A vector of results from BLGTree.getPointVector(minImportance, visibleBounds) from each part.
		 */
		public function getSimplifiedGeometry(minImportance:Number = 0, visibleBounds:IBounds2D = null):Vector.<Vector.<BLGNode>>
		{
			// if bounds is completely contained in visibleBounds, don't pass visibleBounds to getPointVector() (faster this way)
			if (visibleBounds && visibleBounds.containsBounds(bounds))
				visibleBounds = null;
			_simplifiedParts.length = 0;
			var part:BLGTree;
			for (var i:int = 0; i < parts.length; i++)
			{
				part = parts[i] as BLGTree;
				
				// skip this part if we're not sure it's actually a single part
				if (parts.length > 1 && !receivedPartMarkers[part])
					continue;
				
				var simplifiedPart:Vector.<BLGNode> = part.getPointVector(minImportance, visibleBounds);
				
				// skip parts without enough vertices
				if (simplifiedPart.length == 0)
					continue;
				if (simplifiedPart.length == 1 && geomType != GeometryType.POINT)
					continue;
				if (simplifiedPart.length == 2 && geomType == GeometryType.POLYGON)
					continue;
				
				_simplifiedParts.push(simplifiedPart);
			}
			return _simplifiedParts;
		}
		// _simplifiedParts: A place to store results from getSimplifiedGeometry()
		private const _simplifiedParts:Vector.<Vector.<BLGNode>> = new Vector.<Vector.<BLGNode>>();

		/**
		 * Inserts a new point into the appropriate part of the geometry.
		 */
		public function addPoint(vertexID:int, importance:Number, x:Number, y:Number):void
		{
			var partID:int = VectorUtils.binarySearch(partMarkers, vertexID, false);
			
			// special case - if this vertex is exactly at a part marker, it should go to the next part
			if (partID < partMarkers.length && partMarkers[partID] == vertexID)
				partID++;
			
			var part:BLGTree = parts[partID] as BLGTree;
			part.insert(vertexID, importance, x, y);
		}

		/**
		 * Specifies a range of vertexIDs that correspond to a single part.
		 * @param beginIndex The index of the first vertex of a geometry part.
		 * @param endIndex The index after the last vertex of the geometry part.
		 */
		public function addPartMarker(beginIndex:int, endIndex:int):void
		{
			// split BLG trees appropriately.
			splitAtIndex(beginIndex);
			splitAtIndex(endIndex);
			
			// find the corresponding part and mark it as received.
			var partID:int = VectorUtils.binarySearch(partMarkers, endIndex, false);
			var part:BLGTree = parts[partID] as BLGTree;
			receivedPartMarkers[part] = true;
		}
		
		/**
		 * If necessary, this will split a BLGTree for a particular part into two and update the partMarkers.
		 */
		private function splitAtIndex(vertexID:int):void
		{
			if (vertexID <= 0 || vertexID >= int.MAX_VALUE || VectorUtils.binarySearch(partMarkers, vertexID, true) >= 0)
				return;
			
			// partMarkers[i] marks the end of parts[i]
			for (var i:int = partMarkers.length; i > 0; i--)
			{
				if (vertexID > partMarkers[i - 1])
					break;
				
				partMarkers[i] = partMarkers[i - 1];
				parts[i + 1] = parts[i];
			}
			
			partMarkers[i] = vertexID;
			parts[i + 1] = (parts[i] as BLGTree).splitAtIndex(vertexID);
			// We don't have to worry about receivedPartMarkers here because if we need
			// to split an existing part it means we haven't received its partMarker yet.
		}
		
		/**
		 * This function assigns importance values to a list of coordinates and replaces the contents of the BLGTree.
		 * @param xyCoordinates An array of Numbers, even index values being x coordinates and odd index values being y coordinates.
		 */
		public function setCoordinates(xyCoordinates:Array, method:String = "BLGTreeUtils.METHOD_SAMPLE"):void
		{
			// reset bounds and parts before processing coordinates
			bounds.reset();
			partMarkers.length = 0;
			parts.length = 1;
			
			var coordinates:BLGTree = parts[0] as BLGTree;
			coordinates.clear();
			receivedPartMarkers[coordinates] = true;
			
			var firstVertex:VertexChainLink = null;
			var newVertex:VertexChainLink;
			var x:Number, y:Number;
			var firstVertexID:int = 0;
			var ix:int = 0; // index of current x coordinate in xyCoordinates
			// point data doesn't apply to the generalization algorithm
			if (geomType == GeometryType.POINT)
			{
				for (; ix + 1 < xyCoordinates.length; ix += 2)
				{
					x = xyCoordinates[ix];
					y = xyCoordinates[ix + 1];
					coordinates.insert(ix / 2, Infinity, x, y);
					bounds.includeCoords(x, y);
				}
				return;
			}			
			// process each part of the geometry (additional parts may be islands or lakes)
			while (ix + 1 < xyCoordinates.length) // while there is an x,y pair
			{
				if (firstVertexID > 0)
				{
					// create new part and add part marker
					coordinates = new BLGTree();
					receivedPartMarkers[coordinates] = true;
					parts.push(coordinates);
					partMarkers.push(firstVertexID);
				}
				// loop through coordinates
				var numPoints:int = 0;
				for (; ix + 1 < xyCoordinates.length; ix += 2)
				{
					x = xyCoordinates[ix];
					y = xyCoordinates[ix + 1];
		
					if (x <= -Number.MAX_VALUE || x >= Number.MAX_VALUE ||
						y <= -Number.MAX_VALUE || y >= Number.MAX_VALUE)
					{
						// don't add invalid points
						continue;
					}
					// create chain link for this coordinate
					newVertex = VertexChainLink.getUnusedInstance(firstVertexID + numPoints, x, y);
					if (numPoints == 0)
					{
						firstVertex = newVertex;
					}
					else
					{
						// don't add consecutive duplicate points
						if (newVertex.equals2D(firstVertex.prev))
						{
							VertexChainLink.saveUnusedInstance(newVertex);
							continue;
						}
						// stop adding points when the current coord is equal to the first coord
						// or NaN part marker is found
						if (newVertex.equals2D(firstVertex) || isNaN(x) || isNaN(y))
						{
							ix += 2; // make sure to skip this coord

							VertexChainLink.saveUnusedInstance(newVertex);
							break;
						}
						firstVertex.insert(newVertex);
					}
					// include this vertex in the geometry bounds
					bounds.includeCoords(x, y);
					numPoints++;
				}
				// ARC: end points of a part are required points
				if (geomType == GeometryType.LINE && numPoints > 0)
				{
					firstVertex.importance = Infinity;
					firstVertex.prev.importance = Infinity;
				}
				
				// assign importance values to points and save them
				BLGTreeUtils.buildBLGTree(firstVertex, coordinates, method);
				
				// done copying points for this part, advance firstVertexID to after the current part
				firstVertexID += numPoints;
			}
		}
	}
}
