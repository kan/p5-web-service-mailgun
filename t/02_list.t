use strict;
use Test::More 0.98;
use WebService::Mailgun;
use JSON::XS;

my $mailgun = WebService::Mailgun->new(
    api_key => 'key-5fadc3ab81fdda5d628fd3a7dbe3ff57',
    domain => 'sandbox38e48dc6b2204f97ba1220db925e7827.mailgun.org',
);

ok my $res = $mailgun->lists();

note explain $mailgun->list_members($res->[0]->{address});

done_testing;

