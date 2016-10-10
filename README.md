# rancher-haproxy
## Description
This docker image is a haproxy server that uses the rancher-metadata service to do service discovery to route requests via hostname to stacks.

eg this will allow you to create a stack called 'foobar' and have requests hit http://foobar.$domain/ that will route to containers that have a specified label.
This is useful if you for example take an N stacks approach to CI/CD. ie. deploy app build 123 to a stack called 'app-r123'
This will give you an immediate endpoint http://app-r123.$domain'

The label to associate and the domain are configurable
## How to use this container

### ENVIRONMENT Flags
* STACK_DOMAIN - The domain to append to the stack names ie. if your stack was: stack123 and the STACK_DOMAIN was 'dev.tld' you would be able to access the stack via: stack123.dev.tld
* ENABLE_SSL - Enables ssl offloading, only set this to true if you have your ssl cert/key configured as per below
* SSL_BASE64_ENCODED - When supplying certificate/key in metadata, this flag will assume you have base64 encoded them, this is handy if you want to use compose variables for certificates
* ENABLE_STATS - Tells haproxy to expose the stats http interface, listens on STATS_PORT with STATS_USERNAME and STATS_PASSWORD, defaults to false
* STATS_PORT - Tells haproxy what port to use for stats, defaults to 1936
* STATS_USERNAME - haproxy stats username, defaults to haproxy
* STATS_PASSWORD - haproxy stats password, defaults to haproxy
* HAPROXY_CONFIG - The default haproxy.cfg location
* HAPROXY_SSL_CERT - Where the ssl certificate file is used (the certificate/key is combined to this), if you want to volume mount your certificate, mount it to this location
* HAPROXY_BACKEND_CONFIG - Where the dynamic generated backend config is stored
* HAPROXY_DOMAIN_MAP - Where the dynamic domain map generated config is stored
* RANCHER_API_HOST - The rancher metadata service api host
* RANCHER_API_VERSION - The rancher api version to use
* RANCHER_LABEL - The label for to filter by for services to include in the routing
* DISABLE_METADATA - This disables the fetching of data from metadata, more for debug use if you want to run it locally outside of rancher for testing

### Examples
Create a stack for your load balancer
docker-compose.yml:
```
HTTP-generate-maps:
  environment:
    STACK_DOMAIN: MYDOMAIN.tld
  labels:
    io.rancher.container.pull_image: always
  tty: true
  command:
  - generate-maps
  image: nodeintegration/rancher-haproxy
  stdin_open: true
HTTP:
  ports:
  - 80:80/tcp
  - 443:443/tcp
  labels:
    io.rancher.sidekicks: HTTP-generate-maps
    io.rancher.container.pull_image: always
  tty: true
  image: nodeintegration/rancher-haproxy
  stdin_open: true
```
Then create your web applications with the same label you used for "RANCHER_LABEL" above or the default (map-public-http) and the port that the container listens to http on.
e.g. a stack called "test-webservice-r123"
docker-compose.yml:
```
nginx:
  labels:
    io.rancher.container.pull_image: always
    map-public-http: 80
  tty: true
  image: nginx:stable-alpine
  stdin_open: true
```
The value of the label is the port that haproxy will balance to
### What options do i have for ssl certificates?

Add the environment flag: ENABLE_SSL: 'true'

Theres a few ways to supply your certificate and key:
* mount a combined cert and key to $HAPROXY_SSL_CERT
* supply the cert and key through metadata
* supply the cert and key through metadata base64 encoded

rancher-compose.yml: 
You can use a raw certificate multiline string or you can just base64 encode the cert to a single line string to easily preserve formatting:
cat somecert.crt | base64 -w 0 > somecert.crt.base64
```
HTTP:
  metadata:
    ssl_cert: |
      -----BEGIN CERTIFICATE-----
      XXX
    ssl_key: | 
      -----BEGIN RSA PRIVATE KEY-----
      XXX
```

## How does this work?
* Since haproxy can use dynamic maps for host header mappings to backends we use that for $stack_name.$domain -> $stack_name....we cant however dynamically create haproxy backends without reloading haproxy.
* So with that in mind we rely on a docker entrypoint script to achieve this:
* The first process that starts is a python script. This script scans the rancher-metadata service api for the 'containers' path, it then looks for all containers that contain "RANCHER_LABEL" value, if a container has this label, then it adds it to the list with some details (the ip address and the value of the label for the port as well as the stack name)
* The python script then generates 2 files. 1. a domain map which is a list of domains (the $stack_name appended by the $DOMAIN value) to map to a backend (the $stack_name). 2. a backend config file which contains backends ($stack_name) then a list of containers by $service_name-$uuid as the server id and the ip and port
* The python script then writes those 2 files to a tmp file and diffs the current files against them, if they have changed then it renames the tmp file to its final destination
* This python script is backgrounded and run at a 10 second interval
* The entrypoint script then starts haproxy after a few seconds of grace time as a background process
* The last step is looping inotify watching the 2 final destination files...if those files attributes change in anyway it reloads the haproxy daemon

## I want aliases to my stacks!
For example you may want additional aliases...say www.$tld to hit app1 stack
Simply add in the rancher-compose metadata:

HTTP:
  metadata:
    aliases:
      app1:
        - www
        - someotheralias

## I want a different haproxy config, or i want to add more
The default haproxy.cfg contains very little (a frontend that does a domain map and a fallback backend with nothing in it)
You can easily add your own config by localising haproxy.cfg and adding your own additional config to it, so long as you have that domain map in your haproxy.cfg and the default fallback backend you shouldnt break any of the other logic...patches are always welcome to extend functionality

## Rancher SSL Certificate store support
Currently the certificate store is a one way action, ie you cannot retrieve the key from the api or the metadata service for some obvious reasons.
The rancher lb service is a special case in which it makes a call to the api for configscripts, the rancher server prepares a payload for this special type of container which preps the certificate.
Since this is image is essentially a normal container we dont have this luxury. So i've added handling adding ssl cert/key via metadata.

# How does this differ from standard haproxy docker images?
* Added syslog support from environment variables...ie set SYSLOG_HOST and SYSLOG_FACILITY to your docker-compose.yml to get logging!
* Instead of executing haproxy in the foreground i background it and use inotify to trigger config tests and reloads

# TODO
* in short plenty
* add support for http -> https redirection

# Changelog
All noteable changes from version: 0.5 will be documented here

## [0.6] - 2016-10-10
### Changed
- Created example docker-compose.yml and rancher-compose.yml
- Moved python map generation script to a sidekick, this is important because:
  The motiviation for this is because we need to control multiple processes (haproxy and a python script) that if the python script dies for any reason it does not know how to restart the pythong process.
  Something like supervisord to accomplish multiple process monitoring wont work as you cannot get haproxy to reloads in a traditional fashion
- reshuffled docker-entrypoint.sh to handle multiple command invocations

