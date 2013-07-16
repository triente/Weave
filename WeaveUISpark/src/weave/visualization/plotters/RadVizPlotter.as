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

package weave.visualization.plotters
{
	import flash.display.BitmapData;
	import flash.display.Graphics;
	import flash.display.Shape;
	import flash.geom.Matrix;
	import flash.geom.Point;
	import flash.text.TextFieldAutoSize;
	import flash.utils.Dictionary;
	
	import mx.controls.Alert;
	import mx.core.UITextField;
	import mx.graphics.ImageSnapshot;
	
	import weave.Weave;
	import weave.api.WeaveAPI;
	import weave.api.data.IAttributeColumn;
	import weave.api.data.IColumnStatistics;
	import weave.api.data.IQualifiedKey;
	import weave.api.disposeObjects;
	import weave.api.getCallbackCollection;
	import weave.api.linkableObjectIsBusy;
	import weave.api.newLinkableChild;
	import weave.api.primitives.IBounds2D;
	import weave.api.radviz.ILayoutAlgorithm;
	import weave.api.registerLinkableChild;
	import weave.api.ui.IPlotTask;
	import weave.compiler.StandardLib;
	import weave.core.LinkableBoolean;
	import weave.core.LinkableHashMap;
	import weave.core.LinkableNumber;
	import weave.core.LinkableString;
	import weave.data.AttributeColumns.AlwaysDefinedColumn;
	import weave.data.AttributeColumns.DynamicColumn;
	import weave.data.DataSources.CSVDataSource;
	import weave.primitives.Bounds2D;
	import weave.primitives.ColorRamp;
	import weave.radviz.BruteForceLayoutAlgorithm;
	import weave.radviz.GreedyLayoutAlgorithm;
	import weave.radviz.IncrementalLayoutAlgorithm;
	import weave.radviz.NearestNeighborLayoutAlgorithm;
	import weave.radviz.RandomLayoutAlgorithm;
	import weave.utils.ColumnUtils;
	import weave.utils.RadVizUtils;
	import weave.visualization.plotters.styles.SolidFillStyle;
	import weave.visualization.plotters.styles.SolidLineStyle;
	
	/**
	 * RadVizPlotter
	 * 
	 * @author kmanohar
	 */
	public class RadVizPlotter extends AbstractPlotter
	{
		public function RadVizPlotter()
		{
			fillStyle.color.internalDynamicColumn.globalName = Weave.DEFAULT_COLOR_COLUMN;
			setNewRandomJitterColumn();		
			iterations.value = 50;
			algorithms[RANDOM_LAYOUT] = RandomLayoutAlgorithm;
			algorithms[GREEDY_LAYOUT] = GreedyLayoutAlgorithm;
			algorithms[NEAREST_NEIGHBOR] = NearestNeighborLayoutAlgorithm;
			algorithms[INCREMENTAL_LAYOUT] = IncrementalLayoutAlgorithm;
			algorithms[BRUTE_FORCE] = BruteForceLayoutAlgorithm;
			columns.childListCallbacks.addImmediateCallback(this, handleColumnsListChange);
			getCallbackCollection(filteredKeySet).addGroupedCallback(this, handleColumnsChange, true);
			getCallbackCollection(this).addImmediateCallback(this, clearCoordCache);
			columns.addGroupedCallback(this, handleColumnsChange);
		}
		private function handleColumnsListChange():void
		{
			var newColumn:IAttributeColumn = columns.childListCallbacks.lastObjectAdded as IAttributeColumn;
			var newColumnName:String = columns.childListCallbacks.lastNameAdded;
			if(newColumn != null)
			{
				// invariant: same number of anchors and columns
				anchors.requestObject(newColumnName, AnchorPoint, false);
				// When a new column is created, register the stats to trigger callbacks and affect busy status.
				// This will be cleaned up automatically when the column is disposed.
				var stats:IColumnStatistics = WeaveAPI.StatisticsCache.getColumnStatistics(newColumn);
				registerSpatialProperty(stats)
				getCallbackCollection(stats).addGroupedCallback(this, handleColumnsChange);
			}
			var oldColumnName:String = columns.childListCallbacks.lastNameRemoved;
			if(oldColumnName != null)
			{
				// invariant: same number of anchors and columns
				anchors.removeObject(oldColumnName);
			}
		}
		
		public const columns:LinkableHashMap = registerSpatialProperty(new LinkableHashMap(IAttributeColumn));
		public const localNormalization:LinkableBoolean = registerSpatialProperty(new LinkableBoolean(true));
		public const probeLineNormalizedThreshold:LinkableNumber = registerLinkableChild(this,new LinkableNumber(0, verifyThresholdValue));
		
		private function verifyThresholdValue(value:*):Boolean
		{
			if(0<=Number(value) && Number(value)<=1)
				return true;
			else
				return false;
		}
		
		/**
		 * LinkableHashMap of RadViz dimension locations: 
		 * <br/>contains the location of each column as an AnchorPoint object
		 */		
		public const anchors:LinkableHashMap = registerSpatialProperty(new LinkableHashMap(AnchorPoint));
		private var coordinate:Point = new Point();//reusable object
		private const tempPoint:Point = new Point();//reusable object
		
		public const jitterLevel:LinkableNumber = 			registerSpatialProperty(new LinkableNumber(-19));			
		public const enableJitter:LinkableBoolean = 		registerSpatialProperty(new LinkableBoolean(false));
		public const iterations:LinkableNumber = 			newLinkableChild(this,LinkableNumber);
		
		public const lineStyle:SolidLineStyle = newLinkableChild(this, SolidLineStyle);
		public const fillStyle:SolidFillStyle = newLinkableChild(this,SolidFillStyle);
		public function get alphaColumn():AlwaysDefinedColumn { return fillStyle.alpha; }
		public const colorMap:ColorRamp = registerLinkableChild(this, new ColorRamp(ColorRamp.getColorRampXMLByName("Doppler Radar"))) ;		
		
		public var LayoutClasses:Dictionary = null;//(Set via the editor) needed for setting the Cd layout dimensional anchor  locations
		
		
		/**
		 * This is the radius of the circle, in screen coordinates.
		 */
		public const radiusColumn:DynamicColumn = newLinkableChild(this, DynamicColumn);
		private const radiusColumnStats:IColumnStatistics = registerLinkableChild(this, WeaveAPI.StatisticsCache.getColumnStatistics(radiusColumn));
		public const radiusConstant:LinkableNumber = registerLinkableChild(this, new LinkableNumber(5));
		
		private static var randomValueArray:Array = new Array();		
		private static var randomArrayIndexMap:Dictionary;
		private var keyNumberMap:Dictionary;		
		private var keyNormMap:Dictionary;
		private var keyGlobalNormMap:Dictionary;
		private var columnTitleMap:Dictionary;
		
		private const _currentScreenBounds:Bounds2D = new Bounds2D();
		
		private function handleColumnsChange():void
		{
			if (linkableObjectIsBusy(columns) || linkableObjectIsBusy(spatialCallbacks))
				return;
			
			var i:int = 0;
			var keyNormArray:Array;
			var columnNormArray:Array;
			var columnNumberMap:Dictionary;
			var columnNumberArray:Array;
			var sum:Number = 0;
			
			randomArrayIndexMap = 	new Dictionary(true);
			var keyMaxMap:Dictionary = new Dictionary(true);
			var keyMinMap:Dictionary = new Dictionary(true);
			keyNormMap = 			new Dictionary(true);
			keyGlobalNormMap = 		new Dictionary(true);
			keyNumberMap = 			new Dictionary(true);
			columnTitleMap = 		new Dictionary(true);
			
			
			setAnchorLocations();//normal layout
			
			var keySources:Array = columns.getObjects();
			if (keySources.length > 0) 
			{
				keySources.unshift(radiusColumn);
				setColumnKeySources(keySources, [true]);
				
				for each( var key:IQualifiedKey in filteredKeySet.keys)
				{					
					randomArrayIndexMap[key] = i ;										
					var magnitude:Number = 0;
					columnNormArray = [];
					columnNumberArray = [];
					columnNumberMap = new Dictionary(true);
					sum = 0;
					for each( var column:IAttributeColumn in columns.getObjects())
					{
						if(i == 0)
							columnTitleMap[column] = columns.getName(column);
						var stats:IColumnStatistics = WeaveAPI.StatisticsCache.getColumnStatistics(column);
						columnNormArray.push(stats.getNorm(key));
						columnNumberMap[column] = column.getValueFromKey(key, Number);
						columnNumberArray.push(columnNumberMap[column]);
					}
					for each(var x:Number in columnNumberMap)
					{
						magnitude += (x*x);
					}					
					keyMaxMap[key] = Math.sqrt(magnitude);
					keyMinMap[key] = Math.min.apply(null, columnNumberArray);
					
					keyNumberMap[key] = columnNumberMap ;	
					keyNormMap[key] = columnNormArray ;
					i++
				}
				
				for each( var k:IQualifiedKey in filteredKeySet.keys)
				{
					keyNormArray = [];
					i = 0;
					for each( var col:IAttributeColumn in columns.getObjects())
					{
						keyNormArray.push((keyNumberMap[k][col] - keyMinMap[k])/(keyMaxMap[k] - keyMinMap[k]));
						i++;
					}					
					keyGlobalNormMap[k] = keyNormArray;
					
				}
			}
			else
			{
				setSingleKeySource(null);
			}
			
			setAnchorLocations();
		}
		
		public function setclassDiscriminationMetric(tandpMapping:Dictionary,tandpValuesMapping:Dictionary):void
		{
			var anchorObjects:Array = anchors.getObjects(AnchorPoint);
			var anchorNames:Array = anchors.getNames(AnchorPoint);
			for(var type:Object in tandpMapping)
			{
				var colNamesArray:Array = tandpMapping[type];
				var colValuesArray:Array = tandpValuesMapping[type+"metricvalues"];
				for(var n:int = 0; n < anchorNames.length; n++)//looping through all columns
				{
					var tempAnchorName:String = anchorNames[n];
					for(var c:int =0; c < colNamesArray.length; c++)
					{
						if(tempAnchorName == colNamesArray[c])
						{
							var tempAnchor:AnchorPoint = (anchors.getObject(tempAnchorName)) as AnchorPoint;
							tempAnchor.classDiscriminationMetric.value = colValuesArray[c];
							tempAnchor.classType.value = String(type);
						}
						
					}
				}
				
			}
			
		}
		public function setAnchorLocations( ):void
		{	
			var _columns:Array = columns.getObjects();
			
			var theta:Number = (2*Math.PI)/_columns.length;
			var anchor:AnchorPoint;
			anchors.delayCallbacks();
			//anchors.removeAllObjects();
			for( var i:int = 0; i < _columns.length; i++ )
			{
				anchor = anchors.getObject(columns.getName(_columns[i])) as AnchorPoint ;								
				anchor.x.value = Math.cos(theta*i);
				//trace(anchor.x.value);
				anchor.y.value = Math.sin(theta*i);	
				//trace(anchor.y.value);
				anchor.title.value = ColumnUtils.getTitle(_columns[i]);
			}
			anchors.resumeCallbacks();
		}
		
		//this function sets the anchor locations for the Class Discrimination Layout algorithm and marks the Class locations
		public function setClassDiscriminationAnchorsLocations():void
		{
			var numOfClasses:int = 0;
			for ( var type:Object in LayoutClasses)
			{
				numOfClasses++;
			}
			anchors.delayCallbacks();
			//anchors.removeAllObjects();
			var classTheta:Number = (2*Math.PI)/(numOfClasses);
			
			var classIncrementor:Number = 0;
			for( var cdtype:Object in LayoutClasses)
			{
				var cdAnchor:AnchorPoint;
				var colNames:Array = (LayoutClasses[cdtype] as Array);
				var numOfDivs:int = colNames.length + 1;
				var columnTheta:Number = classTheta /numOfDivs;//needed for equidistant spacing of columns
				var currentClassPos:Number = classTheta * classIncrementor;
				var columnIncrementor:int = 1;//change
				
				for( var g :int = 0; g < colNames.length; g++)//change
				{
					cdAnchor = anchors.getObject(colNames[g]) as AnchorPoint;
					cdAnchor.x.value  = Math.cos(currentClassPos + (columnTheta * columnIncrementor));
					cdAnchor.y.value = Math.sin(currentClassPos + (columnTheta * columnIncrementor));
					cdAnchor.title.value = ColumnUtils.getTitle(columns.getObject(colNames[g]) as IAttributeColumn);
					columnIncrementor++;//change
				}
				
				classIncrementor++;
			}
			
			anchors.resumeCallbacks();
			
		}
		
		
		private var coordCache:Dictionary = new Dictionary(true);
		private function clearCoordCache():void
		{
			coordCache = new Dictionary(true);
		}
		
		/**
		 * Applies the RadViz algorithm to a record specified by a recordKey
		 */
		private function getXYcoordinates(recordKey:IQualifiedKey):void
		{
			var cached:Array = coordCache[recordKey] as Array;
			if (cached)
			{
				coordinate.x = cached[0];
				coordinate.y = cached[1];
			}
			
			//implements RadViz algorithm for x and y coordinates of a record
			var numeratorX:Number = 0;
			var numeratorY:Number = 0;
			var denominator:Number = 0;
			
			var anchorArray:Array = anchors.getObjects();			
			
			var value:Number = 0;			
			var name:String;
			var anchor:AnchorPoint;
			var normArray:Array = (localNormalization.value) ? keyNormMap[recordKey] : keyGlobalNormMap[recordKey];
			var _cols:Array = columns.getObjects();
			for (var i:int = 0; i < _cols.length; i++)
			{
				var column:IAttributeColumn = _cols[i];
				var stats:IColumnStatistics = WeaveAPI.StatisticsCache.getColumnStatistics(column);
				value = normArray ? normArray[i] : stats.getNorm(recordKey);
				if (isNaN(value))
					continue;
				
				name = normArray ? columnTitleMap[column] : columns.getName(column);
				anchor = anchors.getObject(name) as AnchorPoint;
				numeratorX += value * anchor.x.value;
				numeratorY += value * anchor.y.value;						
				denominator += value;
			}
			if(denominator==0) 
			{
				denominator = 1;
			}
			coordinate.x = (numeratorX/denominator);
			coordinate.y = (numeratorY/denominator);
			//trace(recordKey.localName,coordinate);
			if( enableJitter.value )
				jitterRecords(recordKey);
			
			coordCache[recordKey] = [coordinate.x, coordinate.y];
		}
		
		private function jitterRecords(recordKey:IQualifiedKey):void
		{
			var index:Number = randomArrayIndexMap[recordKey];
			var jitter:Number = Math.abs(StandardLib.asNumber(jitterLevel.value));
			var xJitter:Number = (randomValueArray[index])/(jitter);
			if(randomValueArray[index+1] % 2) xJitter *= -1;
			var yJitter:Number = (randomValueArray[index+2])/(jitter);
			if(randomValueArray[index+3])yJitter *= -1;
			if(!isNaN(xJitter))coordinate.x += xJitter ;
			if(!isNaN(yJitter))coordinate.y += yJitter ;
		}
		
		/**
		 * Repopulates the static randomValueArray with new random values to be used for jittering
		 */
		public function setNewRandomJitterColumn():void
		{
			randomValueArray = [] ;
			if( randomValueArray.length == 0 )
				for( var i:int = 0; i < 5000 ;i++ )
				{
					randomValueArray.push( Math.random() % 10) ;
					randomValueArray.push( -(Math.random() % 10)) ;
				}
			spatialCallbacks.triggerCallbacks();
		}
		
		override public function drawPlotAsyncIteration(task:IPlotTask):Number
		{
			if (task.iteration == 0)
			{
				if (!keyNumberMap || keyNumberMap[task.recordKeys[0]] == null)
					return 1;
				if (columns.getObjects().length != anchors.getObjects().length)
					return 1;
			}
			return super.drawPlotAsyncIteration(task);
		}
		
		/**
		 * This function may be defined by a class that extends AbstractPlotter to use the basic template code in AbstractPlotter.drawPlot().
		 */
		override protected function addRecordGraphicsToTempShape(recordKey:IQualifiedKey, dataBounds:IBounds2D, screenBounds:IBounds2D, tempShape:Shape):void
		{
			var graphics:Graphics = tempShape.graphics;
			var radius:Number = radiusColumnStats.getNorm(recordKey);
			
			// Get coordinates of record and add jitter (if specified)
			getXYcoordinates(recordKey);
			
			if(radiusColumn.getInternalColumn() != null)
			{
				if(radius <= Infinity) radius = 2 + (radius *(10-2));
				if(isNaN(radius))
				{			
					radius = radiusConstant.value;
					
					lineStyle.beginLineStyle(recordKey, graphics);
					fillStyle.beginFillStyle(recordKey, graphics);
					dataBounds.projectPointTo(coordinate, screenBounds);
					
					// draw a square of fixed size for missing size values				
					graphics.drawRect(coordinate.x - radius/2, coordinate.y - radius/2, radius, radius);		
					graphics.endFill();
					return ;
				}	
			}
			else if (isNaN(radius))
			{
				radius = radiusConstant.value ;
			}
			
			if(isNaN(coordinate.x) || isNaN(coordinate.y)) return; // missing values skipped
			
			lineStyle.beginLineStyle(recordKey, graphics);
			fillStyle.beginFillStyle(recordKey, graphics);
			
			dataBounds.projectPointTo(coordinate, screenBounds);
			graphics.drawCircle(coordinate.x, coordinate.y, radius);
			
			graphics.endFill();
		}
		
		/**
		 * This function draws the background graphics for this plotter, if applicable.
		 * An example background would be the origin lines of an axis.
		 * @param dataBounds The data coordinates that correspond to the given screenBounds.
		 * @param screenBounds The coordinates on the given sprite that correspond to the given dataBounds.
		 * @param destination The sprite to draw the graphics onto.
		 */
		override public function drawBackground(dataBounds:IBounds2D, screenBounds:IBounds2D, destination:BitmapData):void
		{
			var g:Graphics = tempShape.graphics;
			g.clear();
			
			coordinate.x = -1;
			coordinate.y = -1;
			dataBounds.projectPointTo(coordinate, screenBounds);
			var x:Number = coordinate.x;
			var y:Number = coordinate.y;
			coordinate.x = 1;
			coordinate.y = 1;
			dataBounds.projectPointTo(coordinate, screenBounds);
			
			// draw RadViz circle
			try {
				g.lineStyle(2, 0, .2);
				g.drawEllipse(x, y, coordinate.x - x, coordinate.y - y);
			} catch (e:Error) { }
			
			destination.draw(tempShape);
			_destination = destination;
			
			_currentScreenBounds.copyFrom(screenBounds);
		}
		
		/**
		 * This function must be implemented by classes that extend AbstractPlotter.
		 * 
		 * This function returns a Bounds2D object set to the data bounds associated with the given record key.
		 * @param key The key of a data record.
		 * @param output An Array of IBounds2D objects to store the result in.
		 */
		override public function getDataBoundsFromRecordKey(recordKey:IQualifiedKey, output:Array):void
		{
			//_columns = columns.getObjects(IAttributeColumn);
			//if(!unorderedColumns.length) handleColumnsChange();
			getXYcoordinates(recordKey);
			
			initBoundsArray(output).includePoint(coordinate);
		}
		
		/**
		 * This function returns a Bounds2D object set to the data bounds associated with the background.
		 * @param An IBounds2D object used to store the background data bounds.
		 */
		override public function getBackgroundDataBounds(output:IBounds2D):void
		{
			output.setBounds(-1, -1.1, 1, 1.1);
		}		
		
		public var drawProbe:Boolean = false;
		public var probedKeys:Array = null;
		private var _destination:BitmapData = null;
		
		public function drawProbeLines(keys:Array,dataBounds:Bounds2D, screenBounds:Bounds2D, destination:Graphics):void
		{						
			if(!drawProbe) return;
			if(!keys) return;
			
			var graphics:Graphics = destination;
			graphics.clear();
			
			if(filteredKeySet.keys.length == 0)
				return;
			var requiredKeyType:String = filteredKeySet.keys[0].keyType;
			var _cols:Array = columns.getObjects();
			
			for each( var key:IQualifiedKey in keys)
			{
				/*if the keytype is different from the keytype of points visualized on Rad Vis than ignore*/
				if(key.keyType != requiredKeyType)
				{
					return;
				}
				getXYcoordinates(key);
				dataBounds.projectPointTo(coordinate, screenBounds);
				var normArray:Array = (localNormalization.value) ? keyNormMap[key] : keyGlobalNormMap[key];
				
				var value:Number;
				var name:String;
				var anchor:AnchorPoint;
				for (var i:int = 0; i < _cols.length; i++)
				{
					var column:IAttributeColumn = _cols[i];
					var stats:IColumnStatistics = WeaveAPI.StatisticsCache.getColumnStatistics(column);
					value = normArray ? normArray[i] : stats.getNorm(key);
					
					/*only draw probe line if higher than threshold value*/
					if (isNaN(value) || value <= probeLineNormalizedThreshold.value)
						continue;
					
					/*draw the line from point to anchor*/
					name = normArray ? columnTitleMap[column] : columns.getName(column);
					anchor = anchors.getObject(name) as AnchorPoint;
					tempPoint.x = anchor.x.value;
					tempPoint.y = anchor.y.value;
					dataBounds.projectPointTo(tempPoint, screenBounds);
					graphics.lineStyle(.5, 0xff0000);
					graphics.moveTo(coordinate.x, coordinate.y);
					graphics.lineTo(tempPoint.x, tempPoint.y);
					
					/*We  draw the value (upto to 1 decimal place) in the middle of the probe line. We use the solution as described here:
					http://cookbooks.adobe.com/post_Adding_text_to_flash_display_Graphics_instance-14246.html
					*/
					graphics.lineStyle(0,0,0);
					var uit:UITextField = new UITextField();
					var numberValue:String = ColumnUtils.getNumber(column,key).toString();
					numberValue = numberValue.substring(0,numberValue.indexOf('.')+2);
					uit.text = numberValue;
					uit.autoSize = TextFieldAutoSize.LEFT;
					var textBitmapData:BitmapData = ImageSnapshot.captureBitmapData(uit);
					
					var sizeMatrix:Matrix = new Matrix();
					var coef:Number =Math.min(uit.measuredWidth/textBitmapData.width,uit.measuredHeight/textBitmapData.height);
					sizeMatrix.a = coef;
					sizeMatrix.d = coef;
					textBitmapData = ImageSnapshot.captureBitmapData(uit,sizeMatrix);
					
					var sm:Matrix = new Matrix();
					sm.tx = (coordinate.x+tempPoint.x)/2;
					sm.ty = (coordinate.y+tempPoint.y)/2;
					
					graphics.beginBitmapFill(textBitmapData, sm, false);
					graphics.drawRect((coordinate.x+tempPoint.x)/2,(coordinate.y+tempPoint.y)/2,uit.measuredWidth,uit.measuredHeight);
					graphics.endFill();
					
				}
				
				//				for each( var anchor:AnchorPoint in anchors.getObjects(AnchorPoint))
				//				{
				//					tempPoint.x = anchor.x.value;
				//					tempPoint.y = anchor.y.value;
				//					dataBounds.projectPointTo(tempPoint, screenBounds);
				//					graphics.lineStyle(.5, 0xff0000);
				//					graphics.moveTo(coordinate.x, coordinate.y);
				//					graphics.lineTo(tempPoint.x, tempPoint.y);					
				//				}
			}
		}
		
		
		private function changeAlgorithm():void
		{
			if(_currentScreenBounds.isEmpty()) return;
			
			var newAlgorithm:Class = algorithms[currentAlgorithm.value];
			if (newAlgorithm == null) 
				return;
			
			disposeObjects(_algorithm); // clean up previous algorithm
			
			_algorithm = newSpatialProperty(newAlgorithm);
			var array:Array = _algorithm.run(columns.getObjects(IAttributeColumn), keyNumberMap);
			
			RadVizUtils.reorderColumns(columns, array);
		}
		
		public const sampleTitle:LinkableString = registerLinkableChild(this, new LinkableString(""));
		public const dataSetName:LinkableString = registerLinkableChild(this, new LinkableString());
		public const regularSampling:LinkableBoolean = registerLinkableChild(this, new LinkableBoolean(true));
		public const RSampling:LinkableBoolean = registerLinkableChild(this, new LinkableBoolean(false));
		public const sampleSizeRows:LinkableNumber = registerLinkableChild(this, new LinkableNumber(300));
		public const sampleSizeColumns:LinkableNumber = registerLinkableChild(this, new LinkableNumber(20));
		public function sampleDataSet():void
		{
			// we use the CSVDataSource so we can get the rows.
			var originalCSVDataSource:CSVDataSource = WeaveAPI.globalHashMap.getObject(dataSetName.value) as CSVDataSource;
			var randomIndex:int = 0; // random index to randomly pick a row.
			var i:int; // used to iterate over the data.
			var originalArray:Array = [];
			var sampledArray:Array = [];
			var transposedSampledArray:Array = [];
			var col:int;
			var row:int;
			
			if (regularSampling.value && !RSampling.value) // sampling done in actionscript
			{
				// rows first
				if (originalCSVDataSource)
				{
					originalArray = originalCSVDataSource.getCSVData().concat(); // get a copy. otherwise we modify the original array.
				} 
				else
				{
					Alert.show(lang("No data found."))
					return;
				}
				if (originalArray.length < sampleSizeRows.value)
				{
					sampledArray = originalArray; // sample size is bigger than the data set.
					Alert.show(lang("Data sampled successfully."))
				}
				else // sampling begins here
				{
					var titleRow:Array = originalArray.shift(); // throwing the column names first row.
					i = sampleSizeRows.value; // we need to reduce this number by one because the title row already accounts for a row
					var length:int = originalArray.length;
					while( i != 0 )
					{
						randomIndex = int(Math.random() * (length));
						sampledArray.push(originalArray[randomIndex]);
						originalArray.splice(randomIndex, 1);
						length--;
						i--;
					}
					sampledArray.unshift(titleRow); // we put the title row back here..
					originalArray.length = 0; // we clear this array since we don't need it anymore.
					// Sampling is done. we wrap it back into a CSVDataSource
					
					
					transposedSampledArray = transposeDataArray(sampledArray);
					var firstColumn:Array = transposedSampledArray.shift(); // assumed to be the Id column
					var secondColumn:Array = transposedSampledArray.shift(); // assumed to be the class column
					
					// proceed as above with a transposed csv... not sure if there is a better way to do this.
					if (transposedSampledArray.length < sampleSizeColumns.value - 2)
					{
						sampledArray = transposeDataArray(transposedSampledArray); // sample size is bigger than the data set.
					}
					else // column sampling begins here
					{
						i = sampleSizeColumns.value - 2; // we need to reduce this number by one because the title row already accounts for a row
						length = transposedSampledArray.length; // accounted for the first two columns removed.
						sampledArray = []; // making this sampled array reusable
						while( i != 0 )
						{
							randomIndex = int(Math.random() * (length));
							sampledArray.push(transposedSampledArray[randomIndex]);
							transposedSampledArray.splice(randomIndex, 1);
							length--;
							i--;
						}
						transposedSampledArray.splice(0);
						sampledArray.unshift(secondColumn);
						sampledArray.unshift(firstColumn);
						var temp:Array = sampledArray; // quick older for the sample array to be transposed again
						sampledArray = transposeDataArray(temp); // at this stage we should have a complete row and column sample
					}
					
					// begin saving the CSVDataSource.
					if (sampleTitle.value == "" || sampleTitle.value == "optional")
					{
						sampleTitle.value = Weave.root.generateUniqueName("Sampled " + WeaveAPI.globalHashMap.getName(originalCSVDataSource));
					}
					var sampledCSVDataSource:CSVDataSource = WeaveAPI.globalHashMap.requestObject(sampleTitle.value, CSVDataSource, false);
					sampledCSVDataSource.setCSVData(sampledArray);
					sampledCSVDataSource.keyType.value = originalCSVDataSource.keyType.value;
					Alert.show(lang("Data sampled successfully"));
					sampleTitle.value = "";
				} 
			}
				
			else // Rsampling
			{
				// TODO
				// R documentation says to pass it a vector (2 dimensional?)
				// sample(x, size, replace = FALSE, prob = NULL)
				//
				// arguments
				// x       Vector of one or more elements
				// size    The sample size
				// replace Should sampling be done with replacement
				// prob    vector of probability weights (should be null for random sampling)
			}
			return;			
		}
		
		/**
		 * @param array must be two dimensional array
		 * 
		 * @return transposed array
		 **/
		
		private function transposeDataArray (array:Array):Array
		{
			var i:int = 0;
			var j:int = 0;
			if(array)
				var rowLength:int = array.length;
			if (array[0])
				var colLength:int = array[0].length;	
			
			var transposed:Array = new Array(colLength);
			
			for (i = 0; i < colLength; i++)
			{
				transposed[i] = new Array(rowLength);
				for (j = 0; j < rowLength; j++)
					transposed[i][j] = array[j][i];
			}
			return transposed;
		}
		
		private var _algorithm:ILayoutAlgorithm = newSpatialProperty(GreedyLayoutAlgorithm);
		
		// algorithms
		[Bindable] public var algorithms:Array = [RANDOM_LAYOUT, GREEDY_LAYOUT, NEAREST_NEIGHBOR, INCREMENTAL_LAYOUT, BRUTE_FORCE];
		public const currentAlgorithm:LinkableString = registerLinkableChild(this, new LinkableString(GREEDY_LAYOUT), changeAlgorithm);
		public static const RANDOM_LAYOUT:String = "Random layout";
		public static const GREEDY_LAYOUT:String = "Greedy layout";
		public static const NEAREST_NEIGHBOR:String = "Nearest neighbor";
		public static const INCREMENTAL_LAYOUT:String = "Incremental layout";
		public static const BRUTE_FORCE:String = "Brute force";
	}
}
