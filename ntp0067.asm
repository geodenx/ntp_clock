;===================================================================================
; NTP Clock - Network Time Protcol Clock -
; ntp0067.asm (EUC)
;
;
;			Last modified: Jan 5, 2002
;			OKAZAKI Atsuya (atsuya@mac.com)
;			YOKOBORI Masayuki (miyabi@uranus.interq.or.jp)
; 
; 
;  This program is free software; you can redistribute it and/or
;  modify it under the terms of the GNU General Public License
;  as published by the Free Software Foundation; either version 2
;  of the License, or (at your option) any later version.
; 
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
; 
;  You should have received a copy of the GNU General Public License
;  along with this program; if not, write to the Free Software
;  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
; 
; 
; LCD Flag
;	A: transmitted ARP request packet
;	a: received ARP reply from NTP Server or Gateway
;	N: transmitted NTP request packet
;	n: Received NTP packet form server
;
;-----------------------------------------------------------------------------------
		.include	16f877.h

		.osc		hs		; オシレータHS
		.wdt		off		; ウォッチドッグOFF
		.pwrt		on		; Power Up Timer ON
		.protect	off		; Protect OFF
		.bod		on		; BOD ON

;-----------------------------------------------------------------------------------
NTP_PACKET_SIZE	equ	48		; NTP Packet size

;-----------------------------------------------------------------------------------
; EEPROM data
	eeorg	0	; DATA用EEPROMの初期値をセットする際の開始アドレスを指定
	
	eedata	192,168,0,29	; IP address
	eedata	255,255,255,0	; net mask
	eedata	192,168,0,1	; GateWay
	eedata	210,173,160,27	; NTP Server IP address	ntp1.jst.mfeed.ad.jp
;	eedata	0,0,6,5		; Farmware Version x,x,x,x
	eedata	0
	
;-----------------------------------------------------------------------------------
;
;		プロトコル番号など
;
COM_PROTO	equ	08h			; HIGH BYTE(共通)
IP_PROTO	equ	00h			; LOW BYTE (0800h means IP packet)
ARP_PROTO	equ	06h			; LOW BYTE (0806h means ARP packet)

UDP_PROTO	equ	17
ICMP_PROTO	equ	1

;
;		RTL8019AS関連設定項目
;
PAGE_BEGIN	equ	40h			; メモリ先頭アドレス
PAGE_START	equ	46h			; 受信バッファ先頭アドレス
PAGE_STOP	equ	80h			; 受信バッファ終端アドレス

; DATA_SIZE	equ	18

;
;		Ethernet関連設定項目
;
NE_SIZE		equ	4			; RTL8019ステータスエリアサイズ
PACKET_SIZE	equ	6+6+2			; Ethernetヘッダサイズ
ARP_SIZE	equ	28			; ARPパケットサイズ
IP_SIZE		equ	20			; IP(基本)ヘッダサイズ
UDP_SIZE	equ	8			; UDPヘッダサイズ

;-----------------------------------------------------------------------------------
;		I/Oポート設定
;-----------------------------------------------------------------------------------
SA		equ	rc			; NE2000 アドレスバス
SA0		equ	rc.0
SA1		equ	rc.1
SA2		equ	rc.2
SA3		equ	rc.3
SA4		equ	rc.4

SD		equ	rd
SD0		equ	rd.0
SD1		equ	rd.1
SD2		equ	rd.2
SD3		equ	rd.3
SD4		equ	rd.4
SD5		equ	rd.5
SD6		equ	rd.6
SD7		equ	rd.7

RDY		equ	rc.5			; ~IOCHRDY

CNT		equ	re
RD		equ	re.0			; RTL8019AS ~RD
WR		equ	re.1			; RTL8019AS ~WR

;
;		LCD用I/O設定（オプショナルLCD用)
;
D7		equ	rb.7			; 液晶用
D6		equ	rb.6
D5		equ	rb.5
D4		equ	rb.4
E		equ	rb.3			; 液晶イネーブル(これはつかってるけど)
RS		equ	rb.2			; 液晶RSピン

;-----------------------------------------------------------------------------------
;		グローバル変数
;-----------------------------------------------------------------------------------
;		■Bank0 
		org	20h

;-----------------------------------------------------------------------------------
gcn1		ds	1
sum		ds	2		; check sum for TCP,...
bytes		ds	1		; current ptr for calculate above

remote_adr	ds	2		; リモート
remote_len	ds	2

curr		ds	1		; Current page address

val		ds	4
val_m		ds	1		; for DECIMAL
val_cn
proto		ds	1		; プロトコル番号
tcn1		ds	1		; counter fot NTP Packet
;; debug NTP Packet
;  div1d		ds	1		;割られる数上位　（終了時には０になる）
;  div1c		ds	1		; 〜
;  div1b		ds	1		; 〜
;  div1a		ds	1		;下位
;  div1dd		ds	1		; timestamp小数部上位8bit

mynagao	ds	1		; main loop　長押しチェック用
nagatime	equ	80		; chattime[ms] ×nagatime (回)
chattime	equ	30		; チャッタ待ち時間 (ms)
adj_after	equ	10		; 校正後の経過秒

;-----------------------------------------------------------------------------------
; IP Headerからの受信Buffer
;-----------------------------------------------------------------------------------
;		IPプロトコル
;
ip_header
ip_ver_len	ds	1	; VERSION:4,DATA SIZE:5
ip_tos		ds	1	; service type
ip_length	ds	2	; データ長(IP Header含んでそれ以降)
ip_ident	ds	2
ip_flagment	ds	2	
ip_ttl		ds	1	; 生存期間
ip_proto	ds	1	; プロトコル 1:ICMP,6:TCP,17:UDP
ip_sum		ds	2	; ヘッダチェックサム
ip_src		ds	4
ip_dest		ds	4

;-----------------------------------------------------------------------------------
;		TCPプロトコル
;
tcp_header			; 他のプロトコルの先頭Addressに使用中

;-----------------------------------------------------------------------------------
;		UDPプロトコル
;
udp_header	=	tcp_header
udp_src_port	=	tcp_header+0
udp_tar_port	=	tcp_header+2
udp_length	=	tcp_header+4
udp_sum		=	tcp_header+6
udp_data	=	tcp_header+8

;-----------------------------------------------------------------------------------
;		ARPプロトコル
;
arp_header	=	ip_header
arp_hard_type	=	ip_header+0
arp_prot_type	=	ip_header+2
arp_hard_len	=	ip_header+4
arp_prot_len	=	ip_header+5
arp_ope		=	ip_header+6
arp_src_mac	=	ip_header+8
arp_src_ip	=	ip_header+14
arp_dest_mac	=	ip_header+18
arp_dest_ip	=	ip_header+24

;-----------------------------------------------------------------------------------
;		ICMPプロトコル
;
icmp_header	=	tcp_header
icmp_type	=	tcp_header+0
icmp_code	=	tcp_header+1
icmp_sum	=	tcp_header+2
icmp_mes	=	tcp_header+4


;-----------------------------------------------------------------------------------
;		環境設定用変数
;
;		■Bank 1
		org	0a0h
this_ip		ds	4	; 自分のIP address
mymac		ds	6	; 自分のMAC address
ident		ds	2
ntp_ip		ds	4	; NTP server IP address

;-----------------------------------------------------------------------------------
; Ethernet header 送受信（両方?）buffer
;		Ethernetヘッダ
ne_header			; NE2000 Status
ne_stat		ds	1	; 受信ステータス(RSR)
ne_next		ds	1	; 次のバウンダリポインタ(Next Boundary)
ne_cn_l		ds	1	; データサイズ(L)
ne_cn_h		ds	1	; データサイズ(H)

eth_header			; Ethernet Header
eth_dest	ds	6	; 送信先MACアドレス
eth_src		ds	6	; 送信元MACアドレス
eth_type	ds	2	; パケットタイプ
null

bs_ptr		=	ne_header
bs_ptr2		=	ne_header+1
save_line	=	ne_header+2
save_cn		=	ne_header+3

;-----------------------------------------------------------------------------------
;		■Bank2
;-----------------------------------------------------------------------------------
	org	110h

	org	120h	; 余白16Byte

mycc	ds	1
myadjt	ds	1
mystate	ds	1
;-----------------------------------------------------------------------------------
; utility mode
;-----------------------------------------------------------------------------------
seg0	ds	1
seg1	ds	1
seg2	ds	1
seg3	ds	1
seg:

myaddrs	ds	1		; 現在設定中のアドレス
mycursor	ds	1		; カーソル位置
mysegno	ds	1		; セグメント位置 (未使用)
mytemp	ds	1		; 作業用

myasc	ds	1
myasb	ds	1
myasa	ds	1

;-----------------------------------------------------------------------------------
;	area for clock
;-----------------------------------------------------------------------------------
;wait_cn	ds	1
;wait_cn2	ds	1
;--------------------	液晶用変数
;d4	ds	1
;d8	ds	1
cn	ds	1
poi	ds	1
;--------------------	時間用変数
dsec0	ds	1		; sec 1桁目
dsec1	ds	1		; sec 2桁目
dmin0	ds	1		; min 1桁目
dmin1	ds	1		; min 2桁目
dh0	ds	1		; hour 1桁目
dh1	ds	1		; hour 2桁目
;tmp	ds	1
;--------------------	日付用変数
myyear	ds	1		; 年 下２桁(00-36or99)
mydate	ds	1		; 日(1-31)
mymonth	ds	1		; 月(1-12 or 0-11)
myday	ds	1		; 曜日(1-7 or 0-6)

;--------------------	その他変数
myi	ds	1		; manecco M.Y. 1秒タイマ用
myii	ds	1		; manecco M.Y. 未使用。
mypd0	ds	1	; 経過日保存用16bit 下位
mypd1	ds	1	; 経過日保存用16bit 上位
myhour	ds	1	; 時間保存下位4bit 他

