use strict;
use Test::More 0.98;
use WebService::Mailgun;

my $mailgun = WebService::Mailgun->new(
    api_key => 'key-5fadc3ab81fdda5d628fd3a7dbe3ff57',
    domain => 'sandbox38e48dc6b2204f97ba1220db925e7827.mailgun.org',
);

ok my $res = $mailgun->message({
    from => 'test@perl.example.com',
    to => 'kan.fushihara@gmail.com',
    subject => 'test message',
    text => 'Hello, perl',
    'o:testmode' => 'true',
});

is $res->{message}, 'Queued. Thank you.';
note $res->{id};

done_testing;

