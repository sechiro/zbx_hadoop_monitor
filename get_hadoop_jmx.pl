#!/usr/bin/perl
# Author: Seiichiro, Ishida<seiichiro.ishida0@gmail.com>
# Copyright 2013, Seiichiro, Ishida All rights reserved.
use strict;
use warnings;
use JSON;
use Data::Dumper;
use LWP::UserAgent;
use Getopt::Long;
use Scalar::Util qw/looks_like_number/;

# Constant
my $zabbix_server = "127.0.0.1";
my $zabbix_server_version = 1.8;
my $infile_tmp_dir = "/tmp/ZbxHadoopMonitor";
my $debug_output = 0;

# Zabbix specification for external script has changed in Zabbix 2.0.
my $required_args_num = $zabbix_server_version <= 1.8 ? 3 : 2;

if ( @ARGV < $required_args_num ){
    print "[ERROR] Not enough arguments. Passed arguments are ";
    print "@ARGV\n";
    exit 0;
}

# Experimental options
# Get detailed or java.lang:type=memory metrics.(Experimental feature)
# You also need to update Zabbix template if you use these feature.
my $get_detail = 0;
my $nosend = 0;
my $dump_json = 0;
my $get_javalang = 0;
my $getopt_result = GetOptions("detailed" => \$get_detail,
                                "dump_json" => \$dump_json,
                                "nosend" => \$nosend,
                                "debug_output" => \$debug_output,
                                "javalang" => \$get_javalang);

# Zabbix specification for external script has changed in Zabbix 2.0.
my $hostname;
my $port;
my $zabbix_hostname;
if ( $zabbix_server_version <= 1.8 ){
    $hostname = $ARGV[1];
    $port = $ARGV[2];
    $zabbix_hostname = defined($ARGV[3]) ? $ARGV[3] : $hostname;
} else {
    $hostname = $ARGV[0];
    $port = $ARGV[1];
    $zabbix_hostname = defined($ARGV[2]) ? $ARGV[3] : $hostname;
}

# Open temporary merics data file.
if (!-d $infile_tmp_dir) {
    mkdir $infile_tmp_dir
        or die "[ERROR] Couldn't make $infile_tmp_dir in /tmp !";
} elsif (!-w $infile_tmp_dir){
    print "[ERROR] Can't write in infile temporary directory $infile_tmp_dir !";
    exit 0;
}
my $zabbix_sender_infile = "$infile_tmp_dir/$hostname-$port.jmx-infile.dat";
open my $infile_fh, ">", "$zabbix_sender_infile"
    or die "[ERROR] Couldn't open $zabbix_sender_infile in /tmp !";

# Get raw JSON metrics data in mxbean object list format from the Hadoop daemon.
my $json = JSON->new->allow_nonref;
my $request_url = "http://$hostname:$port/jmx";
my $mxbean_object_list = &get_json_mxbean_object_list($request_url);

# Output Raw JSON data dump for debug
if ( $dump_json == 1 ){
    warn "[Debug] Raw JSON data dump.\n";
    warn Dumper($mxbean_object_list);
    warn "\n";
}

# Get process name
my $processName = &get_hadoop_process_name($mxbean_object_list);

# Parse raw JSON data to Zabbix infile format
my @values = &parse_hadoop_jmx_metrics($mxbean_object_list, $hostname, $processName, $get_detail, $get_javalang, $debug_output);

# Output stdout only
if ( $nosend == 1 ){
    print @values;
    exit 0
}

print {$infile_fh} @values;
close $infile_fh;

# Zabbixサーバにデータ送信
eval {
    my $response = `/usr/bin/zabbix_sender -z $zabbix_server -i $zabbix_sender_infile 2>&1`;
    $response =~ s/\n/ /g;
    print "[INFO] $response\n";
};
if ($@) {
    print "[ERROR] Couldn't fork zabbix_sender process!";
    exit 0;
}

exit; # END

#############################
# Sub routine
#############################
# Get raw JSON metrics data in mxbean object list format from the Hadoop daemon.
# Usage: my $mxbean_object_list = &get_json_mxbean_object_list($request_url);
sub get_json_mxbean_object_list{
    my $json = JSON->new->allow_nonref;
    my $res;
    my ($request_url) = @_;
    eval {
        my $ua = LWP::UserAgent->new();
        my $req = HTTP::Request->new(GET => $request_url);
        $res = $ua->request($req);
    };
    if( $@ ) {
        print "[ERROR] Couldn't access $request_url ! \n";
        exit 0;
    }

    my $metrics_data;
    eval {
        $metrics_data = $json->decode( $$res{'_content'} );
    };
    if( $@ ) {
        print "[ERROR] Couldn't Get Metrics Data from $request_url ! \n";
        exit 0;
    }

    my $mxbean_object_list = $$metrics_data{'beans'};
    return $mxbean_object_list;
}

