#!/usr/bin/perl
# Hadoop プラグイン用テンプレート作成スクリプト
# 出力内容をファイルにリダイレクトして保存してください。
# Usage: ./get_hadoop_jmx.pl dummy_arg hostname port --nosend | ./convert_to_hadoop_tmpl.pl > template_name.xml

use strict;
use warnings;
use JSON;
use Data::Dumper;
use LWP::UserAgent;
use POSIX 'strftime';
use Switch;
use Scalar::Util qw/looks_like_number/;
my $date = strftime "%y.%m.%d", localtime;
my $time = strftime "%H.%M", localtime;

# Zabbixパラメータ定義
my $delay = "30";    # 監視間隔
my $history = "90";  # 生データ保存期間
my $trend = "365";   # サマリデータ保存期間

# Port
#my %ports = ( 'NameNode' => 50070, 'SecondaryNameNode' => 50090, 'DataNode' => 50075,
#    'JobTracker' => 50030, 'TaskTracker' => 50060);

my @values = <>; # Read from STDIN

# Get information from header
# ex) [INFO] Service: JobTracker IP: 192.168.97.131 Port: 50030
my @header = split(/ /, shift(@values) );
my $processName = $header[2];
my $port = $header[6];

my %service_name_hash = ();
foreach my $line ( @values ){
    my @record = split(/ /, $line);
    my @item_name = split(/\./, $record[1]);
    my $service_name = $item_name[1];
    $service_name_hash{$service_name} = 1;
}

my @service_name_list = keys %service_name_hash;

my $PROCESSNAME = uc $processName;

my $kind = 'Hadoop';
# $kind = 'HBase' if ( $PROCESSNAME eq "REGIONSERVER" || $PROCESSNAME eq "MASTER" ) ;

my $common_conf = do("zbx_tmpl_common.conf");
my $item_header = $common_conf->{'item_header'};

# データ型を整数型（BigInt）とする。
my $item_unit_int = $common_conf->{'item_unit_int'};
          
# MB単位で取得される値には、1024 * 1024を乗算し、単位をBとする。
# 上記の項目はkeyの最後の文字が「M」（jvm）もしくは「MB」（RS）となる。
# データ型は浮動小数とする。
my $item_unit_MB = $common_conf->{'item_unit_MB'};

# GB単位で取得される値には、1024 * 1024 * 1024を乗算し、単位をBとする。
# 上記の項目はkeyの最後の文字が「GB」（NN）となる。
# データ型は整数型（BigInt）とする。
my $item_unit_GB = $common_conf->{'item_unit_GB'};

# B単位で取得される値は、単位をBとする。
# データ型は整数型（BigInt）とする。
my $item_unit_B = $common_conf->{'item_unit_B'};

# データ型は浮動小数とする。
my $item_unit_float = $common_conf->{'item_unit_float'};
          
# データ型は浮動小数とする。
my $item_unit_string = $common_conf->{'item_unit_string'};

# Definition of Application.
my %item_footer_hash;
foreach my $service_name (@service_name_list){
    $item_footer_hash{$service_name} = '</description>
          <delay>' . $delay . '</delay>
          <history>' . $history . '</history>
          <trends>' . $trend . '</trends>
          <applications>
            <application>' . $kind . ' ' . $processName . ' ' . $service_name . '</application>
          </applications>
        </item>' . "\n";
}

##### テンプレート変数定義 ##############################################
my $template_name = $kind . '_' . $processName . '_JMX';
my $tmpl_header = '<?xml version="1.0" encoding="UTF-8"?>
<zabbix_export version="1.0" date="' . $date . '" time="' . $time .'">
  <hosts>
    <host name="' . $template_name .'">
      <proxy_hostid>0</proxy_hostid>
      <useip>1</useip>
      <dns></dns>
      <ip>127.0.0.1</ip>
      <port>10050</port>
      <status>3</status>
      <useipmi>0</useipmi>
      <ipmi_ip>127.0.0.1</ipmi_ip>
      <ipmi_port>623</ipmi_port>
      <ipmi_authtype>0</ipmi_authtype>
      <ipmi_privilege>2</ipmi_privilege>
      <ipmi_username></ipmi_username>
      <ipmi_password></ipmi_password>
      <groups>
        <group>Templates</group>
      </groups>';

# 監視スクリプトを実行し、実行ログを記録するアイテム
my $script_item = '        <item type="10" key="get_hadoop_jmx.pl[{HOST.CONN} {$' . $PROCESSNAME . 'PORT} &quot;{HOSTNAME}&quot;]" value_type="1">
          <description>' . $kind . ' ' . $processName . ' JMX Metrics 取得ログ</description>
          <ipmi_sensor></ipmi_sensor>
          <delay>' . $delay . '</delay>
          <history>' . $history . '</history>
          <trends>' . $trend . '</trends>
          <status>0</status>
          <data_type>0</data_type>
          <applications>
            <application>' . $kind . ' Monitor Script for ' . $processName . '</application>
          </applications>
        </item>';

my $DataNode_calc_item = '        <item type="15" key="DataNode.FSDatasetState.calc.PercentRemaining" value_type="0">
          <description>DataNode.FSDatasetState.calc.PercentRemaining</description>
          <delay>30</delay>
          <history>90</history>
          <trends>365</trends>
          <status>0</status>
          <data_type>0</data_type>
          <units>%</units>
          <params>last(DataNode.FSDatasetState.Remaining) / last(DataNode.FSDatasetState.Capacity) * 100</params>
          <applications>
            <application>Hadoop DataNode FSDatasetState</application>
          </applications>
        </item>';

