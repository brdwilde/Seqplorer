// Function to reload a page with a given timeout
function reload(timeout) {
	setTimeout(function(){
		location.reload();
	},
	timeout);
}

// Function to check if a given value is a number or not
function is_numeric(value){
	return !isNaN(value);
}

// merge arrays recursivly
function array_merge_recursive (arr1, arr2) {
    var idx = '';
    if (arr1 && Object.prototype.toString.call(arr1) === '[object Array]' && arr2 && Object.prototype.toString.call(arr2) === '[object Array]') {
        for (idx in arr2) {
            arr1.push(arr2[idx]);
        }
    } else if ((arr1 && (arr1 instanceof Object)) && (arr2 && (arr2 instanceof Object))) {
        for (idx in arr2) {
            if (idx in arr1) {
                if (typeof arr1[idx] == 'object' && typeof arr2 == 'object') {
                    arr1[idx] = this.array_merge(arr1[idx], arr2[idx]);
                } else {
                    arr1[idx] = arr2[idx];
                }
            } else {
                arr1[idx] = arr2[idx];
            }
        }
    }

    return arr1;
}


