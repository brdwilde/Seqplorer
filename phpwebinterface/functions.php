<?php
/* This function checks for page authentication
 * If no user is authenticated yet the guest user will be used
 */

function authenticate() {
	// check to make sure the session variable is registered
	if(!(isset($_SESSION['email']))){
		// specify config paths
		$currentpath = getcwd()."/";
		$configpath = array( 0=>$currentpath, 1=>"/etc/nxtvat/", 2=>"/etc/apache2/nxtvat/");
		// search the configuration paths for a config file
		// the first file found wil become the config file
		$searchpath='';
		foreach ($configpath as $path) {
			if (!isset($_SESSION['config'])){
				$searchpath = $searchpath." ".$path;
				if (file_exists($path."config.xml")){
					if (is_writable($path."config.xml")){
						// security risk! warn the user
						die ("Found config file ".$path."config.xml, but it is writable!!! Please fix this security flaw!!!");
					} else {
						$_SESSION['config'] = $path."config.xml";
					}
				}
			}
		}
		if (!isset($_SESSION['config'])){
			die ("No config file found in ".$searchpath.". Please create one.");
		}
		//login as guest
		$_SESSION['email'] = strtoupper("guest@seqplorer.org");
		$_SESSION['password'] = md5("guest");
		$_SESSION['active'] = 1;
		$_SESSION['currentpath'] = $currentpath;
		$_SESSION['credentials'] = xmlobj2arr(read_credentials($_SESSION['config']));
	}
}

// function to get configuration directives from an xml file
function read_credentials($filename){
	if (file_exists($filename)) {
		$credentials = simplexml_load_file($filename);
	}
	else {
		die ("Could not read file ".$filename);
	}
	return $credentials;
}
// Convert an array to string
function array_to_string($array){
	foreach ($array as $key => $value){
		if (is_array($value)){
			$result[$key] = array_to_string($value);
		}
		else {
			$result = gettype($value);
		}
	}
	return $result;
}

// function to connect to a MongoDB-database given certain credentials
function connect_mongo(){
	$m = new Mongo();
#	$db = $m->nxtseq;
	$db = $m->$_SESSION['credentials']['database'];
	return $db;
}

// function to set the mongo collections to use
function get_collections($db){
	// $collections['news'] = $db->$_SESSION['credentials']['collections']['news'];
	// $collections['faq'] = $db->$_SESSION['credentials']['collections']['faq'];
	$collections['adv_filter'] = $db->$_SESSION['credentials']['collections']['adv_filter'];
	// $collections['bugs'] = $db->$_SESSION['credentials']['collections']['bugs'];
	$collections['configurations'] = $db->$_SESSION['credentials']['collections']['configurations'];
	$collections['counts'] = $db->$_SESSION['credentials']['collections']['counts'];
	$collections['genome'] = $db->$_SESSION['credentials']['collections']['genome'];
	$collections['groups'] = $db->$_SESSION['credentials']['collections']['groups'];
	$collections['log'] = $db->$_SESSION['credentials']['collections']['log'];
	$collections['plots'] = $db->$_SESSION['credentials']['collections']['plots'];
	$collections['projects'] = $db->$_SESSION['credentials']['collections']['projects'];
	$collections['samples'] = $db->$_SESSION['credentials']['collections']['samples'];
	$collections['servers'] = $db->$_SESSION['credentials']['collections']['servers'];
	$collections['users'] = $db->$_SESSION['credentials']['collections']['users'];
	$collections['variants'] = $db->$_SESSION['credentials']['collections']['variants'];
	$collections['variants_unique'] = $db->$_SESSION['credentials']['collections']['variants_unique'];
	$collections['vcfheader'] = $db->$_SESSION['credentials']['collections']['vcfheader'];
	$collections['views'] = $db->$_SESSION['credentials']['collections']['views'];

	return $collections;
}

// Recreate MongoIds after they've been past as string
function create_mongo_id($val){
	if(is_array($val)){
		foreach ($val as $key => $value){
			$id[$key] = create_mongo_id($value);
		}
	}
	else {
		$id = new MongoId($val);
	}
	return $id;
}

