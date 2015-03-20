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
url_fields_to_sync <- c("dataset");

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
  
  xrangefunc <- reactive({
    input$xrange
  })
  
  fileselectfunc <- reactive({
    input$fileselect
  })
  
  #################################################
  # build all the dataframes we have to work with #
  #################################################

  # first we get the dataset from the mongo database based on the input$dataset variable set from the url
  dataset <- reactive({
    ret <- NULL
    coveragestats <- NULL
    cumulative <- NULL
    # if the mongoid for the dataset is defined, get it
    if (!(input$dataset == "")){
      
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
        cumdatasetid <- mongo.bson.value(doc, "cumulativeid")
      }
      
      # reformat the mongo data to a data frame
      coveragestats <- as.data.frame(sapply(data,rbind))
      coveragestats <- data.frame(data[[1]])
      names(coveragestats) <- header[1]
      for(column in header){
        coveragestats[column] <- data[column]
      }  
      for(factor in factors){
        coveragestats[[factor]] <- factor(data[[factor]])
      }
      
      ret$coveragestats <- coveragestats
      
      # get the matching cumulative distirbution dataset
      buf = mongo.bson.buffer.create()
      oid <- mongo.oid.from.string(cumdatasetid)
      mongo.bson.buffer.append.oid(buf,"_id",oid)
      query = mongo.bson.from.buffer(buf)
      
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
      cumulative <- as.data.frame(sapply(data,rbind))
      cumulative <- data.frame(data[[1]])
      names(cumulative) <- header[1]
      for(column in header){
        cumulative[column] <- data[column]
      }  
      for(factor in factors){
        cumulative[[factor]] <- factor(data[[factor]])
      }
      
      ret$cumulative <- cumulative
    } else {
      ret$coveragestats <- coveragestats
      ret$cumulative <- cumulative
    }
    ret
  })
  
  # subset the input depending on files selected form the input$fileselect dropdown
  subsetInput <- reactive({  
    mongodataset <- dataset()
    coveragestats <- mongodataset$coveragestats
    if (!(is.null(input$fileselect) || input$fileselect == " ")){
      mongodataset$coveragestats <- mongodataset$coveragestats[mongodataset$coveragestats$Filename %in% input$fileselect,]
      mongodataset$cumulative <- mongodataset$cumulative[mongodataset$cumulative$Filename %in% input$fileselect,]
    }
    mongodataset
  })  
  
  ############################################################
  # Update the input form with the dataset specific controls #
  ############################################################
  
  # create a slider input to limit the coverage range
  output$xrange <- renderUI({
    mongodata <- dataset()
    if (!is.null(mongodata)){
      covdataset <- mongodata$coveragestats
      minval <- min(covdataset$min)
      if (input$logscale && minval == 0 ){
        minval <- 1
      }
      maxval <- max(covdataset$max)
      sliderInput( 'xrange', "Coverage range:", min = minval, max = maxval, value = c(minval,maxval))
    }
  })
  
  # the files for plotting
  output$fileselect <- renderUI({
    mongodata <- dataset()
    if (!is.null(mongodata)){
      files <- levels(mongodata$coveragestats$Filename)
      selectInput( 'fileselect', "View files:", choices = c(" ",files), multiple = TRUE )
    }
  })

  ###############################################################
  # Update the output fields with the dataset specific elements #
  ###############################################################
  
  output$normalizationtableholder <- renderUI({
    mongodata <- subsetInput()
    covdataset <- mongodata$coveragestats
    ret <- NULL
    if (all(covdataset$normalizationfactor == 1)){
      ret <- textOutput("normalizationmessage")
    } else {
      ret <- tableOutput("normalizationtable")
    }
    ret
  })
  
  output$alignmentstatstableholder <- renderUI({
    mongodata <- subsetInput()
    covdataset <- mongodata$coveragestats
    ret <- NULL
    if (!is.null(covdataset$totalreads)){
      # we have data, render a table
      ret <- tableOutput("alignemtstatstable")
    } else {
      # no data avaialable, render text
      ret <- textOutput("alignementstatsmessage")
    }
    ret
  })
    
  ###################################################################
  # Update the output tabs with the summary, the table and the plot #
  ###################################################################
  
  # Generate a summary of the dataset and print it in a table
  output$statstext <- renderText({
    "Coverage statistics"
  })
  output$stats <- renderTable({
    mongodata <- subsetInput()
    covdataset <- mongodata$coveragestats
    coveragestats=data.frame(
      'File' = covdataset$Filename,
      'Minimum' = covdataset$min,
      'Quartile 1' = covdataset$Q1,
      'Mean' = covdataset$mean,
      'Median' = covdataset$median,
      'Quartile 3' = covdataset$Q3,
      'Maximum' = covdataset$max,
      'Standard deviation' = covdataset$stdev
    )
    coveragestats
  })

  output$thresholdstatstext <- renderText({
    "Threshold statistics"
  })
  output$thresholdstatstable <- renderTable({
    mongodata <- subsetInput()
    covdataset <- mongodata$coveragestats
    otherstats=data.frame(
      'File' = covdataset$Filename
    )
    otherstats[['Number of bases evaluated']] = covdataset$totalbases
    if (!is.null(covdataset$threshbases)){
      otherstats[['Coverage threshold']] = covdataset$threshold
      otherstats[['Number of bases above threshold']] = covdataset$threshbases
      otherstats[['% of bases above threshold']] = covdataset$threshbases/covdataset$totalbases
    }
    otherstats
  })
  
  # print a header for the normalization statistics if they are available
  output$normalizationheader <- renderText({
    mongodata <- subsetInput()
    covdataset <- mongodata$coveragestats
    ret <- ""
    if (!is.null(covdataset$normalizationfactor)){
      if (!all(covdataset$normalizationfactor == 1)){
        # normalization was performed, we print the header
        ret <- "normalization statistics"        
      }
    }
    ret
  })
  
  output$normalizationmessage <- renderText({
    'Coverage normalization was not performed'
  })

  # print a data frame with the normalization data for each file
  output$normalizationtable <- renderTable({
    mongodata <- subsetInput()
    covdataset <- mongodata$coveragestats
    normalization = data.frame(
      'File' = covdataset$Filename
    )
    # all reads where normalized to this number
    normalization[['Normalized to']] = covdataset$normalizedreads
    if (!is.null(covdataset$meannorm)){
      # mean normalization was used
      normalization[['Mean coverage before normalization']] = covdataset$meannorm
    }
    normalization[['normalization factor']] = sprintf('%1.5f', covdataset$normalizationfactor)
      
    normalization
  })
  
  # print a header for the alignment statistics if they are available
  output$alignmentstatsheader <- renderText({
    mongodata <- subsetInput()
    covdataset <- mongodata$coveragestats
    ret <- ""
    if (!is.null(covdataset$totalreads)){
      ret <- "Aligment statistics"        
    }
    ret
  })
  
  output$alignementstatsmessage <- renderText({
    "No alignemnt statistics generated"
  }) 
  
  output$alignemtstatstable <- renderTable({
    mongodata <- subsetInput()
    covdataset <- mongodata$coveragestats
    # build a data fram with read statistics
    readstats =data.frame(
      'File' = covdataset$Filename
    )
    readstats[['Total number of reads']] = covdataset$totalreads
    readstats[['Number of reads marked as duplicate']] = covdataset$duplicatereads
    readstats[['Mapped reads']] = covdataset$mappedreads
    readstats[['Reads contributing to coverage']] = covdataset$coveragereads

    readstats
  })
  
  # perform the plotting
  output$Plot <- renderPlot({
    # depends on the subsetInput
    mongodata <- subsetInput()
    covdataset <- mongodata$coveragestats
    distdataset <- mongodata$cumulative
    
    covtitle <- "coverage"
    if (!is.null(covdataset$meannorm)){
      covtitle <- "mean normalized coverage"
    }else if (!all(covdataset$normalizationfactor == 1)){
      covtitle <- "Normalized coverage" 
    }
    
    graph <- graphtype()
    xrange <- xrangefunc()

    plotvar <- NULL
    if (!(length(distdataset[,1]) == 0) && !is.null(graph)){
      # we have data and know what plot is requested, lets plot!
      if (graph == "Cumulative distribution") {
        if (input$mean){
          # Calculate the means for each bin for each File
          aggregate  <- aggregate(distdataset$Value, by=list(distdataset$Bin), FUN= mean, na.rm=TRUE)
          # calculate stdev for each bin in each dataset
          aggregate$stdev  <- aggregate(distdataset$Value, by=list(distdataset$Bin), FUN= sd, na.rm=TRUE)$x
          
          # rename columns
          names(aggregate)[names(aggregate)=="Group.1"] <- "Bin"
          names(aggregate)[names(aggregate)=="x"] <- "mean"
          
          plotvar <- ggplot(NULL ,aes(x=Bin, y=mean, color="Mean")) + geom_line(data = aggregate) 
          plotvar <- plotvar + geom_errorbar( data = aggregate, aes(ymin=mean-stdev, ymax=mean+stdev, color="Standard deviation"))
          plotvar <- plotvar + xlab(covtitle) + ylab("% of bases")+ ggtitle(paste("Mean and standard deviation of cumulative ",covtitle," distributione"))
          plotvar <- plotvar + theme(legend.title=element_blank())
          
        } else {
          plotvar <- ggplot(distdataset, aes(x=Bin, y=Value, colour=Filename)) + geom_line()
          plotvar <- plotvar+ xlab(covtitle)+ ylab("% of bases")+ ggtitle(paste("Cumulative ",covtitle," distribution"))

        }
        if (!is.null(xrange[1])){
          if (input$logscale){
            plotvar <- plotvar + scale_x_log10(limits = c(xrange[1],xrange[2]))
          } else {
            plotvar <- plotvar + xlim(xrange[1],xrange[2])
          }
        } else if (input$logscale){
          plotvar <- plotvar + scale_x_log10()
        }
      }
        
      else if (graph == "Summary per file") {
        
        if (!(input$sortby == " ")){
          # sort by the requested column
          levelsvar <- covdataset$Filename[order(covdataset[[input$sortby]])]
          covdataset$Filename <- factor(covdataset$Filename, levels = levelsvar) 
        }

        plotvar <- ggplot(covdataset, aes(x = Filename, ymin = min, lower = Q1, middle = median, upper = Q3, ymax = max), )
        plotvar <- plotvar + geom_boxplot(stat = "identity") + theme(axis.text.x = element_text(angle = 90, hjust = 1))
        plotvar <- plotvar+ xlab("File")+ ylab(covtitle)+ ggtitle("Base coverage distribution")
        
        # logaritmic plots not working for now (?)... so in comment
        if (!is.null(xrange[1])){
          #if (input$logscale){
          #  plotvar <- plotvar + scale_y_log10(limits = c(xrange[1],xrange[2]))
          #} else {
            if (!input$horizontalplot){
              plotvar <- plotvar + coord_cartesian(ylim=c(xrange[1],xrange[2])) 
            }            
          #}
        } 
        #else if (input$logscale){
          #plotvar <- plotvar + scale_y_log10()
        #}
        if (input$horizontalplot){
          if (!is.null(xrange[1])){
            plotvar <- plotvar + coord_flip(ylim=c(xrange[1],xrange[2]))
          } else {
            plotvar <- plotvar + coord_flip()
          }
        }
      }
      
      # split our plot in facets by horizontal or vertical variable
      if (input$facet=="horizontal"){
        plotvar <- plotvar + facet_grid("Filename ~ .")
      } else if (input$facet=="vertical"){
        plotvar <- plotvar + facet_grid(". ~ Filename")
      }      
  
      # do the actual plotting
      if (!is.null(plotvar)){
        plot(plotvar)
      }
    } 
  })
  
  # generate button for data download
  output$downloadstats <- downloadHandler(
    # create filename from mongoid
    filename = function() {
      paste(input$dataset, '_stats.csv', sep='') 
    },
    # and the contents ftom the subset
    content = function(file) {
      mongodata <- subsetInput()
      covdataset <- mongodata$coveragestats
      write.csv(covdataset, file)
    }
  )
  
  # generate button for data download
  output$downloaddisribution <- downloadHandler(
    # create filename from mongoid
    filename = function() {
      paste(input$dataset, '_distr.csv', sep='') 
    },
    # and the contents ftom the subset
    content = function(file) {
      mongodata <- subsetInput()
      distdataset <- mongodata$cumulative
      write.csv(distdataset, file)
    }
  ) 
})
