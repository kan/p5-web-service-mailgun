use strict;
use Test::More 0.98;
use Test::Exception;
use WebService::Mailgun;

my ($api_key, $domain, $to) = @ENV{qw/MAILGUN_API_KEY MAILGUN_DOMAIN MAILGUN_TO/};

plan skip_all => 'set MAILGUN_API_KEY, MAILGUN_DOMAIN and MAILGUN_TO to run this test'
    unless $api_key && $domain && $to;

my $mailgun = WebService::Mailgun->new(
    api_key => $api_key,
    domain  => $domain,
);

ok my $res = $mailgun->message({
    from => 'test@perl.example.com',
    to => $to,
    subject => 'test message',
    text => 'Hello, perl',
    'o:testmode' => 'true',
});

is $res->{message}, 'Queued. Thank you.';
note $res->{id};

ok my $res2 = $mailgun->message([
    from => 'test@perl.example.com',
    to => $to,
    subject => 'test message',
    text => 'Hello, perl',
    attachment => [ 't/01_message.t' ],
    'o:testmode' => 'true',
]);

is $res2->{message}, 'Queued. Thank you.';
note $res2;

dies_ok { my $res3 = $mailgun->message('scalar'); }, 'unsupport', 'message support only hashref or arrayref';

done_testing;
