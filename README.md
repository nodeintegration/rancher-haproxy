# rancher-haproxy
## Description
This docker image is a haproxy server that uses the rancher-metadata service to do service discovery to route requests via hostname to stacks.

eg this will allow you to create a stack called 'foobar' and have requests hit http://foobar.$domain/ that will route to containers that have a specified label.
This is useful if you for example take an N stacks approach to CI/CD. ie. deploy app build 123 to a stack called 'app-r123'
This will give you an immediate endpoint http://app-r123.$domain'

The label to associate and the domain are configurable
## How to use this container

Create a stack for your load balancer
docker-compose.yml:
```
HTTP:
  ports:
  - 80:80
  environment:
    STACK_DOMAIN: '$MyDomainWithWildcardRecord'
    RANCHER_LABEL: 'IWantMyContainersThatHaveThisLabelToBeDiscovered'
  labels:
    io.rancher.container.pull_image: always
  tty: true
  image: nodeintegration/rancher-haproxy
  stdin_open: true
```
Then create your web applications with the same label you used above ie "RANCHER_LABEL".
e.g. a stack called "test-webservice-r123"
docker-compose.yml:
```
nginx:
  labels:
    io.rancher.container.pull_image: always
    IWantMyContainersThatHaveThisLabelToBeDiscovered: '80'
  tty: true
  image: nginx:stable-alpine
  stdin_open: true
```
The value of the label is the port that haproxy will balance to
