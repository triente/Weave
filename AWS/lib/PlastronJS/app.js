/**
 * @author Patrick Ryan
 */
goog.provide('aws.Panel');
goog.require('goog.string.StringBuffer');

goog.require('goog.json');
goog.require('goog.ui.ComboBox');
goog.require('goog.dom');
goog.require('goog.dom.DomHelper');
goog.require('G');
goog.require('aws.templates');

/**
 * @param {string} color
 * @param {number=} size
 * @constructor
 */
aws.Panel = function(state) {
	//goog.base.call(this);

	if (goog.isDef(state)) {

		this.setState(state);
	}
	renderElement_ = G('#indicator');
	this.Prender()

};
goog.inherits(aws.Panel, goog.ui.ComboBox);

var state_ = {};
var comboBox_ = new goog.ui.ComboBox();
var items_ = [];
var renderElement_

/*/** @return 
example.Panel.prototype.getSize = function() {
	return this.size_;
}; */

/** @return  {string} */


aws.Panel.prototype = {
	/**
	 * Sets the state using a JSON object.
	 * @param {Object} upstate Object shown on normal state.
	 * @return {boolean} .
	 */
	setState: function(state) {
		this.decompileState(state);
		return true;
	},

	/**
	 * Returns the current Panel state object.
	 * @return {Object}
	 */
	getState: function() {
		return this.state_;
	},

	/**
	 * Parses the state_ object to find UI values.
	 * @param {Object} value
	 */
	decompileState: function(value) {
		// Parse the state_ object to update the templated objects.
		// we're going to start with one control box.
		if (value == this.state_) return this;
		//var parsedState = goog.json.unsafeParse(value);

		this.items_ = value.comboOptions;
		for (var i = 0; i < items_.length; i++) {
			comboBox_.addItem(new goog.ui.ComboBoxItem(items_[i]));
		}
		comboBox_.setDefaultText('select 1');
		comboBox_.setUseDropdownArrow(true);

	},
	/**
	 * Renders State.
	 *
	 */
	Prender: function() {
		soy.renderElement(renderElement_, aws.templates.indicatorPanel, state_)
		comboBox_.render(G('#combobox'));
	}


};


var data = {
	'panelType': 'indicator',
	'comboOptions': ['CSVDataSource', 'Database'],
	'listOptions': ['option1', 'option2', 'option3']
};
var panel = new aws.Panel(data);


/*goog.exportSymbol('example.Panel', example.Panel);
goog.exportSymbol('example.Panel.prototype.getcolor', example.Panel.prototype.getcolor);

var panel = new example.Panel('green', 4);
window.console.log(goog.typeOf(panel.toString()));
window.console.log(panel.getcolor());*/