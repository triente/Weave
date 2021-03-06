function(objectID)
{
	var weave = objectID ? document.getElementById(objectID) : document;
	// init event handlers
	weave.addEventListener("dragenter", dragEnter, false);
	weave.addEventListener("dragexit", dragExit, false);
	weave.addEventListener("dragover", dragOver, false);
	weave.addEventListener("drop", drop, false);
	
	function dragEnter(evt) {
		evt.stopPropagation();
		evt.preventDefault();
	}
	
	function dragExit(evt) {
		evt.stopPropagation();
		evt.preventDefault();
	}
	
	function dragOver(evt) {
		evt.stopPropagation();
		evt.preventDefault();
		evt.dataTransfer.dropEffect = 'copy';
	}
	 
	function drop(evt) {
		evt.stopPropagation();
		evt.preventDefault();
	
		var files = evt.dataTransfer.files;
		var count = files.length;
	
		// Only call the handler if 1 or more files was dropped.
		if (count > 0)
			handleFile(files[0]);
	}
	
	function handleFile(file) {
		//console.log(file.name);
	
		var reader = new FileReader();
	
		// init the reader event handlers
		reader.onprogress = function (evt) {
			if (evt.lengthComputable) {
				var loaded = (evt.loaded / evt.total);
				
				//console.log(loaded * 100);
			}
		};
		reader.onloadend = function(evt) {
			var data = evt.target.result;
			data = data.substr(data.indexOf('base64,') + 7);
			
			var libs = ['mx.utils.Base64Decoder', 'weave.Weave'];
			
			var script = "var ba = new Base64Decoder(); ba.decode(data); ";
			if( file.name.substr(-4).toLowerCase() == ".csv" )
				script += "Weave.loadDraggedCSV(ba.flush())";
			else
				script += "Weave.loadWeaveFileContent(ba.flush())";
			
			weave.evaluateExpression([], script, {"data": data}, libs);
		};
	
		// begin the read operation
		reader.readAsDataURL(file);
	}
}