// Create a table based on an array
// Used for variant ID-popup
function create_table($order,$data, $headers){
	foreach($data as $key => $val){
		$rest = array();
		foreach ($val as $val_key => $val_value) {
			if ($val_key != $order) {
				$rest[$val_key] = $val_value;
			}
			$ordered_data[$val[$order]][$key] = $rest;
		}
	}
	$table = "<table id='border_table'><tr class='header_row'>";
	foreach ($headers as $key => $value) {
		if ($key == $order){
			$first .= "<th>".$value."</th>";
		}
		else {
			$follow .= "<th>".$value."</th>";
		} 		
	}
	$table .= $first.$follow;
	$table .= "</tr>";
	$row_key = 'odd';
	foreach ($ordered_data as $key => $value) {
		$old_key = '';
		foreach ($value as $value_key => $value_val){
			if ($row_key == 'odd') {
				$table .= "<tr>";
				$row_key = 'even';
			} 
			else {
				$table .= "<tr class='even_row'>";
				$row_key = 'odd';
			}
			
			if ($key != $old_key){
				$table .= "<td>".$key."</td>";
			}
			else {
				$table .= "<td></td>";
			}
			foreach ($headers as $h_key => $h_value) {
				if ($h_key != $order){
					if (is_array($value_val[$h_key])) {
						$row ="";
						foreach ($value_val[$h_key] as $last_key => $last_value) {
							if ($row_key == 'odd') {
								$row .= "<td>".$last_value."</td></tr><tr><td></td><td></td>";
								$row_key = 'even';
							} 
							else {
								$row .= "<td>".$last_value."</td></tr><tr class='even_row'><td></td><td></td>";
								$row_key = 'odd';
							}	
						}
						// remove empty row at the end of the table
						if ($row_key == 'odd') {
							// remove <tr class='even_row'><td></td><td></td>
							$row = substr($row,0,-39);
						} 
						else {
							// remove <tr><td></td><td></td>
							$row = substr($row,0,-22);
						}
						$table .= $row;
					} else {
						$table .= "<td>".$value_val[$h_key]."</td>";	
					}
				}
			}
			$table .= "</tr>";
			$old_key = $key;
		}
	}
	$table .="</table>";
	echo $table;
}

// Function to collect data from an XML-object and convert it to an array
function xmlobj2arr($Data) {
	if (is_object($Data)) {
		foreach (get_object_vars($Data) as $key => $val) {
			if ($val=="true"){
				$val = true;
			} elseif ($val=="false"){
				$val = false;
			}
			$ret[$key] = xmlobj2arr($val);
		}
		return $ret;
	} elseif (is_array($Data)) {
		foreach ($Data as $key => $val) {
			if ($val=="true"){
				$val = true;
			} elseif ($val=="false"){
				$val = false;
			}
			$ret[$key] = xmlobj2arr($val);
		}
		return $ret;
	} else {
		return $Data;
	}
}

// Function to check if two arrays are equal
function arrays_equal($array1, $array2){

}

/*
 * Function to generate a random password
 */
function generatePassword ($length = 8)
{

	// start with a blank password
	$password = "";

	// define possible characters - any character in this string can be
	// picked for use in the password, so if you want to put vowels back in
	// or add special characters such as exclamation marks, this is where
	// you should do it
	$possible = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

	// we refer to the length of $possible a few times, so let's grab it now
	$maxlength = strlen($possible);

	// check for length overflow and truncate if necessary
	if ($length > $maxlength) {
		$length = $maxlength;
	}

	// set up a counter for how many characters are in the password so far
	$i = 0;

	// add random characters to $password until $length is reached
	while ($i < $length) {

		// pick a random character from the possible ones
		$char = substr($possible, mt_rand(0, $maxlength-1), 1);

		// have we already used this character in $password?
		if (!strstr($password, $char)) {
			// no, so it's OK to add it onto the end of whatever we've already got...
			$password .= $char;
			// ... and increase the counter by one
			$i++;
		}

	}

	// done!
	return $password;

}


