Zabbix Hadoop Monitor
=====================

## What is it?

このツールは、ZabbixにてHadoopのメトリクスを収集するためのツールです。Zabbixの外部スクリプトとして動作します。以下の環境で動作確認をしています。

* CDH3u6
* CDH4.2 + MRv1

    * HBase向けのものもいずれ出す予定です。


## 動作に必要な前提条件

* 監視対象となるHadoop、HBaseが正常に動作していること。
* Zabbixサーバがセットアップされ、外部スクリプトによる情報収集が可能になっていること。
    * このスクリプトはZabbix 1.8 および Zabbix 2.0 の両方に対応しています。ただし、Zabbix 2.0 での動作確認がまだできていません。Zabbix 2.0 でもスクリプト起動用のアイテムだけ手動で修正すれば動くはずです。
    * 参考情報： http://thinkit.co.jp/story/2012/04/27/3535?page=0,1
* ZabbixサーバにPerlのJSONモジュールがインストールされていること。
    * スクリプト内部でPerlのJSONモジュールを使用します。導入されていない場合は、適宜インストールを行ってください。
        * 例：CentOSのリポジトリからインストールを行う場合
            * $ sudo yum install perl-JSON

<br>
# 1. 導入方法
## 1.1 情報収集スクリプトの配置 

Zabbixサーバの外部スクリプトディレクトリが "/etc/zabbix/externalscripts" となっている環境であれば、以下のコマンドにてスクリプトの配置を行うことができます。

```
 $ git clone zbx_hadoop_monitor
 $ cd zbx_hadoop_monitor
 $ sudo cp get_hadoop_jmx.pl /etc/zabbix/externalscripts/
 $ sudo chmod 755 /etc/zabbix/externalscripts/get_hadoop_jmx.pl
```

上記以外をZabbixサーバの外部スクリプトディレクトリとしている場合は、手動でファイルを配置してください。

/tmp/Zbx


Zabbix 2.0 で利用する場合は、スクリプトの以下の箇所を書き換えてください。Zabbix 2.0 では、外部スクリプトに渡す引数の仕様が変更になっているため、このバージョン指定が必要になっています。

    my $zabbix_server_version = 1.8;

        ↓

    my $zabbix_server_version = 2.0;


### 1.2 Zabbixテンプレートのインポート

本サイトのtemplateディレクトリに配置されているXMLファイルをZabbixよりインポートしてください。

ただし、このリポジトリで配布しているテンプレートは、標準的な構成のみに対応したものになります。Namenode HAでのQJMへのメタデータ書き込み状況など、その中に含まれないメトリクスを監視する場合は、添付ツールにてテンプレートを生成する必要があります。


### 1.2.3 監視対象へのテンプレート適用

前項でインポートしたテンプレートを対応するサービスが動作しているサーバに適用してください。情報収集が開始されます。


<br>
# 2. このツールの動作仕様について

## 動作概要
このツールは、Zabbixの外部スクリプトアイテムにて情報収集スクリプトを起動し、各HadoopサービスからJSON形式で情報を取得し、それを整形してzabbix\_senderを使って、メトリクスごとの監視アイテムに登録します。

外部スクリプトを起動する監視アイテムには、スクリプトの実行結果が登録されます。通常時はここにzabbix\_senderの戻り値が登録されます。テンプレートに登録されていないアイテムがある場合は、そのログから確認することができます。また、スクリプトが動作したのちに、情報取得に失敗している場合はエラーメッセージが登録されます。


## スクリプトオプション
このツールには以下のオプションがあります。オプションはこのスクリプトを直接実行する場合だけでなく、Zabbix上から実行する場合にも指定出来ます。Zabbix上からオプション付きで実行する場合は、Zabbixの外部スクリプト実行用のアイテムにオプションをそのまま記述してください。

* --detailed

Hadoopが提供しているメトリクスの中のRPC Detailed Metricsに分類されているものを収集するオプションです。

メソッドごとの実行時間などの詳細なデータを取得することができますが、取得データ量が多くなってしまうため、デフォルトでは取得しないようになっています。

* --nosend

取得結果をZabbixに送信せず、標準出力に出力するオプションです。スクリプト単体での動作確認やテンプレート生成スクリプトにデータを渡す際に利用します。

* --dump_json

スクリプトデバッグ用のオプションです。標準エラー出力にJSONデータのDumpを出力します。

* --debug_output

こちらもスクリプトデバッグ用のオプションです。通常は使用しないJSONデータも、Zabbixに送信するデータ形式に変換し、標準出力に出力します。

## Zabbix Proxy構成への対応
このツールはZabbix Proxy構成でも動作します。その場合は、ここで紹介しているインストール手順に準じて、Zabbix Proxyの外部スクリプトディレクトリにスクリプトを配置してください。

<br>
# 3. 付属ツールを使ったZabbixテンプレートの生成

## テンプレート生成ツールの基本的な使い方

本ツールには、情報収集スクリプトがHadoopサービスから取得したデータをもとにZabbixテンプレートを生成するスクリプトが付属しています。情報収集スクリプトにはこのツールと連携するため、Zabbixにデータを送信せず、標準出力に取得結果を出力するオプションがあり、以下のように使用します。

```
 $ ./get_hadoop_jmx.pl dummy_arg hostname port --nosend | ./convert_to_hadoop_tmpl.pl > template_name.xml
```

Zabbix 1.8 では、外部スクリプトの第一引数にそのアイテムが属しているホストのIPかDNS名が入りますが、このスクリプトではそれを利用していないため、スクリプトの第一引数には任意のものをダミーで入力してください。

たとえば、QJMを使ったNamenode HA構成では、Journalnodeへの書き込み遅延に関するメトリクスが取得可能です。ただし、そのメトリクス名がJournalnodeのIPアドレスとポート番号に依存するため、その環境でテンプレートの生成を行う必要があります。

### テンプレート生成ツールの制限事項

このツールは、テンプレート生成時点でHadoopサービスから取得されているデータを元にZabbix上でのデータ型を決定します。そのため、Hadoopサービスから通常運用時とは異なるデータ型のデータが出力されていたりする場合は正しいデータ型を設定できません。また、運用中に初回設定時のデータ型ではデータが格納できなくなることもあります。それらは適宜手動で調整してください。


----
# Copyright and license

Copyright 2013 Seiichiro, Ishida

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
