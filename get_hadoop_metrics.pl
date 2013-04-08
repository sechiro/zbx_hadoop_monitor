#!/usr/bin/perl
# Author: Seiichiro, Ishida<seiichiro.ishida0@gmail.com>
# Copyright 2013, Seiichiro, Ishida All rights reserved.
use strict;
use warnings;
use JSON;
use Data::Dumper;
use LWP::UserAgent;
use Getopt::Long;

# Constant
my $zabbix_server = "127.0.0.1";
my $zabbix_server_version = 1.8;
my $infile_tmp_dir = "/tmp/ZbxHadoopMonitor";

# Zabbix specification for external script has changed in Zabbix 2.0.
my $required_args_num = $zabbix_server_version <= 1.8 ? 3 : 2;

if ( @ARGV < $required_args_num ){
    print "[ERROR] Not enough arguments. Passed arguments are ";
    print "@ARGV\n";
    exit 0;
}

# script options
my $get_detail = 0;         # Add detailed-metrics
my $nosend = 0;             # Print to stdout only
my $dump_json = 0;          # Dump raw json data to stderr
my $getopt_result = GetOptions("detailed" => \$get_detail,
                                "nosend" => \$nosend,
                                "dump_json" => \$dump_json);

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

my $json = JSON->new->allow_nonref;
my $res;
eval {
my $ua = LWP::UserAgent->new();
my $req = HTTP::Request->new(GET => "http://$hostname:$port/metrics?format=json");
$res = $ua->request($req);
};
if( $@ ) {
    print "[ERROR] Couldn't access $hostname:$port ! \n";
    exit 0;
}

my $metrics_data;
eval {
    $metrics_data = $json->decode( $$res{'_content'} );
};
if( $@ ) {
    print "[ERROR] Couldn't Get Metrics Data from $hostname:$port ! \n";
    exit 0;
}
my $value_tmp;
my @values = ();

my $processName = $$metrics_data{'jvm'}{'metrics'}[0][0]{'processName'};
foreach my $key1 ( keys %$metrics_data ){
    next if ( $key1 eq 'fairscheduler' );
    $value_tmp = $$metrics_data{$key1};
    foreach my $key2 ( keys %$value_tmp ){
        next if ( $key2 eq 'detailed-metrics' && $get_detail == 0 );
        $value_tmp = $$metrics_data{$key1}{$key2};
        foreach my $key3 ( @$value_tmp ) {
            $value_tmp = $key3;
            foreach my $key4 ( @$value_tmp ) {
                $value_tmp = $key4;
                while ( my ( $key5, $value ) = each(%$value_tmp) ) {
                    next if ( $key5 eq 'hostName' || $key5 eq 'sessionId' || $key5 eq 'port' || $key5 eq 'processName' || $key5  eq 'Master' || $key5 eq 'RegionServer' );
                    if ( $key1 eq 'jvm' || $key1 eq 'rpc' ) {
                        #print "$zabbix_hostname $key1.$processName.$key2.$key5 $value\n";
                        push(@values, "\"$zabbix_hostname\" $key1.$processName.$key2.$key5 $value\n");
                    } elsif ( $processName eq 'SecondaryNameNode' && $key1 eq 'dfs' ) {
                        push(@values, "\"$zabbix_hostname\" $key1.$processName.$key2.$key5 $value\n");
                    } else {
                        #print "$zabbix_hostname $key1.$key2.$key5 $value\n";
                        push(@values, "\"$zabbix_hostname\" $key1.$key2.$key5 $value\n");
                    }
                }
            }
        }
    }
}

# Output stdout only
if ( $nosend == 1 ){
    print @values;
    exit 0
}

# Open temporary merics data file.
if (!-d $infile_tmp_dir) {
    mkdir $infile_tmp_dir
        or die "[ERROR] Couldn't make $infile_tmp_dir in /tmp !";
} elsif (!-w $infile_tmp_dir){
    print "[ERROR] Can't write in infile temporary directory $infile_tmp_dir !";
    exit 0;
}
my $zabbix_sender_infile = "$infile_tmp_dir/$hostname-$port.metrics-infile.dat";
open my $infile_fh, ">", "$zabbix_sender_infile"
    or die "[ERROR] Couldn't open $zabbix_sender_infile in /tmp !";

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

exit;
