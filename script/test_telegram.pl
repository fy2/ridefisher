use WWW::Telegram::BotAPI;
use Config::IniFiles;
my $cfg = Config::IniFiles->new( -file => "/home/feyruz/sandbox/RideAway-AutoResponder/config/config.live.ini" );

my $api = WWW::Telegram::BotAPI->new (
    token => $cfg->val( 'telegram', 'token' )
);
my $result = eval { $api->getMe }
    or die 'Got error message: ', $api->parse_error->{msg};
# Uploading files is easier than ever.
$api->sendMessage ({
        #    chat_id => $cfg->val( 'telegram', 'chat_id' ),
    chat_id => 534386928,
    text => 'Kitt is scanning again.',
});
