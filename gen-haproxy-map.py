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
    aliases = get_aliases(apiurl)
    if containers:
      (backends, domainmaps) = generate_config(args.label, containers, aliases)
      update_config('backends', backends, args.backends)
      update_config('domainmaps', domainmaps, args.domainmap)

    time.sleep(args.interval)

def get_containers(apiurl):
  url = '{}/{}'.format(apiurl,'containers')
  try:
    r = requests.get(url, headers = {"Content-Type": "application/json", "Accept": "application/json"})
    if r.status_code == requests.codes.ok:
      return r.json()
    else:
      print "[ERROR]: status_code: {} getting containers".format(r.status_code)
      return None
  except requests.exceptions.RequestException as e: 
    print "[ERROR]: get_containers failed with exception: {}".format(e)
    return None

def get_aliases(apiurl):
  url = '{}/{}'.format(apiurl,'self/service/metadata/aliases')
  try:
    r = requests.get(url, headers = {"Content-Type": "application/json", "Accept": "application/json"})
    if r.status_code == 200 or r.status_code == 404:
      return r.json()
    else:
      print "[ERROR]: status_code: {} getting aliases".format(r.status_code)
      return None
  except requests.exceptions.RequestException as e: 
    print "[ERROR]: get_aliases failed with exception: {}".format(e)
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
        for uuid in sorted(data[backend]):
          f.write('  server {} {}:{}\n'.format(uuid, data[backend][uuid]['ip'], data[backend][uuid]['port']))
    elif config_type == 'domainmaps':
      for domain in sorted(data):
        f.write('{} {}\n'.format(domain, data[domain]))

  if os.path.isfile(output_file):
    if not compare_files(output_file, tmpfile):
      print "[INFO]: config: {} has changed, updating".format(config_type)
      os.rename(tmpfile, output_file)
  else:
    os.rename(tmpfile, output_file)

def generate_config(label, containers, aliases):
  backends   = {}
  domainmaps = {}
  for container in containers:
    if unicode(label) in container[u'labels']:
      stack_name   = container[u'stack_name']
      service_name = container[u'service_name']
      primary_ip   = container[u'primary_ip']
      state        = container[u'state']
      uuid         = container[u'uuid']
      port         = container[u'labels'][unicode(label)]
      fqdn         = '{}.{}'.format(stack_name, args.domain)
      service_id   = '{}-{}'.format(service_name, uuid)

      if not primary_ip:
        print "[WARNING]: stack_name: {} container_uuid: {} does not yet have an ip address, skipping this container".format(stack_name, uuid)
        continue

      # Add stack name domain map
      domainmaps[fqdn] = stack_name
      # Add aliases domain map if required
      if stack_name in aliases:
        for alias in aliases[stack_name]:
          fqdn = '{}.{}'.format(alias, args.domain)
          domainmaps[fqdn] = stack_name
      try:
        backends[stack_name][service_id] = {'ip': primary_ip, 'port': port }
      except KeyError:
        backends[stack_name] = { service_id: { 'ip': primary_ip, 'port': port } }

  return (backends, domainmaps)

if __name__ == "__main__":
  parser = argparse.ArgumentParser(description='Generate haproxy config and maps from Rancher Metadata Service.')
  parser.add_argument('--domain',     required=True,        help='Domain suffix to use for host routing eg: $stack_name.$domain.')
  parser.add_argument('--apiversion', required=True,        help='Rancher Metadata API version.')
  parser.add_argument('--apihost',    required=True,        help='Rancher Metadata API host.')
  parser.add_argument('--domainmap',  required=True,        help='Where to store the haproxy map file.')
  parser.add_argument('--backends',   required=True,        help='Where to store the haproxy backends file.')
  parser.add_argument('--label',      required=True,        help='What rancher label to use to find containers.')
  parser.add_argument('--interval',   default=10, type=int, help='How often to generate the config.')
  args = parser.parse_args()

  main(args)
