Seqplorer
=========

Next generation variant annotation tracker



Installation instructions
=========================

Prerequisites:
* a mongodb database server
* Apache web server for seving php code including the mongodb module
* perl with mojolicious web framework installed
* R shiny web server
* A PBS queue for job execution


Check out the source code:
git clone https://github.com/brdwilde/Seqplorer.git

Move the phpwebinterface folder in the repository to your web servers root folder:
sudo mv phpwebinterface/ /var/www/seqplorer


Move the shiny code to your shiny web folder:
sudo mv shiny/* /srv/shiny-server/


Edit the xml configuration file to match your local configuration and copy it to the webroot of your php pages and the shiny web server

Move the mojo api whatever folder you like:
sudo mv api /opt/seqplorer
Start the deamon:
cd /opt/seqplorer
morbo ./script/seqplorer -l http://*:3939

Configuration
=============

Web services:
As we are curretly using 3 web services to build one site you might run in to so called "cross domain request" issues, to address these we route all web services through an NGINX web server on one domain

location / {
	proxy_pass http://host.running.php.code/;
}
location /shiny/ {
    rewrite ^/shiny/(.*)$ /$1 break;
    proxy_pass http://host.running.shiny.code:3838;
    proxy_redirect http://host.running.shiny.code:3838/ $scheme://$host/shiny/;
}

location /api {
    rewrite ^/api/(.*)$ /$1 break;
    proxy_pass http://host.running.mojo.api:3939;
    proxy_redirect http://host.running.mojo.api:3939/ $scheme://$host/api/;
}

this will cause the requests from you browser to go to api/ and shiny/ url paths instead of to different hosts and ports and thus avoids the problem of cross domain posting many browsers will complain about




