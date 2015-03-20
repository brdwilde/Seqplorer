library(shiny)
library(ggplot2)
library(rmongodb)
library(XML)

# get the database credentials and connect
host <- "localhost"
db <- "seqplorer"
coll <- "plots"

# update the config settings from the config file if it exists
configfile <- NULL
if (file.exists('config.xml')){
  configfile <- 'config.xml'
} else if (file.exists('../config.xml')){
  configfile <- '../config.xml'
} else if (file.exists('../../config.xml')){
  configfile <- '../../config.xml'
} else if (file.exists('/etc/seqplorer/config.xml')){
  configfile <- '/etc/seqplorer/config.xml'
}
if(!is.null(configfile)){
  xmlfile <- xmlTreeParse(configfile) 
  
  # Use the xmlRoot-function to access the top node  
  xmltop = xmlRoot(xmlfile)

  # get the config details if they are specified
  if (!is.null(xmltop[['database']][['dbname']][1]$text)){
    db <- xmlValue(xmltop[['database']][['dbname']][1]$text)
  }
  if (!is.null(xmltop[['database']][['host']][1]$text)){
    host <- xmlValue(xmltop[['database']][['host']][1]$text)
  }
  if (!is.null(xmltop[['database']][['collections']][['plots']][1]$text)){
    coll <- xmlValue(xmltop[['database']][['collections']][['plots']][1]$text)
  }
}

plotscollection <- paste(db,coll, sep=".")
mongo = mongo.create(host=host,db=db)

#get these variables encoded form the url
# use: http://localhost/#dataset=<mongoid>,graphtype=boxplot
url_fields_to_sync <- c("dataset","startgraph");

