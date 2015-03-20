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
    
    textInput("startgraph", ""),

    # The graph type
    uiOutput("graphtype"),
    
    # if the type is distribution, let the user choose between density and histogram
    conditionalPanel(
      condition = "input.graphtype == 'distribution'",
      selectInput( "distribution", "", choices = c("histogram","density")),
      checkboxInput(inputId = "sorted", label = "Sort",value=TRUE)
    ),

    # select what to plot
    # for distribution plots, a plot variable (can be anything)
    conditionalPanel(
      condition = "input.graphtype == 'distribution'",
      uiOutput("plotvariable")),
    # for scatter plots, add an Y variable
    conditionalPanel(
      condition = "input.graphtype == 'scatter' || input.graphtype == 'boxplot' || input.graphtype == 'barplot'",
      uiOutput("xvariable")),
    # for scatter plots, add an Y variable
    conditionalPanel(
      condition = "input.graphtype == 'scatter'",
      uiOutput("yvariable")),
    # for boxplots adn barplots, add a categorical variable
    conditionalPanel(
      condition = "input.graphtype == 'boxplot' || input.graphtype == 'barplot'",
      uiOutput("categoricalvariable")),
    br(),
    
    # download button
    downloadButton('downloadData', 'Download data'),
    br(),
    
    # a placeholder for subsetting the data
    tags$img(id='subset', class='fold', src="img/icon_tree_on.gif","Subset your data:"),
    uiOutput("subsets"),
    br(),

    # the variable user for color in the graph
    #tags$img(id='sort', class='fold', src="img/icon_tree_on.gif","Sort data:"),
    #uiOutput("sortby"),
    #br(),
    
    # the variable user for color in the graph
    tags$img(id='colors', class='fold', src="img/icon_tree_on.gif","Color graph:"),
    uiOutput("color"),
    br(),

    # the variables for splitting the dataset in the graph
    tags$img(id='split', class='fold', src="img/icon_tree_on.gif","Split graph:"),
    uiOutput("vertfacet"),
    uiOutput("horfacet")
  ),
  # The main window, with a plot, a summary and a table view of the data
  mainPanel(
    includeHTML("www/js/URL.js"),
    includeHTML("www/css/default.css"),
    tabsetPanel(
      tabPanel("Plot", plotOutput("distPlot")), 
      tabPanel("Summary", verbatimTextOutput("summary")), 
      tabPanel("Table", tableOutput("table"))
    ),
    hashProxy("hash")
  )
  
))