;--------------------	hexdec8 での使用変数
prm1a	ds	1		;変換したい値（１バイト。変換後は壊れる）
prm3c	ds	1		;10進格納場所（３バイト）上位
prm3b	ds	1
prm3a	ds	1		;〜下位
dec_top:				;　間接アクセス用ラベル
srlc1	ds	1		;カウンタ（サブルーチンで使用）
srwk1	ds	1		;一時余り格納場所（サブルーチンで使用）
;--------------------	sub32 での使用変数
sb1d	ds	1	;引かれる数(上位)
sb1c	ds	1	; 〜
sb1b	ds	1	; 〜
sb1a	ds	1	;(下位)
sb2d	ds	1	;引く数(上位)
sb2c	ds	1	; 〜
sb2b	ds	1	; 〜
sb2a	ds	1	;(下位)
;--------------------	div32 での使用変数
div1d		ds	1		;割られる数上位　（終了時には０になる）
div1c		ds	1		; 〜
div1b		ds	1		; 〜
div1a		ds	1		;下位
div2d		ds	1		;割る数上位       (変化せず戻る）
div2c		ds	1		; 〜
div2b		ds	1		; 〜
div2a		ds	1		;下位
div3d		ds	1		;答え上位　　　　（答えが返る）
div3c		ds	1		; 〜
div3b		ds	1		; 〜
div3a		ds	1		;下位
div4d		ds	1		;余り上位　　　　（余りが返る、内部ワークにも使用）
div4c		ds	1		; 〜
div4b		ds	1		; 〜
div4a		ds	1		;余り下位
divl1		ds	1		;内部ループ用
divl2		ds	1		;内部ループ用
diverr		ds	1		;割る数が０であった場合に１をセットして戻る
;-------------------- NTP 較正誤差縮め用
sb1dd		ds	1		; NTP Timestamp 小数部上位8bit



;-----------------------------------------------------------------------------------
;	RS232C送信先データ
;-----------------------------------------------------------------------------------
;		■Bank 3
		org	190h
on_ether	ds	6		; 宛て先Ethernetアドレス
on_ip		ds	4		; 宛て先IPアドレス
transmitted	ds	1		; 送信済みバイト数

;-----------------------------------------------------------------------------------
;		■共通変数
; 70h-7fhはBankは何処にいても見られるらしい

		org	70h		; COMMON MEMORY PAGE
; BEGIN -- 割り込み時レジスタ待避用
w_save		ds	1
pclath_save	ds	1
status_save	ds	1
fsr_save	ds	1
; END
dest		ds	2
data		ds	1		; a data for transmit to ethernet chip
wk		ds	2
common		ds	1

;    LCD用変数 Bank2(日時計算表示)でも使えるように
wait_cn		ds	1
wait_cn2	ds	1
d4		ds	1
d8		ds	1
rb_save	ds	1	; 液晶書きこみ時RB退避(write_lcd4)

cd
tmp		ds	1
;; もう一杯です 70h-7fh


;-----------------------------------------------------------------------------------
;		■プログラムエントリ program entery
;-----------------------------------------------------------------------------------
		org	0		; リセットベクタ(=0000h)
		mov	pclath,#start>>8; スタートアップルーチンへPageを利用 8bit shiftなるほど
		goto	start

;-----------------------------------------------------------------------------------
;		■割り込み処理 interrupt
;-----------------------------------------------------------------------------------
		org	4		; 割り込みベクタ(=0004h)
interrupt
;	コンテキスト待避処理

	mov	w_save,w		; Wレジスタ保存
	mov	status_save,status		; STATUSレジスタを保存
	mov	pclath_save,pclath		; PCLATHを保存
	mov	fsr_save,fsr		; FSRを保存する

	clrf	pclath		; PCLATH=0にする
	clrf	status		; STATUSを0にする( irp = 0 含む)

	goto	waricom

;||-----------------------------------------------------------------------------
;|| 暦計算用データ　テーブル参照
;||
month_table		; 3,4,5,6,7,8,910,11,12,1,2 月の末日データ
	jmp	pc+w
month_dat
	retw	31,30,31,30,31,31,30,31,30,31,31,28

mon_table
	jmp	pc+w		; 月の表示用テーブル ３月初め
	retw	'MAMJJASONDJF'
	retw	'apauuuecoeae'
	retw	'rrynlgptvcnb'

week_table
	jmp	pc+w		; 曜日の表示用テーブル 水曜初め（2000.3.1 が水曜日）
	retw	'WTFSSMT'
	retw	'ehrauou'
	retw	'duitnne'

;||-----------------------------------------------------------------------------
;|| INTERRUPT ROUTINE
;||	(every 100ms)
waricom
	bsf	rp1		; rp1 = 1
	bcf	rp0		; rp0 = 0 Bank2 要らないかも 元からだから

;	snb	intf		; if ( intf != 0 ) skip
;	goto	intrb0		; RB0(int) による割り込みならintrb0 へ

	;clrb	rb.4		; 1pps 出力？[1/2]
	and	rb,#0111_1110b	; 上の出力を２つ以上出すとき。これは[RB7,RB0] に出力。

;;|| １秒判定
;	xor	rb,#0010_0000b		; 0.1sec で反転（周期T=0.2sec）
	inc	myi		; myi++

;	cjne	myi,#5,ten_judge
;	xor	rb,#0100_0000b		; 0.5sec で反転（周期T=1sec）[1/2]

ten_judge
	cse	myi,#10		; １０回で１秒 if (myi == 10) skip
	goto	intout
;;; ↑↑↑上の２行をコメントアウトすると、１０倍にスピードアップ。（デバッグ用に）

; 一秒毎の処理
	;setb	rb.4		; 1pps 出力か？（パルス幅 0.1sec）[2/2]
	or	rb,#1000_0001b	; 上の出力を２つ以上出すとき。これは[RB7,RB0] に出力。


;	xor	rb,#0100_0001b		; 0.5sec で反転（周期T=1sec）[2/2]
;	xor	rb,#1000_0010b		; 1sec で反転（周期T=2sec）
	call	cup		; １秒毎のカウントアップ

	sb	mystate.7		; if (bit==1) skip
	goto	cup_up
	mov	sb1dd&0ffh,#'!'
	decsz	myadjt		; if(--myadjt == 0)skip
	goto	cup_up
	mov	sb1dd&0ffh,#' '
	clrb	mystate.7

cup_up		; CountUP is UP

	snb	myhour.7		;if(bit7==1)then go out --StealthMode
	goto	cup_up_out
	call	clock_diplay

	sb	myhour.6		;if(bit6==1)then skip --日付けを表示したいとき立ってるはず。
	goto	cup_up_out
	call	date_display		; 日付け表示
	clrb	myhour.6	

cup_up_out


;|| 0.1×10 秒カウント・リセット
	clr	myi & 0ffh
;	goto	intout

;intrb0				; RB0 による割り込み処理

;-----------------------------------------------------------------------------------
intout
;; Int flags reset
	bcf	rp1		; rp1 = 0 (bank0)
;	clrb	tmr1if		; 割り込み再許可。Timer1（Timer1割り込みは発生しない）
	clrb	ccp1if		; 割り込み再許可。CCP1

;	コンテキスト復帰処理
	mov	fsr,fsr_save		; fsrを復帰
	mov	pclath,pclath_save	; pclathを復帰
	mov	status,status_save		; statusを復帰
	mov	w,w_save		; Wを復帰

	retfie

;================ 割り込み終り ================


;|| count up
cup
cup_d0				; CountUP_dsec0
	inc	dsec0		; dsec++
	cse	dsec0,#10	; if (dsec0 == 10) {skip ; 桁上がり;}
	jmp	cup_d1		; else{ カウントアップのみ }
  	clr	dsec0 & 0ffh	; dsec0 = 0
	inc	dsec1		; dsec1++
cup_d1
	cse	dsec1,#6	; if (dsec1 < 6) {skip}
	jmp	cup_m0
	clr	dsec1 & 0ffh
	inc	dmin0		; 60 sec → 1 min
cup_m0
	cse	dmin0,#10	; if (dmin0 < 10) {skip}
	jmp	cup_m1
	clr	dmin0 & 0ffh
	inc	dmin1
cup_m1
	cse	dmin1,#6		;  if (dmin1 < 6) {skip}
	jmp	cup_h0
	clr	dmin1 & 0ffh

;	inc	dh0		; 60 min → 1 h
	inc	myhour		; 60 min → 1 h
	setb	mystate.6		; １時間ごとの校正要求。
cup_h0
	mov	dh0 &0ffh,myhour
	and	dh0,#0fh
	csae	dh0,#12		;if (myhour<12) goto altap_2
	goto	altap_2

	and	myhour,#0f0h
	sb	myhour.4		;if(bit==0)goto altap_1	||| alternate bit
	goto	altap_1
	clrb	myhour.4		;PM→AM (1 Day UP)
;---- 一日毎のルーチン
	inc	mypd0		; 経過日の加算
	snz		; if ( z != 0 ) skip
	inc	mypd1		; 下位ビットが溢れたら上位を加算

	call	hizukkke		; 日付け計算
;	call	date_display		; 日付け表示 後で表示。
	setb	myhour.6		; 日付けを表示したいとき立てる。

	goto	altap_2
altap_1
	setb	myhour.4		;AM→PM
altap_2	
	return

;-----------------------------------------------------------------------------------
;	チェックサムの値をクリアする。 clear check SUM
; (ICMPなども使用しています！削除厳禁)
clear_sum
		clr	sum[0]	; sum[0] = 0
		clr	sum[1]	; sum[1] = 0
		clr	bytes	; HI byte/LO byteの識別用; bytes = 0
		ret

;-----------------------------------------------------------------------------------
;	エラーリカバリールーチン error recovery routine Tr技 p.242 over flow
;-----------------------------------------------------------------------------------
overflow2
overflow
  		clr	status		; STATUS = 0
		
		clr	rc		; RC(SA0-4) = 00h; addressをCR (command register)にセット
		movlw	21h		; w = 21h; RTL8019AS STOP (Remote write,パケット送信,RTL動作STOP)
		call	assert_wr0	; RTL8019へ単純書き込み WをRTLのSD0-7(Data Bus)に入力
		
		mov	pclath,#wait_ms>>8	; Page1に設定
		mov	wait_cn,#2
		call	wait_ms			; 10ms Wait? 2msecでしょ。
		clr	pclath		; Page0へ
		
		mov	rc,#0ah		; RC = 0Ah addressをRBCR0(Remode Byte Counter Register)にセット
		clrw			; w = 0
		call	assert_wr0	; RBCR0 = 0

		mov	rc,#0bh		; RC = OBh adderssをRBCR1にセット
		clrw			; w = 0
		call	assert_wr0	; RBCR1 = 0

		call	initialize	; RTL8019を初期化

		mov	rc,#0ch		; RCR (Receive Configuration Register)
		movlw	000100b		; MONITOR解除(全てのパケット受け入れない,multi cast受け入れない,broadcase受け入れ,64以下のパケット受け入れない,Error Packet受け入れない)
		call	assert_wr0

		mov	rc,#0dh		; TCR (Transmit Configration Register)
		clrw			; w = 0; L/B(Loop back)解除,(CRC付加)
		call	assert_wr0

		goto	main0		; 通常処理に戻る



;===================================================================================
;	メインルーチン main routine 本当はloopじゃないけど main0からが本物
;===================================================================================
main
		clr	rc	; SA0-4 = 00000 CR(Command Register)
		movlw	22h	; w = 22h (0010_0010b)
		call	assert_wr0		; PAGE0に戻す

		mov	rc,#0ch	; RCR (Receive Configration Register)
		movlw	000100b	; broadcast address受け入れ
		call	assert_wr0; Write data
		mov	rc,#0dh	; TCR (Transmit Configration Register)
		clrw		; L/B(Loop back?)解除
		call	assert_wr0
		
		mov	pclath,#wait_ms>>8; Paging wait_msは他のPageにあるから
		mov	wait_cn,#100
		call	wait_ms			; 100ms Wait
;		clr	pclath	; pageを戻す。Page0


;===================================================================================
;	メインループ main loop
;===================================================================================
main0
	;; send arp request when the switch was pushed & START &every 1hour

		;; elecon presentation時comment out　→start 初期化ルーチンでmystate.6 を0に。（現在1）

		bsf	rp1	; rp1 = 0
		bcf	rp0	; rp0 = 0 Bank2

		;snb	myhour.7		; if (bit==0) skip	Stealth 時には呼ばない。と、困る事が判明。
		;goto	switch

		sb	mystate.6		; if (bit==1) skip	ARP 要求の必要があるか？
		goto	switch
		mov	sb1dd & 0ffh,#0011_1111b		; default "?" by ASCII
		clrb	mystate.6		; 次に1 になるまで要求しない
		clrb	mystate.7		; これ以前のセットをクリア

		mov	pclath,#arp_transmit>>8
		call	arp_transmit
		clr	pclath	; pageを戻す Page0

	; スイッチチェック・移転しました。
switch
		bcf	rp1	; rp1 = 0
		bcf	rp0	; rp0 = 0 Bank0
		mov	pclath,#main_check_sw>>8
		goto	main_check_sw

main0_t2
		clr	pclath		; pclath = 0
		mov	rc,#7		; rc = 0000_0111b ISRでしょこりゃ↓RCR?
		call	assert_rd	; RCRリード ;ISR (Interrupt Status Register)
		
		btfsc	data.4		; if (OVW(data.4, ISR.4) == 0) skip
		goto	overflow	; OVW (受信リングバッファが一杯) over flow 処理
		btfsc	data.3		; if (TXE(data.3, ISR.3) == 0(clear)) skip 
		goto	overflow	; TXE (送信に失敗) over flow 処理
		btfsc	data.2		; if (REX(data.2,ISR.2) == 0(clear)) skip
		goto	overflow	; ISR (受信エラー) over flow処理
		goto	get_packet	; パケット受信あり

main99		goto	main0

;-----------------------------------------------------------------------------------
;	■パケット受信処理
;-----------------------------------------------------------------------------------
get_packet
;	PAGE 1
		clr	rc			; CR (command register)
		movlw	01100010b		; Page1,Remote DMA完了 RTL動作開始?
		call	assert_wr0		; PAGE1にする
		
		mov	rc,#7			; CURR (Current Page Register)
		call	assert_rd		; read RTL
		mov	curr,data		; カレントページを取得 curr(Current page address)
;	PAGE 0
		clr	rc			; CR (Command Register)
		movlw	00100010b		; Page0, (abort/remote DMA完了,RTL動作開始)
		call	assert_wr0		; PAGE0に戻す
		
		mov	rc,#3			; BNDY (Boundary:境界 Register)
		call	assert_rd		; BNDYをよむ(データがdata変数に入れられ返る)
		
		inc	data			; BNDY++
		cjb	data,#PAGE_STOP,packet1	; overlap計算
	;; if (data < PAGE_STOP(受信バッファ終端アドレス)) goto packet1
		mov	data,#PAGE_START	; data = PAGE_START(受信バッファ先頭アドレス)
packet1
		csne	data,curr	; (BNDY+1)==CURRの場合は新規データなし
	;; if (data!=curr(Current page address)) skip
		goto	main0			; 中断(新規データが無かったので)

;-----------------------------------------------------------------------------------
;	RTL8019ステータス+Ethernetヘッダの読み出し
		clr	remote_adr[0]		; remote_adr[0] = 0
		mov	remote_adr[1],data	; remote_adr[1] = data
		mov	remote_len[0],#NE_SIZE + PACKET_SIZE; remote_len[0] = NE_SIZE(RTL8019 Satus area size) + PACKET_SIZE(Ethernet Header Size)

		clr	remote_len[1]		; remote_len[a] = 0
		call	remote_read		; prepare for reading remote DMA
		
		mov	gcn1,#NE_SIZE + PACKET_SIZE	; Loop Counter; gcn1 = NE_SIZE + PACKET_SIZE
		bcf	irp			; STATUS.IRP=0 間接address Page0,1
		mov	fsr,#ne_header		; アドレスne_headerへ読み出す
		mov	rc,#10h			; Remote DMA Port
get_packet0
		bcf	RD			; RD (RTL8019AS ~IORB readout I/O port) = 0
		btfss	RDY			; ~Wait if (RDY(RTL ~IOCHRDY)==1) skip
		goto	$-1			; 一つ前に戻る↑
		mov	w,rd			; w = rd
		bsf	RD			; RD = 1
		movwf	indirect		; *indirect = data バッファへセット
		inc	fsr			; fsr++
		djnz	gcn1,get_packet0	; if (--gcn1!=0) goto get_packet0
;
;		Ethernetヘッダによって処理を分岐
		bsf	rp0			; rp0 = 1 bank0
		btfss	ne_stat.0		; if (ne_stat(RSR).0==1) skip;正常に受信できた
		goto	main9			; 正常に受信できなかったとき
		cje	eth_type[1],#ARP_PROTO,do_arp	; ARPプロトコル処理へ分岐
		;; if (eth_type[1] == ARP_PROTO) goto do_arp
		cje	eth_type[1],#IP_PROTO,do_ip	; IPプロトコル処理へ分岐
		;; if (eth_type[1] == IP_PROTO) goto do_ip
		cjne	eth_type[0],#COM_PROTO,main9	; typeの上位8bitが8以外はスキップ
		;; if (eth_type[0] != COM_PROTO) goto main9

;-----------------------------------------------------------------------------------
main9
		bcf	irp	; irp = 0 間接addressing Page0,1
		bcf	rp1	; rp1 = 0 
		bsf	rp0	; rp0 = 1 Bank1
		cjb	ne_next,#PAGE_START,overflow2	; Error Check and Recovery
	;; if (ne_next < PAGE_START(受信バッファ先頭アドレス)) goto overflow2
		cjae	ne_next,#PAGE_STOP,overflow2	; Error Check and Recovery
	;; if (ne_next >= PAAGE_STOP(受信バッファ終端アドレス)) goto overflow2
		dec	ne_next				; 次のバンダリを計算
		cjae	ne_next,#PAGE_START,packet11
	;; if (ne_next >= PAGE_START(受信バッファ先頭アドレス)) goto packet11
		mov	ne_next,#PAGE_STOP-1; ne_next = PAGE_STOP - 1
packet11
		bcf	rp0		; rp0 = 0 bank0
		
		clr	rc		; rc = 0 (CR)
		movlw	00100010b	; w = 00100010b (abort/remote DMA完了,動作開始)
		call	assert_wr0	; write to RTL
		
		mov	rc,#3		; rc = 3 (BNRY)
		mov	fsr,#ne_next	; fsr = ne_next
		mov	w,indirect	; バンダリポインタセット w = indirect
		call	assert_wr0	; RTL write
		goto	main99


;-----------------------------------------------------------------------------------
;		■ARPプロトコル処理
;-----------------------------------------------------------------------------------
do_arp
		bcf	rp0		; rp0 = 0 Bank0
		mov	remote_adr[0],#NE_SIZE + PACKET_SIZE; remote_adr[0] = NE_SIZE + PACKET_SIZE
		mov	fsr,#ne_cn_l	; fsr = ne_cn_l(データサイズ(L))
		mov	remote_len[0],indirect; remote_len[0] = indirect(データサイズ(L))
		inc	fsr		; fsr++
		mov	remote_len[1],indirect; remote_len[1] = indirect(データサイズ(H))
		sub	remote_len[0],#NE_SIZE + PACKET_SIZE; remote_len[0] -= NE_SIZE+PACKET_SIZE
		movlw	1		; w = 1
		btfss	c		; if (c == 1) skip 桁上がりがあるかないか。
		subwf	remote_len[1],1	; remote_len[1] -= w 桁上がり処理
		call	remote_read	; Read with Remote DMA

		mov	fsr,#ip_header	; アドレスip_header以降にデータを読み出す fsr=ip_header
get_packet10
		movf	remote_len[0],0	; remote_len[0] = 0
		iorwf	remote_len[1],0	; w = w OR remote_len[1]
		btfsc	z		; if (z == 0) skip
		goto	get_packet2	; 読み込み終了? ARP header analysis 解析

		bcf	RD	; RD (RTL ~IORB readout I/O port) = 0 I/O port 読み出し開始
		btfss	RDY	; ~Wait if (RDY(RTL ~IOCHRDY)==1) skip
		goto	$-1	; wait要求が終るまで↑にもどる
		mov	w,rd	; w = rd
		bsf	RD	; RD (RTL ~IORB readout I/O port) = 1 I/O port 読み出し終了
		movwf	indirect; indirect = w
		inc	fsr	; fsr++
		
		movlw	1		; length(レングス)をデクリメント
		subwf	remote_len[0],1	; remote_len[0] -= 1
		btfss	c		; if (c == 1) skip
		subwf	remote_len[1],1	; remote_len[1] -= 1
		
		btfss	fsr.7	; over flow? if (fsr.7==1) skip Pageが変わってしまうってこと？over flow?
		goto	get_packet10
;	80h以降
get_packet20
		movf	remote_len[0],0	; w = remote_len[0]
		iorwf	remote_len[1],0	; w = w OR remote_len[1]
		btfsc	z		; if (z==0) skip
		goto	get_packet2		; 読み込み終了
		
		bcf	RD		; RD (RTL ~IORB readout I/O port) = 0 I/O port 読み出し開始
		btfss	RDY		; ~Wait if (RDY(RTL ~IOCHRDY)==1) skip
		goto	$-1		; wait要求が終るまで↑にもどる
	;	mov	w,rd
		bsf	RD		; RD (RTL ~IORB readout I/O port) = 1 I/O port 読み出し終了
	;	movwf	indirect

		movlw	1		; w = 1 ; length(レングス)をデクリメント
		subwf	remote_len[0],1	; remote_len[0] -= w(1)
		btfss	c		; if (c == 1) skip
		subwf	remote_len[1],1	; remote_len[1] -= w(1)
		goto	get_packet20

;---------------------------------------------------------------------------------------
;		ARPヘッダの解析
get_packet2
		cjne	arp_ope[0],#0,main9	; arp_codeが0001以外なら捨てる
	;; if (arp_ope[0] != 0) goto main9
		cje	arp_ope[1],#1,arp_req	; if (arp_ope[1] == 1) goto arp_req
		cje	arp_ope[1],#2,arp_reply	; if (arp_ope[1] == 2) goto arp_reply
		
		goto	main9
arp_reply					; receive ARP reply packet
;  		mov	pclath,#ser_arp>>8	; Paging
;  		goto	ser_arp			; ARP応答受信処理

  		clr	status
	;; debug
  		mov	d4,#'a'
  		mov	pclath,#write_lcd4>>8
  		call	write_lcd4; write LCD

		mov	pclath,#ntp_transmit>>8
		goto	ntp_transmit
arp_req						; receive ARP request packet
arp
	; ARP requestのIP addressが自分と同じか?
		mov	fsr,#this_ip		; this_ipはBank1
		cjne	indirect,arp_dest_ip[0],main9
	;; if (indirect(this_ip) != dest_ip[0]) goto main9
		inc	fsr	; fsr++
		cjne	indirect,arp_dest_ip[1],main9
	;; if (indirect(this_ip) != dest_ip[1]) goto main9
		inc	fsr	; fsr++
		cjne	indirect,arp_dest_ip[2],main9
	;; if (indirect(this_ip) != dest_ip[2]) goto main9
		inc	fsr	; fsr++
		cjne	indirect,arp_dest_ip[3],main9
	;; if (indirect(this_ip) != dest_ip[3]) goto main9
		;自分へのARP要求である
	
		call	prepare_ether2; Ethernetヘッダを作成する。

		movlw	COM_PROTO	; 08 Etherframe type
		call	assert_wr	; write RTL
		movlw	ARP_PROTO	; ARP
		call	assert_wr	; write RTL

		mov	pclath,#arp1>>8	; Paging
		call	arp1		; ARP header write
		clr	pclath		; pclath=0 Page0?
		
		clr	rc		; rc = 0 (CR (Command Register))
		movlw	00100010b	; abort/remote DMA停止, 動作開始
		call	assert_wr0	; write RTL
		
		mov	rc,#4h		; rc = 4 (BNRY)
		movlw	PAGE_BEGIN	; transmit page is start page (RTLメモリ先頭アドレス)
		call	assert_wr0	; write RTL
		
		mov	rc,#5		; rc = 5 (TBCR0 送信バイト数Register (L))
		movlw	60		; minimum packet = 60
		call	assert_wr0	; write RTL
		
		mov	rc,#6		; rc = 6 (TBCR1 送信バイト数Register (H))
		clrw			; adr high ; w = 0
		call	assert_wr0	; write RTL
		
		call	transmit	; ARP応答を送信する
		goto	main9


;-----------------------------------------------------------------------------------
;	■IPプロトコル受信処理
;-----------------------------------------------------------------------------------
do_ip
		bcf	rp0			; rp0 = 0
		mov	remote_adr[0],#NE_SIZE + PACKET_SIZE; remote_adr[0] = NE_SIZE + PACKET_SIZE
		mov	fsr,#ne_cn_l		; fsr = ne_cn_l(データサイズ(L))
		mov	remote_len[0],indirect	; remote_len[0] = indirect
		inc	fsr			; fsr++
		mov	remote_len[1],indirect	; remote_len[1] = indirect
		
		sub	remote_len[0],#NE_SIZE + PACKET_SIZE; 受信バイト数からEtherヘッダ長を引く
		movlw	1			; w = 1
		btfss	c			; if (c==1) skip 引き算の繰り下がりチェック
		subwf	remote_len[1],1		; remote_len[1] -= w(1)
		call	remote_read		; read Remote DMA
;
;	IPパケットの受信
		mov	fsr,#ip_header	; アドレスip_headerへデータを読み込む

		bcf	RD	; RD (RTL ~IORB readout I/O port) = 0 I/O port 読み出し開始
		btfss	RDY	; ~Wait if (RDY(RTL ~IOCHRDY)==1) skip
		goto	$-1	; wait要求が終るまで↑にもどる
		mov	w,rd	; w = rd
		bsf	RD	; RD (RTL ~IORB readout I/O port) = 1 I/O port 読み出し終了
		movwf	indirect; １バイト読む！indirect = w 間接addressing
		inc	fsr	; fsr++

		movlw	1		; LENGTH--
		subwf	remote_len[0],1	; remmote_len[0] -= w(1)
		btfss	c		; if (carry==1) skip
		subwf	remote_len[1],1	; remmote_len[1] -= w(1)
	;; gcn1ってGlobal Counter 1か
		mov	gcn1,ip_ver_len	; 残りバイト数算出 gcn1 = ip_ver_len ??
		and	gcn1,#0fh	; gcn1 = gcn1 AND 0fh
		clc			; c = 0
		rl	gcn1		; gcn1<<=1?
		rl	gcn1		; gcn1<<=1
		dec	gcn1		; IPヘッダからIPヘッダサイズを計算 gcn1--
		call	copy_toram	; RAMに転送

ip_get_packet2
		cjne	ip_ver_len,#45h,ip_get_packet9	; IP Version 4, 
	;; if (ip_ver_len != 45h) goto ip_get_packet9
		cje	ip_proto,#UDP_PROTO,udp		; UDP受信処理へ
	;; if (ip_proto == UDP_PROTO) goto udp
		cje	ip_proto,#ICMP_PROTO,icmp	; ICMP受信処理へ
	;; if (ip_proto == ICMP_PROTO) goto icmp
ip_get_packet9
		call	abort				; リモートDMA中止
		goto	main9

;-----------------------------------------------------------------------------------
;	■gcn1のバイト数分データを読み込む
;-----------------------------------------------------------------------------------
copy_toram
		bcf	RD	; RD (RTL ~IORB readout I/O port) = 0 I/O port 読み出し開始
		btfss	RDY	; ~Wait if (RDY(RTL ~IOCHRDY)==1) skip
		goto	$-1	; wait要求が終るまで↑にもどる
		mov	w,rd	; w = rd
		bsf	RD	; RD (RTL ~IORB readout I/O port) = 1 I/O port 読み出し終了
		movwf	indirect; indirect = w 間接addressing;*indirect = data 
		inc	fsr	; fsr++
		
		movlw	1		; LENGTH--
		subwf	remote_len[0],1	; remote_en[0] -= 1;
		btfss	c		; if (c==1) skip
		subwf	remote_len[1],1	; remote_len[1] -= 1;
		
		djnz	gcn1,copy_toram	; if (--gcn1 != 0) goto copy_toram
		ret


;-----------------------------------------------------------------------------------
;	■パケットの残りをバッファRAMへ
;-----------------------------------------------------------------------------------
get_remain			; icmpだけが利用
get_remain0
		movf	remote_len[0],0		; w = remote_len[0]
		iorwf	remote_len[1],0		; w = w OR remote_len[0]
		btfsc	z			; if (z==0) skip
		goto	get_remain9		; End ? 読み込み終了
		
		bcf	RD	; RD (RTL ~IORB readout I/O port) = 0 I/O port 読み出し開始
		btfss	RDY	; ~Wait if (RDY(RTL ~IOCHRDY)==1) skip
		goto	$-1	; wait要求が終るまで↑にもどる
		mov	w,rd	; w = rd
		bsf	RD	; RD (RTL ~IORB readout I/O port) = 1 I/O port 読み出し終了
		movwf	indirect		; 表にセット *indirect = data 
		inc	fsr	; fsr++
		
		movlw	1			; LENGTH--
		subwf	remote_len[0],1		; remote_en[0] -= 1;
		btfss	c			; if (c==1) skip
		subwf	remote_len[1],1		; remote_len[1] -= 1
		
		movlw	16+128	; w = 16 + 128 ; (10h + 80h)	Bank越えちゃうか検査 if (fsr > 6F) skip
		addwf	fsr,0	; w += fsr
		btfss	c	; if (c==1) skip
		goto	get_remain0

;		mov	fsr,#20h		; バンクを変えて更に読み込み
		mov	fsr,#160; (A0h)		; バンクを変えて更に読み込み 1A0hから
		bsf	irp	; irp = 1 Bank2,3 間接addressing
get_remain20
		movf	remote_len[0],0		; w = remote_len[0]
		iorwf	remote_len[1],0		; w = w OR remote_len[0]
		btfsc	z			; if (z==0) skip
		goto	get_remain9		; 読み込み終了
		
		bcf	RD	; RD (RTL ~IORB readout I/O port) = 0 I/O port 読み出し開始
		btfss	RDY	; ~Wait if (RDY(RTL ~IOCHRDY)==1) skip
		goto	$-1	; wait要求が終るまで↑にもどる
		mov	w,rd	; w = rd
		bsf	RD	; RD (RTL ~IORB readout I/O port) = 1 I/O port 読み出し終了
		movwf	indirect; 裏にセット *indirect = data
		inc	fsr	; fsr++
		
		movlw	1		; w = 1
		subwf	remote_len[0],1	; remote_len[0] -= w(1)
		btfss	c		; if (c==1) skip
		subwf	remote_len[1],1	; remote_len[1] -= w(1)
		
;		movlw	16+128	; w=16+128; (10h + 80h)
		movlw	16	; w=16; (10h) Bank3が終ってないかチェックif (fsr > F0h(1F0h)) skip
		addwf	fsr,0	; w += fsr
		btfss	c	; if (c==1) skip
		goto	get_remain20
get_remain30
		call	abort	; RTL読みだし中止、Remote DMA 一部初期化など
get_remain9
		bcf	irp	; irp = 0
		ret


;-----------------------------------------------------------------------------------
;	■ICMPプロトコル処理
;-----------------------------------------------------------------------------------
icmp
		call	get_remain			; RTL8019からデータを転送
		cjne	icmp_type,#8,main9		; typeが08h以外は捨てる
	;; if (icmp_type != 8) goto main9
		cjne	icmp_code,#0,main9		; codeが08h以外は捨てる
	;; if (icmp_code != 0) goto main9
ping
		mov	proto,#ICMP_PROTO		; プロトコル＝ICMP proto = ICMP_PROTO
		call	prepare_ip			; IPパケットの準備
;
		mov	remote_adr[0],#PACKET_SIZE + IP_SIZE; remote_adr[0]=PACKET_SIZE+IP_SIZE
		mov	remote_adr[1],#PAGE_BEGIN	; remote_adr[1] = PAGE_BEGIN
		mov	remote_len[0],ip_length[1]	; remote_len[0] = ip_length[1];ne_cn_l(データサイズ(L))
		sub	remote_len[0],#IP_SIZE-1	; remote_len[0] -= IP_SIZE-1
		clr	remote_len[1]			; remote_len[1] = 0
		call	remote_write			; write remote DMA
		
		call	clear_sum	; チェックサムの値をクリア
		
		mov	rc,#10h		; rc = 10h; remote DMA port
		call	assert_wr2times	; type : code
		call	assert_wr2times	; sum High : Low
		
		mov	gcn1,ip_length[1]	;ne_cn_l(データサイズ(L)) 256Byte越えたら?
		sub	gcn1,#IP_SIZE + 4	; gcn1 -= IPSIZE + 4
		mov	fsr,#icmp_header+4	; fsr = icmp_header+4 (Identifier,SequenceからData)
icmp10
		mov	w,indirect	; w = indirect
		inc	fsr		; fsr++
		call	assert_wr	; write w to RTL
		
		movlw	16+128	; w = 16+128 bank1(6Fh)を越えないかチェック 越えたらBank3に移る
		addwf	fsr,0	; w += fsr
		btfsc	c	; if (c == 0) skip
		goto	icmp20

		djnz	gcn1,icmp10	; if (--gcn1!=0) goto icmp10
icmp30		bcf	irp		; irp = 0

		clrw			; w = 0
		call	assert_wr	; write to RTL

		mov	remote_adr[0],#PACKET_SIZE + IP_SIZE + 2; remote_adr[0]=PACKET_SIZE+IP_SIZE+2
		mov	remote_adr[1],#PAGE_BEGIN	; remote_adr[1] = PAGE_BEGIN
		call	set_checksum			; check sumを書き込み
		
		mov	rc,#4h		; TPSR
		movlw	PAGE_BEGIN	; transmit page is start page RTL メモリ先頭アドレス
		call	assert_wr0	;  write RTL
		
		mov	rc,#5		; TBCR0 (Transmit Byte Count Register(L))
		mov	fsr,#ne_cn_l	; fsr = ne_cn_l(データサイズ(L))
		mov	w,indirect	; w = indirect
		call	assert_wr0	; write RTL
		
		mov	rc,#6		; TBCR1 (Transmit Byte Count Register(H))
		inc	fsr		; fsr++ (==ne_cn_h(データサイズ(H)))
		mov	w,indirect	; w = indirect
		call	assert_wr0	; write RTL
		
		call	transmit	; PINGの応答を送信
		goto	main9
icmp20
		mov	fsr,#160; fsr = 160 (A0h)
		bsf	irp	; irp = 1 Bank2,3

		djnz	gcn1,icmp21	; if (--gcn1!=0) goto icmp21
		goto	icmp30
	
icmp21		mov	w,indirect	; w = indirect
		inc	fsr		; fsr++
		call	assert_wr	; write w to RTL
		
		movlw	16	; w = 16 Bank3(1F0h)を越えないかチェック
		addwf	fsr,0	; w += fsr
		btfsc	c	; if (c == 0) skip
		goto	icmp30	; これ以上は受信できてないので諦める。ここまでのDataをecho

		djnz	gcn1,icmp21	; if (--gcn1!=0) goto icmp21
		goto	icmp30


;-----------------------------------------------------------------------------------
;	■UDP recieve
;-----------------------------------------------------------------------------------
udp
		mov	gcn1,#8	; gcn1 = 8
		call	copy_toram; gcn1(8) byte読みこ込み UDP header
		
		mov	fsr,#this_ip; fsr = this_ip
		cjne	ip_dest[0],indirect,main9	; 自分への送信データか?
		;; if (ip_dest[0] != indirect) goto main9
		inc	fsr	; fsr++
		cjne	ip_dest[1],indirect,main9; if (ip_dest[1] != indirect) goto main9
		inc	fsr	; fsr++
		cjne	ip_dest[2],indirect,main9; if (ip_dest[2] != indirect) goto main9
		inc	fsr	; fsr++
		cjne	ip_dest[3],indirect,main9; if (ip_dest[3] != indirect) goto main9

	;; 送信元portが NTP port (123) かチェック
		cjne	udp_src_port[1],#123,main9; if (udp_src_port[1]!=123 (NTP port)) goto main9
    		mov	pclath,#udp_ntp>>8; 発信元portが123だったらudp_ntpへ
    		goto	udp_ntp
		
;-----------------------------------------------------------------------------------
get_dgram
		movf	remote_len[0],0	; w = remote_len[0]
		iorwf	remote_len[1],0	; w = w OR remote_len[1]
		btfsc	z		; if (z==0) skip
		goto	get_dgram9	; remote_lenが0のとき
		
		bcf	RD	; RD (RTL ~IORB readout I/O port) = 0 I/O port 読み出し開始
		btfss	RDY	; ~Wait if (RDY(RTL ~IOCHRDY)==1) skip
		goto	$-1	; wait要求が終るまで↑にもどる
		mov	w,rd	; w = rd
		bsf	RD	; RD (RTL ~IORB readout I/O port) = 1 I/O port 読み出し終了
		movwf	data	; data = w

		movlw	1		; w = 1
		subwf	remote_len[0],1	; remote_len[0] -= w(1)
		btfss	c		; if (c==1) skip
		subwf	remote_len[1],1	; remote_len[1] -= w(1)
		
		clc	; OK c (carry flag) = 0
		ret
get_dgram9
		stc	; EOT c (carry flag) = 1
		ret

;-----------------------------------------------------------------------------------
;	リモートDMA転送中止
abort
		clr	rc		; rc = 0; CR (Command Register)
		movlw	22h		; w = 22h (0010_0010; Page0, remote write, RTL start)
		call	assert_wr0	; PAGE0に戻す
		
		mov	rc,#0ah		; rc = 0ah; RBCR0 (Remote Byte Count Register(L))
		clrw			; w = 0
		call	assert_wr0	;  write to RTL
		
		mov	rc,#0bh		; rc = 0bh; RBCR1 (Remote Byte Count Register(R))
		clrw			; w = 0
		call	assert_wr0	; write to RTL
		ret

;===================================================================================
;	■NICの初期化ルーチン
;===================================================================================
initialize
		call	init_nic			; NICリセット
		call	getmac				; MACアドレス取得
		call	setmac				; MACアドレスセット
;		リングバッファ初期化 RS232Cで使用しているから削除
;  		bsf	rp0	; rp0 = 1 Bank1
;  		mov	fifo_buff,#fifo_top; fifo_buff = fifo_top
;  		mov	fifo_poi,w; fifo_poi = w
;  		mov	fifo_line,w; fifo_line = w
		
;  		clr	fifo_cn	; fifo_cn = 0
;  		clr	fifo_line_cn; fifo_line_cn = 0
;  		bcf	rp0	; rp0 = 0 Bank0
		
		ret

;-----------------------------------------------------------------------------------
;	■RTL8019のリセット
;-----------------------------------------------------------------------------------
reset_nic
		clr	rc	; rc = 0 CR (Command Register)
		movlw	21h	; w = 21h (0010_0001b) abort/remote DMA end, RTL stop
		call	assert_wr0		; STOP OPERATION
		
		mov	rc,#1fh	; rc = 1fh reset port
		call	assert_rd		; 1Fhを読む
		
		mov	rc,#1fh	; rc = 1fh reset port
		mov	w,data	; w = data
		call	assert_wr0		; それを書き戻す（RESET)
