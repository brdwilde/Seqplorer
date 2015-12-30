
// Build the user interface
$(document).ready( function() {
	/////////////////////////////////////////////////////////////
	// MAIN WINDOW LAYOUT AND BUILDUP
	/////////////////////////////////////////////////////////////
	$(window).resize(function(){
		$(window).resize(function(){
			var width = $(window).width();
			// header resize to be checked
			$("#header").width(width);
			$("#page").width(width);
		});
	});

	$(function() {
		$( document ).tooltip({
			track: true
		});
	});

	// Create the main page user layout and set some attributes
	_table_create('projects');
	_table_create('samples');
	_table_create('variants');

	// Create an accordion in the center pane
	$centerAccordion = $("#accordion").accordion({
		heightStyle: "fill",
		icons: null
	});


	//////////////////////////
	// DATATABLES FUNCTIONS //
	//////////////////////////
	$("body").on("click", ".page_view", function(){
		var page_view = $(this).attr("pview");
		if (page_view == 'only_variants') {
			SEQPLORER.set_table_value("variants", "view", page_view);
			$("#table_variants").appendTo("#only_variants");
			$("#accordion").hide();
			var height = $("#page").height();
			$("#variants").parent('div.dataTables_scrollBody').css("height",550);
			$("#only_variants").show();
			$(".pv_variants").attr('samples', JSON.stringify(SEQPLORER.samples));
			SEQPLORER.deselect_object_all('samples');
			$(".pv_variants").show();
			$(".pv_normal").hide();
		}
		else if (page_view == 'variants') {
			SEQPLORER.set_table_value("variants", "view", page_view);
			SEQPLORER.deselect_object_all('samples');
			var samples = eval('(' + $(this).attr('samples') + ')');
			$.each(samples, function (index, value){
				console.log("TODO update function");
				SEQPLORER.select_object('samples', value);
			});
			$("#table_variants").appendTo("#accordion > div:last-of-type");
			$("#only_variants").hide();
			$("#accordion").show();
			$(".pv_variants").hide();
			$(".pv_normal").show();
		}
		delete SEQPLORER.tables['variants'].columns;
		_table_create("variants");
		return false;
	});

	// Row detail
	$("body").on("click", ".row_detail", function(){
		var variantid = $(this).attr('variantid');
		$.post(
			"variant/"+variantid,
			function(responseText){
				$('#showhide').html(responseText);
				$('#showhide').fadeIn('slow');
			}
		);
	});

	// Text filtering
	$("body").on("blur", ".textsearch", function(){
		var input = $(this);
		var search = $(this).attr("column");
		var table = $(this).parents().parents().parents().prev().children('table').attr("id");
		var value = '';
		if ($(this).val() !== ''){
			if ($('.ac_over').text() !== ''){
				value = '[{"value":"'+$('.ac_over').text()+'"}]';
			}
			else {
				value = '[{"value":"'+$(this).val()+'"}]';
			}
		}
		// Filter table
		SEQPLORER.tables[table].oTable.fnFilter( value, search );
	});

	// List filtering
	$("body").on("change", ".listsearch", function(){
		// Filter on the column (the index) of this element
		var search = $(this).attr("column");
		// with scrolling
		var table = $(this).parents().parents().parents().prev().children('table').attr("id");
		var value='';
		if ($(this).val()){
			value = '[{"value":"'+$(this).val()+'"}]';
		}
		SEQPLORER.tables[table].oTable.fnFilter( value, search );
	} );

	// Numerical filtering
	$("body").on("blur", ".numericalsearch", function(){
		// Check for operators and negative values
		if ($(this).val().toString().match(/^[\-><=]?\d*?.?\d*?([eE][+\-])?\d*$/)){
			var search = $(this).attr("column");
			// with scrolling
			var table = $(this).parents().parents().parents().prev().children('table').attr("id");
			var value='';
			// Check for operators '<', '>', '=', '>=', '<='
			if ($(this).val().toString().match(/^[><=]/)){
				var operator;
				var number;
				if ($(this).val().toString().match(/^(>=)+/)){
					operator = '$gte';
					number = $(this).val().slice(2);
				}
				else if ($(this).val().toString().match(/^(<=)+/)){
					operator = '$lte';
					number = $(this).val().slice(2);
				}
				else if ($(this).val().toString().match(/^(=)+/)){
					operator = '$in';
					number = $(this).val().slice(1);
				}
				else if ($(this).val().toString().match(/^(<)+/)){
					operator = '$lt';
					number = $(this).val().slice(1);
				}
				else if ($(this).val().toString().match(/^(>)+/)){
					operator = '$gt';
					number = $(this).val().slice(1);
				}
				value = '[{"value":"'+number+'","operator":"'+operator+'"}]';
			}
			else if ($(this).val()){
				value = '[{"value":"'+$(this).val()+'"}]';
			}
			SEQPLORER.tables[table].oTable.fnFilter( value, search );
		}
		// No numerical entry (with or without operators)
		else {
			alert ("Searching on this column is limited to numerical values! Examples:\n\n\t123\n\t12.34\n\t>12.34\n\t>0.5e-8");
		}
	});

	/////////////////////////////////////////////////////////////
	// MENUS
	/////////////////////////////////////////////////////////////

	// create a popup window with a form in it
	$("body").on("click", ".popup", function(){
		var action = $(this).attr("action");
		var data = { 'type':action };
		$('#showhide').html();
		if ($(this).attr('projectsid') && $(this).attr('projectsid') != '[]') {
			data.projects_id = $(this).attr('projectsid');
		}
		if ($(this).attr('samplesid') && $(this).attr('samplesid') != '[]') {
			data.samples_id = $(this).attr('samplesid');
		}
		if ($(this).attr('groups_id') && $(this).attr('groups_id') != '[]') {
			data.groups_id = $(this).attr('groups_id');
		}
		if ($(this).attr('user')) {
			data.user_id = $(this).attr('user');
		}
		if (action === 'advanced_filtering') {
			data.where = SEQPLORER.build_query('variants');
			data.filter = JSON.stringify(SEQPLORER.tables['variants'].filter);
			data.filter_md5id = $(this).attr("md5id");
			data.filter_name = $(this).attr("name");
			data.projects_id = SEQPLORER.projects;
		}
		if (action === 'load_view' || action === 'create_view' || action == 'save_view' || action == 'load_filter' || action == 'save_filter') {
			// data.filter = JSON.stringify(SEQPLORER.tables['variants'].filter);
			data.projects_id = SEQPLORER.projects;
			if ($(this).attr('view_id')) {
				data.view_id = $(this).attr('view_id');
			}
			if ($(this).attr('db_id')) {
				data.filter_id = $(this).attr('db_id');
			}
			if (action == 'load_view' || action == 'create_view' || action == 'save_view'){
				$('#view_opt').toggle();
			}
			else {
				$('#filter_opt').toggle();
			}
		}
		if (action == 'shiny' || action == 'coverage' || action == 'compare_variants' || action == 'map_reads' || action == 'call_variants'){
			if (data.samples_id === undefined) {
				var responseText = "You haven't selected any samples. Please select at leas one one to continue.";
				var form = "<a id='hidediv' href=''><img class='cancel_popup' src='img/back.png'></img></a>"+responseText;
				$('#showhide').html(form);
				$('#showhide').fadeIn('slow');
			}
			else {
				$.post(
					function(responseText){
						var form = "<a id='hidediv' href=''><img class='cancel_popup' src='img/back.png'></img></a>"+responseText;
						$('#showhide').html(form);
					}
				);
			}
			if (action == 'map_reads' || action == 'call_variants') {
				$('#jobs_opt').toggle();
			}	
		}
		else if (action == 'create_filter') {
			if ($(this).attr('db_id')) {
				data.filter_id = $(this).attr('db_id');
			}
			$.post(
				"new_forms.php",
				data,
				function(responseText){
					var form = "<a id='hidediv' href=''><img class='cancel_popup' src='img/back.png'></img></a>"+responseText;
					$('#showhide').html(form);
				}
			);
			$('#filter_opt').toggle();
			// $('#showhide').css('width','80%');
			// TODO: adjust form and page width
		}
		else {
			$.get(
				'forms/'+action,
				data,
				function(responseText){
					var form = responseText;
					$('#showhide').html(form);
				}
			);
		}

		if ( !($(this).attr("keep_visible"))){
			$('#showhide').fadeIn('slow');
		}
		return false;
	});
	// function to remove the popup
	$("body").on("click", "#hidediv", function(){
		$('#showhide').fadeOut('slow');
		$("#showhide").empty();
		$('#showhide').css({height:'auto'});
		$('#showhide').css({width:'auto'});
		return false;
	});
	// Make the showhide 'popup' dragable
	$('#showhide').draggable();

	// log a user in
	$("body").on("click", "#loginbutton", function(){
		var postdata = {};
		postdata.email = $('#user').val();
		postdata.password = $('#password').val();
		$.post(
			"login",
			postdata,
			function(responseText){
				if(!responseText.Success){
					$( '#messagearea' ).text( ' '+responseText.Message );
					$('.required').attr('style', "border-radius: 5px; border:#FF0000 1px solid;");
				} else {
					location.reload();
				}
			}
		);
		return false;
	});

	// log a user out
	$("body").on("click", ".logout", function(){
		$.get("logout");
		return false;
	});

	// settings choice menu
	$("body").on("click", ".settings", function(){
		var html = "<a id='hidediv' href=''><img class='cancel_popup' src='img/back.png'></img></a>";
		html += "<h4>Change your settings</h4>";
		html += "<ul>";
		html += "<li class='li_settings popup' keep_visible='1' action='user' >User settings</li>";
		html += "<li class='li_settings menu' type='groups' keep_visible='1'>Group settings</li>";
		html += "</ul>";
		$('#showhide').html(html);
		$('#showhide').fadeIn('slow');
		return false;
	});

	// groups settings and project management menu
	$("body").on("click", ".menu", function(){
		var type = $(this).attr('type');
		var html = "<a id='hidediv' href=''><img class='cancel_popup' src='img/back.png'></img></a>";
		if (type == 'projects'){
			html += "<h4>Manage your "+type+" & samples</h4>";
		}
		else {
			html += "<h4>Manage your "+type+"</h4>";
		}
		html += "<div id='"+type+"_menu'></div>";
		$('#showhide').html(html);
		$("#"+type+"_menu").jstree({
			"html_data" : {
				"ajax" : {
					"url" : "query/"+type+".php",
					"data" : function (n) {
						return { id : n.attr ? n.attr("id") : 0 };
					}
				}
			},
			"themes" : {
				"theme" : "smoothness",
				"icons" : false
			},
			"plugins" : [ "html_data", "ui", "themeroller" ]
		});
		$('#showhide').fadeIn('slow');
		return false;
	});

	// Logs choice menu
	$("body").on("click", ".logs", function(){
		$('#showhide').html();
		var action = $(this).attr("action");
		var data = { 'type':action };
		$.post(
			SEQPLORER.phpforms_url,
			data,
			function(responseText){
				var form = "<a id='hidediv' href=''><img class='cancel_popup' src='img/back.png'></img></a>"+responseText;
				$('#showhide').html(form);
			}
		);
		$('#showhide').fadeIn('slow');
		return false;
	});
	// Logs splitview
	$("body").on("click",".show_messages",function(){
		var id = $(this).attr('jobid');
		showRight('messages',id);
	});

	// Sortable return to initial state
	$("body").on("click",".clear_view",function(){
		$('#visible_columns').html($('#visible_columns').data('visible_columns'));
		$('#hidden_columns').html($('#hidden_columns').data('hidden_columns'));
		var vis_col = $( "#visible_columns" ).sortable( "toArray" );
		$.each(vis_col, function (index, value){
			vis_col[index] = eval('(' + value + ')');
			vis_col[index].bVisible = true;
		});
		var hid_col = $( "#hidden_columns" ).sortable( "toArray" );
		$.each(hid_col, function (index, value){
			hid_col[index] = eval('(' + value + ')');
			hid_col[index].bVisible = false;
		});
		var merged = $.merge(hid_col, vis_col);
		$("#col_string").val(JSON.stringify(merged));
		return false;
	});

	$("body").on("change", ".load_view", function(){
		//console.log($(this).val());
	});

	//////////////////////////////////////////////////////////////
	// functions to select groups, projects or samples
	//
	// depending on the atributes of the html element a certain
	// change will be made to the selected variables and the
	// tables will be redrawn
	//////////////////////////////////////////////////////////////

	// Select a single sample, project or group
	$("body").on("click", ".pane", function(){
		if ($(this).attr("showtable")){
			// the user has requested us to display this table
			var table = $(this).attr("showtable");
			$( "#accordion").accordion( "option","active", SEQPLORER.accordion[table] );
		}
		if ($(this).attr("samplesid")){
			// change the selected sample and redraw the variants table
			SEQPLORER.deselect_object_all('samples');
			SEQPLORER.select_object('samples',$(this).attr("samplesid"),$(this).attr("samplesname"));
			// reload variants table
			SEQPLORER.tables['variants'].oTable.fnDraw();
		}
		if ($(this).attr("projectsid")){
			// change the selected project and redraw the samples table
			SEQPLORER.deselect_object_all('projects');
			SEQPLORER.select_object('projects',$(this).attr("projectsid"),$(this).attr("projectsname"));
			if (!$(this).attr("samplesid")){
				SEQPLORER.deselect_object_all('samples');
			}
			// redraw samples table
			SEQPLORER.tables['samples'].oTable.fnDraw();
		}
		SEQPLORER.multi_select_all();
		return false;
	});

	// select multiple samples or projects with checkboxes and Update tables accordingly
	$("body").on("click", ".view_opts", function(){
		$('#view_opt').toggle();
		return false;
	});
	$("body").on("click", ".filter_opts", function(){
		$('#filter_opt').toggle();
		return false;
	});
	$("body").on("click", ".jobs_opt", function(){
		$('#jobs_opt').toggle();
		return false;
	});

	// Show dropdown options
	$("body").on("click", ".opts", function(){
		// Check if the image is inside a column header
		// If so, show options
		if ($(this).parent().is('th')){
			$(this).parent().find('#select_opt').toggle();
		}
		return false;
	});

	// multi select
	$("body").on("click", ".multi_select", function(){
		// Check for action (multiselect, deselect of inverse selection)
		if ($(this).attr('action') !== undefined) {
			var table_id = $(this).attr("table");
			var action = $(this).attr('action');
			// Run through all checkboxes in table
			var table;
			$.each($('#'+table_id).find('.multi_select'), function(){
				if ($(this).attr("samplesid")){
					if (action == 'select_all'){
						if ($.inArray($(this).attr("samplesid"), SEQPLORER.samples) == -1) {
							SEQPLORER.select_object('samples', $(this).attr("samplesid"), $(this).attr("samplesname"));
						}
					} else if (action == 'select_none') {
						SEQPLORER.deselect_object($(this).attr("samplesid"), 'samples');
					} else if (action == 'inverse') {
						if ($(this).prop('checked')){
							SEQPLORER.deselect_object($(this).attr("samplesid"), 'samples');
						} else {
							SEQPLORER.select_object('samples', $(this).attr("samplesid"), $(this).attr("samplesname"));
						}
					}
					table = 'variants';
				}
				if ($(this).attr("projectsid")){
					if (action == 'select_all'){
						if ($.inArray($(this).attr("projectsid"), SEQPLORER.projects) == -1) {
							SEQPLORER.select_object('projects', $(this).attr("projectsid"), $(this).attr("projectsname"));
						}
					} else if (action == 'select_none') {
						SEQPLORER.deselect_object($(this).attr("projectsid"), 'projects');
					} else if (action == 'inverse') {
						if ($(this).prop('checked')){
							SEQPLORER.deselect_object($(this).attr("projectsid"), 'projects');
						} else {
							SEQPLORER.select_object('projects', $(this).attr("projectsid"), $(this).attr("projectsname"));
						}
					}
					table = 'samples';
				}
			});
			SEQPLORER.tables[table].oTable.fnDraw();
			$("#"+table+"_header").parents('h3').effect("highlight", {"color":"#22222D"  }, 500);
			$(this).parent().parent("#select_opt").hide();
		}
		// No action is set (single checkbox)
		else {
			if ($(this).attr("samplesid")){
				if ($(this).prop('checked')){
					SEQPLORER.select_object('samples', $(this).attr("samplesid"), $(this).attr("samplesname") );
				} else {
					SEQPLORER.deselect_object($(this).attr("samplesid"), 'samples');
				}
				SEQPLORER.tables['variants'].oTable.fnDraw();
				$("#variants_header").parents('h3').effect("highlight", {"color":"#22222D"  }, 500);
			}
			if ($(this).attr("projectsid")){
				if ($(this).prop('checked')){
					SEQPLORER.select_object('projects', $(this).attr("projectsid"), $(this).attr("projectsname") );
				} else {
					SEQPLORER.deselect_object($(this).attr("projectsid"), 'projects');
				}
				SEQPLORER.tables['samples'].oTable.fnDraw();
				$("#samples_header").parents('h3').effect("highlight", { "color":"#22222D" }, 500);
			}
		}
	});

	// TODO: Visible records sorting
	$("body").on("click", ".custom_sort", function(){
		var table_id = $(this).attr("table");
		var col = $(this).attr("col");
		var direction = $(this).attr("direction");
		SEQPLORER.custom_sort(table_id, col, direction);
		if (direction == 'desc'){
			// Change arrow in column header
			$(this).css("background","url('css/jquery-ui-seqplorer/images/sort_desc.png') no-repeat center right");
			$(this).attr("direction",'asc');
		}
		else if (direction == 'asc'){
			// Change arrow in column header
			$(this).css("background","url('css/jquery-ui-seqplorer/images/sort_asc.png') no-repeat center right");
			$(this).attr("direction",'desc');
		}
	});

	// // Show hidden div ==> used for Q&A
	// $("body").on("click", ".clickMe", function(){
	// 	var id= $(this).attr("id");
	// 	var img = $(this).children("img");
	// 	if (img.is('.open') ){
	// 		img.attr("src","img/icon_tree_off.gif");
	// 		img.removeClass('open');
	// 	}
	// 	else {
	// 		img.attr("src","img/icon_tree_on.gif");
	// 		img.addClass('open');
	// 	}
	// 	$("#textBox_"+id).toggle('slow');
	// });

	// Create a new sample from selection
	// TODO: reveiw code and update to jFormer
	$("body").on("click", "#newsample", function(){
		alert("Comming soon!");
		// var url = $(this).attr("url");
		// var data = $("#form").serialize();
		// $.post(
			// url,
			// data,
			// function(responseText){
				// $("#showhide").html(responseText);
			// },
			// "html"
		// );
		// Hide if required
		// if ( $(this).attr("disappear") ){
			// setTimeout(function(){
				// $('#showhide').fadeOut('slow');
				// $("#showhide").html();
			// }
			// ,2000);
		// }
		return false;
	});

	// Link to IGV
	// $("body").on("click", ".igv", function(){
	// 	var data = {};
	// 	data.type = 'igv';			

	// 	if ($(this).attr('start')){
	// 		var chr = $(this).attr('chromosome');
	// 		var start = $(this).attr('start');

	// 		//appRequest(60151, '', '', 'true', 'chr'+chr+':'+start, '');
	// 	}
	// 	else if ($(this).attr('samplesid') && $(this).attr('samplesid') != "[]") {
	// 		data.samples_id = $(this).attr('samplesid');
	// 		$.post(
	// 			SEQPLORER.phpforms_url,
	// 			data,
	// 			function(responseText){
	// 				var form = "<a id='hidediv' href=''><img class='cancel_popup' src='img/back.png'></img></a>"+responseText;
	// 				$('#showhide').html(form);
	// 			}
	// 			);
	// 		$('#showhide').fadeIn('slow');
	// 	}
	// 	else {
	// 		var responseText = "You haven't selected any samples. Please select one or more to use IGV.";
	// 		var form = "<a id='hidediv' href=''><img class='cancel_popup' src='img/back.png'></img></a>"+responseText;
	// 		$('#showhide').html(form);
	// 		$('#showhide').fadeIn('slow');
	// 	}
	// 	return false;
	// });

	// Link to Ensembl
	// $("body").on("click", ".ensembl", function(){
	// 	var chr = $(this).attr('chromosome');
	// 	var start = $(this).attr('start');
	// 	var end = $(this).attr('end');
	// 	window.open('http://www.ensembl.org/Homo_sapiens/Location/Overview?r='+chr+':'+start+'-'+end);
	// });

	// Export table
	// TODO: review code and test
	$("body").on("click", ".export", function(){
		var action = $(this).attr("action");
		var table = $(this).attr('table');
		var index;
		var data = {};
		var records;
		// Get index from variants table (only exportable table);
		$.each(SEQPLORER.tables[table].oTable.dataTableSettings,function(key,val){
			if (this.sInstance == 'variants'){
				index = key;
				records = val.fnRecordsTotal();
			}
		});
		if (records === 0){
			alert('Your request has no results. You can\'t export an empty file.');
		}
		else {
			data.type = action;
			data.where = SEQPLORER.build_query(table);
			data.filter = SEQPLORER.tables[table].filter;

			$.post(
				SEQPLORER.phpforms_url,
				data,
				function(responseText){
					var form = "<a id='hidediv' href=''><img class='cancel_popup' src='img/back.png'></img></a>"+responseText;
					$('#showhide').html(form);
				}
			);
			$('#showhide').fadeIn('slow');
		}
	});

	// Rename, remove sample
	$("body").on("click", ".resample", function(){

		var action = $(this).attr("action");
		var del = $(this).attr("del");
		var data = {};
		if (del == "yes"){
			action = 'remove';
		}
		else {
			action = 'rename';
		}
		data.type = action;

		if ($(this).attr('sampleid')) {
			data.samples_id = $(this).attr('sampleid');
		}
		if ($(this).attr('samplename')) {
			data.old_sample = $(this).attr('samplename');
		}
		data.projects_id = JSON.stringify(SEQPLORER.projects);
		$.post(
			SEQPLORER.phpforms_url,
			data,
			function(responseText){
				var form = "<a id='hidediv' href=''><img class='cancel_popup' src='img/back.png'></img></a>"+responseText;
				$('#showhide').html(form);
			}
		);
		$('#showhide').fadeIn('slow');
	});

	//////////////////////////////////////////////////////////////
	// FUNCTIONS ATTACHED TO JFORMER FORMS
	//////////////////////////////////////////////////////////////

	// SAMPLE CREATE FUNCTIONS
	//////////////////////////

	// remove preloaded filter line
	// $("body").on("click", 'select[id^="samplefiletype"]', function(){
	// 	var selected = $(this).val();

	// 	var counter;
	// 	var matches = (" " + $(this).parent().attr('id') + " ").match(/\ssamplefiletype(\d+)-wrapper\s/);
	// 	if (matches) {
	// 		counter = parseInt(matches[1], 10);
	// 	}

	// 	if (selected === 'local'){
	// 		$('#file'+counter+'-wrapper').show();
	// 		$('#path'+counter+'-wrapper').hide();
	// 		$('#host'+counter+'-wrapper').hide();
	// 		$('#user'+counter+'-wrapper').hide();
	// 		$('#pass'+counter+'-wrapper').hide();
	// 		$('#compression'+counter+'-wrapper').show();
	// 		$('#filetype'+counter+'-wrapper').show();
	// 	} else if (selected === 'http'){
	// 		$('#file'+counter+'-wrapper').show();
	// 		$('#path'+counter+'-wrapper').hide();
	// 		$('#host'+counter+'-wrapper').show();
	// 		$('#user'+counter+'-wrapper').hide();
	// 		$('#pass'+counter+'-wrapper').hide();
	// 		$('#compression'+counter+'-wrapper').show();
	// 		$('#filetype'+counter+'-wrapper').show();
	// 	} else if (selected === 'ftp'){
	// 		$('#file'+counter+'-wrapper').show();
	// 		$('#path'+counter+'-wrapper').hide();
	// 		$('#host'+counter+'-wrapper').show();
	// 		$('#user'+counter+'-wrapper').hide();
	// 		$('#pass'+counter+'-wrapper').hide();
	// 		$('#compression'+counter+'-wrapper').show();
	// 		$('#filetype'+counter+'-wrapper').show();
	// 	} else if (selected === 'https'){
	// 		$('#file'+counter+'-wrapper').show();
	// 		$('#path'+counter+'-wrapper').hide();
	// 		$('#host'+counter+'-wrapper').show();
	// 		$('#user'+counter+'-wrapper').show();
	// 		$('#pass'+counter+'-wrapper').show();
	// 		$('#compression'+counter+'-wrapper').show();
	// 		$('#filetype'+counter+'-wrapper').show();
	// 	}

	// 	// update the page wrapper height
	// 	var pagewrapper = $('.jFormPageWrapper').height();
	// 	var height = $('#sample_file_type'+newcounter+'-wrapper').height() + $('.jFormPageWrapper').height() + 220;
	// 	$('.jFormPageWrapper').height(height);

	// 	// show the new input fields
	// 	var newcounter = Number(counter) + 1;
	// 	$('#filecounter'+newcounter).show();
	// 	$('#samplefiletype'+newcounter+'-wrapper').show();
	// 	$('.removefileline').attr('counter', newcounter);

	// 	return false;
	// });

	// // remove preloaded filter line
	// $("body").on("click", ".removefileline", function(){
	// 	var counter = $(this).attr('counter');
	// 	//$(this).remove();

	// 	$('#file'+counter+'-wrapper').remove();
	// 	$('#path'+counter+'-wrapper').remove();
	// 	$('#host'+counter+'-wrapper').remove();
	// 	$('#user'+counter+'-wrapper').remove();
	// 	$('#pass'+counter+'-wrapper').remove();
	// 	$('#compression'+counter+'-wrapper').remove();
	// 	$('#filetype'+counter+'-wrapper').remove();
	// });

	// $("body").on("click", ".form_folder", function(){
	// 	var img = $(this);
	// 	if (img.is('.open') ){
	// 		img.attr("src","img/icon_tree_on.gif");
	// 		img.removeClass('open');
	// 		img.next("#form_folder").toggle();
	// 		var height = img.next("#form_folder").height();
	// 		var total_height = $(".jFormPageWrapper").height()-height;
	// 		$(".jFormPageWrapper").height(total_height);
			
	// 	}
	// 	else {
	// 		img.attr("src","img/icon_tree_off.gif");
	// 		img.addClass('open');
	// 		var height = img.next("#form_folder").height();
	// 		var total_height = $(".jFormPageWrapper").height()+height;
	// 		$(".jFormPageWrapper").height(total_height);
	// 		img.next("#form_folder").toggle();
	// 	}
	// });


	// VIEWS FUNCTIONS
	///////////////////////////////

	// reset the view in the variants table
	$("body").on("click", ".reset_view", function(){
        $("#showhide").fadeOut("slow");
        $("#showhide").html();
        $('.header_button[title|="View options"]').removeAttr("name");
		$('.popup[action|="create_view"]').removeAttr("view_id");
		$('.popup[action|="load_view"]').removeAttr("view_id");
		$('.popup[action|="save_view"]').removeAttr("view_id");
		$('.view_opts').replaceWith('<img class="view_opts" src="img/transcript_view.png">');
		$('#view_opt').toggle();
        // SEQPLORER.reset_af();
        SEQPLORER.set_table_value("variants", "view", "variants");
        delete SEQPLORER.tables['variants'].columns;
		_table_create("variants");
        return false;
	});

	// ADVANCED FILTERING FUNCTIONS
	///////////////////////////////

	// reset the advanced filter in the variants table
	$("body").on("click", ".reset_filter", function(){
		var af_string = [];
        $("#showhide").fadeOut("slow");
        $("#showhide").html();
        $('.header_button[title|="Filter options"]').removeAttr("name");
        $('.popup[action|="create_filter"]').removeAttr("db_id");
        $('.popup[action|="save_filter"]').removeAttr("db_id");
        $('.filter_opts').replaceWith('<img class="filter_opts" src="img/af.png">');
        $('#filter_opt').toggle();
        SEQPLORER.reset_af();
        SEQPLORER.set_table_value("variants", "filter", af_string);
        _table_create("variants");
        return false;
	});


	// remove preloaded filter line
	$("body").on("click", ".remove_filter_line", function(){
		var counter = $(this).attr('counter');
		var prefix = '';
		if ($(this).attr('prefix')){
			var prefix = '_'+$(this).attr('prefix')+'_'; 
		}
		$(this).remove();
		$('#filter_column'+prefix+counter+'-wrapper').remove();
		$('#filter_operator'+prefix+counter+'-wrapper').remove();
		$('#filter_value'+prefix+counter+'-wrapper').remove();
		var height = $('.jFormPageWrapper').height() -18 - $('#filter_column'+prefix+counter+'-wrapper').height();
		$('.jFormPageWrapper').height(height);
	});

	// update the operator and value input fields depending on the selected column
	$("body").on("click", 'div[id^="filter_column"] .active-result', function(){
		// get the row_counter
		var id = $(this).parents('div[id^="filter_column"]').attr('id');
		var tmp_id = id.substring(0,id.lastIndexOf("_"));
		var tmp_prefix = tmp_id.substring(0,tmp_id.lastIndexOf("_"));
		var prefix = tmp_prefix.substring(tmp_prefix.lastIndexOf("_")+1);
		var counter = tmp_id.substring(tmp_id.lastIndexOf("_")+1);
		// get the selected element
		var selected = $('#filter_column_'+prefix+'_'+counter+' > option:eq('+$(this).attr('data-option-array-index')+')').val();
		var searchtype;
		var list;


		// search for the matching column and get the searchtype and list values
		$.each(SEQPLORER.tables.variants.columns, function (index, value){
			var json = JSON.stringify(value.queryname);
			if (json){
				json = json.replace(/"/g, "'");
			}
			if (json === selected){
				searchtype = value.searchtype;
				list  = value.list;
			}
		});
		// update the filter operator for this filter record
		var operator = $($('#filter_column_'+prefix+'_'+counter).parent().next().children()[0]);
		operator.empty();
		operator.append('<option value="$in">equals</option>');
		operator.append('<option value="$nin">not equals</option>');
		operator.append('<option value="$exists">exists</option>');
		operator.append('<option value="$notexists">does not exist</option>');
		if (searchtype === "numerical"){
			operator.append('<option value="$gt">greater than</option>');
			operator.append('<option value="$lt">less than</option>');
			operator.append('<option value="$gte">greater than or equals to</option>');
			operator.append('<option value="$lte">less than or equals to</option>');
		}

		// change the filter value form element
		operator.trigger("chosen:updated");

		// get the attributes of the filter element and remove the old one
		var value = $(operator.parent().next().children()[0]);
		var attributes = value.prop("attributes");
		// value.remove();
		var valuewrapper = $(operator.parent().next());
		valuewrapper.empty();
		// console.log(valuewrapper);
		if (list){
			// add the right jformer class to the wrapper
			valuewrapper.addClass( 'jFormComponentDropDown' );
			valuewrapper.removeClass('jFormComponentSingleLineText');
			valuewrapper.show();
			// create a new input element
			var sel = $('<select multiple="multiple" size="5" style="clear:none">').appendTo(valuewrapper);
			// add list elements
			$(list).each(function() {
				sel.append($("<option>").attr('value',this).text(this));
			});
			// loop through <select> attributes and apply them on <div>
			$.each(attributes, function() {
				if (this.name !== 'type' && this.name !== 'value' && this.name != 'style'){
					sel.attr(this.name, this.value);
				}
			});
			sel.addClass( 'jFormComponentDropDown' );
			sel.chosen({placeholder_text_multiple:"Select one or more values...",width:"143px;",search_contains:true});
		} else {
			// add the right jformer class to the wrapper
			valuewrapper.removeClass( 'jFormComponentDropDown' );
			valuewrapper.addClass('jFormComponentSingleLineText');
			valuewrapper.show();

			// create a new input element
			var input = $('<input type="text" style="clear:none"></input>').appendTo(valuewrapper);
			// loop through attributes and apply them on input
			$.each(attributes, function() {
				if (this.name !== 'type' && this.name !== 'value' && this.name != 'style'){
					input.attr(this.name, this.value);
				}
			});
			input.removeClass( 'jFormComponentDropDown' );
		}
	});

	// find the jformer filter operator elements
	$("body").on("click", 'div[id^="filter_operator"] .active-result', function(){
		// get the row_counter
		var id = $(this).parents('div[id^="filter_operator"]').attr('id');
		var tmp_id = id.substring(0,id.lastIndexOf("_"));
		var tmp_prefix = tmp_id.substring(0,tmp_id.lastIndexOf("_"));
		var prefix = tmp_prefix.substring(tmp_prefix.lastIndexOf("_")+1);
		var counter = tmp_id.substring(tmp_id.lastIndexOf("_")+1);
		// get the selected element value
		var selected = $('#filter_operator_'+prefix+'_'+counter+' > option:eq('+$(this).attr('data-option-array-index')+')').val();
		if ( selected ==='$exists' || selected === '$notexists'){
			$('#filter_operator_'+prefix+'_'+counter).parent().next("div").hide();
		} else {
			$('#filter_operator_'+prefix+'_'+counter).parent().next("div").show();
		}
	});

	// add filter line
	$("body").on("click", ".add_filter_line", function(){
		var counter = $(this).attr('counter');
		var newcounter = Number(counter) + 1;
		var prefix = '';
		if ($(this).attr('prefix')){
			var prefix = '_'+$(this).attr('prefix')+'_'; 
		}
		var j = 1;
		while ($('#filter_column'+prefix+(counter-j)+'_chosen').length === 0){
			j++;
		}
		var col_width = $('#filter_column'+prefix+(counter-j)+'_chosen').width();
		var op_width = $('#filter_operator'+prefix+(counter-j)+'_chosen').width();
		var val_width = $('#filter_value'+prefix+(counter-j)+'_chosen').width();
		// update the page wrapper height
		var height = $('#filter_column'+counter+'-wrapper').height() + $('.jFormPageWrapper').height() + 65;
		$('.jFormPageWrapper').height(height);

		// show the new input fields
		$('#filter_column'+prefix+counter+'-wrapper').show();
		$('#filter_column'+prefix+counter+'_chosen').width(col_width);
		$('#filter_operator'+prefix+counter+'-wrapper').show();
		$('#filter_operator'+prefix+counter+'_chosen').width(op_width);
		$('#filter_value'+prefix+counter+'-wrapper').show();
		$('#filter_value'+prefix+counter+'_chosen').width(val_width);
		$('#filter_remove'+prefix+counter).show();

		$(this).attr('counter', newcounter);
		return false;
	});

	// add mapper options line
	$("body").on("click", ".add_mo_line", function(){
		var counter = $(this).attr('counter');
		var newcounter = Number(counter) + 1;

		// update the page wrapper height
		var height = $('#mo_key_'+counter+'-wrapper').height() + $('.jFormPageWrapper').height() + 18;
		$('.jFormPageWrapper').height(height);

		// show the new input fields
		$('#mo_key_'+counter+'-wrapper').show();
		$('#mo_value_'+counter+'-wrapper').show();
		$('#mo_remove_'+counter).show();

		$(this).attr('counter', newcounter);
		return false;
	});
	// remove preloaded filter line
	$("body").on("click", ".remove_mo_line", function(){
		var counter = $(this).attr('counter');
		$(this).remove();
		$('#mo_key_'+counter+'-wrapper').remove();
		$('#mo_value_'+counter+'-wrapper').remove();
		var height = $('.jFormPageWrapper').height() -18 - $('#mo_key_'+counter+'-wrapper').height();
		$('.jFormPageWrapper').height(height);
	});


	$("body").on("click", ".add_genotype_filter", function(){
		var counter = $(this).attr('counter');
		var newcounter = Number(counter) + 1;
		// show div
		$('.per_sample_folder:eq('+counter+')').show();
		// get width from first (shown) element
		var col_width = $('.per_sample_folder:eq(0)').find('.chosen-container[id^="filter_column"]:eq(0)').width();
		var op_width = $('.per_sample_folder:eq(0)').find('.chosen-container[id^="filter_operator"]:eq(0)').width();
		// set width to newly shown element
		$('.per_sample_folder:eq('+counter+')').find('.chosen-container[id^="filter_column"]:eq(0)').width(col_width);
		$('.per_sample_folder:eq('+counter+')').find('.chosen-container[id^="filter_operator"]:eq(0)').width(op_width);
		// adjust counter attribute for further use
		$(this).attr('counter', newcounter);
		return false;
	});
	$("body").on("click", ".remove_genotype_filter", function(){
		$(this).parents('.per_sample_folder').remove();
	});

});

///////////////
// FUNCTIONS //
///////////////

// Create tables
////////////////

function _table_create(table) {
	// set some variables
	var view = SEQPLORER.tables[table].view; // the view on the database table the user requested
	console.log(view);

	// replace table with loader image when table is loading
	$('#table_'+table).html( "<img src='img/loader.gif' alt='loading...' />" );

	// Get the headers for this table
	if (!SEQPLORER.tables[table].hasOwnProperty('columns')){
		console.log("recreate table "+table);
		$.get(
			"view/"+SEQPLORER.tables[table].view,
			//{view:SEQPLORER.tables[table].view,collection:table,columns:"1"},
			function(response){
				// Add the columns post response to the global columns object
				SEQPLORER.set_table_value(table, 'columns', response.columns);
				SEQPLORER.set_table_value(table, 'dom', response.dom);
				SEQPLORER.set_table_value(table, 'columnfilter', response.columnfilter);
				SEQPLORER.set_table_value(table, 'colvis', response.colvis);
				//SEQPLORER.set_table_value(table, 'view', response.view);
				$.get(
					"table/"+table,
					function(response){
						$('#table_'+table).html( response );
						//$('.sparklines').sparkline('html', { enableTagOptions: true });
						_table_build(table);
					},
					"html"
				);
			},
			"json"
		);
	} else {
		console.log("refill table "+table);
		_table_build(table);
	}
}

function _table_build(table) {

	// Create the table object and fill it with data
	SEQPLORER.tables[table].oTable = $('#'+table).dataTable( {
		"bProcessing": true,
		"bServerSide": true,
		"iDisplayLength": 30,
		// "bSort": SEQPLORER.tables[table].sorting, !! there is no sorting response in the columns query?? where did this value come from?
		// "aaSorting":[[sorting, "desc"]],
		"bScrollInfinite": true,
		"bScrollCollapse": true,
		"bAutoWidth": true,
		// "sScrollY": $("#accordion").height()-SEQPLORER.interface_vars.height_correction,
		"sScrollX": "auto",
		"oColVis": {
			"buttonText": "Columns",
			// Exclude some columns from the list
			"aiExclude": SEQPLORER.tables[table].colvis
		},
		"sDom": SEQPLORER.tables[table].dom,
		"sAjaxSource": "query/"+table,
		"aoColumns": SEQPLORER.tables[table].columns,
		"fnDrawCallback": function ( oSettings ) {
			// Add button to reset normal filters
			if ($(".dataTables_scrollHeadInner .opts_th_"+table).children().length === 0){
				var html = "Select";
				html += "<img class='opts' title='Click to see options' src='img/options.png' /><div id='select_opt'><ul><li class='multi_select' action='select_all' id='all_"+table+"' table='"+table+"'>Select all</li><li class='multi_select' action='select_none' id='none_"+table+"' table='"+table+"'>Select none</li><li class='multi_select' action='inverse' id='inverse_"+table+"' table='"+table+"'>Inverse selection</li></ul></div>";
				$(".dataTables_scrollHeadInner .opts_th_"+table).html(html);
			}
			// Set background for custom sort to default
			$(".custom_sort").css("background","url('css/jquery-ui-seqplorer/images/sort_both.png') no-repeat center right");
			
			// Execute table-specific redraw functions
			// if (table == 'projects'){
			// 	var where = SEQPLORER.build_query(table); // TODO: this will always evaluate to true with the SEQPLORER object... other solution?
			// 	if (where){
			// 		$("#table_projects").show();
			// 		$("#welcome").hide();
			// 	} else {
			// 		$("#table_projects").hide();
			// 		$("#welcome").show();
			// 	}
			// }

			// add the sparkline elements
			$('.sparklines').sparkline('html', { enableTagOptions: true });

			oSettings.oScroll.sY = $("#accordion").height()-SEQPLORER.interface_vars.height_correction.variants;
			// Height correction to correctly show one result
			if ($("#"+table).height()<$("#accordion").height()-SEQPLORER.interface_vars.height_correction){
				if ($("#"+table).height() < 75){
					$("#"+table).parent('div.dataTables_scrollBody').css("height",75);
				}
				else {
					$("#"+table).parent('div.dataTables_scrollBody').css("height",$("#"+table).height());
				}
			} else {
				if (SEQPLORER.tables[table].view == 'variants'){
					$("#"+table).parent('div.dataTables_scrollBody').css("height",$("#accordion").height()-SEQPLORER.interface_vars.height_correction.variants);
				}
				else if(SEQPLORER.tables[table].view == 'only_variants'){
					$("#"+table).parent('div.dataTables_scrollBody').css("height",$("#accordion").height()-SEQPLORER.interface_vars.height_correction.only_variants);
				}
				else {
					$("#"+table).parent('div.dataTables_scrollBody').css("height",$("#accordion").height()-SEQPLORER.interface_vars.height_correction.other);
				}
			}

			// Set width of table if it is less than accordion width
			if ($("#"+table).parents('div.dataTables_scroll').children('div.dataTables_scrollHead').children('div.dataTables_scrollHeadInner').width()-15<=$("#accordion").width()){
				$("#"+table).parent("div.dataTables_scrollBody").children('table').css("width","100%");
				$("#"+table).parent("div.dataTables_scrollHeader").children('table').css("width","100%");
				$("#"+table).parent("div.dataTables_scrollFooter").children('table').css("width","100%");
			}
		},
		// Send additional data to backend
		"fnServerData": function ( sSource, aoData, fnCallback ) {
			var where = SEQPLORER.build_query(table);
			aoData.push(
				{"name": "collection", "value": table },
				{"name": "view", "value": SEQPLORER.tables[table].view },
				{"name": "where", "value": JSON.stringify(where) },
				{"name": "advanced_filter", "value": JSON.stringify(SEQPLORER.tables[table].filter) }
			);
			$.ajax( {
				"dataType": 'json',
				"type": "POST",
				"url": sSource,
				"data": aoData,
				"success": function(json){
					fnCallback(json);
				}
			} );
		}
	} );
	// add per column filtering
	if (table === 'variants'){
		SEQPLORER.tables[table].oTable.columnFilter({
			aoColumns: SEQPLORER.tables[table].columnfilter
		});
	}
}

// Formating function for row details
// function formatDetails ( table, row ){
// 	var aData = table.fnGetData( row );
// 	var table_id = table.attr("id");
// 	// Start construction details output
// 	var sOut = '{"html":"<table cellpadding=\\"5\\" cellspacing=\\"0\\" border=\\"0\\" style=\\"padding-left:50px;\\">';
// 	var chr,start,stop,id;
// 	var subtable;
// 	var subtable_array = [];
// 	$.each(SEQPLORER.tables[table_id].columns, function(index, value) {
// 		if (aData[index]){
// 			if (value.row_detail!==false){
// 				if (value.queryname[0] != 'sa' || value.queryname[1] == 'info') {
// 					if (value.row_detail){
// 						switch(value.row_detail.type){
// 							case 'link':
// 								var url = value.row_detail.url;
// 								if (value.row_detail.get){
// 									url = url+'?'+value.row_detail.get+'='+aData[index];
// 								}
// 								sOut += '<tr><td>'+value.sName+'</td><td><a href='+url+'  target=\\"_blank\\">'+aData[index]+'</a></td><tr>';
// 								break;
// 							case 'region':
// 								if (value.row_detail.reg_chr){
// 									chr = aData[index];
// 								} else if (value.row_detail.reg_start){
// 									start = aData[index];
// 								} else if (value.row_detail.reg_stop){
// 									stop = aData[index];
// 								}
// 								break;
// 							case 'subtable':
// 								subtable = value.row_detail.tablename;
// 								if (value.row_detail.columname){
// 									subtable_array.push ({ column : value.row_detail.columname, value :aData[index]});
// 								} else {
// 									subtable_array.push ({ column : value.queryname, value :aData[index]});
// 								}
// 								break;
// 							case 'id':
// 								id = aData[index];
// 								break;
// 							default:
// 								sOut += '<tr><td>'+value.sName+'</td><td>'+aData[index]+'</td></tr>';
// 						}
// 					} else {
// 						sOut += '<tr><td>'+value.sName+'</td><td>'+aData[index]+'</td></tr>';
// 					}
// 				}
// 			}
// 		}
// 	});
// 	if (chr && start && stop){
// 		sOut += '<tr><td>View region '+chr+':'+start+'-'+stop+' in:</td>';
// 		sOut +=	'<td><a href=http://www.ensembl.org/Homo_sapiens/Location/Overview?r='+chr+':'+start+'-'+stop+' target=\\"_blank\\" title=\\"Ensembl\\" ><img class=\\"linkout\\" src=\\"img/Ensembl.jpg\\" alt=\\"Ensembl\\"/></a>';
// 		sOut += '<a href=http://genome.ucsc.edu/cgi-bin/hgTracks?clade=mammal&org=Human&db=hg19&position=chr'+chr+':'+start+'-'+stop+' target=\\"_blank\\" title=\\"UCSC\\"><img class=\\"linkout\\" src=\\"img/UCSC.jpg\\" alt=\\"UCSC\\"/></a>';
// 		sOut += '<a href=http://www.ncbi.nlm.nih.gov/projects/mapview/maps.cgi?TAXID=9606&CHR='+chr+'&MAPS=ideogr,cntg-r,ugHs,genes['+start+'%3A'+stop+'] target=\\"_blank\\" title=\\"NCBI\\"><img class=\\"linkout\\" src=\\"img/NCBI.png\\" alt=\\"NCBI\\"/></a>';
// 		// sOut +=	'<a href=http://localhost:60151/goto?locus=chr'+chr+':'+start+'-'+stop+'&merge=true ><img class=\\"linkout\\" src=\\"img/IGV_32.png\\" alt=\\"IGV\\"/></a></td>';
// 		sOut += '</tr>';
// 		// sOut += '<tr><td>Goldmine literature search:</td>';
// 		// sOut +=	'<td><a href=http://www.nxtvat.org/goldmine/search/'+id+' target=\\"_blank\\"><img class=\\"linkout\\" src=\\"http://www.nxtvat.org/goldmine/img/goldmine.png\\" alt=\\"GoldMine\\"/></a></td>';
// 		// sOut += '</tr>';
// 	}
// 	sOut += '</table>';
// 	// Create subtable in details view if specified
// 	if (subtable){
// 		oWhere[subtable] = subtable_array;
// 		sOut += '<div id=\\"table_'+subtable+'\\">';
// 		sOut += '</div>","subtable":"'+subtable+'"}';
// 	} else {
// 		sOut += '"}';
// 	}
// 	// Return details output
// 	return sOut;
// }



// Jformer response functions
/////////////////////////////

// function messageFade ( message ){
// 	$("#showhide").html(message);
// 	setTimeout(
// 		function(){
// 			$("#showhide").fadeOut("slow");
// 			$("#showhide").html();
// 		},
// 		2000
// 	);
// 	reload("1000");
// }

// function advancedFilter ( name, md5id, jsonsamples, jsonfilter ){
// 	$('.popup[action|="advanced_filtering"]').attr("name",name);
// 	$('.popup[action|="advanced_filtering"]').attr("md5id",md5id);
//     $('.popup[action|="advanced_filtering"]').html("<div><img src=\"img/af_en.png\"> "+name+"</div>");
//     $("#showhide").fadeOut("slow");
//     var samples = $.parseJSON(jsonsamples);
//     var filter = $.parseJSON(jsonfilter);
//     SEQPLORER.require=[];
//     SEQPLORER.exclude=[];
//     $.each(samples,function(key,value){
//         if(key=="$all"){
//             $.each(value,function(k,v){
//                 SEQPLORER.copy_sample(v,"require");
//             });
//         } else if (key=="$nin") {
//             $.each(value,function(k,v){
//                 SEQPLORER.copy_sample(v,"exclude");
//             });
//         }
//     });
//     SEQPLORER.tables["variants"].filter = filter;
//     _table_create("variants");
// }

// function newAdvancedFilter ( name, db_id, jsonfilter ){
// 	var display_name = '';
// 	if(name == ''){
// 		display_name = 'UNSAVED';
// 	}
// 	else {
// 		display_name = name;
// 	}
// 	$('.header_button[title|="Filter options"]').attr("name",display_name);
// 	$('.popup[action|="create_filter"]').attr("db_id",db_id);
// 	$('.popup[action|="save_filter"]').attr("db_id",db_id);
// 	$('.popup[action|="load_filter"]').attr("db_id",db_id);
//     $('.filter_opts').replaceWith('<div class="filter_opts"><img src="img/af_en.png"> '+display_name+'</div>');
//     $("#showhide").fadeOut("slow");
//     var filter = $.parseJSON(jsonfilter);
//     SEQPLORER.tables["variants"].filter = filter;
//     _table_create("variants");
// }

// function applyView (name, view_id) {
// 	$('.header_button[title|="View options"]').attr("name",name);
// 	$('.popup[action|="create_view"]').attr("view_id",view_id);
// 	$('.popup[action|="load_view"]').attr("view_id",view_id);
// 	$('.popup[action|="save_view"]').attr("view_id",view_id);
// 	$('.view_opts').replaceWith('<div class="view_opts"><img src="img/transcript_view_en.png"> '+name+'</div>');
// 	$("#showhide").fadeOut("slow");
// 	SEQPLORER.set_table_value("variants", "view", view_id);
// 	delete SEQPLORER.tables['variants'].columns;
// 	_table_create("variants");
// }

// function showPlot(title, link){
// 	var width = $(window).width()*0.90;
// 	var height = $(window).height()*0.70;
// 	var content = "<a id='hidediv' href=''><img class='cancel_popup' src='img/back.png'></img></a><p class='plot_title'>"+title+"</p>";
// 	content += "<iframe id='plot' src='"+link+"' width='"+width+"' height='"+height+"' frameBorder='0'></iframe>";
// 	$("#showhide").html(content);
// }

// // Splitter functions
// //////////////////////////////////

// function showRight(rightdiv, id, dontslideright) {
// 	$.post(
// 		"query/logs.php",
// 		{jobid:id},
// 		function(responseText){
// 			var form = responseText;
// 			$('#messages').html(form);
// 		}
// 	);
// 	$('#content').simplesplitview('showRight', rightdiv, dontslideright);
// }
