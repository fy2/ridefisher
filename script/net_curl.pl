use strict;

 use Net::Curl::Easy qw(:constants);

 my $file = '';
 my $easy = Net::Curl::Easy->new();
 my $url = 'https://cnn.com';
 $easy->setopt( CURLOPT_URL, $url );

 $easy->setopt( CURLOPT_COOKIEJAR,  '/tmp/cookies.txt');
 $easy->setopt( CURLOPT_COOKIEFILE, '/tmp/cookies.txt' );
 $easy->setopt( CURLOPT_FOLLOWLOCATION, 1);
 $easy->setopt( CURLOPT_SSL_VERIFYHOST, 0);
 $easy->setopt( CURLOPT_FILE, \$file);
 $easy->setopt( CURLOPT_TIMEOUT, 30);
 $easy->setopt( CURLOPT_USERAGENT, "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_8) AppleWebKit/534.30 (KHTML, like Gecko) Chrome/12.0.742.112 Safari/534.30" );

# curl
#      --location
#      --cookie cookies.txt
#      --cookie-jar cookies.txt
#      --insecure
#      --user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_8) AppleWebKit/534.30 (KHTML, like Gecko) Chrome/12.0.742.112 Safari/534.30"
#      "https://cnn.com"


$easy->perform();
print $file;