reset_nic0
		mov	rc,#07h	; rc = 07h ISR (Interrupt Status Register)
		call	assert_rd		; ステータスを読む
		
		btfss	data.7	; RESET 終了チェック if (data.7(reset中?)==1) skip
		goto	reset_nic0; reset待ち
		ret

;-----------------------------------------------------------------------------------
;	■RTL8019の初期化 Tr技2001 1 p.240
;-----------------------------------------------------------------------------------
init_nic
		call	reset_nic; reset RTL
		
		mov	rc,#0eh			; DCR(Data Conifguration Register)
		movlw	68h	; 0110_1000b FIFO 12Byte, Looback非動作,16bit DMA, littleエンディアン, Byte DMA 転送
		call	assert_wr0; write RTL
		
		mov	rc,#0ah	; RBCR0 (Remote Byte Counter Register (L))
		clrw				; w = 0
		call	assert_wr0		; for over flow
		
		mov	rc,#0bh	; RBCR1 (Remote Byte Counter Register (H))
		clrw				; w = 0
		call	assert_wr0		; for over flow
		
		mov	rc,#01h		; PSTART (Page Start Register)
		movlw	PAGE_START	; PAGE START; w = PAGE_START
		call	assert_wr0	; write RTL
		
		mov	rc,#02h		; PSTOP
		movlw	PAGE_STOP	; PAGE STOP; w = PAGE_STOP
		call	assert_wr0	; write RTL
		
		mov	rc,#03h		; BNRY
		movlw	PAGE_START	; BDRY
		call	assert_wr0	; write RTL
		
		mov	rc,#0ch		; RCR (Receive Configuration Register)
		movlw	0h		;20h ;0hでしょ? moniter mode, 全packet受け入れ, multicast address受け入れ, broad cast受け入れ, 64Byte以下のpacket受け入れ, Error Packet受け入れ
		call	assert_wr0	; write RTL
		
		mov	rc,#0dh		; TCR (Transmit Configuration Register)
		movlw	2		; LOOPBACK (内部)
		call	assert_wr0

		mov	rc,#0fh	; IMR (Interrupt Mask Register)
		movlw	11111b	; 受信buffer over flow割り込み,送信/受信Error割り込み,packet送受信割り込み
		call	assert_wr0
		
		mov	rc,#7	; ISR (Interrupt Status Register)
		movlw	0ffh	; 
		call	assert_wr0

		clr	rc		; CR(Command Regster)
		movlw	22h		; START OPERATION with L/B
		call	assert_wr0
		ret

;-----------------------------------------------------------------------------------
;	■MACアドレス取得
;-----------------------------------------------------------------------------------
getmac
		clr	rc	; CR
		movlw	22h	; START OPERATION with L/B
		call	assert_wr0; write RTL
		
		clr	remote_adr[0]; remote_adr[0] = 0
		clr	remote_adr[1]; remote_adr[1] = 0
		mov	remote_len[0],#12	; 12bytes転送 remote_len[0] = 12
		clr	remote_len[1]; remote_len[1] = 0
		call	remote_read; read RTL

		mov	gcn1,#6		; MACアドレスは6バイト gcn1=6
		mov	fsr,#mymac	; アドレスにmymacに設定 fsr=mymac
get_mac0
		mov	rc,#10h		; rc = 10h remote DMA port
		call	assert_rd	; から（空？）読み
		call	assert_rd	; （本？）読み
		
		mov	indirect,data	; MACアドレスをPICに読み込む indirect = data
		inc	fsr		; fsr++
		djnz	gcn1,get_mac0	; if (--gcn1!=0) goto get_mac0
		ret

;-----------------------------------------------------------------------------------
;	■MACアドレス設定
;-----------------------------------------------------------------------------------
setmac
;	PAGE 1
		clr	rc		; CR
		movlw	01100010b	; Page1, abort,start
		call	assert_wr0	; write RTL
;
		mov	rc,#01h		; PAR0
		mov	fsr,#mymac	; fsr=mymac
		mov	gcn1,#6		; MACアドレスは6バイト
setmac0
		mov	w,indirect	; w = indirect
		call	assert_wr0	; MACアドレスの設定 write RTL
		inc	fsr	; fsr++
		inc	rc	; rc++ PAR1,PAR2,PAR3,PAR4,PAR5
		djnz	gcn1,setmac0; if (--gcn1!=0) goto setmac0
	
		mov	rc,#7	; CURR (Current Page Register)
		movlw	PAGE_START+1		; ついでに (w=受信バッファ先頭アドレス+1)
		call	assert_wr0		; カレントページのセット write RTL
		
		mov	rc,#8	; rc =8 MAR0
		clrw		; w = 0
		call	assert_wr0; write RTL
		inc	rc	; rc++ MAR1
		clrw
		call	assert_wr0
		inc	rc	; rc++ MAR2
		clrw
		call	assert_wr0
		inc	rc	; rc++ MAR3
		clrw
		call	assert_wr0
		inc	rc	; rc++ MAR4
		clrw
		call	assert_wr0
		inc	rc	; rc++ MAR5
		clrw
		call	assert_wr0
		inc	rc	; rc++ MAR6
		clrw
		call	assert_wr0
		inc	rc	; rc++ MAR7
		clrw
		call	assert_wr0
		
		clr	rc	; rc=0 CR
		movlw	22h	; START OPERATION with L/B
		call	assert_wr0; write RTL
		ret

;-----------------------------------------------------------------------------------
;	■リモートDMA書き込み準備
;-----------------------------------------------------------------------------------
remote_write
		mov	rc,#8		; RSAR0 (Remote Start Address Register(L))
		mov	w,remote_adr[0]	; w = remote_adr[0]
		call	assert_wr0	; write to RTL
		
		mov	rc,#9		; RSAR1 (Remote Start Address Register(H))
		mov	w,remote_adr[1]	; w = remote_adr[1]
		call	assert_wr0	; write to RTL
		
		mov	rc,#0ah		; RBCR0 (Remote Byte Count Register(L))
		mov	w,remote_len[0]	; w = remote_len[0]
		call	assert_wr0	; write to RTL
		
		mov	rc,#0bh		; RBCR1 (Remote Byte Count Register(H))
		mov	w,remote_len[1]	; w = remote_len[1]
		call	assert_wr0	; write to RTL
		
		clr	rc		;  CR (Command Register)
		movlw	00010010b	; Page0,remote write, RTL start
		call	assert_wr0	; write now! write RTL
		mov	rc,#10h		; rc = 10h ;Remote DMA port
		ret

;-----------------------------------------------------------------------------------
;	■リモートDMA読み込み準備
;-----------------------------------------------------------------------------------
remote_read
		mov	rc,#8		; RSAR0 (Remote Start Address Register (L))
		mov	w,remote_adr[0]	; w = remote_adr[0]
		call	assert_wr0	; wを書き込み
		
		mov	rc,#9		; RSAR1 (Remote Start Address Register (H))
		mov	w,remote_adr[1]	; w = remote_adr[1]
		call	assert_wr0
		
		mov	rc,#0ah		; RBCR0 (Remote Byte Count Register(L))
		mov	w,remote_len[0]	; w = remote_len[0]
		call	assert_wr0
		
		mov	rc,#0bh		; RBCR1 (Remote Byte Count Register(H))
		mov	w,remote_len[1]	; w = remote_len[1]
		call	assert_wr0
		
		clr	rc		; rc = 0; CR (Command Register)
		movlw	00001010b	; Remote Write Command, (RTL動作開始)
		call	assert_wr0	; read now!
		mov	rc,#10h		; rc = 10h; Remote DMA port
		ret

;-----------------------------------------------------------------------------------
;	■チェックサムの計算
;-----------------------------------------------------------------------------------
calc_sum
		btfss	bytes.0			; アラインメントチェック
		goto	calc_sum_high
;	LOWバイト
		add	sum[0],w		; データを(sum[1],sum[0])に加算
		movlw	1
		btfsc	c
		addwf	sum[1],1

		btfsc	c			; 1の補数の計算
		addwf	sum[0],1
		btfsc	c
		addwf	sum[1],1
		inc	bytes			; アラインを次に
		ret
;	HIGHバイト
calc_sum_high
		add	sum[1],w		; データを(sum[1],sum[0])に加算
		movlw	1
		
		btfsc	c			; 1の補数の計算
		addwf	sum[0],1
		btfsc	c
		addwf	sum[1],1
	
		inc	bytes			; アラインを次に
		ret


