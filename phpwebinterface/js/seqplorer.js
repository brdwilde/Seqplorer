/*
 *	Create new SEQPLORER-object
 *	Usage: var SEQPLORER = new SEQPLORER('{user:"user@test.com",all_groups:['4c2209f9f3924d31102bd84a','4c2209fef3924d31102bd84b'],all_projects:['4c2209f9f3924d31102bd84a','4c2209fef3924d31102bd84b'],all_samples:['4c220a42f3924d31102bd856'],accordion:{"projects":0,"samples":1,"variants":2},tables:{datatables_tables_object},interface_vars:{height_correction:230,width_correction:67},job_config:{json_job_config_object},site_config:{json_site_config_object},tables:{'samples':{'view':'samples','collection','samples'},'projects':{'view':'projects','collection','projects'},'variants':{'view':'variants','collection','variants'}}}');
 */
function SEQPLORER(json_args){
	// get argurments from JSON-string
	var args					= eval('(' + json_args + ')');
	this.user					= args.user;
	this.all_groups				= args.all_groups;
	this.all_projects			= args.all_projects;
	this.all_samples			= args.all_samples;
	// selected projects-array
	this.projects				= [];
	this.select_object			= select_object;
	this.deselect_object		= deselect_object;
	this.deselect_object_all	= deselect_object_all;
	this.multi_select_all		= multi_select_all;
	// selected samples-array
	this.samples				= [];
	this.require				= [];
	this.exclude				= [];
	this.copy_sample			= copy_sample;
	// datatables table-objects
	this.tables					= args.tables;
	this.set_table_value		= set_table_value;
	this.custom_sort			= custom_sort;
	this.reset_af				= reset_af;
	// functions
	this.update_header			= update_header;
	// query
	this.build_query			= build_query;
	// submit job function
	this.submit_job				= submit_job;
	// general args
	this.accordion				= args.accordion;
	this.interface_vars			= args.interface_vars;
	this.site_config			= args.site_config;
	this.job_config				= args.job_config;
}
/*
 *	Add an object to the selected-array
 *	Usage: SEQPLORER.select_object('4bfa81198cf5fc1002a42b90', 'projects');
 */
function select_object(id, type){
	var all = 'all_'+type;
	var idstring = type+'id';

	// add object to selected-array
	this[type].push(id);

	$('.multi_select').each(function() {
		if ($(this).attr(idstring) == id){
			$(this).prop('checked', true);
		}
	});

	// update the headers
	this.update_header(type);
}
/*
 *	Remove an object from the selected-array
 *	Usage: SEQPLORER.deselect_object('4bfa81198cf5fc1002a42b91', 'samples');
 */
function deselect_object(id, type){
	var all = 'all_'+type;
	var idstring = type+'id';
	// remove object from selected-array
	this[type] = jQuery.grep(this[type], function(value) {
		return value != id;
	});
	// sample-> object-id needs to be removed from require/exclude-array
	if (type == 'samples'){
		this.require = jQuery.grep(this.require, function(value) {
			return value != id;
		});
		this.exclude = jQuery.grep(this.exclude, function(value) {
			return value != id;
		});
	}

	$('.multi_select').each(function() {
		if ($(this).attr(idstring) == id){
			$(this).prop('checked', false);
		}
	});

	// update the headers
	this.update_header(type);
}
/*
 *	Remove an object from the selected-array
 *	Usage: SEQPLORER.deselect_object_all('samples');
 */
function deselect_object_all(type){
	var idstring = type+'id';
	// remove object from selected-array
	this[type] = [];

	if (type == 'samples'){
		this.require = [];
		this.exclude = [];
	}

	$('.multi_select').each(function() {
		if ($(this).attr(idstring)){
			$(this).prop('checked', false);
		}
	});
	// update the headers
	var header_selector = '#'+type+'_header';
	var header = type.charAt(0).toUpperCase() + type.slice(1)+':';
	$(header_selector).html(header);

}
/*
 *	Make sure all multi_select elements are consistent with the SEQPLORER object
 *	Usage: SEQPLORER.multi_select_all();
 */
function multi_select_all(){
	var samples = this.samples;
	var projects = this.projects;
	$('.multi_select').each(function() {
		if ($.inArray($(this).attr('samplesid'), samples) > -1){
			$(this).prop('checked', true);
		} else if ($.inArray($(this).attr('projectsid'), projects) > -1){
			$(this).prop('checked', true);
		}
	});
}
/*
 *	Switch an object from one array to another
 *	Usage: SEQPLORER. copy_sample('4bfa81198cf5fc1002a42b91','required');
 */
function copy_sample(id,to){
	this[to].push(this['all_samples'][id]['_id']['$id']);

	this.update_header('samples');
}
/*
 *	Set value's of the table object
 *	Usage: SEQPLORER.set_table_value('variants', 'columns', 'columnsobject');
 */
function set_table_value(table, key, value){
	this.tables[table][key] = value;
}
/*
 *	Build a query given a certain table-view and selected groups/projects/samples
 *	Usage: SEQPLORER.build_query('samples');
 */