my $tmpl_footer = '
      <templates/>
      <macros>
        <macro>
          <value>' . $port . '</value>
          <name>{$' . $PROCESSNAME . 'PORT}</name>
        </macro>
      </macros>
    </host>
  </hosts>
  <dependencies/>
</zabbix_export>';

my $common_triggers = '        <trigger>
          <description>' . $kind . ' ' . $processName . ' Log Error</description>
          <type>1</type>
          <expression>{' . $kind . '_'  . $processName . '_JMX:' . $processName . '.JvmMetrics.LogError.change(0)}&gt;0</expression>
          <url></url>
          <status>0</status>
          <priority>3</priority>
          <comments></comments>
        </trigger>
        <trigger>
          <description>' . $kind . ' ' . $processName . ' Log Fatal</description>
          <type>1</type>
          <expression>{' . $kind . '_'  . $processName . '_JMX:' . $processName . '.JvmMetrics.LogFatal.change(0)}&gt;0</expression>
          <url></url>
          <status>0</status>
          <priority>4</priority>
          <comments></comments>
        </trigger>
        <trigger>
          <description>' . $kind . ' ' . $processName . ' Log Warn</description>
          <type>1</type>
          <expression>{' . $kind . '_'  . $processName . '_JMX:' . $processName . '.JvmMetrics.LogWarn.change(0)}&gt;0</expression>
          <url></url>
          <status>0</status>
          <priority>2</priority>
          <comments></comments>
        </trigger>
        <trigger>
          <description>' . $kind . ' ' . $processName . ' Metrics 取得失敗</description>
          <type>1</type>
          <expression>(({' . $kind . '_' . $processName . '_JMX:get_hadoop_jmx.pl[{HOST.CONN} {$' .  $PROCESSNAME . 'PORT} "{HOSTNAME}"].regexp(ERROR)})#0)</expression>
          <url></url>
          <status>0</status>
          <priority>4</priority>
          <comments></comments>
        </trigger>';

#######################################################################

my $metrics_items;
my $item_name;


foreach my $line (@values){
    chomp $line;
    my ($zabbix_host, $item_key, $value) = split(/ /,$line,3);

    # Note: java.lang.type.Memory is not work well but it is enough for this script.
    my ($process_name, $service_name, $mxbean_name) = split(/\./,$item_key,3);
    # Note: For items like 'IPCLoggerChannel-10.0.4.1-8485'
    if ( $service_name =~ /IPCLoggerChannel/ ){
        $service_name = "IPCLoggerChannel";
        my @pop_lastitem = split(/\./,$mxbean_name);
        $mxbean_name = pop( @pop_lastitem );
    }
    &make_template($item_key, $service_name, $mxbean_name, $value);
}

sub make_template{
   my ($item_key, $service_name, $mxbean_name, $value) = @_;
   my $item_footer = $item_footer_hash{$service_name};
   if ( $item_key =~ /MB|M$/ ) {
       $metrics_items .= $item_header . $item_key . $item_unit_MB . $item_key . $item_footer;
   } elsif ( $item_key =~ 'GB$' ) {
       $metrics_items .= $item_header . $item_key . $item_unit_GB . $item_key . $item_footer;
   } elsif ( $item_key =~ '_max$' || $item_key =~ '_mean$' || $item_key =~ '_median$' || $item_key =~ '_min$' 
       || $item_key =~ '_std_dev$' || $item_key =~ '_percentile$' || $item_key =~ 'cluster_requests$') {
       $metrics_items .= $item_header . $item_key . $item_unit_float . $item_key . $item_footer;
   } elsif ( $item_key =~ '[tT]ime$' && !($item_key eq "NameNode.FSNamesystem.LastCheckpointTime") ) {
       $metrics_items .= $item_header . $item_key . $item_unit_float . $item_key . $item_footer;
   } elsif ( $service_name eq "java.lang.type.Memory" ) {
       $metrics_items .= $item_header . $item_key . $item_unit_B . $item_key . $item_footer;
   } elsif ( looks_like_number($value) ) {
       $metrics_items .= $item_header . $item_key . $item_unit_int . $item_key . $item_footer;
       if ( $value =~ /^\d+\.\d+/ ) {
           $metrics_items .= $item_header . $item_key . $item_unit_float . $item_key . $item_footer;
       } elsif ( $value eq "true" ) {
           $metrics_items .= $item_header . $item_key . $item_unit_string . $item_key . $item_footer;
       }
   } else {
       $metrics_items .= $item_header . $item_key . $item_unit_string . $item_key . $item_footer;
   }
}
my $item_definition;
if ( $processName eq "DataNode" ){
    $item_definition = '<items>' . $metrics_items . $script_item . $DataNode_calc_item . '</items>';
} else {
    $item_definition = '<items>' . $metrics_items . $script_item . '</items>';
}

my $graph_definition = '<graphs/>';
my $trigger_definition = '<triggers/>';

# output
my $zbx_tmpl = $tmpl_header . $item_definition . $graph_definition . $trigger_definition . $tmpl_footer;
print $zbx_tmpl . "\n";

exit;