assert_wr2times			; 2回書き込むだけ。用途と意図は？
		clrw		; w = 0
		call	assert_wr
		clrw		; w = 0
		goto	assert_wr
;-----------------------------------------------------------------------------------
;	送信データ=data
assert_wr2x
		add	remote_len[0],#1	; remote_len++
		btfsc	c	; if (c==0) skip
		inc	remote_len[1]; remote_len[1]++
		mov	w,data			; data変数を媒介 w = data
		goto	assert_wr
;	送信データ=W
assert_wr2	movwf	data		; 一度しまう data = w
		add	remote_len[0],#1; remote_len[0]++
		btfsc	c		; if (c==0) skip
		inc	remote_len[1]	; remote_len[1]++
		mov	w,data	; w = data

;-----------------------------------------------------------------------------------
;	■RTL8019へ書き込み(チェックサム考慮)
;-----------------------------------------------------------------------------------
assert_wr
		movwf	rd	; rd = w
assert_wr_2	btfss	bytes.0	; if (bytes.0==1) skip; bytes(current ptr for calculate above) ??
		goto	asser_wr_high
		
		add	sum[0],w; sum[0] = sum[0] + w
		movlw	1	; w = 1
		btfsc	c	; if (c==0) skip
		addwf	sum[1],1; sum[1] += w;

		btfsc	c	; if (c==0) skip
		addwf	sum[0],1; sum[0] += w
		btfsc	c	; if (c==0) skip
		addwf	sum[1],1; sum[1] += w;
		
		inc	bytes	; bytes++
		goto	assert_wr0_2
asser_wr_high
		add	sum[1],w; sum[1] += w
		movlw	1	; w = 1
		
		btfsc	c	; if (c==0) skip
		addwf	sum[0],1; sum[0] += w
		btfsc	c	; if (c==0) skip
		addwf	sum[1],1; sum[1] += w;
	
		inc	bytes	; bytes++
		goto	assert_wr0_2

;-----------------------------------------------------------------------------------
;	■RTL8019へ単純書き込み WをRTLのSD0-7(Data Bus)に入力
;-----------------------------------------------------------------------------------
assert_wr0
		movwf	rd	; rd = w
assert_wr0_2	bsf	rp0	; rp0 = 1 bank1に移動
		clr	rd	; RDポート出力に設定
		bcf	rp0	; rp0 = 0 bank0に移動
		
		bcf	WR	; WR (RTL8019AS ~IOWB: I/O port書き込み) = 0 
		
		btfss	RDY	; ~IOCHRDY ウエイト要求; if (RDY==1) skip
		goto	$-1	; $(現在のアドレス) ウエイト要求↑に戻る
		
		bsf	WR	; WR = 1
		
		bsf	rp0	; rp0 = 1 bank1に移動
		mov	rd,#0ffh; RDポート入力に設定
		bcf	rp0	; rp0 = 0 bank0に移動
		ret

; SD0-7 Data Bus 読み出し data に代入
assert_rd
		bcf	RD	; RD (~IORB: I/O port読み出し) = 0 読み出し開始
		
		btfss	RDY	; ~IOCHRDY ウエイト要求; if (RDY==1) skip ウエイト要求チェック
		goto	$-1	; $(現在のアドレス)-1 ウエイト要求チェック↑に戻る
		
		mov	data,rd	; data (a data for transmit to ethernet chip) = rd
		
		bsf	RD	; RD = 1 読み出し終り
		ret

;-----------------------------------------------------------------------------------
;	■パケット送信関連処理
;-----------------------------------------------------------------------------------
transmit_this_ip
		mov	fsr,#this_ip	; fsr = this_ip
		movlw	4		; w = 4

transmit_nbytes
		movwf	gcn1		; gcn1 = w
		mov	rc,#10h		; rc = 10h (remote DMA port)
transmit0	mov	w,indirect	; w = indirect
		call	assert_wr	; write RTL
		inc	fsr		; fsr++
		djnz	gcn1,transmit0	; if (--gcn1!=0) goto transmit0
		ret


transmit_nbytes2
		movwf	gcn1		; gcn1 = w(counter(Byte数)を貰う)
		mov	rc,#10h		; rc = 10h remote DMA port
transmit2_0	mov	w,indirect	; w = indirect
		call	assert_wr2	; write w RTL
		inc	fsr		; fsr++
		djnz	gcn1,transmit2_0; if (--gcn1!=0) goto transmit2_0
		ret

;-----------------------------------------------------------------------------------
;	■パケット送信
;-----------------------------------------------------------------------------------
transmit
retry
		clr	rc		; rc = 0 (CR (Command Register))
		call	assert_rd	; read RTL
		
		btfsc	data.2		; 送信ビット(TXP)を見る if (data.2(TXP) == 0) skip
		goto	transmit	; （送信完了していないので）送信待ち
		
		clr	rc		; rc = 0 (CR)
		movlw	00100110b	; 送信ビットを立てる remote DMA abort, transmit packet, RTL start
		call	assert_wr0	; 送信！ write RTL
trans100
		mov	rc,#4		; rc = 4 (TSR (Trinsmit Status Register))
		call	assert_rd	; read RTL
		
		btfsc	data.0		; if (data.0(PTX)==0) skip packet送信完了？
		goto	transmit9	; 送信完了？送信完了
		btfsc	data.3		; if (data.3(COL)==0) skip 送信アボート？
		goto	retry		; 再送信
		
		goto	trans100	; 送信待ち
transmit9	ret


;-----------------------------------------------------------------------------------
;	■Ethernetヘッダを作成する。
;-----------------------------------------------------------------------------------
prepare_ether2	; ARPの場合
		mov	remote_len[0],#PACKET_SIZE + ARP_SIZE	;2ah	;PACKET_SIZE + ARP_SIZE
		goto	prepare_ether1
prepare_ether	; IPの場合
		mov	remote_len[0],#PACKET_SIZE + IP_SIZE	;2ah	;PACKET_SIZE + IP_SIZE
prepare_ether1	; 共通Routine
		clr	remote_len[1]	; remote_len[1] = 0
		clr	remote_adr[0]	; remote_adr[0] = 0
		mov	remote_adr[1],#PAGE_BEGIN; remote_adr[1] = PAGE_BEGIN
		call	remote_write	; prepare for writing remote DMA
		
		mov	rc,#10h		; このパケットを送ってくれた相手のMAC (remote DMA port)
		mov	fsr,#eth_src	; fsr = eth_src(送信元MACアドレス)
		movlw	6		; w = 6
		call	transmit_nbytes	; write eth_src (6Bytes) to remote DAM
		
		mov	fsr,#mymac	; fsr = mymac 自分のMACアドレスを設定
		movlw	6		; w = 6
		call	transmit_nbytes	; write maymac (6Bytes) to remote DAM
		ret

;-----------------------------------------------------------------------------------
;	■IPヘッダ作成作業
;-----------------------------------------------------------------------------------
prepare_ip			; Ethernet frame header
		call	prepare_ether	; prepare for transmitting Ethernet frame
		movlw	COM_PROTO	; w = COM_PROTO (08h) Ethernet frame type
		call	assert_wr	; write RTL
		movlw	IP_PROTO	; w = IP_PROTO (00)
		call	assert_wr	; write RTL
	;; IP freme header
		call	ip_common
		
	;	call	abort
		
		mov	remote_adr[0],#ip_sum - ip_header + PACKET_SIZE
		mov	remote_adr[1],#PAGE_BEGIN
	;	goto	set_checksum
set_checksum
		comf	sum[0]	; sum[0]の補数 格納先は w or sum[0]?どっち
		comf	sum[1]	; sum[1]の補数
		
		mov	remote_len[0],#2		; チェックサムは2バイトである
		clr	remote_len[1]; remote_len[1] = 0
		call	remote_write; prepare for writting remote DMA
		
		mov	rc,#10h		; remote DMA port
		mov	w,sum[1]	; w = sum[1]
		call	assert_wr0	; チェックサムの書き込み(assert_wr0をコールしなければならない)
		mov	w,sum[0]	; w = sum[0]
		call	assert_wr0	; wをRTLに書き込み
		ret

;-----------------------------------------------------------------------------------
;	■IPプロトコルヘッダ作成
;-----------------------------------------------------------------------------------
ip_common
		call	clear_sum	; チェックサムの値をクリア
		
		mov	rc,#10h		; rc = 10h remote DMA port
		movlw	45h		; ID (Version 4, Data length 5(*4=20byte))
		call	assert_wr	; write RTL
		movlw	00h		; TOS
		call	assert_wr	; write RTL
		
		mov	w,ip_length[0]	; length high 全データ長
		call	assert_wr	; write RTL
		mov	w,ip_length[1]	; length low
		call	assert_wr	; write RTL
		
		mov	fsr,#ident	; fsr = ident 識別子
		mov	w,indirect	; Seq No High
		call	assert_wr	; write RTL
		inc	fsr		; fsr++
		
		mov	w,indirect	; Seq No Low
		call	assert_wr	; write RTL
		add	indirect,#1	; indirect += 1
		dec	fsr	; fsr--
		btfsc	c	; if (c==0) skip
		addwf	indirect,1; indirect += w

		movlw	00h			; flagment(2bytes)
		call	assert_wr		; write RTL
		movlw	00h			;
		call	assert_wr		; write RTL
		
		movlw	0ffh			; TTL
		call	assert_wr		; write RTL
		
		mov	w,proto			; PROTOCOL = anything
		call	assert_wr		; write RTL
		
		call	assert_wr2times		; sum is zero ;0を2回書き込む
		
		call	transmit_this_ip	; 自分のIP書き込み
		
		mov	fsr,#ip_src		; to IP (送信先IP)
		movlw	4			; 4 byte
		call	transmit_nbytes		; write w(4) byte to RTL
		ret




;||-----------------------------------------------------------------------------
;|| SUB ROUTINE
;||

;|| NTP パケット解析ルーチン

calendar
		bcf	rp1		; rp1=0
		bcf	rp0		; rp0=0 Bank0

		clrb	tmr1on	; Timer1 停止。＆クリア
		clr	tmr1l	; tmr1l = 0 (clear timer1 holding register(L))
		clr	tmr1h	; tmr1h = 0 (clear timer1 holding register(H))

		bsf	rp1		; rp1=1 Bank2
;		bcf	rp0		; rp0=0
		call	hikizahaan

		;sb1dd 1/256 sec 反映

myss0
		csb	sb1dd,#141		; if (sb1dd >= 0.550781) goto myss6 (なんとなくジャンプ)
		goto	myss6

		csb	sb1dd,#13		; if (sb1dd >= 0.05078) goto myss1
		goto	myss1
		clr	myi & 0ffh
		goto	myssup
myss1
		csb	sb1dd,#39		; if (sb1dd >= 0.15234) goto myss2
		goto	myss2
		mov	myi & 0ffh,#1
		goto	myssup
myss2
		csb	sb1dd,#64		; if (sb1dd >= 0.25) goto myss3
		goto	myss3
		mov	myi & 0ffh,#2
		goto	myssup
myss3
		csb	sb1dd,#90		; if (sb1dd >= 0.35156) goto myss4
		goto	myss4
		mov	myi & 0ffh,#3
		goto	myssup
myss4
		csb	sb1dd,#116		; if (sb1dd >= 0.453125) goto myss5
		goto	myss5
		mov	myi & 0ffh,#4
		goto	myssup
myss5
;		csb	sb1dd,#141		; ５までで終わり。141 以上は既に跳んでいる。
;		goto	myss6
		mov	myi & 0ffh,#5
		goto	myssup
myss6
		csb	sb1dd,#167		; if (sb1dd >= 0.65234) goto myss7
		goto	myss7
		mov	myi & 0ffh,#6
		goto	myssup
myss7
		csb	sb1dd,#192		; if (sb1dd >= 0.75) goto myss8
		goto	myss8
		mov	myi & 0ffh,#7
		goto	myssup
myss8
		csb	sb1dd,#218		; if (sb1dd >= 0.85156) goto myss9
		goto	myss9
		mov	myi & 0ffh,#8
		goto	myssup
myss9
		csb	sb1dd,#244		; if (sb1dd >= 0.953125) goto myss10
		goto	myss10
		mov	myi & 0ffh,#9
		goto	myssup
myss10
;		csb	sb1dd,#255		; １０で１秒あがり。
;		goto	myss
		mov	myi & 0ffh,#0
		call	cup
myssup
		mov	sb1dd & 0ffh,myi
		add	sb1dd,#30h		; →ascii

		snb	myhour.7		; if (bit==0) skip
		goto	myssup0
		mov	sb1dd&0ffh,#'!'
myssup0

		call	date_display
		call	clock_diplay
	
		bcf	rp1	; rp1 = 0 : Bank 0
		setb	tmr1on	; Timer1 再起動
		goto	main9

;|| time divide routine 1

;; -------- ひきざ〜ん ------------
hikizahaan

;sb1d(上位),sb1c,sb1b,sb1a(下位) に引かれる数、
;sb2d(上位),sb2c,sb2b,sb2a(下位) に引く数をセットして呼ぶ。
;答は sb1d(上位),sb1c,sb1b,sb1a(下位) に得られます。

;	mov	sb1d,#0bfh		; 2001.7.20 Xday (3204551514 = bf01_935ah)
;	mov	sb1c,#009h
;	mov	sb1b,#05dh
;	mov	sb1a,#060h

	mov	sb2d & 0ffh,#0bch		; 2001.3.1 への換算 (3160825200=bc66_5d70h)
	mov	sb2c & 0ffh,#066h
	mov	sb2b & 0ffh,#05dh
	mov	sb2a & 0ffh,#070h

	call	sub32

;; -------- じょさ〜ん ------------
josahaan
	mov	div1d & 0ffh,sb1d	;割られる数上位 (ntp_T - 2000.3.1)
	mov	div1c & 0ffh,sb1c	; 〜
	mov	div1b & 0ffh,sb1b	; 〜
	mov	div1a & 0ffh,sb1a	;下位
	mov	div2d & 0ffh,#00h	;割る数上位	(86400 =01_51_80h)
	mov	div2c & 0ffh,#01h	; 〜
	mov	div2b & 0ffh,#051h 	; 〜
	mov	div2a & 0ffh,#080h	;下位
	call	div32		;答えは div3d,c,b,a 、余りは div4d,c,b,a に返る

	mov	mypd0 & 0ffh,div3a	; Pastday (2000.3.1 からの経過日)16bit 下位
	mov	mypd1 & 0ffh,div3b	; Pastday 16bit 上位
;; ------------------------------
	mov	div1d & 0ffh,#00h		;ntp_T mod 86400 (0-86399 17bit)
	mov	div1c & 0ffh,div4c
	mov	div1b & 0ffh,div4b
	mov	div1a & 0ffh,div4a
	mov	div2d & 0ffh,#00h		; 3600 (=0e_10h)
	mov	div2c & 0ffh,#00h
	mov	div2b & 0ffh,#0eh
	mov	div2a & 0ffh,#010h
	call	div32
;; ------------------------------
	and	myhour,#1110_0000b		; bit4[AM/PM],bit3-0[hour] are clear

	csae	div3a,#12		;if (hour<12) goto myhset
	goto	myhset		;

	setb	myhour.4		;PM bit set
	sub	div3a,#12		;12時間戻す
;	add	myhour,div3a
;	goto	myhset_out
myhset
	add	myhour,div3a		; set hour
;myhset_out
;; ------------------------------
	mov	div1d & 0ffh,#0h		;ntp_T mod 86400 mod 3600 (0-3599 12bit)
	mov	div1c & 0ffh,#0h
	mov	div1b & 0ffh,div4b
	mov	div1a & 0ffh,div4a
	mov	div2d & 0ffh,#0h		; 60 (=0_3ch)
	mov	div2c & 0ffh,#0h
	mov	div2b & 0ffh,#0h
	mov	div2a & 0ffh,#03ch
	call	div32

	mov	prm1a & 0ffh,div3a		; 8bit 数値→BCD ３桁
	call	hexdec8		; 結果はprm3c-a

	mov	dmin0 & 0ffh,prm3a		; 分 一の位
	mov	dmin1 & 0ffh,prm3b		; 分 十の位
;; ------------------------------
	mov	prm1a & 0ffh,div4a		; 8bit 数値→BCD ３桁
	call	hexdec8		; 結果はprm3c-a

	mov	dsec0 & 0ffh,prm3a		; 秒 一の位
	mov	dsec1 & 0ffh,prm3b		; 秒 十の位

;	ret		次のルーチンに突入。

;|| time divide routine 2

hizukkke
	mov	div1d & 0ffh,#00h		; 経過日
	mov	div1c & 0ffh,#00h
	mov	div1b & 0ffh,mypd1
	mov	div1a & 0ffh,mypd0
	mov	div2d & 0ffh,#00h		; 曜日計算用 (Mod 7 = 0 = 2000.3.1 is Wednesday)
	mov	div2c & 0ffh,#00h
	mov	div2b & 0ffh,#00h
	mov	div2a & 0ffh,#07h
	call	div32

	mov	myday & 0ffh,div4a
;	ret

	mov	div1d & 0ffh,#00h		; 経過日
	mov	div1c & 0ffh,#00h
	mov	div1b & 0ffh,mypd1
	mov	div1a & 0ffh,mypd0
	mov	div2d & 0ffh,#00h		; 年計算用 (４年間 = 1461=5b5h 日)
	mov	div2c & 0ffh,#00h
	mov	div2b & 0ffh,#05h
	mov	div2a & 0ffh,#0b5h
	call	div32

	mov	myyear & 0ffh,div3a

	mov	mydate & 0ffh,div4a		; ４年周期の経過日下位 (0-1460=5b4h 11bit)
	mov	mymonth & 0ffh,div4b		; ４年周期の経過日上位

;	mov	mydate,mypd0
;	mov	mymonth,mypd1
;	mov	mydate,#01h
;	mov	mymonth,#00h
;	mov	myyear,#9

;	mov	myyear,#myyear<<2		;myyear*4
	rl	myyear
	rl	myyear
	and	myyear,#1111_1100b

;	ret		;次のルーチンに突入。

;|| time divide routine 3

daycalc
	clr	poi & 0ffh
	mov	cn & 0ffh,#48		; 4年間 12*4 ヶ月

;daycalc0

	mov	sb1d & 0ffh,#0
	mov	sb1c & 0ffh,#0
	mov	sb1b & 0ffh,mymonth
	or	sb1b & 0ffh,#0000_1000b	; 12 bit 目に１を立てる。
	mov	sb1a & 0ffh,mydate                

	clr	sb2d & 0ffh
	clr	sb2c & 0ffh
	clr	sb2b & 0ffh
daycalc0

	mov	w,poi
	call	month_table
	mov	sb2a & 0ffh,w
	call	sub32

;	mov	mymonth,sb1b
;	mov	mydate,sb1a
;	ret

	snb	sb1b.3		; if (12 bit 目が0 = 負になった。) then skip
	goto	tuginotuki

	mov	mymonth & 0ffh,poi		; 月は(0-11 になる)
	inc	mydate		; 日付は(0-30 →1-31 になる)

	ret		; 計算終了