// Set up a list of all countries
function country_list(){
	$countries = array();
	array_push($countries, array ('value' => '','label' => ' - Select country - ','disabled' => true,'selected' => true,));
	array_push($countries, array('value'=>"AF",'label'=>"Afghanistan"));
	array_push($countries, array('value'=>"AX",'label'=>"Åland Islands"));
	array_push($countries, array('value'=>"AL",'label'=>"Albania"));
	array_push($countries, array('value'=>"DZ",'label'=>"Algeria"));
	array_push($countries, array('value'=>"AS",'label'=>"American Samoa"));
	array_push($countries, array('value'=>"AD",'label'=>"Andorra"));
	array_push($countries, array('value'=>"AO",'label'=>"Angola"));
	array_push($countries, array('value'=>"AI",'label'=>"Anguilla"));
	array_push($countries, array('value'=>"AQ",'label'=>"Antarctica"));
	array_push($countries, array('value'=>"AG",'label'=>"Antigua and Barbuda"));
	array_push($countries, array('value'=>"AR",'label'=>"Argentina"));
	array_push($countries, array('value'=>"AM",'label'=>"Armenia"));
	array_push($countries, array('value'=>"AW",'label'=>"Aruba"));
	array_push($countries, array('value'=>"AU",'label'=>"Australia"));
	array_push($countries, array('value'=>"AT",'label'=>"Austria"));
	array_push($countries, array('value'=>"AZ",'label'=>"Azerbaijan"));
	array_push($countries, array('value'=>"BS",'label'=>"Bahamas"));
	array_push($countries, array('value'=>"BH",'label'=>"Bahrain"));
	array_push($countries, array('value'=>"BD",'label'=>"Bangladesh"));
	array_push($countries, array('value'=>"BB",'label'=>"Barbados"));
	array_push($countries, array('value'=>"BY",'label'=>"Belarus"));
	array_push($countries, array('value'=>"BE",'label'=>"Belgium"));
	array_push($countries, array('value'=>"BZ",'label'=>"Belize"));
	array_push($countries, array('value'=>"BJ",'label'=>"Benin"));
	array_push($countries, array('value'=>"BM",'label'=>"Bermuda"));
	array_push($countries, array('value'=>"BT",'label'=>"Bhutan"));
	array_push($countries, array('value'=>"BO",'label'=>"Bolivia"));
	array_push($countries, array('value'=>"BA",'label'=>"Bosnia and Herzegovina"));
	array_push($countries, array('value'=>"BW",'label'=>"Botswana"));
	array_push($countries, array('value'=>"BV",'label'=>"Bouvet Island"));
	array_push($countries, array('value'=>"BR",'label'=>"Brazil"));
	array_push($countries, array('value'=>"IO",'label'=>"British Indian Ocean Territory"));
	array_push($countries, array('value'=>"BN",'label'=>"Brunei Darussalam"));
	array_push($countries, array('value'=>"BG",'label'=>"Bulgaria"));
	array_push($countries, array('value'=>"BF",'label'=>"Burkina Faso"));
	array_push($countries, array('value'=>"BI",'label'=>"Burundi"));
	array_push($countries, array('value'=>"KH",'label'=>"Cambodia"));
	array_push($countries, array('value'=>"CM",'label'=>"Cameroon"));
	array_push($countries, array('value'=>"CA",'label'=>"Canada"));
	array_push($countries, array('value'=>"CV",'label'=>"Cape Verde"));
	array_push($countries, array('value'=>"KY",'label'=>"Cayman Islands"));
	array_push($countries, array('value'=>"CF",'label'=>"Central African Republic"));
	array_push($countries, array('value'=>"TD",'label'=>"Chad"));
	array_push($countries, array('value'=>"CL",'label'=>"Chile"));
	array_push($countries, array('value'=>"CN",'label'=>"China"));
	array_push($countries, array('value'=>"CX",'label'=>"Christmas Island"));
	array_push($countries, array('value'=>"CC",'label'=>"Cocos (Keeling) Islands"));
	array_push($countries, array('value'=>"CO",'label'=>"Colombia"));
	array_push($countries, array('value'=>"KM",'label'=>"Comoros"));
	array_push($countries, array('value'=>"CG",'label'=>"Congo"));
	array_push($countries, array('value'=>"CD",'label'=>"Congo, The Democratic Republic of The"));
	array_push($countries, array('value'=>"CK",'label'=>"Cook Islands"));
	array_push($countries, array('value'=>"CR",'label'=>"Costa Rica"));
	array_push($countries, array('value'=>"CI",'label'=>"Cote D'ivoire"));
	array_push($countries, array('value'=>"HR",'label'=>"Croatia"));
	array_push($countries, array('value'=>"CU",'label'=>"Cuba"));
	array_push($countries, array('value'=>"CY",'label'=>"Cyprus"));
	array_push($countries, array('value'=>"CZ",'label'=>"Czech Republic"));
	array_push($countries, array('value'=>"DK",'label'=>"Denmark"));
	array_push($countries, array('value'=>"DJ",'label'=>"Djibouti"));
	array_push($countries, array('value'=>"DM",'label'=>"Dominica"));
	array_push($countries, array('value'=>"DO",'label'=>"Dominican Republic"));
	array_push($countries, array('value'=>"EC",'label'=>"Ecuador"));
	array_push($countries, array('value'=>"EG",'label'=>"Egypt"));
	array_push($countries, array('value'=>"SV",'label'=>"El Salvador"));
	array_push($countries, array('value'=>"GQ",'label'=>"Equatorial Guinea"));
	array_push($countries, array('value'=>"ER",'label'=>"Eritrea"));
	array_push($countries, array('value'=>"EE",'label'=>"Estonia"));
	array_push($countries, array('value'=>"ET",'label'=>"Ethiopia"));
	array_push($countries, array('value'=>"FK",'label'=>"Falkland Islands (Malvinas)"));
	array_push($countries, array('value'=>"FO",'label'=>"Faroe Islands"));
	array_push($countries, array('value'=>"FJ",'label'=>"Fiji"));
	array_push($countries, array('value'=>"FI",'label'=>"Finland"));
	array_push($countries, array('value'=>"FR",'label'=>"France"));
	array_push($countries, array('value'=>"GF",'label'=>"French Guiana"));
	array_push($countries, array('value'=>"PF",'label'=>"French Polynesia"));
	array_push($countries, array('value'=>"TF",'label'=>"French Southern Territories"));
	array_push($countries, array('value'=>"GA",'label'=>"Gabon"));
	array_push($countries, array('value'=>"GM",'label'=>"Gambia"));
	array_push($countries, array('value'=>"GE",'label'=>"Georgia"));
	array_push($countries, array('value'=>"DE",'label'=>"Germany"));
	array_push($countries, array('value'=>"GH",'label'=>"Ghana"));
	array_push($countries, array('value'=>"GI",'label'=>"Gibraltar"));
	array_push($countries, array('value'=>"GR",'label'=>"Greece"));
	array_push($countries, array('value'=>"GL",'label'=>"Greenland"));
	array_push($countries, array('value'=>"GD",'label'=>"Grenada"));
	array_push($countries, array('value'=>"GP",'label'=>"Guadeloupe"));
	array_push($countries, array('value'=>"GU",'label'=>"Guam"));
	array_push($countries, array('value'=>"GT",'label'=>"Guatemala"));
	array_push($countries, array('value'=>"GG",'label'=>"Guernsey"));
	array_push($countries, array('value'=>"GN",'label'=>"Guinea"));
	array_push($countries, array('value'=>"GW",'label'=>"Guinea-bissau"));
	array_push($countries, array('value'=>"GY",'label'=>"Guyana"));
	array_push($countries, array('value'=>"HT",'label'=>"Haiti"));
	array_push($countries, array('value'=>"HM",'label'=>"Heard Island and Mcdonald Islands"));
	array_push($countries, array('value'=>"VA",'label'=>"Holy See (Vatican City State)"));
	array_push($countries, array('value'=>"HN",'label'=>"Honduras"));
	array_push($countries, array('value'=>"HK",'label'=>"Hong Kong"));
	array_push($countries, array('value'=>"HU",'label'=>"Hungary"));
	array_push($countries, array('value'=>"IS",'label'=>"Iceland"));
	array_push($countries, array('value'=>"IN",'label'=>"India"));
	array_push($countries, array('value'=>"ID",'label'=>"Indonesia"));
	array_push($countries, array('value'=>"IR",'label'=>"Iran, Islamic Republic of"));
	array_push($countries, array('value'=>"IQ",'label'=>"Iraq"));
	array_push($countries, array('value'=>"IE",'label'=>"Ireland"));
	array_push($countries, array('value'=>"IM",'label'=>"Isle of Man"));
	array_push($countries, array('value'=>"IL",'label'=>"Israel"));
	array_push($countries, array('value'=>"IT",'label'=>"Italy"));
	array_push($countries, array('value'=>"JM",'label'=>"Jamaica"));
	array_push($countries, array('value'=>"JP",'label'=>"Japan"));
	array_push($countries, array('value'=>"JE",'label'=>"Jersey"));
	array_push($countries, array('value'=>"JO",'label'=>"Jordan"));
	array_push($countries, array('value'=>"KZ",'label'=>"Kazakhstan"));
	array_push($countries, array('value'=>"KE",'label'=>"Kenya"));
	array_push($countries, array('value'=>"KI",'label'=>"Kiribati"));
	array_push($countries, array('value'=>"KP",'label'=>"Korea, Democratic People's Republic of"));
	array_push($countries, array('value'=>"KR",'label'=>"Korea, Republic of"));
	array_push($countries, array('value'=>"KW",'label'=>"Kuwait"));
	array_push($countries, array('value'=>"KG",'label'=>"Kyrgyzstan"));
	array_push($countries, array('value'=>"LA",'label'=>"Lao People's Democratic Republic"));
	array_push($countries, array('value'=>"LV",'label'=>"Latvia"));
	array_push($countries, array('value'=>"LB",'label'=>"Lebanon"));
	array_push($countries, array('value'=>"LS",'label'=>"Lesotho"));
	array_push($countries, array('value'=>"LR",'label'=>"Liberia"));
	array_push($countries, array('value'=>"LY",'label'=>"Libyan Arab Jamahiriya"));
	array_push($countries, array('value'=>"LI",'label'=>"Liechtenstein"));
	array_push($countries, array('value'=>"LT",'label'=>"Lithuania"));
	array_push($countries, array('value'=>"LU",'label'=>"Luxembourg"));
	array_push($countries, array('value'=>"MO",'label'=>"Macao"));
	array_push($countries, array('value'=>"MK",'label'=>"Macedonia, The Former Yugoslav Republic of"));
	array_push($countries, array('value'=>"MG",'label'=>"Madagascar"));
	array_push($countries, array('value'=>"MW",'label'=>"Malawi"));
	array_push($countries, array('value'=>"MY",'label'=>"Malaysia"));
	array_push($countries, array('value'=>"MV",'label'=>"Maldives"));
	array_push($countries, array('value'=>"ML",'label'=>"Mali"));
	array_push($countries, array('value'=>"MT",'label'=>"Malta"));
	array_push($countries, array('value'=>"MH",'label'=>"Marshall Islands"));
	array_push($countries, array('value'=>"MQ",'label'=>"Martinique"));
	array_push($countries, array('value'=>"MR",'label'=>"Mauritania"));
	array_push($countries, array('value'=>"MU",'label'=>"Mauritius"));
	array_push($countries, array('value'=>"YT",'label'=>"Mayotte"));
	array_push($countries, array('value'=>"MX",'label'=>"Mexico"));
	array_push($countries, array('value'=>"FM",'label'=>"Micronesia, Federated States of"));
	array_push($countries, array('value'=>"MD",'label'=>"Moldova, Republic of"));
	array_push($countries, array('value'=>"MC",'label'=>"Monaco"));
	array_push($countries, array('value'=>"MN",'label'=>"Mongolia"));
	array_push($countries, array('value'=>"ME",'label'=>"Montenegro"));
	array_push($countries, array('value'=>"MS",'label'=>"Montserrat"));
	array_push($countries, array('value'=>"MA",'label'=>"Morocco"));
	array_push($countries, array('value'=>"MZ",'label'=>"Mozambique"));
	array_push($countries, array('value'=>"MM",'label'=>"Myanmar"));
	array_push($countries, array('value'=>"NA",'label'=>"Namibia"));
	array_push($countries, array('value'=>"NR",'label'=>"Nauru"));
	array_push($countries, array('value'=>"NP",'label'=>"Nepal"));
	array_push($countries, array('value'=>"NL",'label'=>"Netherlands"));
	array_push($countries, array('value'=>"AN",'label'=>"Netherlands Antilles"));
	array_push($countries, array('value'=>"NC",'label'=>"New Caledonia"));
	array_push($countries, array('value'=>"NZ",'label'=>"New Zealand"));
	array_push($countries, array('value'=>"NI",'label'=>"Nicaragua"));
	array_push($countries, array('value'=>"NE",'label'=>"Niger"));
	array_push($countries, array('value'=>"NG",'label'=>"Nigeria"));
	array_push($countries, array('value'=>"NU",'label'=>"Niue"));
	array_push($countries, array('value'=>"NF",'label'=>"Norfolk Island"));
	array_push($countries, array('value'=>"MP",'label'=>"Northern Mariana Islands"));
	array_push($countries, array('value'=>"NO",'label'=>"Norway"));
	array_push($countries, array('value'=>"OM",'label'=>"Oman"));
	array_push($countries, array('value'=>"PK",'label'=>"Pakistan"));
	array_push($countries, array('value'=>"PW",'label'=>"Palau"));
	array_push($countries, array('value'=>"PS",'label'=>"Palestinian Territory, Occupied"));
	array_push($countries, array('value'=>"PA",'label'=>"Panama"));
	array_push($countries, array('value'=>"PG",'label'=>"Papua New Guinea"));
	array_push($countries, array('value'=>"PY",'label'=>"Paraguay"));
	array_push($countries, array('value'=>"PE",'label'=>"Peru"));
	array_push($countries, array('value'=>"PH",'label'=>"Philippines"));
	array_push($countries, array('value'=>"PN",'label'=>"Pitcairn"));
	array_push($countries, array('value'=>"PL",'label'=>"Poland"));
	array_push($countries, array('value'=>"PT",'label'=>"Portugal"));
	array_push($countries, array('value'=>"PR",'label'=>"Puerto Rico"));
	array_push($countries, array('value'=>"QA",'label'=>"Qatar"));
	array_push($countries, array('value'=>"RE",'label'=>"Reunion"));
	array_push($countries, array('value'=>"RO",'label'=>"Romania"));
	array_push($countries, array('value'=>"RU",'label'=>"Russian Federation"));
	array_push($countries, array('value'=>"RW",'label'=>"Rwanda"));
	array_push($countries, array('value'=>"SH",'label'=>"Saint Helena"));
	array_push($countries, array('value'=>"KN",'label'=>"Saint Kitts and Nevis"));
	array_push($countries, array('value'=>"LC",'label'=>"Saint Lucia"));
	array_push($countries, array('value'=>"PM",'label'=>"Saint Pierre and Miquelon"));
	array_push($countries, array('value'=>"VC",'label'=>"Saint Vincent and The Grenadines"));
	array_push($countries, array('value'=>"WS",'label'=>"Samoa"));
	array_push($countries, array('value'=>"SM",'label'=>"San Marino"));
	array_push($countries, array('value'=>"ST",'label'=>"Sao Tome and Principe"));
	array_push($countries, array('value'=>"SA",'label'=>"Saudi Arabia"));
	array_push($countries, array('value'=>"SN",'label'=>"Senegal"));
	array_push($countries, array('value'=>"RS",'label'=>"Serbia"));
	array_push($countries, array('value'=>"SC",'label'=>"Seychelles"));
	array_push($countries, array('value'=>"SL",'label'=>"Sierra Leone"));
	array_push($countries, array('value'=>"SG",'label'=>"Singapore"));
	array_push($countries, array('value'=>"SK",'label'=>"Slovakia"));
	array_push($countries, array('value'=>"SI",'label'=>"Slovenia"));
	array_push($countries, array('value'=>"SB",'label'=>"Solomon Islands"));
	array_push($countries, array('value'=>"SO",'label'=>"Somalia"));
	array_push($countries, array('value'=>"ZA",'label'=>"South Africa"));
	array_push($countries, array('value'=>"GS",'label'=>"South Georgia and The South Sandwich Islands"));
	array_push($countries, array('value'=>"ES",'label'=>"Spain"));
	array_push($countries, array('value'=>"LK",'label'=>"Sri Lanka"));
	array_push($countries, array('value'=>"SD",'label'=>"Sudan"));
	array_push($countries, array('value'=>"SR",'label'=>"Suriname"));
	array_push($countries, array('value'=>"SJ",'label'=>"Svalbard and Jan Mayen"));
	array_push($countries, array('value'=>"SZ",'label'=>"Swaziland"));
	array_push($countries, array('value'=>"SE",'label'=>"Sweden"));
	array_push($countries, array('value'=>"CH",'label'=>"Switzerland"));
	array_push($countries, array('value'=>"SY",'label'=>"Syrian Arab Republic"));
	array_push($countries, array('value'=>"TW",'label'=>"Taiwan, Province of China"));
	array_push($countries, array('value'=>"TJ",'label'=>"Tajikistan"));
	array_push($countries, array('value'=>"TZ",'label'=>"Tanzania, United Republic of"));
	array_push($countries, array('value'=>"TH",'label'=>"Thailand"));
	array_push($countries, array('value'=>"TL",'label'=>"Timor-leste"));
	array_push($countries, array('value'=>"TG",'label'=>"Togo"));
	array_push($countries, array('value'=>"TK",'label'=>"Tokelau"));
	array_push($countries, array('value'=>"TO",'label'=>"Tonga"));
	array_push($countries, array('value'=>"TT",'label'=>"Trinidad and Tobago"));
	array_push($countries, array('value'=>"TN",'label'=>"Tunisia"));
	array_push($countries, array('value'=>"TR",'label'=>"Turkey"));
	array_push($countries, array('value'=>"TM",'label'=>"Turkmenistan"));
	array_push($countries, array('value'=>"TC",'label'=>"Turks and Caicos Islands"));
	array_push($countries, array('value'=>"TV",'label'=>"Tuvalu"));
	array_push($countries, array('value'=>"UG",'label'=>"Uganda"));
	array_push($countries, array('value'=>"UA",'label'=>"Ukraine"));
	array_push($countries, array('value'=>"AE",'label'=>"United Arab Emirates"));
	array_push($countries, array('value'=>"GB",'label'=>"United Kingdom"));
	array_push($countries, array('value'=>"US",'label'=>"United States"));
	array_push($countries, array('value'=>"UM",'label'=>"United States Minor Outlying Islands"));
	array_push($countries, array('value'=>"UY",'label'=>"Uruguay"));
	array_push($countries, array('value'=>"UZ",'label'=>"Uzbekistan"));
	array_push($countries, array('value'=>"VU",'label'=>"Vanuatu"));
	array_push($countries, array('value'=>"VE",'label'=>"Venezuela"));
	array_push($countries, array('value'=>"VN",'label'=>"Viet Nam"));
	array_push($countries, array('value'=>"VG",'label'=>"Virgin Islands, British"));
	array_push($countries, array('value'=>"VI",'label'=>"Virgin Islands, U.S."));
	array_push($countries, array('value'=>"WF",'label'=>"Wallis and Futuna"));
	array_push($countries, array('value'=>"EH",'label'=>"Western Sahara"));
	array_push($countries, array('value'=>"YE",'label'=>"Yemen"));
	array_push($countries, array('value'=>"ZM",'label'=>"Zambia"));
	array_push($countries, array('value'=>"ZW",'label'=>"Zimbabwe"));

	return $countries;
}
?>