# Get process name
# Usage: my $processName = &get_hadoop_process_name($mxbean_object_list);
sub get_hadoop_process_name{
    my $processName = "";
    my ($mxbean_object_list) = @_;
    foreach my $mxbean_object ( @$mxbean_object_list ) {
        my $service_name;
        my $mxbean_name;
        my $mxbean_name_attribute = $$mxbean_object{'name'};
        if ( $mxbean_name_attribute =~ /^[hH]adoop:service=(\w+),name=(\w+)/ ) {
            $processName = $1;
            last;
        }
    }

    # Only for SecondaryNamenode
    if ( $processName eq "" ){
        foreach my $mxbean_object ( @$mxbean_object_list ) {
            my $mxbean_name_attribute = $$mxbean_object{'name'};
            if ( $mxbean_name_attribute eq "java.lang:type=Runtime" ) {
                my $runtime_keylist = $$mxbean_object{'SystemProperties'};
                #    print Dumper(@runtime_keylist);
                foreach my $record ( @$runtime_keylist ){
                    if ( $$record{'key'} eq 'sun.java.command' ){
                        my @value = split(/\./, $$record{'value'});
                        $processName = pop( @value );
                    }
                }
            }
        }
    }
    if ( $processName eq "" ){
        print "[ERROR] Can't get the Hadoop process name.";
        exit 0;
    }
    return $processName;
}

# Parse raw JSON data to Zabbix infile format
# Usage: my @values = &parse_hadoop_jmx_metrics($mxbean_object_list, $hostname, $processName, $get_d    etail, $get_javalang, $debug_output);
sub parse_hadoop_jmx_metrics{
    my $json = JSON->new->allow_nonref;
    my @values;
    my ($mxbean_object_list, $zabbix_hostname, $processName, $get_detail, $get_javalang, $debug_output) = @_;

    # Get metrics data
    MXBEAN: foreach my $mxbean_object ( @$mxbean_object_list ) {
        my $service_name;
        my $mxbean_name;
        my $mxbean_name_attribute = $$mxbean_object{'name'};

        # Hadoop services
        # ex) Hadoop:service=NameNode,name=MetricsSystem
        if ( $mxbean_name_attribute =~ /^[hH]adoop:service=(\w+),name=(\w+)/ ) {
            my $service_name = $1;
            my $mxbean_name = $2;

            # Journalnode IPC Logger check
            if ( $$mxbean_object{'modelerType'} =~ /^IPCLoggerChannel/ ) {
                $mxbean_name = $$mxbean_object{"modelerType"};
            }

            foreach my $attribute ( keys %$mxbean_object ){
                # exclude useless attributes
                if ( $attribute =~ /^tag\.|^modelerType|^name/ ){
                #if ( $attribute =~ /^tag\.|^name/ ){
                    next;
                # insert "" to attributes with no value.
                } elsif ( !defined($$mxbean_object{$attribute}) ) { 
                    my $value = "null";
                    push(@values, "\"$zabbix_hostname\" $service_name.$mxbean_name.$attribute '$value'\n");
                # exclude attributes "RpcDetailedActivity" in default mode.
                } elsif ( $mxbean_name =~ /^RpcDetailedActivity/ && $get_detail == 0 ) { 
                    next;
                # count nodes in following attributes
                } elsif ( $attribute eq "LiveNodes" || $attribute eq "DeadNodes" || $attribute eq "DecomNodes" ) {
                    my $nodes = $json->decode($$mxbean_object{$attribute});
                    push(@values, "\"$zabbix_hostname\" $service_name.$mxbean_name.$attribute.count " . scalar keys (%$nodes) . "\n");
                # count active and failed name dirs
                } elsif ( $attribute eq "NameDirStatuses" ) {
                    # text output
                    my $value = $$mxbean_object{$attribute};
                    push(@values, "\"$zabbix_hostname\" $service_name.$mxbean_name.$attribute '$value'\n");

                    # count dirs number
                    my $name_dirs = $json->decode($$mxbean_object{$attribute});
                    my $failed_name_dirs = $$name_dirs{"failed"};
                    my $active_name_dirs = $$name_dirs{"active"};
                    push(@values, "\"$zabbix_hostname\" $service_name.$mxbean_name.$attribute.failed_count " . scalar keys (%$failed_name_dirs) . "\n");
                    push(@values, "\"$zabbix_hostname\" $service_name.$mxbean_name.$attribute.active_count " . scalar keys (%$active_name_dirs) . "\n");
                } else { 
                    my $value = $$mxbean_object{$attribute};
                    # erase "ForPort" in rpc and rpc metrics.
                    $mxbean_name =~ s/ForPort[0-9]+$//;
                    if ( looks_like_number($value) ) {
                        push(@values, "\"$zabbix_hostname\" $service_name.$mxbean_name.$attribute $value\n");
                    } else {
                        push(@values, "\"$zabbix_hostname\" $service_name.$mxbean_name.$attribute '$value'\n");
                    }
                }
            }
        } elsif ( $mxbean_name_attribute eq "java.lang:type=Memory" && $get_javalang == 1 ) {
            # replace ":" and "=" for zabbix key require
            my $service_name = "java.lang.type.Memory";
            my @memory_attributes = ( 'HeapMemoryUsage', 'NonHeapMemoryUsage' );
            foreach my $memory_attribute ( @memory_attributes ){
                my $mxbean_memory = $$mxbean_object{$memory_attribute};
                foreach my $attribute ( keys %$mxbean_memory ) {
                    my $value = $$mxbean_memory{$attribute};
                        push(@values, "\"$zabbix_hostname\" $processName.$service_name.$memory_attribute.$attribute $value\n");
                }
            }
        } else {
            if ( defined($debug_output) &&  $debug_output == 1 ){
                # Print Metrics that have not been caught
                warn "[Debug] Metrics that have not been caught.\n";
                foreach my $attribute ( keys %$mxbean_object ){
                    my $value = defined($$mxbean_object{$attribute}) ? $$mxbean_object{$attribute} : "";
                    warn "'$zabbix_hostname' $mxbean_name_attribute.$attribute '$value'\n";
                }
                warn "\n";
            }
            next;
        }
    }
    return @values;
}

