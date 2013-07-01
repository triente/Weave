/**
* @author Patrick Ryan
*/
goog.provide('Panel');

/**
* @param {*} color
* @param {*} size
* @constructor 
*/
Panel = function(color, size){
	 /** @type {*}
	 * 
	 */
	this.color_ = color;
	


	if (goog.isDef(size)) {
		this.size_ = size;
	}
};

/** @return */
Panel.prototype.getSize = function() {
	return this.size_;
};

/** @return  */
Panel.prototype.getColor = function() {
	return this.color_;
};