tuginotuki
	mov	mymonth & 0ffh,sb1b		;
	mov	mydate & 0ffh,sb1a		;

	inc	poi		; poi = poi + 1

	csne	poi,#10		; if (poi ==10) then myyear ++
	inc	myyear		; （１１番目の月＝１月に年が上がる。）

	csne	poi,#12		; if (poi ==12 then poi=0
	clr	poi & 0ffh	; （２月がdate_table の終わり。）

	djnz	cn,daycalc0		; 4年分くり返し

	mov	mymonth & 0ffh,#11		; ４年周期の最後は２月２９日
	mov	mydate & 0ffh,#29		;
	ret		; 最終日の時の計算終了

;; ------------------------------

;|| display time on LCD routine 2
date_display
	clrb	RS		; change to command mode
	mov	d4,#10000000b
	mov	pclath,#write_lcd4>>8
	call	write_lcd4		; カーソルを1行目に移動
	clr	pclath	; pageを戻す Page0

	setb	RS		; 以後のコマンドは文字表示


; [0123456789ABCDEF]
; [WWW, MMM DD YYYY]
;------------ 曜日の出力

	mov	w,myday		; W1
	call	week_table
	mov	d4,w

	mov	pclath,#write_lcd4>>8
	call	write_lcd4
	clr	pclath	; pageを戻す Page0

	add	myday,#7		; w2
	mov	w,myday
	call	week_table
	mov	d4,w

	mov	pclath,#write_lcd4>>8
	call	write_lcd4
	clr	pclath	; pageを戻す Page0

	add	myday,#7		; w3
	mov	w,myday
	call	week_table
	mov	d4,w

	sub	myday,#14

	mov	pclath,#write_lcd4>>8
	call	write_lcd4

	mov	d4,#','		; ' 'を出力
	call	write_lcd4
	mov	d4,#' '		; ' 'を出力
	call	write_lcd4

	clr	pclath	; pageを戻す Page0


;------------ 月の出力

	mov	w,mymonth		; M1
	call	mon_table
	mov	d4,w

	mov	pclath,#write_lcd4>>8
	call	write_lcd4
	clr	pclath	; pageを戻す Page0

	add	mymonth,#12		; m2
	mov	w,mymonth
	call	mon_table
	mov	d4,w

	mov	pclath,#write_lcd4>>8
	call	write_lcd4
	clr	pclath	; pageを戻す Page0

	add	mymonth,#12		; m3
	mov	w,mymonth
	call	mon_table
	mov	d4,w

	sub	mymonth,#24

	mov	pclath,#write_lcd4>>8
	call	write_lcd4
	mov	d4,#' '		; ' 'を出力
	call	write_lcd4
	clr	pclath	; pageを戻す Page0

;------------ 日の出力
	mov	prm1a & 0ffh,mydate		; 8bit 数値→BCD ３桁
	call	hexdec8		; 結果はprm3c-a

	add	prm3a,#30h		; bin → ascii
	add	prm3b,#30h		; bin → ascii

	mov	d4,prm3b		; 日付十の位を出力

	mov	pclath,#write_lcd4>>8
	call	write_lcd4
	mov	d4,prm3a		; 日付一の位を出力
	call	write_lcd4

	mov	d4,#' '		; ' 'を出力
	call	write_lcd4

;------------ 年の出力
	mov	d4,#'2'		; 年頭２桁は２０で固定
	call	write_lcd4
	mov	d4,#'0'		;
	call	write_lcd4
	clr	pclath	; pageを戻す Page0



	mov	prm1a & 0ffh,myyear		; 8bit 数値→BCD ３桁
	call	hexdec8		; 結果はprm3c-a

	add	prm3b,#30h		; bin → ascii
	add	prm3a,#30h		; bin → ascii

	mov	d4,prm3b		; ３桁目を出力

	mov	pclath,#write_lcd4>>8
	call	write_lcd4
	mov	d4,prm3a		; ４桁目を出力
	call	write_lcd4
	clr	pclath	; pageを戻す Page0

	ret

;; ------------------------------


;|| display time on LCD routine

clock_diplay

;; decimal -> ascii
	movlw	0011_0000b		; 上位ビットを追加
	add	dsec0,w
	add	dsec1,w
	add	dmin0,w
	add	dmin1,w
	add	dh0,w
	add	dh1,w

;; 液晶下準備
	clrb	RS		; command mode
	mov	d4,#11000000b
	mov	pclath,#write_lcd4>>8
	call	write_lcd4		; カーソルを2行目に移動
	setb	RS		; 以後のコマンドは文字表示

;; '   hh:mm:ss JST '　をLCDに表示
;	mov	d4,#' '		 ; ' 'を出力
;	call	write_lcd4

	mov	pclath,#myho24>>8
	snb	myhour.5		;if (bit==1)goto myho24
	goto	myho24

;;------------AM/PM表示---------
	snb	myhour.4		;if (bit==1)goto myhoAP_2
	goto	myhoAP_2
;--AM-------
	mov	pclath,#write_lcd4>>8
	mov	d4,#'A'
	call	write_lcd4
	mov	pclath,#myhoAP_3>>8
	goto	myhoAP_3
;--PM-------
myhoAP_2
	mov	pclath,#write_lcd4>>8
	mov	d4,#'P'
	call	write_lcd4
;--AM/PM 共通-------
myhoAP_3
	mov	pclath,#write_lcd4>>8
	mov	d4,#'M'
	call	write_lcd4
	mov	d4,#' '
	call	write_lcd4

	mov	pclath,#myhoAP_1>>8
	mov	dh0 &0ffh,myhour
	and	dh0,#0fh
	csb	dh0,#10		;if (myhour>=10) goto myhoAP_1
	goto	myhoAP_1
;--時間１桁-------
	mov	pclath,#write_lcd4>>8
	mov	d4,#' '		; d4 = dh1 時間の上位1桁目
	call	write_lcd4
	add	dh0,#30h
	mov	d4,dh0		; d4 = dh0 時間の上位2桁目
	call	write_lcd4

	mov	pclath,#myho>>8
	goto	myho
;--時間２桁-------
myhoAP_1
	mov	pclath,#write_lcd4>>8
	mov	d4,#'1'		; d4 = dh1 時間の上位1桁目
	call	write_lcd4
	and	dh0,#01h
	add	dh0,#30h
	mov	d4,dh0		; d4 = dh0 時間の上位2桁目
	call	write_lcd4

	mov	pclath,#myho>>8
	goto	myho

;;------------AM/PM表示------終わり---
;;------------２４時間表示---------
myho24
	mov	pclath,#write_lcd4>>8
	mov	d4,#' '
	call	write_lcd4
;	mov	d4,#'*'
;	call	write_lcd4
	mov	d4,#' '
	call	write_lcd4

	mov	pclath,#myho24_1>>8
	snb	myhour.4		;if (bit==1)goto myho24_1
	goto	myho24_1

	mov	dh0 &0ffh,myhour
	and	dh0,#0fh
	csb	dh0,#10		;if (myhour>=10) goto myho24_2
	goto	myho24_2

;--[0-9]-------
	mov	pclath,#write_lcd4>>8
	mov	d4,#' '		; d4 = dh1 時間の上位1桁目
	call	write_lcd4
	mov	w,myhour
	and	w,#0fh
	add	w,#30h
	mov	d4,w		; d4 = dh0 時間の上位2桁目
	call	write_lcd4

	mov	pclath,#myho>>8
	goto	myho
;--[10-11]-------
myho24_2
	mov	pclath,#write_lcd4>>8
	mov	d4,#'1'		; d4 = dh1 時間の上位1桁目
	call	write_lcd4
	mov	w,myhour
	and	w,#01h
	add	w,#30h
	mov	d4,w		; d4 = dh0 時間の上位2桁目
	call	write_lcd4

	mov	pclath,#myho>>8
	goto	myho
	
;--[12-19]-------
myho24_1
	mov	pclath,#myho24_3>>8
	snb	myhour.3		;if (bit==1)goto myho24_3
	goto	myho24_3

	mov	pclath,#write_lcd4>>8
	mov	d4,#'1'		; d4 = dh1 時間の上位1桁目
	call	write_lcd4
	mov	w,myhour
	and	w,#0fh
	add	w,#32h
	mov	d4,w		; d4 = dh0 時間の上位2桁目
	call	write_lcd4

	mov	pclath,#myho>>8
	goto	myho
;--[20-23]-------
myho24_3
	mov	pclath,#write_lcd4>>8
	mov	d4,#'2'		; d4 = dh1 時間の上位1桁目
	call	write_lcd4
	mov	w,myhour
	and	w,#07h
	add	w,#30h
	mov	d4,w		; d4 = dh0 時間の上位2桁目
	call	write_lcd4
;;------------２４時間表示------終わり---
myho
	mov	pclath,#write_lcd4>>8
	mov	d4,#3ah		; d4 = ':'
	call	write_lcd4
	mov	d4,dmin1	; d4 = dmin1 分の上位1桁目
	call	write_lcd4
	mov	d4,dmin0	; d4 = dmin0 分の上位2桁目
	call	write_lcd4
	mov	d4,#3ah		; d4 = ':'
	call	write_lcd4
	mov	d4,dsec1	; d4 = dsec1 秒の上位1桁目
	call	write_lcd4
	mov	d4,dsec0	; d4 = dsec0 秒の上位2桁目
	call	write_lcd4
	mov	d4,#' '		; ' '
	call	write_lcd4
	mov	d4,#'J'		; 'J'
	call	write_lcd4
	mov	d4,#'S'		; 'S'
	call	write_lcd4
	mov	d4,#'T'		; 'T'
	call	write_lcd4
	mov	d4,sb1dd		; ' '
	call	write_lcd4
	mov	d4,#' '		; ' '
	call	write_lcd4
	mov	d4,#' '		; ' '
	call	write_lcd4

	clr	pclath	; pageを戻す Page0

;; ascii -> decimal
	movlw 0000_1111b		; 上位ビット消去
	and	dsec0,w
	and	dsec1,w
	and	dmin0,w
	and	dmin1,w
	and	dh0,w
	and	dh1,w

	ret

;||-----------------------------------------------------------------------------
;|| 8bit (0-255) → BCD
;|| from http://www.sikasenbey.or.jp/~enaga/pic/pic.html

;８ビット（１バイト）数値を１０進数３桁のＢＣＤ数値に変換する
;引き数は prm1a の１バイト
;結果は prm3c,prm3b,prm3a に得られる。
;右の prm3a が下位の数になる
;使用変数宣言の際に prm3a の下で、ラベル名 dec_top: を記述しておくこと。

;;使用例
;	movlw	0ffh		; ffh=255
;	movwf	prm1a
;	call	hexdec8
hexdec8:
	bsf	irp		; Bank2,3
	
	movlw	dec_top & 0ffh		;格納場所初期値
	movwf	4h		;4h=fsr
	call	devide	;最下位変換
	call	devide
	call	devide	;最上位変換

	bcf	irp		; Bank0,1
	return

devide:		;÷１０サブルーチン　（１０で除算）
	movlw	8	;８ビットくり返し
	movwf	srlc1 & 0ffh
	clrf	srwk1 & 0ffh
devide0:
	bcf	3h,0		;キャリフラグのクリア
	rlf	prm1a,1
	rlf	srwk1,1
	movlw	11110110b
	addwf	srwk1,0
	btfsc	3h,0
	movwf	srwk1 & 0ffh
	btfsc	3h,0
	incf	prm1a,1
	decfsz	srlc1,1
	goto	devide0
	decf	4h,1		;4h=fsr
	movf	srwk1,0
	movwf	0h	;余り (0h=indirect)

	return
;||-----------------------------------------------------------------------------
;|| 32bit 減算
;|| from http://www.sikasenbey.or.jp/~enaga/pic/pic.html

;３２−３２ビット＝３２ビットの減算サブルーチン
;sb1d(上位),sb1c,sb1b,sb1a(下位) に引かれる数、
;sb2d(上位),sb2c,sb2b,sb2a(下位) に引く数をセットして呼ぶ。
;答は sb1d(上位),sb1c,sb1b,sb1a(下位) に得られます。
;sb2d,sb2c,sb2b,sb2a は変化しない。

sub32:
	movf	sb2a,0
	subwf	sb1a,1
	movlw	1
	btfss	3h,0
	subwf	sb1b,1
	btfss	3h,0
	subwf	sb1c,1
	btfss	3h,0
	subwf	sb1d,1

	movf	sb2b,0
	subwf	sb1b,1
	movlw	1
	btfss	3h,0
	subwf	sb1c,1
	btfss	3h,0
	subwf	sb1d,1

	movf	sb2c,0
	subwf	sb1c,1
	movlw	1
	btfss	3h,0
	subwf	sb1d,1

	movf	sb2d,0
	subwf	sb1d,1

	return

;||-----------------------------------------------------------------------------
;|| 32bit 除算
;|| from http://www.sikasenbey.or.jp/~enaga/pic/pic.html

; ３２÷３２ビット＝３２ビットの割り算ルーチン
; div1d,c,b,a ÷ div2d,c,b,a ＝ 結果 div3d,c,b,a  余り div4d,c,b,a
; 演算後、式の左項（割られる数）は壊れる
; 割る数が０（エラー）なら diverr に１を代入して戻る
; エラーの場合、引き数は変化しない
; 正常終了の場合は diverr=0 で戻る
; 32ビットで扱える数の最大は 4294967295　(42億9496万7295)

;; 使用例
;	mov	div1d,#0ffh	;割られる数上位    (ffffffffh=4,294,967,295)
;	mov	div1c,#0ffh	; 〜
;	mov	div1b,#0ffh	; 〜
;	mov	div1a,#0ffh	;下位
;	mov	div2d,#00h	;割る数上位	   (989680h=10,000,000)
;	mov	div2c,#098h	; 〜
;	mov	div2b,#096h 	; 〜
;	mov	div2a,#080h	;下位
;	call	div32		;答えは div3d,c,b,a 、余りは div4d,c,b,a に返る

div32:
		mov	divl1 & 0ffh,#32
		mov	div4a & 0ffh,div2a	;割る数をワークにコピー
		mov	div4b & 0ffh,div2b
		mov	div4c & 0ffh,div2c
		mov	div4d & 0ffh,div2d
di3201:		rl	div4a		;左シフトする
		rl	div4b
		rl	div4c
		rl	div4d
		jc	di3202		;割る数の上位ビットが見付かったなら di3202 へ
		djnz	divl1,di3201
		mov	diverr & 0ffh,#01	;割る数が０である、エラー
		ret

di3202:		clr	div3a & 0ffh		;答えのクリア
		clr	div3b & 0ffh
		clr	div3c & 0ffh
		clr	div3d & 0ffh
		clr	div4a & 0ffh		;ワークのクリア（ワークには余りが残る）
		clr	div4b & 0ffh
		clr	div4c & 0ffh
		clr	div4d & 0ffh
		mov	divl2 & 0ffh,#32
		sub	divl2,divl1	;残り、実ループの回数

di3203:		clc			;キャリフラグを０に
		rl	div1a		;有効位置までシフトする
		rl	div1b
		rl	div1c
		rl	div1d
		rl	div4a		;押し出されたビットをワークに
		rl	div4b
		rl	div4c
		rl	div4d
		djnz	divl1,di3203	;割られる数を初期位置までシフトしておく

di3204:	
		movf	div2d,0		;div2c を w にコピー
		subwf	div4d,0		;比較
		btfsc	3,2		;結果が＝なら di3205 へ
		goto	di3205
		btfsc	3,0		;引くことが可なら di3210 へ
		goto	di3210
		btfss	3,0		;引くことは不可なら di3211 へ
		goto	di3211
di3205:
		movf	div2c,0
		subwf	div4c,0
		btfsc	3,2
		goto	di3206
		btfsc	3,0
		goto	di3210
		btfss	3,0
		goto	di3211
di3206:
		movf	div2b,0
		subwf	div4b,0
		btfsc	3,2
		goto	di3207
		btfsc	3,0
		goto	di3210
		btfss	3,0
		goto	di3211
di3207:
		movf	div2a,0
		subwf	div4a,0
		btfsc	3,2
		goto	di3210
		btfss	3,0
		goto	di3211

di3210:		sub	div4a,div2a	;ワークから下位を引く
		movlw	1		;ワークには余りが残る
		btfss	3,0
		subwf	div4b,1
		btfss	3,0
		subwf	div4c,1
		btfss	3,0
		subwf	div4d,1
		sub	div4b,div2b	;ワークから２位を引く
		movlw	1
		btfss	3,0
		subwf	div4c,1
		btfss	3,0
		subwf	div4d,1
		sub	div4c,div2c	;ワークから３位を引く
		btfss	3,0
		dec	div4d		;４上位 -1
		sub	div4d,div2d	;ワークから上位を引く
		stc			;キャリフラグを１に
		goto	di3212

di3211:		clc			;キャリフラグを０に
di3212:		rl	div3a		;キャリフラグの内容を答えにシフトしてゆく
		rl	div3b
		rl	div3c
		rl	div3d
		cje	divl2,#0,di3213	;最下位まで処理したなら終了
		dec	divl2		;ビット位置を１つ下げる（右へ）
		clc			;キャリフラグを０に
		rl	div1a		;ワークへ１ビット左シフト
		rl	div1b
		rl	div1c
		rl	div1d
		rl	div4a
		rl	div4b
		rl	div4c
		rl	div4d
		goto	di3204

di3213:		mov	diverr & 0ffh,#00	;正常終了
		ret


;||-----------------------------------------------------------------------------
;|| OPENING MESSAGE page1
;||
		org	800h
page1_table
utility_table
	jmp	pc+w
	retw	'__ IP Setting __'		; [0-15]
	retw	' __ Utility ___ '		; [16-31]
	retw	' The NTP Clock  '		; [32-47]
	retw	'+PICNIC powered+'		; [48-63]
	retw	' My IP Address ?'		; [64-79]
	retw	' SubNet Mask ?  '		; [80-95]
	retw	'DefaultGateway ?'		; [96-111]
	retw	' NTP Server ?   '		; [112-127]
	retw	'Edit End...     '		; [128-143]
	retw	'  Please Wait...'		; [144-159]
	retw	'SaveOK? ',127,'Y ',1,'C ',126,'N'		; [160-175]
	retw	'Now Saving...   '		; [176-191]
	retw	'Canceling...    '		; [192-207]
		; [208-223]
		; [224-239]
		; [240-255] 使用不可

;-----------------------------------------------------------------------------------
;		Trasmit ARP request
;-----------------------------------------------------------------------------------
		org	920h

arp_transmit
		clrb	RS		; command mode
		mov	d4,#11000000b; カーソルを2行目に移動
		mov	pclath,#write_lcd4>>8
		call	write_lcd4; write LCD
		setb	RS		; 以後のコマンドは文字表示

		mov	d4,#'A'
		mov	pclath,#write_lcd4>>8
		call	write_lcd4; write LCD
;		mov	pclath,#$>>8

;    		bsf	rp0	; rp0 = 1
;    		bsf	rp1	; rp1 = 1 Bank3
    		bcf	rp1	; rp1 = 0
    		bsf	rp0	; rp0 = 1 Bank1

  		bsf	irp			; irp = 1
  		mov	fsr,#on_ip & 0ffh	; fsr = on_ip(destination IP address) & 0ffh
  		mov	indirect,ntp_ip[0]
  		inc	fsr
  		mov	indirect,ntp_ip[1]
  		inc	fsr
  		mov	indirect,ntp_ip[2]
  		inc	fsr
  		mov	indirect,ntp_ip[3]
