(function ($) {
  $.layout.callbacks.resizeDataTables = function (x, ui) {
    // may be called EITHER from layout-pane.onresize OR tabs.show
    var oPane = ui.jquery ? ui[0] : ui.panel;
    // cannot resize if the pane is currently closed or hidden
    if ( !$(oPane).is(":visible") ) return;
    // find all data tables inside this pane and resize them
    $( $.fn.dataTable.fnTables(true) ).each(function (i, table) {
      if ($.contains( oPane, table )) {
        $(table).dataTable().fnAdjustColumnSizing(false);
        $("#accordion").accordion("refresh");
      }
    });
  };
})( jQuery );
