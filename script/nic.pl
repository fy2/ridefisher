use Net::IMAP::Client;
use Config::IniFiles;
use strict;
use warnings;
use Data::Dumper;

my $cfg = Config::IniFiles->new( -file => "/home/feyruz/sandbox/RideAway-AutoResponder/config/config.live.ini" );

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);



my $logger = Log::Log4perl::get_logger();

my $imap = Net::IMAP::Client->new(

    server => $cfg->val( 'email', 'server' ),
    user   => $cfg->val( 'email', 'username' ),
    pass   => $cfg->val( 'email', 'password' ),
    ssl    => 1,                              # (use SSL? default no)
    ssl_verify_peer => 0,                     # (use ca to verify server, default yes)
  #  ssl_ca_file => '/etc/ssl/certs/certa.pm', # (CA file used for verify server) or
  # ssl_ca_path => '/etc/ssl/certs/',         # (CA path used for SSL)
    port   => 993                             # (but defaults are sane)

) or die "Could not connect to IMAP server";


$imap->login or
  die('Login failed: ' . $imap->last_error);

# let's see what this server knows (result cached on first call)

DEBUG $imap->capability;


# get total # of messages, # of unseen messages etc. (fast!)

# select folder
$imap->select('INBOX');
my $status;
while(1) {
    # DEBUG Dumper($imap->search('ALL', 'SUBJECT'));
    $status = $imap->status('INBOX'); # hash ref!
    DEBUG Dumper($status);
    sleep(10);
}

$SIG{'INT'} = sub {
    $imap->logout;
}