;        		mov	on_ip[0] & 0ffh,#NTP_Server_Seg4
;        		mov	on_ip[1] & 0ffh,#NTP_Server_Seg3
;        		mov	on_ip[2] & 0ffh,#NTP_Server_Seg2
;        		mov	on_ip[3] & 0ffh,#NTP_Server_Seg1

		bcf	rp1	; rp1 = 0
		bcf	rp0	; rp0 = 0 Bank0
		mov	pclath,#arp_request>>8
		call	arp_request
		ret
	
;-----------------------------------------------------------------------------------
;		Transmit NTP request 
;-----------------------------------------------------------------------------------
ntp_transmit			; called from ser_arp
  	        mov     d4,#'N'
  		mov	pclath,#write_lcd4>>8
  		call	write_lcd4; write LCD
; 		mov	pclath,#$>>8

  		;; MAC address destination
;  		bsf	irp	; irp = 1 Bank2,3
;  		mov	fsr,#on_ether & 0ffh
;  		bsf	rp0	; rp0 = 1 Bank1
;  		mov	eth_src[0],indirect; @eth_src = @on_ether
;  		inc	fsr
;  		mov	eth_src[1],indirect
;  		inc	fsr
;  		mov	eth_src[2],indirect
;  		inc	fsr
;  		mov	eth_src[3],indirect
;  		inc	fsr
;  		mov	eth_src[4],indirect
;  		inc	fsr
;  		mov	eth_src[5],indirect
;  		bcf	rp0	; rp0 = 0 Bank0
		

		bcf	irp	; irp = 0 Bank0,1

		clr	ip_length[0]
		mov	ip_length[1],#IP_SIZE + UDP_SIZE + NTP_PACKET_SIZE
		
		clr	pclath
		
		mov	proto,#UDP_PROTO; protocol


		mov	fsr,#ip_src; NTP Server IP address
    		bsf	rp0	; rp0 = 1 Bank1
		mov	indirect,ntp_ip[0]
		inc	fsr
		mov	indirect,ntp_ip[1]
		inc	fsr
		mov	indirect,ntp_ip[2]
		inc	fsr
		mov	indirect,ntp_ip[3]
    		bcf	rp0	; rp0 = 0 Bank0
	
		call	prepare_ip	; IPパケットまで作成
		call	clear_sum	; チェックサムの値をクリア
		
		mov	remote_adr[0],#PACKET_SIZE+IP_SIZE
		mov	remote_adr[1],#PAGE_BEGIN
		mov	remote_len[0],#(UDP_SIZE + NTP_PACKET_SIZE) & 0ffh
		mov	remote_len[1],#(UDP_SIZE + NTP_PACKET_SIZE) >> 8
		call	remote_write
		
		mov	rc,#10h	; remote DMA port

		mov	w,#0	; From PORT #(HIGH)
		call	assert_wr
		mov	w,#123	; From port (Low)
		call	assert_wr

		mov	w,#0	; to port (H)
		call	assert_wr
		mov	w,#123	; to port (L) = 123 (NTP)
		call	assert_wr
		
		movlw	(UDP_SIZE + NTP_PACKET_SIZE) >>8
		call	assert_wr
		movlw	(UDP_SIZE + NTP_PACKET_SIZE) & 0ffh ; UDP DATAGRAM SIZE
		call	assert_wr
		
		call	assert_wr2times			; sum(not fixed)
;
;		DGRAM (Data Gram)

		mov	w,#0Bh	; sample data
		call	assert_wr			; write RTL

		mov	tcn1,#47	; tcn1 = 47 (00hを47byte書き込む)
ntp_dgram_b	mov	w,#00h
		clr	pclath	; pclath = 0
		call	assert_wr	; write RTL
		mov	pclath,#$>>8
		djnz	tcn1,ntp_dgram_b; if (--tcn1!=0) goto ntp_dgram_b
		clr	tcn1
		
;  		mov	pclath,#calc_udp_sum>>8
		call	calc_udp_sum; check udp sum

		clr	pclath	; palath = 0
		
		mov	rc,#4h	; rc = 4   TPSR (Transmit Page Register)
		movlw	PAGE_BEGIN	; transmit page is start page 40h?
		call	assert_wr0
		
		mov	rc,#5	; TBCR0 (Transmit Byte Count Register (L))
		movlw	90	; あやしい90 Bytes? NTP Packet data length
		call	assert_wr0
		
		mov	rc,#6	; TBCR1 (Transmit Byte Count Register (H))
		movlw	0
		call	assert_wr0
		
		call	transmit
      		mov	pclath,#main9>>8; 無くても良いかな?when the function in same page
		goto	main9	

;-----------------------------------------------------------------------------------
;		■UDPチェックサム計算＋送信
;
calc_udp_sum
		clr	pclath
		clr	bytes			; 2バイトアラインの調整
		mov	fsr,#this_ip		; 自分のIPアドレスを加算
		mov	w,indirect
		call	calc_sum
		inc	fsr
		mov	w,indirect
		call	calc_sum
		inc	fsr
		mov	w,indirect
		call	calc_sum
		inc	fsr
		mov	w,indirect
		call	calc_sum
	
		mov	w,ip_src[0]		; 相手のIPアドレスを加算
		call	calc_sum
		mov	w,ip_src[1]
		call	calc_sum
		mov	w,ip_src[2]
		call	calc_sum
		mov	w,ip_src[3]
		call	calc_sum

		clrw				; プロトコル番号を加算
		call	calc_sum
		mov	w,#UDP_PROTO
		call	calc_sum
		
		mov	w,remote_len[1]
		call	calc_sum
		mov	w,remote_len[0]
		call	calc_sum

		mov	remote_adr[0],#PACKET_SIZE + IP_SIZE + 6	; チェックサムのセット位置
		mov	remote_adr[1],#PAGE_BEGIN
		call	set_checksum
		ret

transmit_60bytes
		clr	pclath	; palath = 0
		
		mov	rc,#4h	; rc = 4   TPSR (Transmit Page Register)
		movlw	PAGE_BEGIN	; transmit page is start page 40h?
		call	assert_wr0
		
		mov	rc,#5	; TBCR0 (Transmit Byte Count Register (L))
		movlw	60	; 基本的に60バイトとする。
		call	assert_wr0
		
		mov	rc,#6	; TBCR1 (Transmit Byte Count Register (H))
		movlw	0
		call	assert_wr0
		
		call	transmit
		ret

;
;		ARP応答受信処理 MAC addressを store
;  ser_arp
;  		bcf	irp	; irp = 0 Bank0,1
;  		mov	fsr,#arp_src_mac & 0ffh; fsr = arp_src_mac & 0ffh
		
;  		bsf	rp0	; rp0 = 1
;  		bsf	rp1	; rp1 = 1 Bank3
;  		mov	on_ether[0] & 0ffh,indirect	; ハードウェアアドレスをセット
;  		inc	fsr
;  		mov	on_ether[1] & 0ffh,indirect
;  		inc	fsr
;  		mov	on_ether[2] & 0ffh,indirect
;  		inc	fsr
;  		mov	on_ether[3] & 0ffh,indirect
;  		inc	fsr
;  		mov	on_ether[4] & 0ffh,indirect
;  		inc	fsr
;  		mov	on_ether[5] & 0ffh,indirect
;    		clr	status
	;	bcf	rp1
	;	bcf	rp0
	;	bcf	irp
		
;  		bsf	cren
;  		bsf	peie				; 使用許可

		;; debug
;    		mov	d4,#'a'
;    		mov	pclath,#write_lcd4>>8
;    		call	write_lcd4; write LCD

;  		mov	pclath,#ntp_transmit>>8
;  		goto	ntp_transmit

	
;-----------------------------------------------------------------------------------
		org	0a00h
;===================================================================================
;		■スタートアップルーチン start up routine
;===================================================================================
start
		bsf	rp1	; rp1 = 1 Bank2
	; 時計関連、リセットというかプリセット。値は結構適当。デバッグのため。
		clr	myi & 0ffh
		mov	mypd0 & 0ffh,#1
		mov	mypd1 & 0ffh,#0

		mov	myday & 0ffh,#1
		mov	mymonth & 0ffh,#1
		mov	mydate & 0ffh,#1
		mov	myyear & 0ffh,#1

		mov	dsec0 & 0ffh,#2
		mov	dsec1 & 0ffh,#3
		mov	dmin0 & 0ffh,#9
		mov	dmin1 & 0ffh,#5
		mov	dh0 & 0ffh,#7
		mov	dh1 & 0ffh,#1
		mov	myhour & 0ffh,#0111_1011b		; 7[Stealth on]6[disp date on]5[24h on]4[PM]3-0[hour]
		mov	sb1dd & 0ffh,#0011_1111b		; default "?" by ASCII
		mov	mystate &0ffh,#0100_0000b		; 7[Adjusted]6[ARP Request]
		bcf	rp1	; rp1 = 0 Bank0

start0		; Utility OUT Restart
		clr	ra	; ra = 0	; 各ポートの初期化
		clr	rb	; rb = 0
		clr	rc			; rc = 0 RTL8019AS SA0-SA5 (Address Bus)
		clr	rd			; rd = 0 RTL8019AS Data Bus
		mov	re,#111b		; 各コントロールポート = H意味ある?
		
		bsf	rp0	; rp0 =1 Bank1 に移動 (STATUS RP0)

		mov	adcon1,#1000_0111b	; RE,RA are Digital Pin

		mov	ra,#0011_1111b		; RA0-5は入力ピンとする TRISA0-5 input pin
		mov	rb,#0000_0000b		; RB7-0出力
		mov	rc,#1010_0000b		; trisc = 1010_0000b(1:input 0:output)
		mov	rd,#1111_1111b		; Address Bus
		mov	re,#000b		; RE0-2は出力ピンとする TRISE0-2 output pin

		;mov	option,#1011_1111b		;RB0 H -> L でトリガー（RB 割り込み設定）

		mov	pie1,#0000_0101b		;CCP1,Timer1 割り込み許可
		bcf	rp0	; rp0 = 0 Bank0

		call	get_ip_address		; EEPROMのIPアドレスをファイルレジスタに読み出す。
		call	get_ntp_address; EEPROMのNTP Server IP Addressを読む
	
		call	init_lcd		; 液晶モジュールの初期化
		mov	re,#011b		; 各コントロールポート = H
		
		mov	wait_cn,#5		; 5ms待つ
		call	wait_ms
		
		clr	pclath	; pclath = 0
		call	initialize		; RTL8019ASの初期化
		
	bsf	rp1		; rp1 = 1
		mov	poi&0ffh,#0
		mov	pclath,#ccl>>8; pclath = wait_us>>8
		call	ccl
	bcf	rp1

		mov	pclath,#opening_mess>>8
		call	opening_mess

		mov	pclath,#wait_us>>8; pclath = wait_us>>8
		mov	wait_cn,#100		; 100us待つ
		call	wait_us
		mov	pclath,#$>>8; pclath = $ >> 8 必要?

	;; timer1初期化
		clr	tmr1l	; tmr1l = 0 (clear timer1 holding register(L))
		clr	tmr1h	; tmr1h = 0 (clear timer1 holding register(H))
		mov	t1con,#0011_0001b	;内部タイマ、Timer1 使用 1:8

	;; CCP
		mov	ccpr1l,#0010_0011b		;比較、下位
		mov	ccpr1h,#1111_0100b		;比較、上位 (62500-1)
		mov	ccp1con,#1011b		;CCP1 コンペア、一致時にTimer1クリア

	;; 割り込み全体設定
;		bcf	peie	; すべての周辺装置割り込み不可! INTCON.PEIE
;		bsf	peie	; すべての周辺装置割り込み許可! INTCON.PEIE
;		bsf	gie	; グローバル割り込み許可
		mov	intcon,#1100_0000b		;gie,peie 割り込み許可

		clr	rb	; 初期状態 RB=00h

		mov	mynagao,#nagatime	; 長押し時間設定

		clr	pclath	; pclath = 0 Page0
		goto	main

;-----------------------------------------------------------------------------------
;		■PIC16F877のEEPROMからIPアドレスを取得
;-----------------------------------------------------------------------------------
get_ip_address
		bsf	rp0	; rp0 = 1 Bank1
		
		mov	fsr,#this_ip; fsr = &this_ip
		mov	common,#4; common = 4
		
		bsf	rp1	; rp1 = 1
		bcf	rp0	; rp0 = 0 Bank2
		clr	eeadr	; eeadr = 0
get_ip_address0
		bsf	rp1	; rp1 = 1
		bsf	rp0	; rp0 = 1 Bank3
		bcf	eepgd	; eepgd(EECON1.EEPGD) = 0 Access to Data Memory
		bsf	eecon1,0; eecon1.0(EECON1.RD) = 1 読み出し開始
		bcf	rp0	; rp0 = 0 Bank2
		mov	w,eedata; w = eedata(EEDATA)
		inc	eeadr	; eeadr(EEADR)++
		bcf	rp1	; rp1 = 0 Bank0
		
		movwf	indirect; indirect = w
		inc	fsr	; fsr++
		djnz	common,get_ip_address0; if (--common!=0) goto get_ip_address0
		;; get 4 segments xxx.xxx.xxx.xxx

		mov	fsr,#ident; fsr = ident (IP headerの識別子)
		clr	indirect; indirect = 0
		inc	fsr	; fsr++
		clr	indirect; indirect = 0
		ret

;================================================================
; EEPROMからNTP Server IP Addressを読み込む
;================================================================
get_ntp_address
	bsf	rp0		; rp0 = 1 Bank1
	mov	fsr,#ntp_ip	; fsr = &ntp_ip アドレスだから#が必要!
	mov	common,#4	; common = 4

	bsf	rp1		; rp1 = 1
	bcf	rp0		; rp0 = 0 Bank2
	mov	eeadr,#12	; eeadr = 12
get_ntp_address0
	bsf	rp1		; rp1 = 1
	bsf	rp0		; rp0 = 1 Bank3
	bcf	eepgd		; eepgd(EECON1.EEPGD) = 0 Access to Data Memory
	bsf	eecon1,0	; eecon1.0(EECON1.RD) = 1 読み出し開始
	bcf	rp0		; rp0 = 0 Bank2
	mov	w,eedata	; w = eedata(EEDATA)
	inc	eeadr		; eeadr(EEADR)++
	bcf	rp1		; rp1 = 0 Bank0

	movwf	indirect; indirect = w
	inc	fsr	; fsr++
	djnz	common,get_ntp_address0; if (--common!=0) goto get_ntp_address0
	;; get 4 segments xxx.xxx.xxx.xxx

	ret

;-----------------------------------------------------------------------------------
;		■液晶初期化 initialize LCD 
;-----------------------------------------------------------------------------------
init_lcd
		mov	wait_cn,#15		; wait 15ms
		call	wait_ms
		
		clrb	RS			; RS='L'
		mov	d8,#00110000b
		call	write_lcd8
		mov	wait_cn,#5		; wait 4.1ms
		call	wait_ms
		
		mov	d8,#00110000b
		call	write_lcd8
		mov	wait_cn,#100		; wait 100us
		call	wait_us
		
		mov	d8,#00110000b
		call	write_lcd8		; 0 0 0011 (3)
		
		mov	d8,#00100000b
		call	write_lcd8		; 0 0 0010 (4bit)
	;
		mov	d4,#00101000b		; duty,font set9
		call	write_lcd4
		
		mov	d4,#00000001b		; クリアコマンド
		call	write_lcd4
		mov	wait_cn,#2		; クリアが終わるまで待つ
		call	wait_ms
		
		mov	d4,#00000110b		; entry mode set
		call	write_lcd4
		
		mov	d4,#00001110b		; display on,cursor on
		call	write_lcd4
		ret
;-----------------------------------------------------------------------------------
;		■Opening Message
;-----------------------------------------------------------------------------------
opening_mess
	mov	poi&0ffh,#32
	call	putchar_L1
	call	putchar_L2
	mov	wait_cn,#0		; 256ms待つ
	call	wait_ms
	call	wait_ms
	call	wait_ms
	call	wait_ms
	ret

;-----------------------------------------------------------------------------------
;		■液晶１行（１６文字）出力ルーチン　とりあえずPage1 専用
;-----------------------------------------------------------------------------------
; poi に呼び出す位置を入れて、一行目ならputchar_L1,二行目ならputchar_L2 をcall

putchar_L1
	mov	d4,#10000000b
	goto	putchar00
putchar_L2
	mov	d4,#10000000b+64		; 40h (16進数64 = 10進数64)

putchar00
	clrb	RS		; change to command mode
	call	write_lcd4		; カーソルを2行目に移動
	setb	RS		; 以後のコマンドは文字表示 (set bit 1)

	mov	cn&0ffh,#16		; 16文字

putchar0

	mov	pclath,#page1_table>>8
	mov	w,poi
	call	page1_table
	mov	d4,w
	mov	pclath,#write_lcd4>>8
	call	write_lcd4	; 文字表示(RS='H'にしてください)

	inc	poi		; poi = poi + 1
	djnz	cn,putchar0	; 16文字分くり返し
	ret


;-----------------------------------------------------------------------------------
;		■8ビットモード用液晶書き込みルーチン
;-----------------------------------------------------------------------------------
write_lcd8
		mov	tmp,rb	; tmp = rb
		and	tmp,#0fh; tmp &= 0fh (下位4bit取り出し)
		and	d8,#0f0h; d8 &= 0f0h (上位4bit取り出し)
		or	tmp,d8	; tmp |= d8 ()
		mov	rb,tmp			; RBポートへ出力
		
		jmp	$+1	; goto $(program address) + 1 (次の行ってこと？時間稼ぎ？)
		setb	E			; Eピンを'H'
		jmp	$+1
		clrb	E
lcd_skip
		mov	wait_cn,#40
		call	wait_us
		ret

;-----------------------------------------------------------------------------------
;		■4ビットモード用液晶書き込みルーチン
;-----------------------------------------------------------------------------------
write_lcd4
		mov	rb_save,rb

		mov	d8,d4	; d8 = d4
		call	write_lcd8; write LCD d8
		
		mov	d8,d4	; d8 = d4
		swap	d8	; swap d8
		call	write_lcd8; write LCD d8

		mov	rb,rb_save
		ret

;-----------------------------------------------------------------------------------
;		■msオーダーのウェイト
;-----------------------------------------------------------------------------------
wait_ms
wait_ms0
		mov	wait_cn2,#0
wait_ms1	jmp	$+1
		jmp	$+1
		jmp	$+1
		jmp	$+1
		jmp	$+1
		jmp	$+1
		jmp	$+1
		djnz	wait_cn2,wait_ms1
		djnz	wait_cn,wait_ms0
		ret

;-----------------------------------------------------------------------------------
;		■μsオーダーのウェイト
;-----------------------------------------------------------------------------------
wait_us
wait_us0
		jmp	$+1	; $(現在のProgramアドレス)+1 ということは次の行
		djnz	wait_cn,wait_us0; if(--wait_cn!=0) goto wait_us0
		ret





