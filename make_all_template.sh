#!/bin/bash
set -ue

target_host=$1
cdh_version=$2

for i in 50030 50060 50070 50075 50090
do
    ./get_hadoop_jmx.pl dummy_arg $target_host $i --detailed --nosend | ./convert_to_hadoop_tmpl.pl > ./template/template_for_${cdh_version}_port_${i}.xml
done

