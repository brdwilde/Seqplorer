<script type="text/javascript">
(function(){
 
  this.countValue=0;
  
  var changeInputsFromHash = function(newHash) {
    // get hash OUTPUT
    var hashVal = $(newHash).data().shinyInputBinding.getValue($(newHash));
    if (hashVal === "") return;
    // get values encoded in hash
    var keyVals = hashVal.substring(1).split(",").map(function(x){
      return x.split("=");
    });
    // find input bindings corresponding to them
    keyVals.map(function(x) {
      var el=$("#"+x[0]);

      if (el.length > 0 && el.val() != x[1]) {

        console.log("Attempting to update input " + x[0] + " with value " + x[1]);
        if (el.attr("type") == "checkbox") {
            el.prop('checked',x[1]==="TRUE");
            el.change();
        } else if(el.attr("type")==="radio") {
          console.log("I don't know how to update radios");
        } else if(el.attr("type")==="slider") {
          // This case should be setValue but it's not implemented in shiny
          el.slider("value",x[1]);
          //el.change()
        } else { 
            el.data().shinyInputBinding.setValue(el[0],x[1]);
            el.change();
        }
      }
    });
  };
  
  var HashOutputBinding = new Shiny.OutputBinding();
  $.extend(HashOutputBinding, {
    find: function(scope) {
      return $(scope).find(".hash");
    },
    renderError: function(el,error) {
      console.log("Shiny app failed to calculate new hash");
    },
    renderValue: function(el,data) {
      console.log("Updated hash");
      document.location.hash=data;
      changeInputsFromHash(el);
    }
  });
  Shiny.outputBindings.register(HashOutputBinding);
  
  var HashInputBinding = new Shiny.InputBinding();
  $.extend(HashInputBinding, {
    find: function(scope) {
      return $(scope).find(".hash");
    },
    getValue: function(el) {
      return document.location.hash;
    },
    subscribe: function(el, callback) {
      window.addEventListener("hashchange",
        function(e) {
          changeInputsFromHash(el);
          callback();
        },
        false);
    }
  });
  Shiny.inputBindings.register(HashInputBinding);

})();

$(document).ready( function() {
  // start by hiding the dataset control
  $('#dataset').hide();

  // make sure all graphical controls are in the same state when graph type changes
  $("body").on("change", "#graphtype", function(){
    if ($("#graphcontrol").is('.open') ){
      $('#xrange').show();
      $('#fileselect').show();
      $('#logscale').parent().show();
      $('#mean').parent().show();
      $('#horizontalplot').parent().show();
    }
    else {
      $('#xrange').hide();
      $('#fileselect').hide();
      $('#logscale').parent().hide();
      $('#mean').parent().hide();
      $('#horizontalplot').parent().hide();
    }
    if ($("#split").is('.open') ){
      $('#facet').show();
      $('#facet').prev().show();
    } else {
      $('#facet').hide();
      $('#facet').prev().hide();
    }

  });

  // toggle image and graphical controls on click
  $("body").on("click", "#graphcontrol", function(){
    updateimage($(this));
    $('#xrange').toggle('slow');
    $('#fileselect').toggle('slow');
    $('#logscale').parent().toggle('slow');
    $('#mean').parent().toggle('slow');
    $('#horizontalplot').parent().toggle('slow');
  });


  $("body").on("click", "#split", function(){
    updateimage($(this));
    $('#facet').toggle('slow');
    $('#facet').prev().toggle('slow');
  });

  setTimeout(function () {
    $('#xrange').hide('slow');
    $('#fileselect').hide('slow');
    $('#logscale').parent().hide('slow');
    $('#mean').parent().hide('slow');
    $('#horizontalplot').parent().hide('slow');
    $('#facet').hide('slow');
    $('#facet').prev().hide('slow');
    $('.fold').css('cursor','pointer');
  }, 1000);


});

function updateimage (img){
    if (img.is('.open') ){
      img.attr("src","img/icon_tree_on.gif");
      img.removeClass('open');
    }
    else {
      img.attr("src","img/icon_tree_off.gif");
      img.addClass('open');
    }
}

</script>