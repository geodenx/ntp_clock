# NTP Clock using PICNIC
秋月電子通商の PICNIC を改造し、NTP (Network Time Protocol) を実装した時計を開発しました。
正確な時刻をインターネット上の NTP サーバ (情報通信研究機構) から取得し、その時刻情報を時計の較正に利用します。

<img src="https://github.com/geodenx/ntp_clock/blob/img/img/system.png" width="320" height="103"/>

PICNIC の PIC16F877 のファームウェアを書き換えるだけで LCD に日本標準時 (JST) を表示させることが可能です。 さらにスイッチ付き拡張 I/O 基板を付ければ、 IP アドレス、ネットマスク、ゲートウェイアドレス、NTP サーバアドレスの設定を焼き込まなくても設定可能になります。 詳しくは詳細仕様書を御覧ください。<br />

[詳細仕様書](https://www.dropbox.com/s/f8mwq441tuh3fos/spec.pdf)

We developed a clock that has Network Time Protocol (NTP) implemented by modifying PICNIC, sold by Akitsuki Denshi. The clock fetches the time information from NTP server at National Institute of Information and Communications Technology. It utilizes the information for the time synchronization.<br />
Japan Standard Time (JST) can be displayed on LCD, by only overwriting the firmware for PIC16F84. If you add the extended switches board to PICNIC, you can configure IP address, netmask, gateway address and NTP server address without the firmware re-compilation. Please see the above spec.pdf (in Japanese) for further details.<br />

## 作り方 (簡易版)
細かい情報は詳細仕様書に書きました。参照してください。

1. PICNIC組み立て
2. 拡張I/O回路作製

(最低限の機能限定ならば、 IP アドレスなどの設定をアセンブル時にすれば拡張I/O基板を作製しなくても使用可能です。)
PICNIC の拡張基板用コネクタに接続する RA0-3 にプッシュスイッチをつけた拡張基板を作る。
[回路図](https://github.com/geodenx/ntp_clock/blob/img/img/ext2.ce2.png)

3. コーディング, アセンブル
[ntp0067.asm](ntp0067.asm) (EUC)

アセンブラソース (ntp*.asm) に IP アドレス、ネットマスク、ゲートウェイアドレス、NTP サーバアドレスを書き込む
（拡張I/O基板としてスイッチを作ればこれらの IP などの設定は後からスイッチで変更できます）。

4. PA-3.0.5 でアセンブラソースファイルをアセンブル

5. PIC書き込み

生成された hex ファイルを PIC ライタで PIC16F877-20MHz に書き込む。

Configuration bit: 3F32

6. 完成
<img border="0" src="https://github.com/geodenx/ntp_clock/blob/img/img/DSCF0003.jpg" width="200" height="150" />


## ISA-Bus NIC NTP Clock
<img src="https://github.com/geodenx/ntp_clock/blob/img/img/isanic.jpg" width="200" height="140" />
ほぼPICNICの回路図のまま ISA-Bus NIC [Planex ENW-2401P-T](http://www.planex.co.jp/product/adapter/enw2401pt.shtml) を利用して NTP Clock を作成してみました。 
PIC のクロックは 12.8000 MHz の高精度水晶モジュールを使用しています。
これでネットワークに繋がらなくても月差が数秒になります。
せっかく時間精度がよくなったのでネットワーク遅延による誤差も補正できるようにしました。
1時間に一度自動的に較正します。
この二つの機能によって、+-0.02 sec の誤差で常に JST を保持することができます。 

コレガの ISA-Bus NIC [CG-E2ISAT](http://www.corega.co.jp/product/list/lanadp/e2isat.htm)は RTL8019AS の JP ピンを H に上げないと動きません。
また、他の NIC は確認していません。 

マザーボード基板データ (PCB): [isanic4.pdf](https://www.dropbox.com/s/1i3c02618bu131s/isanic4.pdf?dl=0)

<img src="https://github.com/geodenx/ntp_clock/blob/img/img/DSCF0040s.jpg" width="200" height="154">
<img src="https://github.com/geodenx/ntp_clock/blob/img/img/DSCF0036s.jpg" width="200" height="165">

## UEC Electronics Contest (2001)
NTP Clock は <a href="http://www.gp.uec.ac.jp/elecon/">UEC Electronics Contest</a> にエントリし、総合優勝することが出来ました。関係者の皆様に感謝いたします。
- 配布資料：簡易仕様書 2nd edition <a href="https://www.dropbox.com/s/rdafwd57sh8t1un/spec3.pdf?dl=0">spec3.pdf</a>
- プレゼンテーション <a href="https://www.dropbox.com/s/ftkvk73k9z6sr53/pr.ppt?dl=0">pr.ppt</a> 551KB 展示ポスタ
- <a href="https://www.dropbox.com/s/8gm8qbi1kzoi3t2/poster.ppt?dl=0">poster.ppt</a>

## NICT NTP Client Contest (2006)
高精度バージョンの ISA-Bus NIC NTP Clock 「時缶 (トキカン)」が独立行政法人情報通信研究機構 [NTP クライアントコンテスト](http://www2.nict.go.jp/w/w114/stsi/PubNtp/Contest/contest_result.html) で優秀賞を頂きました (December 15, 2006)．
- <a href="http://www2.nict.go.jp/w/w114/stsi/PubNtp/Contest/contest_result.html">NICT 公開NTP クライアントコンテスト</a> [nict.go.jp]
- <a href="http://www2.nict.go.jp/pub/whatsnew/press/h18/061215-1/061215-1.html">「NICT公開NTPクライアントコンテスト」授賞者決定！ (報道資料)</a> [nict.go.jp]
- <a href="http://www.forest.impress.co.jp/article/2006/12/15/ntpconresult.html">情報通信研究機構、“NICT NTP クライアントコンテスト”の審査結果を発表</a> [impress.co.jp]

## 開発者向け情報
- NTP Clock frimware for PICNIC ver.2 [ntp0067.asm](ntp0067.asm) (EUC)
- [ChangeLog](ChangeLog)
- <a href="https://www.dropbox.com/s/nbx8iyvrltsmqjg/ntp0045.png?dl=0">Ethernet log (ntp0045e.asm on PICNIC)</a>
- <a href="https://www.dropbox.com/s/ye67xb691p9faey/etherealdump.png?dl=0">Ethernet log (ntpdate on Linux)</a>
- 拡張I/O基板 <a href="https://github.com/geodenx/ntp_clock">ext2.pcb (extended board design for PCBE)</a>
- <a href="https://www.dropbox.com/s/u1hyiuax0quk2be/ext2.pcb.png?dl=0">ext2.pcb.png (PCBE exported image: png 12KB)</a>
- <a href="https://github.com/geodenx/ntp_clock">ext2.ce2 (circuit chart for CE2)</a>
- <a href="https://www.dropbox.com/s/09wljgkjgtrongq/ext2.ce2.png?dl=0">ext2.ce2.png (exported image: png 3KB)</a>
- <a href="https://www.dropbox.com/s/swjfl2t7hcy5euh/DSC00016.JPG?dl=0">基板写真裏 (jpeg 66KB)</a>
- <a href="https://www.dropbox.com/s/71khwtgx56yr5a4/DSC00022.JPG?dl=0">基板写真表 (jpeg 71KB)</a>
注）CMOSの未使用Pinの処理をしていませんでした。未使用の入力PinはVccに繋げるかかGNDに落してください。

## Contributors
- YOKOBORI Masayuki miyabi at uranus.interq.or.jp 企画/原案
- Clock routine, User Interface, Network routine, and others. OKAZAKI Atsuya

## References
- <a href="http://www.tristate.ne.jp/">TriState</a> (PICNIC製作) [tristate.ne.jp]<br />
- <a href="http://www.tristate.ne.jp/picnic/menu.html">PICNICのひろば (PA-3.0.5 Windows版 配布元)</a> [tristate.ne.jp]<br />
- 秋月電子通商 (PICNIC販売) <a href="http://pic.strawberry-linux.com/pa/">PA-3.0.5</a> [strawberry-linux.com] (assembler)<br />
- <a href="http://www.realtek.com.tw/">RTL8019AS (RealTek Ethernet Controller)</a> [realtek.com.tw]<br />
- <a href="http://www.jst.mfeed.ad.jp/">Experimental NTP Servers</a> [jst.mfeed.ad.jp] RFC958 (NTP) RFC2030 (SNTP)<br />
- <a href="http://elecon.ee.uec.ac.jp/">Electronics Contest (ELECON) @UEC</a> [elecon.ee.uec.ac.jp]<br />
- <a href="http://elecon.ee.uec.ac.jp/~elec0101/">NTP Clock another web page on ELECON@UEC</a> [elecon.ee.uec.ac.jp]<br />


##  Perl NTP Client
UNIX では ntpdate, ntpq, xntpd などの NTP クライアント、サーバがあります。
既存のものを重複して作るのも意味が無いですし、素人には ntpdate より高性能で軽いプログラムなど書けません。
実際にカーネルの時刻同期をするのなら ntpdate などを利用することをお勧めします。

ここでは NTP (UDP) プロトコル, Perl でのネットワークプログラミングの勉強を兼ねて Perl スクリプトを書いてみました。
秒の整数部までを NTP サーバから取得して表示するだけのスクリプトです。
<a href="https://github.com/geodenx/ntp_clock/blob/master/ntp.pl">ntp.pl</a>

実行結果
```
$ perl ntp.pl
packet to sent:
--- B32 B32 B32 B32 B64 B64 B64 B64 ---
   01234567890123456789012345678901
0: 00001011000000000000000000000000
1: 00000000000000000000000000000000
2: 00000000000000000000000000000000
3: 00000000000000000000000000000000
4: 0000000000000000000000000000000000000000000000000000000000000000
5: 0000000000000000000000000000000000000000000000000000000000000000
6: 0000000000000000000000000000000000000000000000000000000000000000
7: 0000000000000000000000000000000000000000000000000000000000000000
Host: ftp07.apple.com, Port: 123

returned packet:
--- B32 B32 B32 B32 B64 B64 B64 B64 B*---
   01234567890123456789012345678901
0: 00001100000000110000010011110001
1: 00000000000000000000011100110100
2: 00000000000000000000101001111011
3: 01000000101010100110001000001010
4: 1011111011111011101001010110000000010011110010100111000000000000
5: 0000000000000000000000000000000000000000000000000000000000000000
6: 1011111011111011101001011000110010110011010010010110000000000000
7: 1011111011111011101001011000110010110011010110010001000000000000
8: 
--- N* ---
0: 201524465
1: 1844
2: 2683
3: 1084908042
4: 3204162912
5: 332034048
6: 0
7: 0
8: 3204162956
9: 3007930368
10: 3204162956
11: 3008958464
                               $TransmitTime: 3204162956
NTP time:  Sun Jul 15 14:15:56 2001    $ntp:  995174156
localtime:  Sun Jul 15 14:15:57 2001  time():  995174157
```

### NTP Message Format (RFC2030 Section 4)

```
1                   2                   3
        0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
0 (0)  |LI | VN  |Mode |    Stratum    |     Poll      |   Precision   |
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
1 (1)  |                          Root Delay                           |
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
2 (2)  |                       Root Dispersion                         |
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
3 (3)  |                     Reference Identifier                      |
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
       |                                                               |
4      |                   Reference Timestamp (64)                    |
(4,5)  |                                                               |
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
       |                                                               |
5      |                   Originate Timestamp (64)                    |
(6,7)  |                                                               |
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
       |                                                               |
6      |                    Receive Timestamp (64)                     |
(8,9)  |                                                               |
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
       |                                                               |
7      |                    Transmit Timestamp (64)                    |
(10,11)|                                                               |
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
       |                 Key Identifier (optional) (32)                |
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
       |                                                               |
       |                                                               |
       |                 Message Digest (optional) (128)               |
       |                                                               |
       |                                                               |
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

64bit timestamp format
```
       0                   1                   2                   3   
       0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
       |                         Integer Part                          |
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
       |                         Fraction Part                         |
       +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### References
- RFC2030 (SNTP) Oreily "Perl Cookbook" section 17.4 (UDP client) <a href="http://www.ntp.org/" target=top>Network Time<br />
- Protocol project</a> [ntp.org] <a href="http://www.atmarkit.co.jp/icd/root/61/5784861.html" target=top>SNTP</a> @IT 用語辞典 [atmarkit.co.jp] </p>

# PIC development environment for Linux
<a href="http://www.microchip.com">Microchip社</a>のPICマイコンをLinuxで開発する場合の方法について書きます。
秋月のライタとPAアセンブラを利用します。

## Install
いろいろな言語で開発できるようですが、ここでは一番一般的なアセンブラを使用します。
アセンブラのなかでも Microchip 社の配布している MPLAB に付属している MPASM ではなく、秋月電子通商の PIC ライタキットに付属していた PA アセンブラを使用します。
PA アセンブラ開発者の方の<a href="http://pic.strawberry-linux.com/">サイト</a> [strawberry-linux.com] には Linux 版の PA があります。
この PA は、後ほどパッチを当てなければならないので、make する前にライタソフトの準備をします。

秋月の PIC ライタキット用の <a href="http://members.jcom.home.ne.jp/pnms/akipic.html">Linux 版ライタソフト</a> [jcom.ne.jp] を作って公開されている方がいます。
README を良く読んでください。
現時点 (Sep 2001) では PA にパッチを当てるように指示が出ているのでその通りにします。
次に、このライタソフトを make し、最後に PA を make します。
PA の make の際に yacc と lex が必要なので、予め bison (yacc) と flex (lex) をインストールしておきました。
これで Linux での PIC 開発環境が整います。
PA のシミュレータやデバッガが無く、MPLAB に比べるとまだまだですが、最低限の開発はできます。
シミュレータなどご存知の方は教えてください。 

## 使い方
PAアセンブラを書いてからアセンブルします。
```
$ pa -m sample2.asm 16f84.h
```
つぎに、ライタをシリアルポートに接続してアセンブルされたhexファイルを書き込みます。
```
# akipic -p /dev/ttyS0 -d 16f84a -e
Erase OK
# akipic -p /dev/ttyS0 -d 16f84a -w sample2.hex 
ID information...
   0xf 0xf 0xf 0xf 
config word status...
   CP      disable
   PWRTE   enable
   WDTE    disable
   FOSC    HS
Program memory = 0056
Data memory = 003F
Config word = 0007
```
他にもオプションなどいろいろな機能があるので、PA や AKIPIC 付属のドキュメントを読んでください。

## FYI
使ったことはありませんが、秋月のライタやPAアセンブラではなくて [GNUPIC](http://www.gnupic.org) というものもあります。
simulatorなど開発環境が充実しるようです。
また、トランジスタ技術 2000年9月号には PA を Linux で使う詳しい記事が掲載されています。 </p>
