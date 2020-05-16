#!/bin/bash
set +ex

mkdir -p keys

test -f keys/ec2-key || yes | ssh-keygen -t rsa -b 4096 -f keys/ec2-key -N ''

echo -e 'public_key = ''"'"$(cat keys/ec2-key.pub)"'"' > ./terraform.tfvars