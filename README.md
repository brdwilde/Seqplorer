Seqplorer
=========

Next generation variant annotation tracker



INSTALLATION INSTRUCTIONS
=========================

Prerequisites:
* a mongodb database server
* Apache web server for seving php code including the mongodb module
* perl with mojolicious web framework installed
* R shiny web server


Check out the source code:
git clone https://github.com/brdwilde/Seqplorer.git

Move the phpwebinterface folder in the repository to your web servers root folder:
sudo mv phpwebinterface/ /var/www/seqplorer


Move the shiny code to your shiny web folder:
sudo mv shiny/* /srv/shiny-server/