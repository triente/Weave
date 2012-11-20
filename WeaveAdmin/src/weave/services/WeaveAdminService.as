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

package weave.services
{
	import avmplus.DescribeType;
	import avmplus.getQualifiedClassName;
	
	import flash.events.Event;
	import flash.utils.ByteArray;
	import flash.utils.Dictionary;
	
	import mx.controls.Alert;
	import mx.rpc.AsyncToken;
	import mx.rpc.events.FaultEvent;
	import mx.rpc.events.ResultEvent;
	import mx.utils.ObjectUtil;
	import mx.utils.StringUtil;
	
	import weave.core.CallbackCollection;
	import weave.services.beans.ConnectionInfo;
	import weave.services.beans.Entity;
	import weave.services.beans.EntityMetadata;
	
	/**
	 * The functions in this class correspond directly to Weave servlet functions written in Java.
	 * This object uses a queue to guarantee that asynchronous servlet calls will execute in the order they are requested.
	 * @author adufilie
	 * @see WeaveServices/src/weave/servlets/AdminService.java
	 * @see WeaveServices/src/weave/servlets/DataService.java
	 */	
	public class WeaveAdminService
	{
		public static const messageLog:Array = new Array();
		public static const messageLogCallbacks:CallbackCollection = new CallbackCollection();
		public static function messageDisplay(messageTitle:String, message:String, showPopup:Boolean):void 
		{
			// for errors, both a popupbox and addition in the Log takes place
			// for successes, only addition in Log takes place
			if (showPopup)
				Alert.show(message,messageTitle);

			// always add the message to the log
			if (messageTitle == null)
				messageLog.push(message);
			else
				messageLog.push(messageTitle + ": " + message);
			
			messageLogCallbacks.triggerCallbacks();
		}
		
		/**
		 * @param url The URL pointing to where a WeaveServices.war has been deployed.  Example: http://example.com/WeaveServices
		 */		
		public function WeaveAdminService(url:String)
		{
			adminService = new AMF3Servlet(url + "/AdminService");
			dataService = new AMF3Servlet(url + "/DataService");
			queue = new AsyncInvocationQueue();
			
			var info:* = describeTypeJSON(this, DescribeType.METHOD_FLAGS);
			for each (var item:Object in info.traits.methods)
				propertyNameLookup[this[item.name]] = item.name;
		}
		
		/**
		 * avmplus.describeTypeJSON(o:*, flags:uint):Object
		 */		
		private const describeTypeJSON:Function = DescribeType.getJSONFunction();
		
		private var queue:AsyncInvocationQueue;
		private var adminService:AMF3Servlet;
		private var dataService:AMF3Servlet;
		private var propertyNameLookup:Dictionary = new Dictionary(); // Function -> String
		private var methodHooks:Object = {}; // methodName -> Array (of MethodHook)
		
		/**
		 * @param method A pointer to a function of this WeaveAdminService.
		 * @param resultHandler A ResultEvent handler:  function(event:ResultEvent, parameters:Array = null):void
		 */
		public function addHook(method:Function, captureHandler:Function, resultHandler:Function, faultHandler:Function = null):void
		{
			var methodName:String = propertyNameLookup[method];
			if (!methodName)
				throw new Error("method must be a member of " + getQualifiedClassName(this));
			var hooks:Array = methodHooks[methodName];
			if (!hooks)
				methodHooks[methodName] = hooks = [];
			var hook:MethodHook = new MethodHook();
			hook.captureHandler = captureHandler;
			hook.resultHandler = resultHandler;
			hook.faultHandler = faultHandler;
			hooks.push(hook);
		}
		
		private function hookCaptureHandler(query:DelayedAsyncInvocation):void
		{
			for each (var hook:MethodHook in methodHooks[query.methodName])
			{
				if (hook.captureHandler == null)
					continue;
				var args:Array = (query.parameters as Array).concat();
				args.length = hook.captureHandler.length;
				hook.captureHandler.apply(null, args);
			}
		}
		
		/**
		 * This gets called automatically for each ResultEvent from an RPC.
		 * @param method The WeaveAdminService function which corresponds to the RPC.
		 */
		private function hookHandler(event:Event, query:DelayedAsyncInvocation):void
		{
			var handler:Function;
			for each (var hook:MethodHook in methodHooks[query.methodName])
			{
				if (event is ResultEvent)
					handler = hook.resultHandler;
				else
					handler = hook.faultHandler;
				if (handler == null)
					continue;
				
				var args:Array = [event, query.parameters];
				args.length = handler.length;
				handler.apply(null, args);
			}
		}
		
		/**
		 * This function will generate a DelayedAsyncInvocation representing a servlet method invocation and add it to the queue.
		 * @param methodName The name of a Weave AdminService servlet method.
		 * @param parameters Parameters for the servlet method.
		 * @param queued If true, the request will be put into the queue so only one request is made at a time.
		 * @return The DelayedAsyncInvocation object representing the servlet method invocation.
		 */		
		private function invokeAdmin(method:Function, parameters:Array, queued:Boolean = true):DelayedAsyncInvocation
		{
			var methodName:String = propertyNameLookup[method];
			if (!methodName)
				throw new Error("method must be a member of " + getQualifiedClassName(this));
			if (queued)
				return generateQueryAndAddToQueue(adminService, methodName, parameters);
			return adminService.invokeAsyncMethod(methodName, parameters) as DelayedAsyncInvocation;
		}
		
		/**
		 * This function will generate a DelayedAsyncInvocation representing a servlet method invocation and add it to the queue.
		 * @param methodName The name of a Weave AdminService servlet method.
		 * @param parameters Parameters for the servlet method.
		 * @param queued If true, the request will be put into the queue so only one request is made at a time.
		 * @return The DelayedAsyncInvocation object representing the servlet method invocation.
		 */		
		private function invokeAdminWithLogin(method:Function, parameters:Array, queued:Boolean = true):DelayedAsyncInvocation
		{
			parameters.unshift(Admin.instance.activeConnectionName, Admin.instance.activePassword);
			return invokeAdmin(method, parameters, queued);
		}
		
		/**
		 * This function will generate a DelayedAsyncInvocation representing a servlet method invocation and add it to the queue.
		 * @param methodName The name of a Weave DataService servlet method.
		 * @param parameters Parameters for the servlet method.
		 * @param queued If true, the request will be put into the queue so only one request is made at a time.
		 * @return The DelayedAsyncInvocation object representing the servlet method invocation.
		 */		
		private function invokeDataService(method:Function, parameters:Array, queued:Boolean = true):DelayedAsyncInvocation
		{
			var methodName:String = propertyNameLookup[method];
			if (!methodName)
				throw new Error("method must be a member of " + getQualifiedClassName(this));
			if (queued)
				return generateQueryAndAddToQueue(dataService, methodName, parameters);
			return dataService.invokeAsyncMethod(methodName, parameters) as DelayedAsyncInvocation;
		}
			
		/**
		 * This function will generate a DelayedAsyncInvocation representing a servlet method invocation and add it to the queue.
		 * @param service The servlet.
		 * @param methodName The name of a servlet method.
		 * @param parameters Parameters for the servlet method.
		 * @param byteArray An optional byteArray to append to the end of the stream.
		 * @return The DelayedAsyncInvocation object representing the servlet method invocation.
		 */		
		private function generateQueryAndAddToQueue(service:AMF3Servlet, methodName:String, parameters:Array):DelayedAsyncInvocation
		{
			var query:DelayedAsyncInvocation = new DelayedAsyncInvocation(service, methodName, parameters);
			// we want to use a queue so the admin functions will execute in the correct order.
			queue.addToQueue(query);
			hookCaptureHandler(query);
			// automatically display FaultEvent error messages as alert boxes
			addAsyncResponder(query, hookHandler, alertFault, query);
			return query;
		}
		
		// this function displays a String response from a server in an Alert box.
		private function alertResult(event:ResultEvent, token:Object = null):void
		{
			messageDisplay(null,String(event.result),false);
		}
		
		// this function displays an error message from a FaultEvent in an Alert box.
		public function alertFault(event:FaultEvent, token:Object = null):void
		{
			var query:AsyncToken = token as AsyncToken;
			
			var paramDebugStr:String = '';
			if (query.parameters.length > 0)
				paramDebugStr = '"' + query.parameters.join('", "') + '"';
			trace(StringUtil.substitute(
					"Received error on {0}({1}):\n\t{2}",
					query.methodName,
					paramDebugStr,
					event.fault.faultString
				));
			
			//Alert.show(event.fault.faultString, event.fault.name);
			var msg:String = event.fault.faultString;
			if (msg == "ioError")
				msg = "Received no response from the servlet.\nHas the WAR file been deployed correctly?\nExpected servlet URL: "+ adminService.servletURL;
			messageDisplay(event.fault.name, msg, true);
		}

		//////////////////////////////
		// Initialization
		
		public function initializeAdminService():AsyncToken
		{
			return invokeAdmin(initializeAdminService, arguments);
		}
		
		public function checkDatabaseConfigExists():AsyncToken
		{
			return invokeAdmin(checkDatabaseConfigExists, arguments);
		}
		
		public function authenticate(user:String, pass:String):AsyncToken
		{
			return invokeAdmin(authenticate, arguments);
		}

		//////////////////////////////
		// Weave client config files

		public function getWeaveFileNames(showAllFiles:Boolean):AsyncToken
		{
			return invokeAdminWithLogin(getWeaveFileNames, arguments);
		}
		public function saveWeaveFile(fileContent:ByteArray, fileName:String, overwriteFile:Boolean):AsyncToken
		{
			var query:AsyncToken = invokeAdminWithLogin(saveWeaveFile, arguments);
			//addAsyncResponder(query, alertResult);
			return query;
		}
		public function removeWeaveFile(fileName:String):AsyncToken
		{
			var query:AsyncToken = invokeAdminWithLogin(removeWeaveFile, arguments);
			addAsyncResponder(query, alertResult);
			return query;
		}
		public function getWeaveFileInfo(fileName:String):AsyncToken
		{
			return invokeAdminWithLogin(getWeaveFileInfo, arguments, false); // bypass queue
		}
		
		//////////////////////////////
		// ConnectionInfo management
		
		public function generateConnectString(dbms:String, ip:String, port:String, database:String, user:String, pass:String):AsyncToken
		{
			return invokeAdmin(generateConnectString, arguments);
		}
		public function getConnectionNames():AsyncToken
		{
			return invokeAdminWithLogin(getConnectionNames, arguments);
		}
		public function getConnectionInfo(userToGet:String):AsyncToken
		{
			return invokeAdminWithLogin(getConnectionInfo, arguments, false);
		}
		public function saveConnectionInfo(info:ConnectionInfo, configOverwrite:Boolean):AsyncToken
		{
			var query:AsyncToken = invokeAdminWithLogin(saveConnectionInfo, [info.name, info.dbms, info.ip, info.port, info.database, info.user, info.pass, info.folderName, info.is_superuser, configOverwrite]);
			addAsyncResponder(query, alertResult);
		    return query;
		}
		public function removeConnectionInfo(connectionNameToRemove:String):AsyncToken
		{
			var query:AsyncToken = invokeAdminWithLogin(removeConnectionInfo, arguments);
			addAsyncResponder(query, alertResult);
			return query;
		}
		
		//////////////////////////////////
		// DatabaseConfigInfo management
		
		public function getDatabaseConfigInfo():AsyncToken
		{
			return invokeAdminWithLogin(getDatabaseConfigInfo, arguments, false);
		}
		public function setDatabaseConfigInfo(connectionName:String, password:String, schema:String):AsyncToken
		{
			var query:AsyncToken = invokeAdmin(setDatabaseConfigInfo, arguments);
			addAsyncResponder(query, alertResult);
			return query;
		}

		//////////////////////////
		// DataEntity management
		
		public function addParentChildRelationship(parentId:int, childId:int, index:int):AsyncToken
		{
			return invokeAdminWithLogin(addParentChildRelationship, arguments);
		}
		public function removeParentChildRelationship(parentId:int, childId:int):AsyncToken
		{
			return invokeAdminWithLogin(removeParentChildRelationship, arguments);
		}
		public function newEntity(entityType:int, metadata:EntityMetadata, parentId:int):AsyncToken
		{
			return invokeAdminWithLogin(newEntity, arguments);
		}
		public function removeEntity(entityId:int):AsyncToken
		{
			return invokeAdminWithLogin(removeEntity, arguments);
		}
		public function updateEntity(entityId:int, diff:EntityMetadata):AsyncToken
		{
			return invokeAdminWithLogin(updateEntity, arguments);
		}
		public function getEntityChildIds(parentId:int):AsyncToken
		{
			return invokeAdminWithLogin(getEntityChildIds, arguments);
		}
		public function getEntityIdsByMetadata(metadata:EntityMetadata, entityType:int):AsyncToken
		{
			return invokeAdminWithLogin(getEntityIdsByMetadata, arguments);
		}
		public function getEntitiesById(entityIds:Array):AsyncToken
		{
			return invokeAdminWithLogin(getEntitiesById, arguments);
		}
		public function getDataTableList():AsyncToken
		{
			return invokeAdminWithLogin(getDataTableList, arguments);
		}
		
		///////////////////////
		// SQL info retrieval

		public function getSQLSchemaNames():AsyncToken
		{
			return invokeAdminWithLogin(getSQLSchemaNames, arguments, false);
		}
		public function getSQLTableNames(schemaName:String):AsyncToken
		{
			return invokeAdminWithLogin(getSQLTableNames, arguments, false);
		}
		public function getSQLColumnNames(schemaName:String, tableName:String):AsyncToken
		{
			return invokeAdminWithLogin(getSQLColumnNames, arguments, false);
		}

		/////////////////
		// File uploads
		
		public function uploadFile(fileName:String, content:ByteArray):AsyncToken
		{
			// queue up requests for uploading chunks at a time, then return the token of the last chunk
			
			var MB:int = ( 1024 * 1024 );
			var maxChunkSize:int = 20 * MB;
			var chunkSize:int = (content.length > (5*MB)) ? Math.min((content.length / 10 ), maxChunkSize) : ( MB );
			content.position = 0;
			
			var append:Boolean = false;
			var token:AsyncToken;
			do
			{
				var chunk:ByteArray = new ByteArray();
				content.readBytes(chunk, 0, Math.min(content.bytesAvailable, chunkSize));
				
				token = invokeAdmin(uploadFile, [fileName, chunk, append], true); // queued
				append = true;
			}
			while (content.bytesAvailable > 0);
			
			return token;
		}
		public function getUploadedCSVFiles():AsyncToken
		{
			return invokeAdmin(getUploadedCSVFiles, arguments, false);
		}
		public function getUploadedSHPFiles():AsyncToken
		{
			return invokeAdmin(getUploadedSHPFiles, arguments, false);
		}
		public function getCSVColumnNames(csvFiles:String):AsyncToken
		{
			return invokeAdmin(getCSVColumnNames, arguments);
		}
		public function getDBFColumnNames(dbfFileName:String):AsyncToken
		{
		    return invokeAdmin(getDBFColumnNames, arguments);
		}
		public function getDBFData(dbfFileName:String):AsyncToken
		{
			return invokeAdmin(getDBFData, arguments);
		}
		
		/////////////////////////////////
		// Key column uniqueness checks
		
		public function checkKeyColumnForSQLImport(schemaName:String, tableName:String, keyColumnName:String, secondaryKeyColumnName:String):AsyncToken
		{
			return invokeAdminWithLogin(checkKeyColumnForSQLImport, arguments);
		}
		public function checkKeyColumnForCSVImport(csvFileName:String, keyColumnName:String, secondaryKeyColumnName:String):AsyncToken
		{
			return invokeAdmin(checkKeyColumnForCSVImport,arguments);
		}
		
		////////////////
		// Data import
		
		public function importCSV(
				csvFile:String, csvKeyColumn:String, csvSecondaryKeyColumn:String,
				sqlSchema:String, sqlTable:String, sqlOverwrite:Boolean, configDataTableName:String,
				configOverwrite:Boolean, configKeyType:String, nullValues:String,
				filterColumnNames:Array
			):AsyncToken
		{
		    var query:AsyncToken = invokeAdminWithLogin(importCSV, arguments);
			addAsyncResponder(query, alertResult);
		    return query;
		}
		public function importSQL(
				schemaName:String, tableName:String, keyColumnName:String,
				secondaryKeyColumnName:String, configDataTableName:String,
				keyType:String, filterColumns:Array
			):AsyncToken
		{
		    var query:AsyncToken = invokeAdminWithLogin(importSQL, arguments);
			addAsyncResponder(query, alertResult);
		    return query;
		}
		public function importSHP(
				configfileNameWithoutExtension:String, keyColumns:Array,
				sqlSchema:String, sqlTablePrefix:String, sqlOverwrite:Boolean, configTitle:String,
				configKeyType:String, configProjection:String, nullValues:String, importDBFAsDataTable:Boolean
			):AsyncToken
		{
		    var query:AsyncToken = invokeAdminWithLogin(importSHP, arguments);
			addAsyncResponder(query, alertResult);
		    return query;
		}
		
		public function importDBF(
				fileNameWithoutExtension:String, sqlSchema:String,
				sqlTableName:String, sqlOverwrite:Boolean, nullValues:String
			):AsyncToken
		{
			var query:AsyncToken = invokeAdminWithLogin(importDBF, arguments);
			addAsyncResponder(query, alertResult);
			return query;
		}
		
		//////////////////////
		// SQL query testing
		
		public function testAllQueries(tableId:int):AsyncToken
		{
			return invokeAdminWithLogin(testAllQueries, arguments, false);
		}
		
		//////////////////
		// Miscellaneous
		
		public function getKeyTypes():AsyncToken
		{
			return invokeAdmin(getKeyTypes, arguments);
		}
		
		//////////////////////////
		// DataService functions
		
		public function getAttributeColumn(metadata:Object):AsyncToken
		{
			return invokeDataService(getAttributeColumn, arguments, false);
		}
	}
}

internal class MethodHook
{
	public var captureHandler:Function;
	public var resultHandler:Function;
	public var faultHandler:Function;
}