;-----------------------------------------------------------------------------------
;	utility mode
;-----------------------------------------------------------------------------------
		org	0c00h		; Page 1 後半

utility
	bsf	rp1	; rp1 = 1 Bank2
;	bcf	rp0
;	mov	pclath,#wait_ms>>8

	clr	myaddrs&0ffh
	mov	mycursor&0ffh,#0fh

	clrb	RS		; command mode
	mov	d4,#0000_1111b		; カーソル位置でブリンク
	call	write_lcd4		; write LCD
		; ↑初期化ルーチンで設定しませう？

ip_utility
	bsf	rp1	; rp1 = 1 Bank2
;	bcf	rp0
	clr	myaddrs&0ffh
	setb	myaddrs.0

	mov	poi&0ffh,#64
	clr	eeadr	; address = 0 IP address (LSByte)
	goto	utility_do
mask_utility
	bsf	rp1	; rp1 = 1 Bank2
;	bcf	rp0
	clr	myaddrs&0ffh
	setb	myaddrs.1

	mov	poi&0ffh,#80
	mov	eeadr,#4		; address = 0 IP address (LSByte)
	goto	utility_do
gate_utility
	bsf	rp1	; rp1 = 1 Bank2
;	bcf	rp0
	clr	myaddrs&0ffh
	setb	myaddrs.2

	mov	poi&0ffh,#96
	mov	eeadr,#8		; address = 0 IP address (LSByte)
	goto	utility_do
server_utility
	bsf	rp1	; rp1 = 1 Bank2
;	bcf	rp0
	clr	myaddrs&0ffh
	setb	myaddrs.3

	mov	poi&0ffh,#112
	mov	eeadr,#12		; address = 0 IP address (LSByte)
	goto	utility_do

utility_do
	;; Read IP address from EEPROM
		call	get_seg

print_title_addrs
	;; Print title
		call	putchar_L2

	;; Print IP address
print_addrs
		call	print_seg

	clrb	RS		; command mode
	mov	d4,#0001_0000b		; カーソル左シフト*2
	call	write_lcd4		; write LCD
	call	write_lcd4		; write LCD
	setb	RS		; 以後のコマンドは文字表示

	goto	utility0


;Start Utility Loop
utility0
	bcf	rp1	; Bank0
	bcf	rp0

check_swRA0u
	sb	ra.0		; if (ra.0 = 0) then skip
	goto	check_swRA1u
	mov	wait_cn,#chattime		; 30ms待つ
;	mov	pclath,#wait_ms>>8
	call	wait_ms
;	clr	pclath
	snb	ra.0		; if (ra.0 = 1) then skip
	goto	$-1
;	xor	rb,#0001_0000b
	goto	hitRA0u

check_swRA1u
	sb	ra.1		; if (ra.1 = 0) then skip
	goto	check_swRA2u
	mov	wait_cn,#chattime		; 30ms待つ
;	mov	pclath,#wait_ms>>8
	call	wait_ms
;	clr	pclath
	snb	ra.1		; if (ra.1 = 1) then skip
	goto	$-1
;	xor	rb,#0010_0000b
	goto	hitRA1u

check_swRA2u
	sb	ra.2		; if (ra.2 = 0) then skip
	goto	check_swRA3u
	mov	wait_cn,#chattime		; 30ms待つ
;	mov	pclath,#wait_ms>>8
	call	wait_ms
;	clr	pclath
	snb	ra.2		; if (ra.2 = 1) then skip
	goto	$-1
;	xor	rb,#0100_0000b
	goto	hitRA2u

check_swRA3u
	sb	ra.3		; if (ra.3 = 0) then skip
	goto	check_swRA4u
	mov	wait_cn,#chattime		; 30ms待つ
;	mov	pclath,#wait_ms>>8
	call	wait_ms
;	clr	pclath
	snb	ra.3		; if (ra.3 = 1) then skip
	goto	$-1
;	xor	rb,#1000_0000b
	goto	hitRA3u

check_swRA4u		; 無いッス。
	goto	utility0

; end Utility Loop
;-----------------------------------------------------------------------------------
matome
	and	myasc,#0fh
	and	myasb,#0fh
	and	myasa,#0fh

	csae	myasc,#2		; 200 未満はmato
	goto	mato
	cjae	myasb,#6,mato255		; 260 以上はmato255
	csae	myasb,#5		; 250 未満はmato
	goto	mato
	csae	myasa,#5		; 200 以上、255未満はmato
	goto	mato

mato255
	mov	mytemp&0ffh,#255
	ret

mato
	clr	mytemp&0ffh
	cje	myasc,#0,mato1		; if (myasc==0) goto mato1
mato0
	add	mytemp,#100
	djnz	myasc,mato0
mato1
	cje	myasb,#0,mato3
mato2
	add	mytemp,#10
	djnz	myasb,mato2
mato3
	add	mytemp,myasa

	ret
;-----------------------------------------------------------------------------------
hex8byascii
	mov	pclath,#hexdec8>>8
	call	hexdec8
	mov	pclath,#$>>8

	mov	myasc&0ffh,prm3c
	mov	myasb&0ffh,prm3b
	mov	myasa&0ffh,prm3a
	add	myasc,#30h
	add	myasb,#30h
	add	myasa,#30h

	ret
;************************************	[←] ボタン
hitRA1u
	bsf	rp1		; rp1 = 1 Bank2
;	bcf	rp0		; rp0 = 0

	sb	myaddrs.7		; if (bit == 1) skip
	goto	hitRA1um

	; Save & Next
;CALL SAVE SEGMENT
	mov	poi&0ffh,#176
	call	putchar_L2
	mov	wait_cn,#0		; 256ms待つ
	call	store_seg	; call store EEPROM
	call	wait_ms
	call	wait_ms
	call	wait_ms

	snb	myaddrs.0
	goto	mask_utility
	snb	myaddrs.1
	goto	gate_utility
	snb	myaddrs.2
	goto	server_utility
	snb	myaddrs.3
	goto	utility_out

hitRA1um
	djnz	mycursor,hitRA1u0
	mov	mycursor&0ffh,#0fh	; 0のとき15 へ

	call	matome
	mov	seg0&0ffh,mytemp
	goto	print_addrs

hitRA1u0
	clrb	RS		; command mode
	mov	d4,#0001_0000b		; カーソル左シフト
	call	write_lcd4		; write LCD

	cje	mycursor,#12,hitRA1u1a		; 12,8,4 のときjump
	cje	mycursor,#8,hitRA1u1b
	cje	mycursor,#4,hitRA1u1c
	goto	hitRA1u_out

hitRA1u1a
	call	matome
	mov	seg3&0ffh,mytemp
	mov	prm1a&0ffh,seg2
	call	hex8byascii
	goto	hitRA1u1
hitRA1u1b
	call	matome
	mov	seg2&0ffh,mytemp
	mov	prm1a&0ffh,seg1
	call	hex8byascii
	goto	hitRA1u1
hitRA1u1c
	call	matome
	mov	seg1&0ffh,mytemp
	mov	prm1a&0ffh,seg0
	call	hex8byascii
	;goto	hitRA1u1
	
hitRA1u1
	call	write_lcd4		; write LCD
	dec	mycursor

hitRA1u_out
	goto	utility0

;************************************	[→] ボタン
hitRA2u
	bsf	rp1		; rp1 = 1 Bank2
;	bcf	rp0		; rp0 = 0

	sb	myaddrs.7		; if (bit == 1) skip
	goto	hitRA2um

	; Cancel & Next
	mov	poi&0ffh,#192
	call	putchar_L2
	mov	wait_cn,#0		; 256ms待つ
	call	wait_ms
	call	wait_ms

	snb	myaddrs.0
	goto	mask_utility
	snb	myaddrs.1
	goto	gate_utility
	snb	myaddrs.2
	goto	server_utility
	snb	myaddrs.3
	goto	utility_out

hitRA2um
	cse	mycursor,#0fh		; if (mycursor==0) skip	|右端からの移動は次address
	goto	hitRA2u0

	call	matome
	mov	seg3&0ffh,mytemp

	setb	myaddrs.7
	mov	poi&0ffh,#160
	goto	print_title_addrs

hitRA2u0
	clrb	RS		; command mode
	mov	d4,#0001_0100b		; カーソル右シフト
	call	write_lcd4		; write LCD

	inc	mycursor
	cje	mycursor,#12,hitRA2u1a		; 12,8,4 のときjump
	cje	mycursor,#8,hitRA2u1b
	cje	mycursor,#4,hitRA2u1c
	goto	hitRA2u_out

hitRA2u1a
	call	matome
	mov	seg2&0ffh,mytemp
	mov	prm1a&0ffh,seg3
	call	hex8byascii
	goto	hitRA2u1
hitRA2u1b
	call	matome
	mov	seg1&0ffh,mytemp
	mov	prm1a&0ffh,seg2
	call	hex8byascii
	goto	hitRA2u1
hitRA2u1c
	call	matome
	mov	seg0&0ffh,mytemp
	mov	prm1a&0ffh,seg1
	call	hex8byascii
	;goto	hitRA2u1
	
hitRA2u1
	call	write_lcd4		; write LCD
	inc	mycursor

hitRA2u_out
	goto	utility0

;************************************	[↑] ボタン
hitRA3u
	bsf	rp1		; rp1 = 1 Bank2
;	bcf	rp0		; rp0 = 0

	sb	myaddrs.7		; if (bit == 1) skip
	goto	hitRA3um

	; Cancel
	clrb	myaddrs.7

	mov	poi&0ffh,#64
	jb	myaddrs.0,print_title_addrs
	mov	poi&0ffh,#80
	jb	myaddrs.1,print_title_addrs
	mov	poi&0ffh,#96
	jb	myaddrs.2,print_title_addrs
	mov	poi&0ffh,#112
	;jb	myaddrs.3,print_title_addrs
	;goto	utility0		; ←無いはず
	goto	print_title_addrs

hitRA3um
	snb	mycursor.1		; if (bit==0) skip
	goto	hitRA3u0
	;case top

	inc	myasc
	csa	myasc,#32h		; if ( myasc > (2 by ascii) ) skip
	goto	hitRA3u_o

	mov	myasc&0ffh,#30h		; myasc = 0 by ascii
hitRA3u_o
	mov	d4,myasc
	goto	hitRA3u_out

hitRA3u0
	snb	mycursor.0		; if (bit==0) skip
	goto	hitRA3u1
	;case middle

	inc	myasb
	csa	myasb,#39h		; if ( myasb > (9 by ascii) ) skip
	goto	hitRA3u0_o

	mov	myasb&0ffh,#30h		; myasb = 0 by ascii
hitRA3u0_o
	mov	d4,myasb
	goto	hitRA3u_out

hitRA3u1
	;case bottom

	inc	myasa
	csa	myasa,#39h		; if ( myasa > (9 by ascii) ) skip
	goto	hitRA3u1_o

	mov	myasa&0ffh,#30h		; myasa = 0 by ascii
hitRA3u1_o
	mov	d4,myasa
	;goto	hitRA3u_out

hitRA3u_out
	setb	RS		; 文字表示
	call	write_lcd4		; write LCD
	clrb	RS		; command mode
	mov	d4,#0001_0000b		; カーソル左シフト
	call	write_lcd4		; write LCD

	goto	utility0
;************************************
hitRA0u
;-----------------------------------------------------------------------------------
utility_out
utility_quit
	bsf	rp1		; rp1 = 1 Bank2
;	bcf	rp0		; rp0 = 0

	bcf	myhour.7	; myhour.7 = 0 quit stealth-mode
	bsf	myhour.6	; myhour.6 = 1 display date on
	bcf	mystate.7	; mystate.7 = 0 Adjust Status Reset
	bsf	mystate.6	; mystate.6 = 1 Request ARP

	bcf	rp1		; rp1 = 0 Bank0
	bcf	gie		; Global Interrupt Enable: disable gie = 0
	bcf	irp		; irp = 0 Bank0,1	必須!status
	mov	pclath,#start0>>8
	goto	start0

;-----------------------------------------------------------------------------
; get 4 segments -> seg , print the IP on LCD
; Get 4 segments from EEPROM
get_seg
	bsf	rp1	; rp1 = 1
	bcf	rp0	; rp0 = 0 Bank2
	bsf	irp		; irp = 1
	mov	fsr,#seg & 0ffh -4
	mov	common,#4
get_seg0	

	bsf	rp1	; rp1 = 1
	bsf	rp0	; rp0 = 1 Bank3
	bcf	eepgd	; eepgd(EECON1.EEPGD) = 0 Access to Data Memory
	bsf	eecon1,0; eecon1.0(EECON1.RD) = 1 読み出し開始
	bcf	rp0	; rp0 = 0 Bank2
	mov	w,eedata; w = eedata(EEDATA)
	inc	eeadr	; eeadr(EEADR)++
;	bcf	rp1	; rp1 = 0 Bank0
	movwf	indirect; indirect = w

	inc	fsr	; fsr++
	djnz	common,get_seg0; if (--common!=0) goto get_seg

	ret
	
;; Print 4 segments
print_seg
	clrb	RS		; command mode
	mov	d4,#1000_0000b		; カーソルを2行目に移動
	call	write_lcd4		; write LCD
	setb	RS		; 以後のコマンドは文字表示

	mov	d4,#' '		; space 出力
	call	write_lcd4

	mov	common,#4
print_seg0
	bsf	irp		; irp = 1 Bank2,3
	bsf	rp1		; rp1 = 1
	bcf	rp0		; rp0 = 0 Bank2	

	mov	fsr,#seg &0ffh
;	add	fsr,#4
	sub	fsr,common
	mov	prm1a & 0ffh,indirect
	mov	pclath,#hexdec8>>8
	call	hexdec8
	mov	pclath,#$>>8

	mov	myasc&0ffh,prm3c
	mov	myasb&0ffh,prm3b
	mov	myasa&0ffh,prm3a
	add	myasc,#30h		; bin → ascii
	add	myasb,#30h		; bin → ascii
	add	myasa,#30h		; bin → ascii

	mov	d4,myasc
	call	write_lcd4
	mov	d4,myasb
	call	write_lcd4
	mov	d4,myasa
	call	write_lcd4
	mov	d4,#'.'
	call	write_lcd4

	djnz	common,print_seg0; 	if (--common!=0) goto print_seg

	ret
;-----------------------------------------------------------------------------------
; Store 4 segment
store_seg
	bsf	rp1	; rp1 = 1
	bcf	rp0	; rp0 = 0 Bank2
	sub	eeadr,#4	; EEADR -= 4
	bsf	irp		; irp = 1
	mov	fsr,#seg0 & 0ffh
	mov	common,#4
store_seg0
	mov	eedata,indirect	; EEDATA = seg0

	bsf	rp0	; rp0 = 1 Bank3
	bcf	eepgd	; EECNO1.EEPGD = 0 access Data RAM
	bsf	wren	; Enable to write EEPROM cycle
	
	bcf	gie	; Global Interrupt Enable gie = 0
	mov	eecon2,#55h; 
	mov	eecon2,#0aah
	bsf	wr	; wr = 1 Set WR bit to begin write
	
	btfsc	wr	; if (wr == 1) skip
	goto	$-1	; goto ↑
	
	bcf	wren	; wren = 0
	bsf	gie		; gie = 1

	bsf	rp1	; rp1 = 1
	bcf	rp0	; rp0 = 0 Bank2
	inc	eeadr		; eeadr++
	inc	fsr		; fsr++
	djnz	common,store_seg0; if (--common!=0) goto get_seg

;  	bcf	rp1	; rp1 = 0
;  	bcf	rp0	; rp0 = 0 Bank0
	ret


;||| 難民受入先。from main ルーチン

main_check_sw

check_swRA0
	sb	ra.0		; if (ra.0 = 0) then skip
	goto	check_swRA1
	mov	wait_cn,#chattime		; 30ms待つ
	mov	pclath,#wait_ms>>8
	call	wait_ms
;	clr	pclath
	mov	pclath,#$>>8
	snb	ra.0		; if (ra.0 = 1) then skip
	goto	$-1
	call	hitRA0
	
	bsf	rp1		; Bank2
	setb	mystate.6
	bcf	rp1		; Bank1

;	xor	rb,#0001_0000b

check_swRA1
	sb	ra.1		; if (ra.1 = 0) then skip
	goto	check_swRA2
	mov	wait_cn,#chattime		; 30ms待つ
	mov	pclath,#wait_ms>>8
	call	wait_ms
;	clr	pclath
	mov	pclath,#$>>8

	snb	ra.1		; if (ra.1 = 1) then skip
	goto	$-1
	call	hitRA1
;	xor	rb,#0010_0000b

	bsf	rp1		; rp1 = 1
	xor	myhour,#0010_0000b
	bcf	rp1		; rp1 = 1
	

check_swRA2	goto	check_swRA3		; RA2 は長押し対応のため後回し。
	sb	ra.2		; if (ra.2 = 0) then skip
	goto	check_swRA3
	mov	wait_cn,#chattime		; 30ms待つ
	mov	pclath,#wait_ms>>8
	call	wait_ms
;	clr	pclath
	mov	pclath,#$>>8

	snb	ra.2		; if (ra.2 = 1) then skip
	goto	$-1
	call	hitRA2
;	xor	rb,#0100_0000b

check_swRA3
	sb	ra.3		; if (ra.3 = 0) then skip
	goto	check_swRA4
	mov	wait_cn,#chattime		; 30ms待つ
	mov	pclath,#wait_ms>>8
	call	wait_ms
;	clr	pclath
	mov	pclath,#$>>8

	snb	ra.3		; if (ra.3 = 1) then skip
	goto	$-1
	call	hitRA3
;	xor	rb,#1000_0000b
	bsf	rp1		; rp1 = 1
	xor	myhour,#1000_0000b
	bcf	rp1		; rp1 = 1


check_swRA4		; 無いッス。

;*********************************************
check_swRA22
	sb	ra.2		; if (ra.0 = 0) then skip
	goto	check_outRA22

chk_cntRA22
	mov	wait_cn,#chattime		; 256ms待つ
	mov	pclath,#wait_ms>>8
	call	wait_ms
;	clr	pclath
	mov	pclath,#$>>8

	djnz	mynagao,chk_offRA22	; if (--mynagao != 0) jump　長押し判定
	mov	mynagao,#nagatime		; mynagao を元に戻して長押し処理。
;|| 長押し処理。

; 押しつづけている時の処理。

	bsf	rp1		; rp1 = 1
	bcf	rp0		; rp0 = 0 Bank2 要らないかも 元からだから
	bsf	myhour.7	; myhour.7 = 1 stealth-mode

	mov	poi&0ffh,#0
	mov	pclath,#putchar_L1>>8
	call	putchar_L1
	call	putchar_L2

	bcf	rp1		; Bank0
;	clr	pclath
	mov	pclath,#$>>8
	snb	ra.2		; if (ra.0 = 1) then skip	ボタンが離されるまで待つ。
	goto	$-1
; 離された時の処理。
	mov	pclath,#utility>>8
	goto	utility

chk_offRA22
	snb	ra.2		; if (ra.0 = 1) then skip
	goto	chk_cntRA22
	mov	mynagao,#nagatime
;|| 短押し処理。
	call	hitRA2
