// This file was automatically generated from gridsterTemplate.soy.
// Please don't edit this file by hand.

goog.provide('aws.templates');

goog.require('soy');
goog.require('soydata');


/**
 * @param {Object.<string, *>=} opt_data
 * @param {(null|undefined)=} opt_ignored
 * @param {Object.<string, *>=} opt_ijData
 * @return {string}
 * @notypecheck
 */
aws.templates.gridster = function(opt_data, opt_ignored, opt_ijData) {
  var output = '<div class="gridster"><ul>';
  var liList4 = opt_data.grid;
  var liListLen4 = liList4.length;
  for (var liIndex4 = 0; liIndex4 < liListLen4; liIndex4++) {
    var liData4 = liList4[liIndex4];
    output += '<li data-row="' + soy.$$escapeHtml(liData4.row) + '" data-col="' + soy.$$escapeHtml(liData4.col) + '" data-sizex="' + soy.$$escapeHtml(liData4.sizex) + '" data-sizey="' + soy.$$escapeHtml(liData4.sizey) + '"></li>';
  }
  output += '</ul></div></div>';
  return output;
};
