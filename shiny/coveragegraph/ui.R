# load shiny library
library(shiny)

hashProxy <- function(inputoutputID) {
  div(id=inputoutputID,class=inputoutputID,tag("div",""));
}

# Generate a stub user interface
# contents will be filled depending on the dataset for the backend script
shinyUI(bootstrapPage(

  # The header
  headerPanel(""),
  
  # Sidebar with controls to select plot types, subsets and other options
  sidebarPanel(
    # select the dataset to display, this input will be hidden form the user at all time
    textInput("dataset", ""),
    
    # The graph type
    selectInput( "graphtype", "Select graph type:", choices = c("Summary per file","Cumulative distribution"), selected = "Summary per file"),
    
    # if the type is a sumary per file, let the user sort on...
    conditionalPanel(
      condition = "input.graphtype == 'Summary per file'",
      selectInput( "sortby", "Sort by:", choices = c(" ", "mean", "median", "min", "Q1", "Q3", "max"))
    ),
    br(),
    
    tags$img(id='graphcontrol', class='fold', src="img/icon_tree_on.gif","Graph controls:"),
    uiOutput("xrange"),
    uiOutput("fileselect"),
    conditionalPanel(
      condition = "input.graphtype == 'Cumulative distribution'",
      checkboxInput("logscale", "Logaritmic axis", FALSE),
      checkboxInput("mean", "Plot mean and stdev for all files", FALSE)
    ),
    conditionalPanel(
      condition = "input.graphtype == 'Summary per file'",
      checkboxInput("horizontalplot", "Plot horizontal", FALSE)
    ),
    br(),

    # the variables for splitting the dataset in the graph
    conditionalPanel(
      condition = "input.graphtype == 'Cumulative distribution'",
      tags$img(id='split', class='fold', src="img/icon_tree_on.gif","Split graph:"),
      selectInput( "facet", "By file", choices =  c(" ","vertical","horizontal"))
    ),
    br(),

    # download button
    downloadButton('downloadstats', 'Download general stats data'),
    br(),
    br(),
    downloadButton('downloaddisribution', 'Download cumulative distribution data')

  ),

  # The main window, with a plot, a summary and a table view of the data
  mainPanel(
    includeHTML("www/js/URL.js"),
    includeHTML("www/css/default.css"),
    tabsetPanel(
      tabPanel("Statistics",
               h3(textOutput("statstext")),
               tableOutput("stats"),
               h3(textOutput("normalizationheader")),
               uiOutput("normalizationtableholder"),
               h3(textOutput("alignmentstatsheader")),
               uiOutput("alignmentstatstableholder"),
               h3(textOutput("thresholdstatstext")),
               tableOutput("thresholdstatstable")),
      tabPanel("Graphics",plotOutput("Plot"))
    ),
    hashProxy("hash")
  )
))