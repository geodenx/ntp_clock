################################################################
# NTP client
#
#                  15 July, 2001
#                  OKAZAKI Atsuya (atsuya@mac.com)
#
#  reference: RFC2030 (SNTP)
#             Oreily "Perl Cookbook" section 17.4 (UDP client)
#             http://www.nakka.com/lib/inet/sntpcex.html
#
################################################################
use strict;
use Socket;

my $i = 0; # counter
my @buf;
################ socket process ################
my ($host, $protocol, $him, $src, $port, $ipaddr, $res, $delta, $msg);

#### prepare socket

#$host = 'ntp1.wakwak.com';
#$host = 'ntp2.wakwak.com';
#$host = 'cesium.mtk.nao.ac.jp';
#$host = 'ntp1.jst.mfeed.ad.jp';
#$host = 'ntp2.jst.mfeed.ad.jp';
#$host = 'ntp3.jst.mfeed.ad.jp';
$host = 'time.apple.com';

$protocol = "ntp";

socket(MsgBox, PF_INET, SOCK_DGRAM, getprotobyname("udp"))
    or die "socket: $!";
$him = sockaddr_in(scalar(getservbyname($protocol, "udp")),
		   inet_aton($host));

#### send message to NTP server
$msg = pack("N12", 0x0B000000);

my @msg_print =  unpack("B32 B32 B32 B32 B64 B64 B64 B64", $msg);
print "packet to sent:\n".
    "--- B32 B32 B32 B32 B64 B64 B64 B64 ---\n".
    "   01234567890123456789012345678901\n";
foreach (@msg_print) {
    print "$i: $_\n";
    ++$i;
}

defined(send(MsgBox, $msg, 0, $him))
    or die "send : $!";
#### receive packet
defined($src = recv(MsgBox, $res, 1024, 0))
    or die "recv : $!";
($port, $ipaddr) = sockaddr_in($src);
$host = gethostbyaddr($ipaddr, AF_INET);
print "Host: $host, Port: $port\n";

################ parse SNTP packet from NTP server ################
# reference: RFC2030
my $SECS_of_70_YEARS = 2_208_988_800; #70年間の秒数

print "\nreturned packet:\n".
    "--- B32 B32 B32 B32 B64 B64 B64 B64 B*---\n";
print "   01234567890123456789012345678901\n";
@buf = unpack("B32 B32 B32 B32 B64 B64 B64 B64 B*", $res);
$i = 0; #counter
foreach (@buf) {
    print "$i: $_\n";
    ++$i;
}

print "--- N* ---\n";
@buf = unpack("N*" , $res);
$i = 0; #counter
foreach (@buf) {
    print "$i: $_\n";
    ++$i;
}

my $TransmitTime = $buf[10];
print "                               \$TransmitTime: $TransmitTime\n";
my $ntp = $TransmitTime - $SECS_of_70_YEARS;

print " NTP time:  ". scalar(localtime($ntp)) . "    \$ntp:  ". $ntp . "\n";
print "localtime:  ". scalar(localtime()) . "  time():  ". time() . "\n";