# Define server logic required to summarize and view the selected dataset
shinyServer(function(input, output) {

  # the first time we run we will get the url encoded variable names
  firstTime <- TRUE
  #newhash <- 
  urlhash <- reactive({
    # create the ret variable form the input field
    ret <- isolate(input$hash)
    if (!firstTime) {
      ret = paste(collapse=",",
                  Map(function(field) { 
                    paste( sep="=", field, input[[field]])
                  },url_fields_to_sync)
                )
    }
    if(!is.null(ret)){
      firstTime <- FALSE;        
    }
    return(ret)
  })
  
  output$hash <- renderText(urlhash())
  
  # create reactive expressions to get data form input form fields
  # making these reactive means they will triger an update if the input value changes
  graphtype <- reactive({
    input$graphtype
  })
  
  distribution <- reactive({
    input$distribution 
  })

  plotvariable <- reactive({
    input$plotvariable
  })
  
  xvariable <- reactive({
    input$xvariable
  })
  
  yvariable <- reactive({
    input$yvariable
  })
  
  categoricalvariable <- reactive({
    input$categoricalvariable
  })
  
  colorby <- reactive({
    input$color
  })
  
  sortby <- reactive({
    input$color
  })
  
  horfacet <- reactive({
    input$horfacet      
  })
  
  vertfacet <- reactive({
    input$vertfacet      
  })

  ###########################################
  # build all the data we have to work with #
  ###########################################

  # first we get the dataset form the mongo database based on the input$dataset variable set from the url
  dataset <- reactive({
    # if the mongoid for the dataset is defined, get it
    if (input$dataset == ""){
      # return an empty value if no dataset mongoid is provided      
      dataset <- NULL
    } else {  
      # create the mongo buffer
      buf = mongo.bson.buffer.create()
      # create mongo object id from input dataset
      oid <- mongo.oid.from.string(input$dataset)
      # add the object id to the buffer, query on the _id field
      mongo.bson.buffer.append.oid(buf,"_id",oid)
      # prepare the query
      query = mongo.bson.from.buffer(buf)
  
      # get a cursor, perform the query
      cursor <- mongo.find(mongo,plotscollection,query)
  
      # get the records
      while (mongo.cursor.next(cursor)) {
        # get the mongo document
        doc <- mongo.cursor.value(cursor)
        # translate the relevant fields from bson to R data
        header <- mongo.bson.value(doc, "header")
        factors <- mongo.bson.value(doc, "factor")
        data <- mongo.bson.value(doc, "data")
      }
      
      # reformat the mongo data to a data frame
      dataset <- as.data.frame(sapply(data,rbind))
      dataset <- data.frame(data[[1]])
      names(dataset) <- header[1]
      
      for(column in header){
        dataset[column] <- data[column]
      }  
      for(factor in factors){
        dataset[[factor]] <- factor(data[[factor]])
      }
      names(dataset) <- gsub(" ",".",names(dataset),fixed = TRUE)
    }
    dataset
  })
  
  startgraph <- reactive({
    input$startgraph
  })

  # from this dataset we get a list of all categorical variables
  getallcategoricalvariables <- reactive({
    # depends on dataset
    dataset <- dataset()
    # default return NULL
    ret <- NULL
    # find all "factor" columns
    for (column in names(dataset)) {
      class <- class(dataset[,column])
      if ( class == "factor" ) {
        # add the column to the colors input list
        ret <- c(ret,column)
      }
    }
    ret
  })

  # from this dataset we get a list of all numerical variables
  getallnumericalvariables <- reactive({
    # depends on dataset
    dataset <- dataset()
    #default returns NULL
    ret <- NULL
    # find all numerical columns in dataset
    for (column in names(dataset)) {
      class <- class(dataset[,column])
      if (class == "array" || class == "numeric"){
        # add the column to the colors input list
        ret <- c(ret,column)
      }
    }
    ret
  })
  
  # from this dataset we create a list of graph types depending on the data we have
  getallgraphtypes <- reactive({
    dataset <- dataset()
    numericals <-  getallnumericalvariables()
    numericounter = length(numericals)
    categoricals <- getallcategoricalvariables()
    factorcounter = length(categoricals)

    # we now know how many numerical and categorical columns we have    
    if (numericounter>1 && factorcounter > 0){
      # we at least have on factorial and two numerical variables
      # => all plots are allowed
      return (c("distribution","scatter","boxplot","barplot"))
    } else if (numericounter == 1 && factorcounter > 0){
      # we at least have on factorial but only one numerical variables
      # => we need at least two numerical columns for scatter plots
      return (c("distribution","boxplot","barplot"))  
    } else if (numericounter>1  ){
      # we only have numerical variables, and more than 1
      # => only scatter plots are usefull
      return (c("scatter"))
    } else if (factorcounter > 0){
      # we only have factors
      # => we have no plots for only factors yet
      return (NULL)
    }
    return (NULL)
  })
  
  # this funciton will use the selected values form the input form
  # to subset the dataset before we plot, summarize or print it
  subsetInput <- reactive({
    dataset <- dataset()
    # copy the dataset, default we return the whole dataset
    ret <- dataset
    for (column in names(dataset)) {
      # get the data type for this column
      class <- class(dataset[,column])
      if (class == "factor") {
        # for factors we subset the data frame by the selected factor if it exists
        if (!is.null(input[[column]])){
          if(!(input[[column]][1]==" ")){
            select <- input[[column]]
            ret <- ret[ret[,column] %in% select,]
          }          
        }
      } else if (class == "array"){
        if (!is.null(input[[column]][1])){
          ret <- ret[ret[,column]>=input[[column]][1],]
          ret <- ret[ret[,column]<=input[[column]][2],]
        }
      }
    }
    ret
  })
  
  ############################################################
  # Update the input form with the dataset specific controls #
  ############################################################
  
  # the graph type control
  output$graphtype <- renderUI({
    graphtypes <- getallgraphtypes()
    startgraph <- startgraph()
    if (!is.null(graphtypes)){
      selectInput( "graphtype", "Select graph type:", choices = graphtypes, selected = startgraph)      
    }
  })
  
  # the dataset subset controls
  output$subsets <- renderUI({
    # depends on dataset
    dataset <- dataset()
    # defautl return NULL
    ret <- NULL
    for (column in names(dataset)) {
      class <- class(dataset[,column])
      if (class == "factor") {
        # levels for this factor with blank option
        levels <- c(" ",levels(dataset[,column]))
        if (length(levels)< 100){          
          # remove empty strings
          levels <- levels[levels != ""]
          # create dropdown from the levels and add to return array
          ret <- c( ret, selectInput( column, paste(column,":"), choices = levels, multiple = TRUE ))
        }
      } else if (class == "array" || class == "numeric"){
        # get minimum and maximum value for this column
        minval <- min(dataset[,column])
        maxval <- max(dataset[,column])
        interval <- maxval
        lastvalue <- NULL
        for (value in sort(dataset[,column])){
          if (!is.null(lastvalue)){
            step = value - lastvalue
            if (step < interval && step > 0.00001){
              interval <- step
            }
          }
          lastvalue <- value
        }
        minval <- minval - interval
        maxval <- maxval + interval
        # add selection slider for this column
        ret <- c( ret, sliderInput( column, paste(column," range:"), min = minval, max = maxval, value = c(minval,maxval), step = interval) )
      }
    }
    # return an array with selectInputs and sliderInputs
    ret
  })

  # all variables avalaible for plotting
  output$plotvariable <- renderUI({
    dataset <- dataset()
    choices <- names(dataset)
    if (!is.null(choices)){
      selectInput( "plotvariable", "Select plot variable", choices = choices)      
    }
  })
  
  # the x variable for plotting
  output$xvariable <- renderUI({
    plotvariable <- getallnumericalvariables()
    if (!is.null(plotvariable)){
      selectInput( "xvariable", "Select x variable", choices = plotvariable)      
    }
  })
  
  # the y variable for plotting
  output$yvariable <- renderUI({
    plotvariable <- getallnumericalvariables()
    if (!is.null(plotvariable)){
      selectInput( "yvariable", "Select y variable", choices = plotvariable)
    }
  })
  
  # the categorical variable for plotting
  output$categoricalvariable <- renderUI({
    categoricalvariable <- getallcategoricalvariables()
    if (!is.null(categoricalvariable)){
      selectInput( "categoricalvariable", "Select categorical variable", choices = categoricalvariable)
    }
  })
  
  # graph color variable
  output$color <- renderUI({
    colorinput <- getallcategoricalvariables()
    if (!is.null(colorinput)){
      selectInput( "color", "Color by:", choices = c(" ",colorinput))
    }
  })
  
  # graph color variable
  output$sortby <- renderUI({
    dataset <- dataset()
    choices <- names(dataset)
    if (!is.null(choices)){
      selectInput( "sortby", "Select sort variable", choices = choices)      
    }
  })
  
  # vertical faceting
  output$vertfacet <- renderUI({
    colorinput <- getallcategoricalvariables()
    if (!is.null(colorinput)){
      selectInput( "vertfacet", "Vertical", choices =  c(" ",colorinput))
    }
  })
  
  # horizontal faceting
  output$horfacet <- renderUI({
    colorinput <- getallcategoricalvariables()
    if (!is.null(colorinput)){
      selectInput( "horfacet", "Horizontal", choices =  c(" ",colorinput))
    }
  })
    
  ###################################################################
  # Update the output tabs with the summary, the table and the plot #
  ###################################################################
  
  # Generate a summary of the dataset
  output$summary <- renderPrint({
    # depends on the subsetInput
    summary(subsetInput())
  })
  
  # Show the first "n" observations
  output$table <- renderTable({
    # depends on the subsetInput
    head(subsetInput(),30)
  })

  # perform the plotting
  output$distPlot <- renderPlot({
    # depends on the subsetInput
    subset <- subsetInput()
    # and on the other form fields
    graph <- graphtype()
    categoricalvariable <- categoricalvariable()
    plotvariable <- plotvariable()
    xvariable <- xvariable()
    yvariable <- yvariable()
    color <- colorby()
    horfacet <- horfacet()
    vertfacet <- vertfacet()

    plotvar <- NULL
    if (!(length(subset[,1]) == 0) && !is.null(graph)){
      # we have data and know what plot is requested, lets plot!
      if (graph=="distribution"){
        if (input$sorted){
          # ggplot woll sort its graph by the levels of the variable being plotted
          # get the frequency of occurance of each level
          freq <- ave(rep(1, times=nrow(subset)), subset[[plotvariable]], FUN=sum)
          # create levels sorted by this frequency
          levelsvar <- unique(subset[[plotvariable]][order(freq,subset[[plotvariable]],decreasing=TRUE)])
          #replace the levels of the plot variable in the dataframe by the sorted levels
          subset[[plotvariable]] <- factor(subset[[plotvariable]], levels = unique(levelsvar))
        }
        if (color==" "){
          plotvar <- ggplot(subset, aes_string(x=plotvariable))
        } else{
          plotvar <- ggplot(subset, aes_string(x=plotvariable,color=color))
        }
        # what type of distribution do you want me to plot
        distribution <- distribution()
        if (distribution=="histogram"){
          plotvar <- plotvar + geom_histogram(position="dodge")        
        } else if (distribution=="density"){
          plotvar <- plotvar + geom_density()
        }
      } else if (graph=="scatter"){
        if (!is.null(xvariable) && !is.null(yvariable)){
          if (color==" "){
            plotvar <- ggplot(subset, aes_string(x=xvariable, y=yvariable)) + geom_line()
          } else {
            plotvar <- ggplot(subset, aes_string(x=xvariable, y=yvariable, colour=color)) + geom_line()
          }          
        }
      } else if (graph=="boxplot"){        
        if(!is.null(categoricalvariable)){
          #if (!is.null(input$sortby)){
          #  if (!(input$sortby == " ")){
          #    levelsvar <- subset[[plotvariable]][order(subset[[input$sortby]])]
          #    subset[[plotvariable]] <- factor(subset[[plotvariable]], levels = levelsvar)         
          #    }
          #        # sort by the requested column
          #      }      
          #    }
          
          if (color==" "){
            plotvar <- ggplot(subset, aes_string(x=categoricalvariable, y=xvariable)) + geom_boxplot()
          } else {
            plotvar <- ggplot(subset, aes_string(x=categoricalvariable, y=xvariable, fill=color)) + geom_boxplot() + guides(fill=FALSE)
          }          
        }
      } else if (graph=="barplot"){
        if(!is.null(categoricalvariable)){
          if (color==" "){
            plotvar <- ggplot(subset, aes_string(x=categoricalvariable, y=xvariable)) + geom_bar(stat="identity")
            
          } else {
            plotvar <- ggplot(subset, aes_string(x=categoricalvariable, y=xvariable, fill=color)) + geom_bar(stat="identity")
          }
        }
      }
  
      
      # split our plot in facets by horizontal or vertical variable
      facet <- ""
      if (horfacet!=" " && vertfacet!=" "){
        facet <- paste(horfacet, "~", vertfacet) 
      } else if (horfacet!=" "){
        facet <- paste(horfacet, "~ .")      
      } else if (vertfacet!=" "){
        facet <- paste(". ~", vertfacet)
      }
      if (facet!=""){
        plotvar <- plotvar + facet_grid(facet)      
      }
      
  
      # do the actual plotting
      if (!is.null(plotvar)){
        plot(plotvar)
      }
    } else {
      renderText("Please select input data\n")
    }
    
  })
  
  # generate button for data download
  output$downloadData <- downloadHandler(
    # create filename from mongoid
    filename = function() {
      paste(input$dataset, '.csv', sep='') 
    },
    # and the contents ftom the subset
    content = function(file) {
      write.csv(subsetInput(), file)
    }
  )  
})
