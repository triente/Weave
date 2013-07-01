// This file was automatically generated from indicatorPanel.soy.
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
aws.templates.indicatorPanel = function(opt_data, opt_ignored, opt_ijData) {
  var output = '<div id="' + soy.$$escapeHtml(opt_data.panelID) + '" class="portlet"><div class="portlet-header">Indicators</div><div class="portlet-content">Data Source:<select id="combobox">';
  var optList6 = opt_data.comboOptions;
  var optListLen6 = optList6.length;
  for (var optIndex6 = 0; optIndex6 < optListLen6; optIndex6++) {
    var optData6 = optList6[optIndex6];
    output += '<option>' + soy.$$escapeHtml(optData6) + '</option>';
  }
  output += '</select>\r<input id="indicatorsInput" />\rIndicators:<select name="listPanel1" size="5" multiple="multiple" style="width: 80%; margin: auto;">';
  var optList12 = opt_data.listOptions;
  var optListLen12 = optList12.length;
  for (var optIndex12 = 0; optIndex12 < optListLen12; optIndex12++) {
    var optData12 = optList12[optIndex12];
    output += '<option>' + soy.$$escapeHtml(optData12) + '</option>';
  }
  output += '</select></div></div>';
  return output;
};


/**
 * @param {Object.<string, *>=} opt_data
 * @param {(null|undefined)=} opt_ignored
 * @param {Object.<string, *>=} opt_ijData
 * @return {string}
 * @notypecheck
 */
aws.templates.gridster = function(opt_data, opt_ignored, opt_ijData) {
  var output = '<div class="gridster"><ul>';
  var liList20 = opt_data.grid;
  var liListLen20 = liList20.length;
  for (var liIndex20 = 0; liIndex20 < liListLen20; liIndex20++) {
    var liData20 = liList20[liIndex20];
    output += '<li data-row="' + soy.$$escapeHtml(liData20.row) + '" data-col="' + soy.$$escapeHtml(liData20.col) + '" data-sizex="' + soy.$$escapeHtml(liData20.sizex) + '" data-sizey="' + soy.$$escapeHtml(liData20.sizey) + '"></li>';
  }
  output += '</ul></div></div>';
  return output;
};
