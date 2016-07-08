#!/usr/bin/env python

import requests
import json
import pprint
import argparse
import time
import hashlib
import os

def main(args):
  apiurl = 'http://{}/{}'.format(args.apihost, args.apiversion)
  while True:
    containers = get_containers(apiurl)
    if containers:
      (backends, domainmaps) = generate_config(containers)
      update_config('backends', backends, args.backends)
      update_config('domainmaps', domainmaps, args.domainmap)

    time.sleep(args.interval)

def get_containers(apiurl):
  url = '{}/{}'.format(apiurl,'containers')
  r = requests.get(url, headers = {"Content-Type": "application/json", "Accept": "application/json"})
  if r.status_code == requests.codes.ok:
    return r.json()
  else:
    print "[ERROR]: status_code: {} getting containers".format(r.status_code)
    return None

def hashfile(afile, hasher, blocksize=65536):
    buf = afile.read(blocksize)
    while len(buf) > 0:
        hasher.update(buf)
        buf = afile.read(blocksize)
    return hasher.hexdigest()

def compare_files(file1, file2):
   file1_hex = hashfile(open(file1, 'rb'), hashlib.sha256())
   file2_hex = hashfile(open(file2, 'rb'), hashlib.sha256())

   if file1_hex == file2_hex:
     return True
   else:
     return False

def update_config(config_type, data, output_file):
  tmpfile = '{}.tmp'.format(output_file)
  with open(tmpfile, 'w') as f:
    if config_type == 'backends':
      for backend in sorted(data):
        f.write('\nbackend {}\n  mode http\n'.format(backend))
        for ip in sorted(data[backend]):
          f.write('  server {}:80\n'.format(ip))
    elif config_type == 'domainmaps':
      for domain in sorted(data):
        f.write('{} {}\n'.format(domain, data[domain]))

  if os.path.isfile(output_file):
    if not compare_files(output_file, tmpfile):
      print "[INFO]: config: {} has changed, updating".format(config_type)
      os.rename(tmpfile, output_file)
  else:
    os.rename(tmpfile, output_file)

def generate_config(containers):
  backends   = {}
  domainmaps = {}
  for container in containers:
    if u'map-public-http' in container[u'labels']:
      stack_name   = container[u'stack_name']
      service_name = container[u'service_name']
      primary_ip   = container[u'primary_ip']
      state        = container[u'state']

      fqdn = '{}.{}'.format(stack_name, args.domain)
      domainmaps[fqdn] = stack_name
      try:
        backends[stack_name][primary_ip] = service_name
      except KeyError:
        backends[stack_name] = { primary_ip: service_name }

  return (backends, domainmaps)

if __name__ == "__main__":
  parser = argparse.ArgumentParser(description='Generate haproxy config and maps from Rancher Metadata Service.')
  parser.add_argument('--domain',     required=True,                                         help='Domain suffix to use for host routing eg: $stack_name.$domain.')
  parser.add_argument('--apiversion', default='2015-12-19',                                  help='Rancher Metadata API version.')
  parser.add_argument('--apihost',    default='rancher-metadata.rancher.internal',           help='Rancher Metadata API host.')
  parser.add_argument('--domainmap',  default='/usr/local/etc/haproxy/domain.map',           help='Where to store the haproxy map file.')
  parser.add_argument('--backends',   default='/usr/local/etc/haproxy/haproxy-backends.cfg', help='Where to store the haproxy backends file.')
  parser.add_argument('--interval',   default=10, type=int,                                  help='How often to generate the config.')
  args = parser.parse_args()

  main(args)