;	xor	rb,#0100_0000b

check_outRA22
;*********************************************

	mov	pclath,#main0_t2>>8
	goto	main0_t2
	; 故郷に戻る。

;*********↓ スイッチモニター ↓(削除予定)*******************
hitRA0
	clrb	RS		; change to command mode
	mov	d4,#10000000b+64		; 40h (16進数64 = 10進数64)
	mov	pclath,#write_lcd4>>8
	call	write_lcd4		; カーソルを2行目に移動
	setb	RS		; 以後のコマンドは文字表示 (set bit 1)

	mov	d4,#'H'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'i'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'t'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'0'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#' '
	call	write_lcd4	; 文字表示(RS='H'にしてください)
;	clr	pclath
	mov	pclath,#$>>8
	ret
hitRA1
	clrb	RS		; change to command mode
	mov	d4,#10000000b+64		; 40h (16進数64 = 10進数64)
	mov	pclath,#write_lcd4>>8
	call	write_lcd4		; カーソルを2行目に移動
	setb	RS		; 以後のコマンドは文字表示 (set bit 1)

	mov	d4,#'H'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'i'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'t'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'1'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#' '
	call	write_lcd4	; 文字表示(RS='H'にしてください)
;	clr	pclath
	mov	pclath,#$>>8
	ret
hitRA2
	clrb	RS		; change to command mode
	mov	d4,#10000000b+64		; 40h (16進数64 = 10進数64)
	mov	pclath,#write_lcd4>>8
	call	write_lcd4		; カーソルを2行目に移動
	setb	RS		; 以後のコマンドは文字表示 (set bit 1)

	mov	d4,#'H'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'i'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'t'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'2'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#' '
	call	write_lcd4	; 文字表示(RS='H'にしてください)
;	clr	pclath
	mov	pclath,#$>>8
	ret
hitRA3
	clrb	RS		; change to command mode
	mov	d4,#10000000b+64		; 40h (16進数64 = 10進数64)
	mov	pclath,#write_lcd4>>8
	call	write_lcd4		; カーソルを2行目に移動
	setb	RS		; 以後のコマンドは文字表示 (set bit 1)

	mov	d4,#'S'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'t'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'e'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'a'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'l'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'t'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'h'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'-'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'i'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#'n'
	call	write_lcd4	; 文字表示(RS='H'にしてください)
	mov	d4,#' '
	call	write_lcd4	; 文字表示(RS='H'にしてください)
;	clr	pclath
	mov	pclath,#$>>8
	ret
;*********↑ スイッチモニター ↑*******************







;||-----------------------------------------------------------------------------
;|| MESSAGE page2
;||
		org	1000h

page2_table
;utility_table
	jmp	pc+w
;0-1-2-3-4-5-6-7-8-9-10-11-12-13-14-15
	retw	1,00100b,01000b,01000b,00001b,00001b,00001b,00001b
	retw	2,01110b,01111b,01111b,00001b,00001b,00001b,00001b
	retw	3,10101b,01010b,01110b,00001b,00001b,00001b,00001b
	retw	4,00100b,11110b,11110b,00001b,00001b,00001b,00001b
	retw	5,00100b,00010b,00010b,10001b,00001b,00001b,00001b
	retw	6,00100b,00000b,00010b,00001b,10001b,00001b,00001b
	retw	7,00100b,00000b,00000b,00001b,00001b,10001b,00001b
	retw	8,00000b,00000b,00000b,00001b,00001b,00001b,10001b

;64-65-66-67-68-69-70-71-72-73-74-75-76-77-78-79
	retw	1,00000b,00000b,00000b,00000b,00000b,00000b,10000b
	retw	2,00000b,00001b,00001b,10001b,10001b,10001b,01000b
	retw	3,00100b,00000b,00000b,00000b,00000b,00000b,11000b
	retw	4,01110b,00000b,00100b,00000b,00100b,10001b,00100b
	retw	5,00100b,00000b,00000b,00000b,00000b,00000b,10100b
	retw	6,00000b,10000b,10000b,10001b,10001b,10001b,01100b
	retw	7,00000b,00000b,00000b,00000b,00000b,00000b,11100b
	retw	8,11111b,11111b,11111b,11111b,11111b,11111b,00010b

;128-129-130-131-132-133-134-135-136-137-138-139-140-141-142-143
	retw	1,11111b,11111b,11111b,10001b,00001b,11111b,10000b
	retw	2,00000b,00100b,00000b,11011b,00011b,10001b,01000b
	retw	3,00100b,00100b,01010b,11011b,00111b,01010b,11000b
	retw	4,01110b,01110b,00100b,11111b,00111b,00100b,00100b
	retw	5,00100b,00100b,01010b,11011b,01111b,01010b,10100b
	retw	6,00000b,00100b,00000b,11011b,01111b,10001b,01100b
	retw	7,00000b,00100b,00000b,10001b,11111b,11111b,11100b
	retw	8,11111b,11111b,11111b,00000b,00000b,00000b,00010b

		; [208-223]
		; [224-239]
		; [240-255] 使用不可

;-----------------------------------------------------------------------------------
;		■カスタムキャラクタ／８文字一括ロード
;-----------------------------------------------------------------------------------
;; Custom Character Load
;; poi に読み込み開始位置指定。８文字ずつの指定のみ可能。

ccl
	bsf	rp1	; rp1 = 1 Bank2

	mov	mycc&0ffh,#0
	mov	d4,#01_000_000b
	mov	pclath,#write_lcd4>>8

	clrb	RS		; change to command mode
	call	write_lcd4		; カーソルを2行目に移動
	setb	RS		; 以後のコマンドは文字表示 (set bit 1)

ccl00
	mov	cn&0ffh,#8		; 16文字
ccl0

	mov	pclath,#page2_table>>8
	mov	w,poi
	call	page2_table
	mov	d4,w
	mov	pclath,#write_lcd4>>8
	call	write_lcd4	; 文字表示(RS='H'にしてください)

	add	poi,#8

	mov	pclath,#$>>8
	djnz	cn,ccl0	; 16文字分くり返し

	sub	poi,#63
	inc	mycc
	cjb	mycc,#8,ccl00	; 16文字分くり返し

	bcf	rp1	; rp1 = 1 Bank0
	ret

;-----------------------------------------------------------------------------------
;		ARP Request
;-----------------------------------------------------------------------------------
		org	1200h	; Page 2
		bcf	irp	; irp = 0
;
;		ARP要求を送信
;
arp_request
		clr	pclath				; Important!
		
		clr	remote_adr[0]; remote_adr[0] = 0
		mov	remote_adr[1],#PAGE_BEGIN; remote_adr[1] = PAGE_BEGIN
		mov	remote_len[0],#PACKET_SIZE+ARP_SIZE; remote_len[0] = PACKET_SIZE+ARP_SIZE
		clr	remote_len[1]; remote_len[1] = 0
		call	remote_write

		mov	rc,#10h		; Remote DMA port 宛て先："ff-ff-ff-ff-ff-ff"に送信
		movlw	0ffh
		call	assert_wr
		movlw	0ffh
		call	assert_wr
		movlw	0ffh
		call	assert_wr
		movlw	0ffh
		call	assert_wr
		movlw	0ffh
		call	assert_wr
		movlw	0ffh
		call	assert_wr

		bcf	irp
		mov	fsr,#mymac	; 送信元：自分のMACアドレスを設定
		movlw	6		; w = 6
		call	transmit_nbytes	; w(6) byte書き込み
		
		movlw	COM_PROTO	; 08 Etherframe type
		call	assert_wr
		movlw	ARP_PROTO	; ARP
		call	assert_wr
		
 		mov	pclath,#$>>8
		call	arp2		; ARP header write
  		clr	pclath		; Important! assert_wr0が使う分けね
		
		clr	rc	; CR 
		movlw	00100010b; abort/start
		call	assert_wr0
		
		mov	rc,#4h	; TPSR (Transmit Page Start Register)
		movlw	PAGE_BEGIN	; transmit page is start page 
		call	assert_wr0
		
		mov	rc,#5	; TBCR0 (L)
		movlw	60		; minimum packet = 60
		call	assert_wr0
		
		mov	rc,#6	; TBCR0 (H)
		clrw			; adr high = 0
		call	assert_wr0

		call	transmit	; ARP応答を送信する

	;; debug bug
;  		mov	pclath,#main9>>8
;  		goto	main9		
		ret

;-----------------------------------------------------------------------------------
;		■ARPヘッダの作成 reply
arp1
		clr	pclath	; pclath = 0
		clrw		; w = 0
		call	assert_wr; write RTL
		movlw	01h			; Ethernetは1固定
		call	assert_wr

		movlw	COM_PROTO
		call	assert_wr
		movlw	IP_PROTO		; IPでよい
		call	assert_wr
		
		movlw	06h		; Ethernetアドレスのバイト数=6
		call	assert_wr
		movlw	04h		; IPアドレスのバイト数=4
		call	assert_wr

		movlw	00h
		call	assert_wr
		movlw	02h		; ARP応答(=2)
		call	assert_wr
		
		mov	fsr,#mymac
		movlw	6
		call	transmit_nbytes		; 自分のMACを送信
		call	transmit_this_ip	; 自分のIPを送信
		
		mov	fsr,#arp_src_mac	; 相手のMACを送信
		movlw	10			; 相手のIPを送信
		call	transmit_nbytes
		ret

;-----------------------------------------------------------------------------------
;		■ARPヘッダの作成 request
arp2
		clr	pclath		; pclath = 0
		
		clrw			; w = 0 Hard type
		call	assert_wr	; write RTL
		movlw	01h		; Ethernetは1固定
		call	assert_wr	; write RTL

		movlw	COM_PROTO	; protocol type
		call	assert_wr	; write RTL
		movlw	IP_PROTO	; IPでよい
		call	assert_wr	; write RTL
		
		movlw	06h		; Ethernetアドレスのバイト数=6 (MAC Address 6 Bytes)
		call	assert_wr	; write RTL
		movlw	04h		; IPアドレスのバイト数=4 (IP Address 4 Bytes)
		call	assert_wr	; write RTL

		movlw	00h		; operation
		call	assert_wr	; write RTL
		movlw	01h		; ARP要求(=1)
		call	assert_wr	; write RTL
		
		mov	fsr,#mymac	; fsr = mymac
		movlw	6		; w = 6
		call	transmit_nbytes	; 自分のMACを送信
		call	transmit_this_ip; 自分のIPを送信
		
		movlw	00h		; destination MAC Address
		call	assert_wr	; write RTL
		movlw	00h
		call	assert_wr	; write RTL
		movlw	00h
		call	assert_wr	; write RTL
		movlw	00h
		call	assert_wr	; write RTL
		movlw	00h
		call	assert_wr	; write RTL
		movlw	00h
		call	assert_wr	; write RTL
		
		bsf	irp		; irp = 1
		mov	fsr,#on_ip & 0ffh; fsr = on_ip(destination IP address) & 0ffh
check_netid
		mov	pclath,#$>>8
		bsf	rp1		; rp1 = 1
		bcf	rp0		; rp0 = 0 Bank2
		mov	eeadr,#4	; address=16 netmask
		bcf	rp1		; rp1 = 0 Bank0
		
		call	getnetmask	; get netmask 8bit return wk[0] 上位8bit
		bsf	rp0		; rp0 = 1
		mov	wk[1],this_ip[0]; wk[1] = this_ip[0](IP Addressの上位8bit)
		and	wk[1],wk[0]	; wk[1] = wk[1](this_ip) & wk[0](netmask)
		and	wk[0],indirect	; wk[0] = wk[0](netmask) & indirect(on_ip[0]:dest.)
		inc	fsr		; fsr++
		cjne	wk[0],wk[1],gateway; if (wk[0]!=wk[1]) goto gateway

		call	getnetmask	; get netmask 8bit return wk[0] 上位9-16bit
		bsf	rp0
		mov	wk[1],this_ip[1]
		and	wk[1],wk[0]		; [1] = this
		and	wk[0],indirect		;on_ip[0]		; [0] = host
		inc	fsr
		cjne	wk[0],wk[1],gateway

		call	getnetmask	; get netmask 8bit return wk[0] 上位17-24bit
		bsf	rp0
		mov	wk[1],this_ip[2]
		and	wk[1],wk[0]		; [1] = this
		and	wk[0],indirect		;on_ip[0]		; [0] = host
		inc	fsr
		cjne	wk[0],wk[1],gateway

		call	getnetmask	; get netmask 8bit return wk[0] 下位8bit
		bsf	rp0
		mov	wk[1],this_ip[3]
		and	wk[1],wk[0]		; [1] = this
		and	wk[0],indirect		;on_ip[0]		; [0] = host
		cjne	wk[0],wk[1],gateway

direct				; 同じsub net内にon_ip(destination IP address)が存在
		bcf	rp0	; rp0 = 0
		bcf	rp1	; rp1 = 0 Bank0
		clr	pclath	; pclath = 0
		mov	fsr,#on_ip & 0ffh; fsr = on_ip(destination) & 0ffh
		movlw	4			; 相手のIPを送信
		call	transmit_nbytes; w(4) bytes transmit
		
		bcf	irp	; irp = 0
		mov	pclath,#$>>8; pclath = $ >> 8;
		ret

gateway		; Gatewayへ
		bsf	rp1		; rp1 = 1
		bcf	rp0		; rp0 = 0 Bank2
		mov	eeadr,#8	; address=16 Gateway IP address 上位8bit
		bsf	rp0		; rp0 = 0
		bcf	rp1		; rp1 = 0 Bank0

		mov	pclath,#$>>8	; pclath = $ >> 8;
		call	getnetmask	; wk[0] = gateway 上位8bit 
		;;  	"getnetmask"とかいいながら、gatewayじゃん
		clr	pclath		; pclath = 0
		mov	w,wk[0]		; w = wk[0]
		call	assert_wr	; write RTL

		mov	pclath,#$>>8
		call	getnetmask	; wk[0] = gateway 次の8bit 
		clr	pclath
		mov	w,wk[0]
		call	assert_wr

		mov	pclath,#$>>8
		call	getnetmask	; wk[0] = gateway 次の8bit 
		clr	pclath
		mov	w,wk[0]
		call	assert_wr

		mov	pclath,#$>>8
		call	getnetmask	; wk[0] = gateway 下位8bit 
		clr	pclath
		mov	w,wk[0]
		call	assert_wr
		
		bcf	irp	; irp = 0
		mov	pclath,#$>>8; pclath = $ >> 8
		ret

getnetmask
		bsf	rp1	; rp1 = 1
		bsf	rp0	; rp0 = 1 Bank3
		bcf	eepgd	; eepgd = 0
		bsf	eecon1,0; eecon1.0(EECON1.RD) = 1
		bcf	rp0	; rp0 = 0 Bank2
		mov	wk[0],eedata; wk[0] = eedata
		inc	eeadr	; eeadr++
		bcf	rp1	; rp1 = 0 Bank0
		ret


;-----------------------------------------------------------------------------------
;	■Receive NTP packet, and save 32bit variable of the transmit timestamp
;-----------------------------------------------------------------------------------
udp_ntp
	;; debug
  		mov	d4,#'n'
  		mov	pclath,#write_lcd4>>8
  		call	write_lcd4; write LCD
  		mov	pclath,#$>>8

    		mov	remote_len[1], udp_length[0]; remote_len[1] = udp_length[0]
    		mov	remote_len[0], udp_length[1]; remote_len[0] = udp_length[1]
      		sub	remote_len[0],#8	; remote_len[0] -= 8 (UDP header分を減算)
      		btfss	c			; if (c==1) skip (桁上がり計算)
      		dec	remote_len[1]		; remote_len[1]--

		mov	tcn1,#40		; jump to transmit time stamp of NTP packet 40
ntp_timestamp	mov	pclath,#get_dgram>>8	; pclath = get_dgram>>8
    		call	get_dgram		; 1 byte get
    		mov	pclath,#$>>8		; pclath = $>>8
  		btfsc	c			; if (c==1) skip
  		goto	udp_ntp9
		djnz	tcn1,ntp_timestamp	; if (--tcn1!=0) goto ntp_timestamp
		clr	tcn1
	
	;; get transmit time stamp
		mov	pclath,#get_dgram>>8	; pclath = get_dgram>>8
    		call	get_dgram		; 1 byte get
    		mov	pclath,#$>>8		; pclath = $>>8
  		btfsc	c			; if (c==1) skip
  		goto	udp_ntp9
		bsf	rp1	; Bank2
		mov	sb1d & 0ffh,data
		bcf	rp1	; Bank0
;    		mov	div1d,data
		
		mov	pclath,#get_dgram>>8	; pclath = get_dgram>>8
    		call	get_dgram		; 1 byte get
    		mov	pclath,#$>>8		; pclath = $>>8
  		btfsc	c			; if (c==1) skip
  		goto	udp_ntp9
		bsf	rp1	; Bank2
		mov	sb1c & 0ffh,data
		bcf	rp1	; Bank0
;    		mov	div1c,data
	
		mov	pclath,#get_dgram>>8	; pclath = get_dgram>>8
    		call	get_dgram		; 1 byte get
    		mov	pclath,#$>>8		; pclath = $>>8
  		btfsc	c			; if (c==1) skip
  		goto	udp_ntp9
  		bsf	rp1	; Bank2 
  		mov	sb1b & 0ffh,data
  		bcf	rp1	; Bank0
;    		mov	div1b,data

		mov	pclath,#get_dgram>>8	; pclath = get_dgram>>8
    		call	get_dgram		; 1 byte get
    		mov	pclath,#$>>8		; pclath = $>>8
  		btfsc	c			; if (c==1) skip
  		goto	udp_ntp9
  		bsf	rp1	; Bank2	
  		mov	sb1a & 0ffh,data
  		bcf	rp1	; Bank0
;    		mov	div1a,data

		mov	pclath,#get_dgram>>8	; pclath = get_dgram>>8
    		call	get_dgram		; 1 byte get
    		mov	pclath,#$>>8		; pclath = $>>8
  		btfsc	c			; if (c==1) skip
  		goto	udp_ntp9
  		bsf	rp1	; Bank2	
  		mov	sb1dd & 0ffh,data
		mov	myadjt&0ffh,#adj_after
		setb	mystate.7

  		bcf	rp1	; Bank0
;    		mov	div1dd,data

    		clr	pclath
    		goto	calendar

	;; display transmit time stamp
;  		mov	d4,div1d
;  		mov	pclath,#write_lcd4>>8
;  		call	write_lcd4; write LCD
;  		mov	pclath,#$>>8
	
;  		mov	d4,div1c
;  		mov	pclath,#write_lcd4>>8
;  		call	write_lcd4; write LCD
;  		mov	pclath,#$>>8
	
;  		mov	d4,div1b
;  		mov	pclath,#write_lcd4>>8
;  		call	write_lcd4; write LCD
;  		mov	pclath,#$>>8
	
;  		mov	d4,div1a
;  		mov	pclath,#write_lcd4>>8
;  		call	write_lcd4; write LCD
;  		mov	pclath,#$>>8

;  		mov	d4,div1dd
;  		mov	pclath,#write_lcd4>>8
;  		call	write_lcd4; write LCD
;  		mov	pclath,#$>>8
	
	
udp_ntp9
		clr	pclath
		goto	main9

		end
