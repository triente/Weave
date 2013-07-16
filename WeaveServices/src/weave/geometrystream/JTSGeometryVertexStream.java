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

package weave.geometrystream;

import com.vividsolutions.jts.geom.Coordinate;
import com.vividsolutions.jts.geom.Geometry;

/**
 * This is an interface to a stream of vertices from a geometry.
 * 
 * @author adufilie
 */
public class JTSGeometryVertexStream implements IGeometryVertexStream
{
	public JTSGeometryVertexStream(Geometry geom)
	{
		coords = geom.getCoordinates();
		index = -1; // start before the first coord so the first call to next() will not skip anything
	}
	
	private Coordinate[] coords;
	private int index;
	
	/**
	 * This checks if there is a vertex available from the stream.
	 * @return true if there is a next vertex available from the stream, meaning a call to next() will succeed.
	 */
	public boolean hasNext()
	{
		return index + 1 < coords.length;
	}
	
	/**
	 * This advances the internal pointer to the next vertex.
	 * Initially, the pointer points before the first vertex.
	 * This function must be called before getX() and getY() are called.
	 * @return true if advancing the vertex pointer succeeded, meaning getX() and getY() can now be called.
	 */
	public boolean next()
	{
		return ++index < coords.length;
	}
	
	/**
	 * @return The X coordinate of the current vertex.
	 */
	public double getX()
	{
		return coords[index].x;
	}

	/**
	 * @return The Y coordinate of the current vertex.
	 */
	public double getY()
	{
		return coords[index].y;
	}
}
