Zabbix Hadoop Monitor
=====================

------

# 現在工事中です。

------

## What is it?

このツールは、ZabbixにてHadoopとHBaseのメトリクスを収集するためのツールです。Zabbixの外部スクリプトとして動作します。以下の環境で動作確認をしています。

* CDH3
* CDH4 + MRv1


## 動作に必要な前提条件

* 監視対象となるHadoop、HBaseが正常に動作し、後述する事前設定が済んでいること。
* Zabbixサーバがセットアップされ、外部スクリプトによる情報収集が可能になっていること。
* ZabbixサーバにPerlのJSONモジュールがインストールされていること。
* スクリプト内部でPerlのJSONモジュールを使用します。導入されていない場合は、適宜インストールを行ってください。
 * 例：CentOSのリポジトリからインストールを行う場合
     *  $ sudo yum install perl-JSON


# 1. 導入方法

## Hadoop and HBase 事前設定

Hadoopサービスから本ツールがメトリクスを取得できるようするため、以下の設定を行います。

### CDH3向け設定
CDH3に対する情報収集を行う場合は、Metrics Servletを有効にして、そこから情報取得ができるようにする必要があります。
すでにGangliaでのメトリクス収集を行っている場合は、Metrics Servletも同時に有効になっているので、追加の設定は必要ありません。Metrics Servletのみ有効にする場合は、以下の通りの設定を行い、クラスタ全体に配布し、該当のHadoopサービスの再起動を行ってください。

/etc/hadoop/conf/hadoop-metrics.properties


    dfs.class=org.apache.hadoop.metrics.spi.NoEmitMetricsContext
    dfs.period=30
    mapred.class=org.apache.hadoop.metrics.spi.NoEmitMetricsContext
    mapred.period=30
    jvm.class=org.apache.hadoop.metrics.spi.NoEmitMetricsContext
    jvm.period=30
    rpc.class=org.apache.hadoop.metrics.spi.NoEmitMetricsContext
    rpc.period=30
    ugi.class=org.apache.hadoop.metrics.spi.NoEmitMetricsContext
    ugi.period=30


/etc/hbase/conf/hadoop-metrics.properties

    hbase.class=org.apache.hadoop.metrics.spi.NoEmitMetricsContext
    hbase.period=30
    jvm.class=org.apache.hadoop.metrics.spi.NoEmitMetricsContext
    jvm.period=30
    rpc.class=org.apache.hadoop.metrics.spi.NoEmitMetricsContext
    rpc.period=30
    ugi.class=org.apache.hadoop.metrics.spi.NoEmitMetricsContext
    ugi.period=30



### CDH4向け設定
#### HDFS(Namenode, SecondaryNamenode, Datanode, Journalnode)
これらのコンポーネントはデフォルトでJMX Servletによるメトリクス取得ができるようになっています。そのため、特に追加の設定は必要ありません。

#### それ以外（JobTracker、TaskTracker、HBase Master、HBase Regionserver）
これらのコンポーネントは、JMX Servletによるメトリクス取得ができないため、Metrics Servletを有効にして、そこから情報取得ができるようにする必要があります。設定方法はCDH3でのMetrics Servletの設定と同様です。



### CDH3、CDH4共通：TaskTrackerポートの固定
TaskTrackerから取得するメトリクス名を固定するため、mapred-site.xmlに以下の設定を加え、クラスタ全体に配布します。設定を終えたら、TaskTrackerを再起動してください。

    <property>
      <name>mapred.task.tracker.report.port</name>
      <value>50050</value>
    </property>

* この設定を行う趣旨は以下のブログに書いているので、そちらをご覧ください。
 * http://sechiro.hatenablog.com/entry/20120411/1334094242


## 本ツールの導入

### 情報収集スクリプトの配置 

Zabbixサーバの外部スクリプトディレクトリが "/etc/zabbix/externalscripts" となっている環境であれば、以下のコマンドにてスクリプトの配置を行うことができます。

```
 $ git clone zbx_hadoop_monitor
 $ cd zbx_hadoop_monitor
 $ ./install.sh
```

上記以外をZabbixサーバの外部スクリプトディレクトリとしている場合は、手動で以下のようにファイルを配置してください。


### Zabbixテンプレートのインポート

本サイトのtemplateディレクトリに配置されているXMLファイルをZabbixよりインポートしてください。
（配布しているテンプレートは、標準的な構成のみに対応したものになります。その中に含まれないメトリクスを監視する場合は、添付ツールにてテンプレートを生成する必要があります）


### 監視対象へのテンプレート適用

前項でインポートしたテンプレートを対応するサービスが動作しているサーバに適用してください。情報収集が開始されます。

----
# このツールの動作仕様について

## 動作概要
このツールは、Zabbixの外部スクリプトアイテムにて情報収集スクリプトを起動し、各HadoopサービスからJSON形式で情報を取得し、それを整形してzabbix\_senderを使って、メトリクスごとの監視アイテムに登録します。
外部スクリプトを起動する監視アイテムには、スクリプトの実行結果が登録されます。通常時はここにzabbix\_senderの戻り値が登録されます。テンプレートに登録されていないアイテムがある場合は、そのログから確認することができます。また、スクリプトが動作したのちに、情報取得に失敗している場合はエラーメッセージが登録されます。


## スクリプトオプション
このツールには以下のオプションがあります。（特に明記されていないものは、スクリプト共通のオプションです）

* --detailed
detailed metrics
メソッドごとの実行時間などの詳細なデータを取得することができますが、取得データ量が多くなってしまうため、デフォルトでは取得しないようになっています。
このメトリクスを使う場合は、スクリプト実行時に"--detailed"というオプションをつけてください。

* --javalang (get_hadoop_jmx.pl only)

JMX Servlet 経由で取得できる情報には、Hadoopサービス固有のもののほかに、一般的なJMXの値も含めまれています。そのうち、"java.lang"に分類されているヒープ使用量等を追加取得するためのオプションです。Hadoopサービス固有のメトリクスと重なっている部分が多いため、デフォルトではオフになっています。

* --nosend

取得結果をZabbixに送信せず、標準出力に出力するオプションです。


* --dump_json

スクリプトデバッグ用のオプションです。標準エラー出力にJSONデータのDumpを出力します。


## Zabbix Proxy構成への対応
このツールはZabbix Proxy構成でも動作します。その場合は、ここで紹介しているインストール手順に準じて、Zabbix Proxyの外部スクリプトディレクトリにスクリプトを配置してください。

----
# 付属ツールを使ったZabbixテンプレートの生成

## テンプレート生成ツールの基本的な使い方

本ツールには、情報収集スクリプトがHadoopサービスから取得したデータをもとにZabbixテンプレートを生成するスクリプトが付属しています。情報収集スクリプトにはこのツールと連携するため、Zabbixにデータを送信せず、標準出力に取得結果を出力するオプションがあり、以下のように使用します。

```
 $ ./get_hadoop_metrics.pl dummy hostname port --nosend | ./convert_infile.pl > template_name.xml
```

たとえば、QJMを使ったNamenode HA構成では、Journalnodeへの書き込み遅延に関するメトリクスが取得可能です。ただし、そのメトリクス名がJournalnodeのIPアドレスとポート番号に依存するため、その環境でテンプレートの生成を行う必要があります。


## グラフ、トリガー設定も含めた自動生成

取得対象に合わせたコンフィグファイルを作成することで、グラフやトリガーを含んだテンプレートを生成することができます。使い方は申し訳ないですが、ソースコードを参照してください。