function build_query(table){
	var where = {};
	if (table == 'projects') {
		// create needed empty object(s) and array(s)
		if (Object.keys(this.all_groups).length){
			where['groups'] = {
				'id' : {
					'$in' : []
				}
			};
			// add groups to where-object
			$.each(this.all_groups, function(key, val){
				where['groups']['id']['$in'].push(key);
			});
		}
	}
	if (table == 'samples') {
		if (this.projects.length){
			// create needed empty object(s) and array(s)
			where['project'] = {
				'id' : {
					'$in' : []
				}
			};
			$.each(this.projects, function(key, val){
				where['project']['id']['$in'].push(val);
			});
		}
	}
	if (table == 'variants' || table == 'only_variants') {
		if (this.samples.length){
			// create needed empty object(s) and array(s)
			where['sa'] = {
				'id' : {
					'$in' : []
				}
			};
			// add selected samples to where-array
			$.each(this.samples, function(key, val){
				where['sa']['id']['$in'].push(val);
			});
		}
		// add required samples to where-array
		if (this.require.length){
			where['sa.id'] = {
				'$all' : []
			};
			$.each(this.require, function(key, val){
						where['sa.id']['$all'].push(val);
			});
		}
		if (this.exclude.length){
			if (where.hasOwnProperty("sa.id")){
				where['sa.id']['$nin'] = [];
			} else {
				where['sa.id'] = {
					'$nin' : []
				};
			}
			// add excluded samples to where-array
			$.each(this.exclude, function(key, val){
						where['sa.id']['$nin'].push(val);
			});
		}
	}

	// put where-array in query
	return (where);
}
/*
 *	Update header html to reflect object contents
 *	Usage: SEQPLORER.update_header('samples');
 */
function update_header(type){
	var all = 'all_'+type;

	// update the headers
	var header_selector = '#'+type+'_header';
	var header = type.charAt(0).toUpperCase() + type.slice(1)+':<i> ';
	var this_all = this[all];
	$.each(this[type], function(index, value) {
		header += this_all[value]['name']+' - ';
	});
	if (type == 'samples'){
		$.each(this.require, function(index, value) {
			header = header.replace(" "+this_all[value]['name']+" ", ' <font color="green">'+this_all[value]['name']+'</font> ');
		});
		$.each(this.exclude, function(index, value) {
			header = header.replace(" "+this_all[value]['name']+" ", ' <font color="red">'+this_all[value]['name']+'</font> ');
		});
	}
	this[all] = this_all;
	if (header.lastIndexOf("-") == -1){
		header = header.substr(0,header.length-4);
	}
	else {
		header = header.substr(0,header.length-3);
	}
	header += ' </i>';
	$(header_selector).html(header);
}
/*
 *	Submit jobs to php (curl)
 *	Usage: SEQPLORER.submit_job({script:'bitqc_rename_remove_sample.pl', config:{sampleid:'4bfa81198cf5fc1002a42b91',del:1}, message:'Your file has been removed successfully'});
 */
function submit_job(json_args){
	// Create config_id
	var date		= _get_date();
	var username	= this.user.substring(0,this.user.indexOf("@"));
	var args		= eval('(' + json_args + ')');
	var config		= this.job_config;
	// add additional script_config to general job_config
	$.each(args.config, function(key, val){
		config[key] = val;
	});
	config['config_id']	= date+'_'+username+'_rename_remove_sample';
	config['email_to']	= [this.user];
	// post to PHP
	$.post(
			SEQPLORER.site_config.qsubdeamon,
			{script: args.script, config:JSON.stringify(config)},
			function() {
				confirm(args.message);
			}
	);
}
/*
 *	Reset advanced_filtering on a table
 *	Usage: SEQPLORER.reset_af();
 */
function reset_af(){
	// clear all values from require and exclude array, this rebuilds the select array
	this.require = [];
	this.exclude = [];
	this.tables['variants']['filter'] = [];

	// update the headers
	this.update_header('samples');
}
/*
 *	Function to sort visible records in a table
 *	Usage: SEQPLORER.custom_sort(datatables_table, 1, 'asc');
 */
function custom_sort(table, column, direction){
	var index;
	var oSettings = this.tables[table_id].oTable[table_id].fnSettings();
	var table_id = table.attr('id');
	$.each(table.dataTableSettings,function(key,val){
		if (this.sInstance == table_id){
			index = key;
		}
	});
	// Only show alert if not all values are preloaded
	if (table.dataTableSettings[index].aoData.length != table.dataTableSettings[index]._iRecordsTotal){
		alert('Attention!\nOnly visible values are sorted!');
	}
	// Set bServerSide to false to prevent table from getting new records from database
	oSettings.oFeatures.bServerSide = false;
	// Sort loaded values based on direction
	if (direction == 'desc'){
		table.fnSort( [ [column,'desc'] ] );
	}
	else if (direction == 'asc'){
		table.fnSort( [ [column,'asc'] ] );
	}
	// Set bServerSide to true again to make sure table is working properly as before
	oSettings.oFeatures.bServerSide = true;
}

// igv websocket functions
// When the connection is open, send some data to the server
function onopen() {
	console.log ('connection open!');
	//connection.send('echo\r\n'); // Send the message 'Ping' to the server
}
function onclose() {
	console.log ('connection closed!');
	//connection.send('echo\r\n'); // Send the message 'Ping' to the server
}
// Log errors
function onerror(error) {
	console.log('WebSocket Error ' + error);
}
// Log messages from the server
function onmessage(e) {
	console.log('Server: ' + e.data);
}

/*
 *	Function to get current datetime in Y-m-d_H-i-s format
 *	Usage: _get_date();
 */
function _get_date(){
	var now = new Date();
	var mm = (now.getUTCMonth()+1).toString();
	var dd  = now.getUTCDate().toString();
	var min = now.getUTCMinutes().toString();
	var ss = now.getUTCSeconds().toString();
	// format date to yyyy-mm-dd_hh-ii-ss
	var date = now.getUTCFullYear()+"-"+(mm[1]?mm:"0"+mm[0])+"-"+(dd[1]?dd:"0"+dd[0])+"_"+now.getUTCHours()+"-"+(min[1]?min:"0"+min[0])+"-"+(ss[1]?ss:"0"+ss[0]);
	return date;
}