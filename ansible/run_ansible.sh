#!/bin/bash
set +ex

# todo genereate inventory.yml file with ec2 host
instance_public_ip="$(cd ../infra && terraform output instance_public_ip)"
echo -e 'all:\n  hosts:\n    ''"'"${instance_public_ip}"'"' > inventory.yml

# todo add any additional variables
db_endpoint="$(cd ../infra && terraform output db_endpoint)"
db_user="$(cd ../infra && terraform output db_user)"
db_pass="$(cd ../infra && terraform output db_pass)"

echo -e 'db_endpoint: '"${db_endpoint}"'\n'\
'db_user: '"${db_user}"'\n'\
'db_pass: '"${db_pass}" > ./vars/external_vars.yml;

# ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.yml -e 'record_host_keys=True' -u ec2-user --private-key <ssh key> playbook.yml
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.yml -e 'record_host_keys=True' -u ec2-user --private-key ~/.ssh/id_rsa playbook.yml
