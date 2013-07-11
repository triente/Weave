goog.provide('weave.utils');

goog.require('weave.MyComponent');

/**
 * @param {number} numer
 * @param {number} denom
 */
weave.utils.myTestFunc = function(numer, denom) {
	var comp = new weave.MyComponent("this is my component", numer / denom);
	return comp.doSomething('doing something');
};
